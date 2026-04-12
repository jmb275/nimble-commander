# CLAUDE.md — nimble-commander

Personal fork of [Nimble Commander](https://github.com/mikekazakov/nimble-commander) for column browser feature development.

## Git Setup

- `upstream` → `mikekazakov/nimble-commander` (original repo)
- `origin` → `jmb275/nimble-commander` (Justin's fork, HTTPS)
- Feature branch: `column-browser`
- Base: upstream main at v1.9.0 (commit b207defa6, 2026-04-12)

## Build

- Xcode 26.2+ required (26.4 works fine)
- Scheme: **NimbleCommander-Unsigned** (find under Product > Scheme if not in dropdown)
- `Cmd+B` to build, `Cmd+R` to run under debugger
- No CMake — Xcode projects only

## Feature Plan

See `COLUMN_BROWSER_PLAN.md` for full architecture and phased implementation plan.

## Column Browser Status (as of 2026-04-12)

**Working:**
- 4th presentation mode, accessible via Ctrl+6 (layout slot 6)
- Ancestor columns (left of active) with sorted/filtered VFSListings
- Active column backed by panel's data::Model (full NC functionality)
- Preview column (right of active) — shows directory contents as cursor moves
- Left/Right arrow navigation (Left=parent, Right=enter directory)
- Global sort mode sync via IndirectListingComparator across all columns
- Hidden files toggle applies to all columns
- File/folder icons in all columns (active uses full icon repository)
- Active/inactive emphasis toggle (blue/grey on Tab)
- Tabs work out of the box

**Known bugs (see COLUMN_BROWSER_PLAN.md):**
- Ancestor highlight beyond immediate parent doesn't stick
- Horizontal scroll gesture doesn't work (nested NSScrollView issue)
- NC theme colors not matched (uses system blue/grey instead)

## Key Files

- `Source/NimbleCommander/.../ColumnBrowser/PanelColumnBrowserView.h/.mm` — the view (~1065 LOC)
- `Source/NimbleCommander/.../ColumnBrowser/Layout.h` — layout config struct
- `Source/NimbleCommander/.../PanelViewImplementationProtocol.h` — added onMoveLeft:/onMoveRight:
- `Source/NimbleCommander/.../PanelView.mm` — arrow key dispatch guards
- User config (unsigned build): `~/Library/Application Support/NimbleCommander-Unsigned/Config/Config.json`
- User config (official NC): `~/Library/Application Support/Nimble Commander/Config/Config.json`
- The two installs use separate configs (based on CFBundleExecutable name), so they can coexist
- **Warning**: Don't edit the column browser layout in NC's Settings > Panels > Layout UI — it doesn't know about the `column_browser` type and will overwrite it with a Brief layout

## Pulling Upstream Updates

```
git fetch upstream
git rebase upstream/main
```
