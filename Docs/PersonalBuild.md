# Nimble Commander Personal

This is Justin's personal build of NC with the optional external-request new-tab fix.
It is separate from the stock app, which stays in `/Applications/Nimble Commander.app`.

## Install on either Mac

Make this Dropbox folder and `6_computing/dotfiles/nimblecommander` available offline.
Quit all NC copies, including NC Tab Test, then run:

```sh
uv run --script ~/Dropbox/6_computing/apps/nimble_commander_personal/install_personal.py
```

The installer verifies the archive checksum and CPU architecture, installs into
`~/Applications/Nimble Commander Personal.app`, links the personal app's configuration
to the existing portable dotfiles configuration, and sets both the global and Alfred
file viewers to the personal app. The new-tab option is enabled in that saved config.
It supersedes the temporary Alfred test override; do not run the old test `restore`
command as part of this installation.

Your saved themes, layouts, hotkeys, tools, and editors are reused. Window/tab state
and security permissions are separate from configuration and are not migrated.
Because this is a distinct app identity, macOS may ask for permissions again.
This is a locally built unsigned app, without Developer ID notarization.

The same package works on every architecture listed in `manifest.json`; the MBA
needs uv, not Xcode. Installation is per-Mac. Preferences remain shared through Dropbox.
Quit other NC copies before using the personal app so they do not rewrite shared config.

Check without changing anything:

```sh
uv run --script ~/Dropbox/6_computing/apps/nimble_commander_personal/install_personal.py --check
```

Restore the previous file-viewer defaults (quit NC first):

```sh
uv run --script ~/Dropbox/6_computing/apps/nimble_commander_personal/install_personal.py --restore
```

The restore option preserves the personal app and preferences and does not overwrite
viewer settings that you have subsequently changed to another app. Replacing an old
personal build creates a zipped app backup under its Application Support/Installer folder.
A replaced personal config is preserved there too.

## Build and update

The PR-sized change is on `fix/external-reveal-tabs`. Personal packaging lives on
`personal/external-reveal-tabs`; it is not part of the proposed upstream change.
From the personal branch, build/package with:

```sh
uv run --script Scripts/build_personal.py
```

The builder uses the Release unsigned scheme, creates the distinct personal app
identity and executable, and disables automatic upstream update checks/downloads
through Sparkle's documented Info.plist settings. Do not use the app's built-in
Check for Updates to update this fork; rebuild it from source instead.
The generated archive, manifest, installer, and license are copied to
`6_computing/apps/nimble_commander_personal` for Dropbox distribution.
Source provenance and SHA-256 are recorded in the manifest.

Test installer transactions without changing real apps or preferences:

```sh
uv run --script Scripts/test_personal_installer.py
```

Before incorporating upstream updates, merge the desired upstream changes on the
personal branch, resolve conflicts, rerun the application unit tests, and test an
Alfred reveal. Commit and push the source before publishing the replacement package.
