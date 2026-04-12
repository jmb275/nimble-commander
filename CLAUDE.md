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

## Pulling Upstream Updates

```
git fetch upstream
git rebase upstream/main
```
