# /// script
# dependencies = []
# requires-python = ">=3.11"
# ///
"""Install the packaged personal NC on either Mac; run in your own terminal."""
import argparse
import hashlib
import json
import os
import platform
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
from datetime import datetime
from pathlib import Path

APP_NAME = "Nimble Commander Personal"
BUNDLE_ID = "com.jbradley.nimblecommander.personal"
ALFRED = "com.runningwithcrayons.Alfred"
TEST_ID = "info.filesmanager.Files.TabTest"
ABSENT = "__ABSENT__"
REGISTRAR = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
LEGACY_TEST_RECEIPT = Path("/private/tmp/nc_external_reveal_test/alfred_file_viewer_before_test")


def command(*args, check=True):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, check=check)


def read_default(domain):
    result = command("/usr/bin/defaults", "read", domain, "NSFileViewer", check=False)
    return result.stdout.strip() if result.returncode == 0 else ABSENT


def write_default(domain, value):
    if value == ABSENT:
        if read_default(domain) != ABSENT:
            command("/usr/bin/defaults", "delete", domain, "NSFileViewer")
    else:
        command("/usr/bin/defaults", "write", domain, "NSFileViewer", "-string", value)


def restart_alfred():
    command("/usr/bin/killall", "-TERM", "Alfred", check=False)
    deadline = time.monotonic() + 10
    while command("/usr/bin/pgrep", "-x", "Alfred", check=False).returncode == 0:
        if time.monotonic() > deadline:
            raise RuntimeError("Alfred has not finished quitting; quit it normally and retry")
        time.sleep(0.1)
    time.sleep(0.5)
    if command("/usr/bin/open", "-b", ALFRED, check=False).returncode:
        time.sleep(1)
        command("/usr/bin/open", "-b", ALFRED)


def validate(package_dir, user_root):
    manifest = json.loads((package_dir / "manifest.json").read_text())
    name = manifest["archive"]
    if Path(name).name != name:
        raise RuntimeError("Invalid archive filename")
    archive = package_dir / name
    if not archive.is_file() or archive.stat().st_size == 0:
        raise RuntimeError("The archive is missing or online-only. Make this Dropbox folder available offline first.")
    if hashlib.sha256(archive.read_bytes()).hexdigest() != manifest["sha256"]:
        raise RuntimeError("The archive checksum does not match; let Dropbox finish syncing")
    if platform.machine() not in manifest["architectures"]:
        raise RuntimeError(f"This package does not support {platform.machine()}")
    prefs = user_root / "Dropbox/6_computing/dotfiles/nimblecommander/Config.json"
    if not prefs.is_file() or prefs.stat().st_size == 0:
        raise RuntimeError("The saved NC preferences are missing or online-only; make dotfiles available offline")
    settings = json.loads(prefs.read_text())
    if settings.get("filePanel", {}).get("general", {}).get("openExternalRequestsInNewTab") is not True:
        raise RuntimeError("The saved preferences have not synced the new-tab option yet")
    return manifest, archive, prefs


def ensure_quit():
    pattern = r"/(Nimble Commander( Personal)?|NimbleCommander-Unsigned|NC Tab Test)\.app/Contents/MacOS/"
    if command("/usr/bin/pgrep", "-f", pattern, check=False).returncode == 0:
        raise RuntimeError("Quit all Nimble Commander / NC Tab Test copies first, then run this command again")


def stop_failed_launch(app):
    command("/usr/bin/killall", "-TERM", APP_NAME, check=False)
    pattern = re.escape(str(app / "Contents/MacOS" / APP_NAME))
    deadline = time.monotonic() + 10
    while command("/usr/bin/pgrep", "-f", pattern, check=False).returncode == 0:
        if time.monotonic() > deadline:
            return False
        time.sleep(0.1)
    return True


def install(package_dir, user_root, check_only=False):
    manifest, archive, prefs = validate(package_dir, user_root)
    if check_only:
        print(f"Package verified: {manifest['version']}, {', '.join(manifest['architectures'])}; saved preferences found.")
        return
    app = user_root / "Applications" / f"{APP_NAME}.app"
    support = user_root / "Library/Application Support" / APP_NAME
    config = support / "Config/Config.json"
    receipt_path = support / "Installer/before_personal.json"
    current_info = {}
    if app.exists():
        current_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if current_info.get("CFBundleIdentifier") != BUNDLE_ID:
            raise RuntimeError("A different app occupies the personal app path; leaving it alone")
    previous = {"global": read_default("-g"), "alfred": read_default(ALFRED)}
    if (current_info.get("NCSourceCommit") == manifest["source_commit"]
            and config.is_symlink() and config.resolve() == prefs.resolve()
            and previous["global"] == BUNDLE_ID and previous["alfred"] == BUNDLE_ID):
        print("This personal build and its saved preferences are already configured; no changes needed.")
        return
    ensure_quit()
    app.parent.mkdir(parents=True, exist_ok=True)
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    baseline = previous.copy()
    if baseline["alfred"] == TEST_ID and LEGACY_TEST_RECEIPT.is_file():
        baseline["alfred"] = LEGACY_TEST_RECEIPT.read_text().strip()
    if not receipt_path.exists():
        receipt_path.write_text(json.dumps(baseline, indent=2) + "\n")
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    backup = support / "Installer" / f"config_before_{stamp}"
    had_config = os.path.lexists(config)
    with tempfile.TemporaryDirectory(prefix=".nc_personal_", dir=app.parent) as temporary:
        stage = Path(temporary)
        command("/usr/bin/ditto", "-x", "-k", archive, stage)
        incoming = stage / f"{APP_NAME}.app"
        info = plistlib.loads((incoming / "Contents/Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("NCSourceCommit") != manifest["source_commit"]:
            raise RuntimeError("The packaged app identity does not match the manifest")
        # Check the complete bundle before replacing anything or launching code.
        command("/usr/bin/codesign", "--verify", "--deep", "--strict", "--all-architectures", incoming)
        previous_app = stage / "previous.app"
        replaced_app = False
        replaced_config = False
        defaults_changed = False
        try:
            if app.exists():
                backup_archive = support / "Installer" / f"app_before_{stamp}.zip"
                command("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, backup_archive)
                app.rename(previous_app)
            incoming.rename(app)
            replaced_app = True
            config.parent.mkdir(parents=True, exist_ok=True)
            if not (config.is_symlink() and config.resolve() == prefs.resolve()):
                if had_config:
                    config.rename(backup)
                config.symlink_to(prefs)
                replaced_config = True
            command(REGISTRAR, "-f", app)
            # Verify Launch Services can find the installed identity before changing routing.
            command("/usr/bin/open", "-b", BUNDLE_ID)
            defaults_changed = True
            write_default("-g", BUNDLE_ID)
            write_default(ALFRED, BUNDLE_ID)
            restart_alfred()
            print(f"Installed {app}\nSaved preferences restored; new-tab option is on.\nGlobal and Alfred file viewers now use {APP_NAME}.")
        except Exception:
            if defaults_changed or previous["alfred"] == TEST_ID:
                write_default("-g", previous["global"])
                write_default(ALFRED, previous["alfred"])
                restart_alfred()
            if not stop_failed_launch(app):
                # Keep both app versions, including the old one outside the staging directory.
                if previous_app.exists():
                    previous_app.rename(support / "Installer" / f"recovery_{stamp}.app")
                print("The personal app did not quit; files were kept for manual recovery.")
                raise
            if replaced_config:
                config.unlink(missing_ok=True)
                if had_config:
                    backup.rename(config)
            if replaced_app:
                shutil.rmtree(app)
            if previous_app.exists():
                previous_app.rename(app)
                command(REGISTRAR, "-f", app, check=False)
            raise


def restore(user_root):
    ensure_quit()
    receipt = user_root / "Library/Application Support" / APP_NAME / "Installer/before_personal.json"
    if not receipt.is_file():
        raise RuntimeError("No personal-install receipt exists on this Mac")
    before = json.loads(receipt.read_text())
    for domain, field in (("-g", "global"), (ALFRED, "alfred")):
        if read_default(domain) == BUNDLE_ID:
            write_default(domain, before[field])
    restart_alfred()
    print("Previous file-viewer settings restored. The personal app and its preferences are kept.")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify the package and preferences without installing")
    parser.add_argument("--restore", action="store_true", help="Restore this Mac's original file-viewer defaults")
    args = parser.parse_args()
    try:
        if args.restore:
            restore(Path.home())
        else:
            install(Path(__file__).resolve().parent, Path.home(), args.check)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Personal NC setup failed: {error}")
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr or error.stdout or "")
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
