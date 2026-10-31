# Nimble Commander fork

Read `CONTRIBUTING.md` and `Docs/Building.md` before source changes.

- `fix/external-reveal-tabs` is the focused optional-preference patch for upstream review.
- `personal/external-reveal-tabs` adds personal packaging; keep those changes out of an upstream PR.
- `archive/column-browser` preserves Justin's old column-browser work. Do not merge it into either reveal branch.
- Personal distribution and installer usage: `Docs/PersonalBuild.md`.
- Build with `NimbleCommander-Unsigned` and `CODE_SIGNING_ALLOWED=NO`; agent sessions cannot use signing credentials.
- Application tests: build the `NimbleCommanderUT` scheme, then run the resulting executable directly.
- The reveal change has regression tests in `ServicesHandler_UT.mm`. Live Alfred acceptance was verified on 2026-10-30.
- Test app registration from `/private/tmp` failed. Install distinct app identities in `~/Applications` before configuring file-viewer defaults.
- Installer actions that launch apps and write user preferences run from Justin's terminal, not inside an agent sandbox.
