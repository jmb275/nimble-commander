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
The complete app and its bundled helpers are sealed with local ad-hoc signatures;
it has no Developer ID signature or notarization. The original package omitted
this sealing step, which can prevent macOS from remembering folder-access grants.
After installing the corrected package, allow requested folders once and check
that revisiting them no longer prompts. Ad-hoc identity changes with the code,
so permissions may need approval again after a future rebuild. A persistent
certificate-based signing identity would be needed to preserve identity across
updates. See [Apple's code identity explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

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
through Sparkle's documented Info.plist settings. After all changes, it signs
unsigned or modified nested bundles inside out, preserves valid vendor signatures,
and seals the outer app using its personal bundle ID. Deep, strict signature
verification covers both CPU architectures before packaging and installation.
No certificate, private key, or keychain access is needed. Do not use the app's built-in
Check for Updates to update this fork; rebuild it from source instead.
The generated archive, manifest, installer, and license are copied to
`6_computing/apps/nimble_commander_personal` for Dropbox distribution.
Source provenance and SHA-256 are recorded in the manifest.

## Keyboard Maestro

The `NimbleCommander` macro group must include **Nimble Commander Personal**
in its application list. `NC: Go to Dropbox` (Command-Shift-H) uses one active
**Select or Show a Menu Item** action targeting **Nimble Commander Personal**:
**Go > Favorites > Dropbox**. The Dropbox favorite comes from the saved config.
This navigates the current tab; Alfred Command-Enter continues to create a new tab.
The macro was run twice in a disposable tab on 2026-10-31 and did not add tabs.

Do not use `open` for this shortcut: it sends an external request and obeys the
new-tab preference. The previous shell action remains disabled for reference.
A portable export containing the corrected action and hotkey is saved at
`6_computing/apps/keyboardmaestro/nc_go_to_dropbox.kmmacros` for import on the MBA
if Keyboard Maestro does not already sync the change.

## Accessibility prompt after an update

The saved `general.alwaysUseFnKeysAsFunctional` setting is enabled. At launch,
NC's function-key remapper calls `AXIsProcessTrustedWithOptions` with prompting
on. This is separate from folder-access permission and requires Accessibility
permission for **Nimble Commander Personal**, even if stock NC already has it.

If the popup repeats despite the Accessibility switch appearing on, the grant
may refer to a previous ad-hoc build. Quit Personal NC; in System Settings >
Privacy & Security > Accessibility, remove only **Nimble Commander Personal**,
then add `~/Applications/Nimble Commander Personal.app` and enable it. Reopen NC
and check another launch. Re-adding the app is a user-performed permission change;
the installer does not grant or reset it. Do not rebuild/re-sign the app just
to troubleshoot this, because that changes its ad-hoc identity again.

The permission refresh still needs live confirmation. Disabling function-key
remapping would also avoid this request but would change the saved key behavior;
it has not been disabled.

## Installer verification

Test installer transactions without changing real apps or preferences:

```sh
uv run --script Scripts/test_personal_installer.py
```

Before incorporating upstream updates, merge the desired upstream changes on the
personal branch, resolve conflicts, rerun the application unit tests, and test an
Alfred reveal. Commit and push the source before publishing the replacement package.
