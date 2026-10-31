# /// script
# dependencies = []
# requires-python = ">=3.11"
# ///
"""Build and package the personal distribution; do not change upstream app sources."""
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

APP_NAME = "Nimble Commander Personal"
BUNDLE_ID = "com.jbradley.nimblecommander.personal"
REPO = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPO.parents[1] / "apps/nimble_commander_personal"
MACHO_MAGIC = {bytes.fromhex(s) for s in ("cafebabe", "cafebabf", "bebafeca", "bfbafeca", "feedface", "feedfacf", "cefaedfe", "cffaedfe")}


def run(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()


def architectures(app):
    """Only advertise architectures supported by every bundled Mach-O binary."""
    common = None
    for path in app.rglob("*"):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as stream:
            magic = stream.read(4)
        if magic not in MACHO_MAGIC:
            continue
        found = set(run("/usr/bin/lipo", "-archs", path).split())
        common = found if common is None else common & found
    if not common:
        raise RuntimeError("No common CPU architecture found in the app bundle")
    return sorted(common)


def package(built_app, output):
    output.mkdir(parents=True, exist_ok=True)
    commit = run("git", "-C", REPO, "rev-parse", "HEAD")
    with tempfile.TemporaryDirectory(prefix="nc_personal_package_") as temporary:
        app = Path(temporary) / f"{APP_NAME}.app"
        subprocess.run(["/usr/bin/ditto", str(built_app), str(app)], check=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        original_executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        original_executable.rename(original_executable.with_name(APP_NAME))
        info.update(CFBundleExecutable=APP_NAME, CFBundleName=APP_NAME,
                    CFBundleDisplayName=APP_NAME, CFBundleIdentifier=BUNDLE_ID,
                    CFBundleVersion=run("git", "-C", REPO, "rev-list", "--count", "HEAD"),
                    NCSourceCommit=commit, NCPersonalBuild=True,
                    SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False,
                    SUAllowsAutomaticUpdates=False)
        info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
        cpu_architectures = architectures(app)
        version = info["CFBundleShortVersionString"]
        archive_name = f"nimble_commander_personal_{version}_{commit[:9]}.zip"
        archive_path = output / archive_name
        temporary_archive = Path(temporary) / archive_name
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                        str(app), str(temporary_archive)], check=True)
        shutil.copy2(temporary_archive, archive_path)
        manifest = dict(archive=archive_name, sha256=hashlib.sha256(archive_path.read_bytes()).hexdigest(),
                        version=version, source_commit=commit,
                        source_url=f"https://github.com/jmb275/nimble-commander/tree/{commit}",
                        bundle_id=BUNDLE_ID, architectures=cpu_architectures,
                        built_at=datetime.now(timezone.utc).isoformat())
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.copy2(REPO / "Scripts/install_personal.py", output / "install_personal.py")
    shutil.copy2(REPO / "Docs/PersonalBuild.md", output / "README.md")
    shutil.copy2(REPO / "LICENSE.md", output / "LICENSE.md")
    print(f"Packaged {archive_path}\nArchitectures: {', '.join(cpu_architectures)}\nSource: {commit}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--from-app", type=Path, help="Package an already-built unsigned app")
    args = parser.parse_args()
    if args.from_app:
        package(args.from_app.resolve(), args.output.resolve())
        return
    derived = Path(tempfile.gettempdir()) / "nc_personal_release_build"
    subprocess.run(["xcodebuild", "-quiet", "-project", str(REPO / "Source/NimbleCommander/NimbleCommander.xcodeproj"),
                    "-scheme", "NimbleCommander-Unsigned", "-configuration", "Release",
                    "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "build"], check=True)
    package(derived / "Build/Products/Release_Unsigned/NimbleCommander-Unsigned.app", args.output.resolve())


if __name__ == "__main__":
    main()
