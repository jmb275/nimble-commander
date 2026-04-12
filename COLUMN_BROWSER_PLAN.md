# Nimble Commander Column Browser — Implementation Plan

**Date:** 2026-04-06
**Status:** Planning / Phase 1 not yet started
**Nature:** Personal fork enhancement (not intended as upstream contribution)

---

## Overview

Add a Finder-style column browser as a 4th presentation mode in Nimble Commander, alongside the existing Brief, List, and Gallery modes. The column view shows the current directory's ancestor chain left-to-right, with the rightmost column being the active (fully-featured) directory.

## Why This Works

NC's panel view system is protocol-based and designed for extensibility:

- **`NCPanelViewPresentationProtocol`** — 7 required methods. Each view mode (Brief, List, Gallery) implements this protocol. A column browser would be the 4th implementation.
- **`PanelViewLayout` variant** — `std::variant` of layout config types. We add `PanelColumnBrowserLayout`.
- **View factory pattern** — `PanelView` already has `setupBriefPresentation`, `setupListPresentation`, `setupGalleryPresentation`. We add `setupColumnBrowserPresentation`.
- **Data model is view-agnostic** — `nc::panel::data::Model` handles sorting, filtering, selection independently of rendering.
- **Purely additive** — no changes to existing view modes or core architecture.

## Architecture Decision

### Where Multi-Directory State Lives

The key tension: `PanelController` manages one `data::Model` for one directory. A column browser shows N directories.

**Approach:** The column browser view manages ancestor columns internally, but the **rightmost (active) column** is backed by the PanelController's Model.

```
PanelController.m_Data  →  manages the "current" directory (rightmost column)
ColumnBrowserView       →  manages ancestor columns as lightweight VFSListings
                           + renders all columns in a horizontal NSScrollView
```

### Why Not Reuse Full PanelControllers for Each Column?

Each `PanelController` is heavyweight (~2000+ lines of state): full `data::Model`, `History` stack, `PanelView` with header/footer, `QuickSearch` instance, icon repository, volatile data. For 15 levels of depth that's 15 full controllers. Sync on every navigation would be O(N) panel reshuffling through the `NSSplitView`/`FilePanelsTabbedHolder` system (designed for 2 panes). File operations (F5 copy etc.) would target ancestor columns incorrectly. Ancestor columns don't need any of that — they're just: path → VFSListing → render filenames.

## What You Get For Free

These work on the active (rightmost) column because it's backed by the real Model:

- **Filtering / QuickSearch** — type-to-filter works unchanged
- **Sorting** — unchanged
- **Selection** — multi-select in active column works
- **VFS support** — archives, SFTP, WebDAV all work (navigation goes through PanelController)
- **File operations** — F5 copy, F6 move, F7 mkdir, F8 delete all operate on current selection
- **History** — back/forward navigation still works
- **Tabs** — column browser is per-tab; other tabs can use different view modes

## What Needs Custom Work

1. **Ancestor column rendering** — loading parent directories as read-only lightweight columns
2. **Horizontal scroll management** — keeping active column visible, smooth scroll on navigation
3. **Column-aware arrow key dispatch** — Left/Right override (view already defines `itemsInColumn` per mode)
4. **State persistence** — remembering column depth when switching layouts or restoring tabs
5. **Column sizing** — fixed or resizable dividers

## Keyboard Behavior

| Key | Column Browser Action | Notes |
|-----|----------------------|-------|
| Up/Down | Move cursor in active column | Same as today |
| **Right** | On directory: navigate into it (new column appears) | Calls PanelController.GoToDir() |
| **Right** | On file: no-op (or preview in Phase 3) | |
| **Left** | Navigate to parent (active column shifts left) | Calls PanelController.GoToDir("..") |
| Home/End | First/last item in active column | Same as today |
| Page Up/Down | Scroll active column | Same as today |
| Tab | Switch to other panel | Unchanged |
| Return | Open file / enter directory | Unchanged |
| Type-to-filter | QuickSearch on active column | Free — uses existing Model |
| F3-F8 | View, edit, copy, move, mkdir, delete | Unchanged — operates on selection |
| Shift+arrows | Extend selection | Works in active column |

**Note:** Left/Right arrows currently do "jump by itemsInColumn" (page-width jump in Brief, redundant page-up/down in List, single-item in Gallery). Each view mode already defines its own semantics for these keys, so redefining them for column browser is consistent with the pattern.

## File Changes

### New Files (~800-1200 LOC)

#### 1. `Source/NimbleCommander/.../States/FilePanels/ColumnBrowser/NCPanelColumnBrowserView.h`

```objc
@interface NCPanelColumnBrowserView : NSView <NCPanelViewPresentationProtocol>

@property (nonatomic) int cursorPosition;
@property (nonatomic, readonly) int itemsInColumn;      // rows visible in one column
@property (nonatomic, readonly) int maxNumberOfVisibleItems;

// Column management
- (void)rebuildAncestorColumns;  // reconstruct from current path
@end
```

Core internals:
- `NSScrollView` containing horizontally-arranged column views
- Each column ~200pt wide (configurable), shows file list for one directory level
- Rightmost column reads from `m_Data` (the panel's Model)
- Ancestor columns are simple `VFSListing` snapshots in basic `NSTableView`s

#### 2. `Source/NimbleCommander/.../States/FilePanels/ColumnBrowser/NCPanelColumnBrowserView.mm`

Protocol implementation + column management logic.

#### 3. `Source/NimbleCommander/.../States/FilePanels/ColumnBrowser/ColumnBrowserColumn.h/.mm`

Individual column component — lightweight NSTableView wrapper for a single directory level. Handles:
- Rendering file names + icons for a VFSListing
- Click-to-select (which triggers navigation in the parent view)
- Visual distinction between active and ancestor columns

### Modified Files (~200-400 LOC)

#### 4. `Source/NimbleCommander/.../States/FilePanels/PanelViewLayoutSupport.h`

Add layout config struct and extend the variant:

```cpp
struct PanelColumnBrowserLayout {
    short column_width = 200;
    bool show_icons = true;
    bool show_preview = false;  // Phase 3: QuickLook preview column
    constexpr bool operator==(const PanelColumnBrowserLayout&) const noexcept = default;
};

// Add to existing variant:
using LayoutVariant = std::variant<
    PanelViewDisabledLayout,
    PanelBriefViewColumnsLayout,
    PanelListViewColumnsLayout,
    PanelGalleryViewLayout,
    PanelColumnBrowserLayout       // <-- new
>;
```

#### 5. `Source/NimbleCommander/.../States/FilePanels/PanelView.h/.mm`

Add setup method following the existing pattern:

```objc
- (void)setupColumnBrowserPresentationWithLayout:(PanelColumnBrowserLayout)_layout;
```

In `setPresentationLayout:`:
```objc
if (const auto *col = _layout.columnBrowser()) {
    [self setupColumnBrowserPresentationWithLayout:*col];
}
```

#### 6. Presentation Factory

Add `create_column_browser_view` factory function to the `PresentationFactory` struct.

#### 7. `Source/NimbleCommander/.../Bootstrap/Actions.h`

Wire column browser layout into one of the 10 available layout toggle slots (Ctrl+1 through Ctrl+0). Requires adding a default layout preset that uses `PanelColumnBrowserLayout`.

#### 8. Build system

Add new files to the Xcode project / CMake build target.

## Key Source Files to Study

| File | What It Tells You |
|------|-------------------|
| `Source/NimbleCommander/.../PanelView.mm` | How view modes are swapped (setupBrief/List/Gallery methods) |
| `Source/NimbleCommander/.../PanelViewImplementationProtocol.h` | The protocol your view must implement |
| `Source/NimbleCommander/.../PanelViewLayoutSupport.h` | Layout variant type + persistence |
| `Source/NimbleCommander/.../Brief/PanelBriefView.mm` | Best reference implementation (NSCollectionView-based) |
| `Source/NimbleCommander/.../Gallery/PanelGalleryView.mm` | Newest view mode, most recent patterns |
| `Source/NimbleCommander/.../PanelController.mm` | How GoToDir works, how data flows |
| `Source/Panel/include/Panel/PanelData.h` | Data model API (SortedDirectoryEntries, filtering) |
| `Source/Panel/include/Panel/QuickSearch.h` | Filtering system (works transparently) |
| `Source/NimbleCommander/.../Bootstrap/Actions.h` | All keyboard shortcuts, lines 219-418 |

## Phases

### Phase 1 — Proof of Concept

**Goal:** Get columns rendering, basic navigation works.

- [ ] Understand build system (Xcode project structure, how to add files)
- [ ] Create `NCPanelColumnBrowserView` implementing `NCPanelViewPresentationProtocol`
- [ ] Hardcode ancestor columns by walking up from current path
- [ ] Basic `NSTableView` per column inside horizontal `NSScrollView`
- [ ] Rightmost column backed by `m_Data` (active, gets filtering for free)
- [ ] Left/Right arrow navigation triggers `GoToDir` on PanelController
- [ ] Add `PanelColumnBrowserLayout` to variant
- [ ] Wire into `PanelView.mm` setup method
- [ ] Assign to one layout slot for testing

### Phase 2 — Polish

- [ ] Smooth horizontal scroll animation on navigation
- [ ] Proper column sizing and resizable dividers
- [ ] Icon rendering in all columns (not just active)
- [ ] Visual distinction for active vs ancestor columns (background tint, selection highlight)
- [ ] Keyboard selection (Shift+Up/Down in active column)
- [ ] Handle edge cases: root directory, VFS boundaries, archive navigation

### Phase 3 — Advanced

- [ ] Preview column (QuickLook rendering for selected file, like Finder)
- [ ] Drag and drop between columns
- [ ] Column width persistence per-directory or global
- [ ] Soft filtering visual indicators in ancestor columns
- [ ] Click-to-navigate in ancestor columns (click item in parent → active column changes)
- [ ] Animated column transitions

## Known Bugs / Deferred Work

- [x] **Ancestor sort mode sync**: Now uses `IndirectListingComparator` with the panel's real `SortMode`.
- [ ] **Ancestor highlight beyond immediate parent**: `selectRowIndexes:` on newly-created NSTableViews doesn't stick for columns beyond the immediate parent. May need custom cell background drawing instead of NSTableView selection.
- [ ] **Horizontal scroll gesture**: Nested NSScrollViews prevent trackpad horizontal scroll from reaching the outer container. Need custom scroll event forwarding or a different container approach.
- [ ] **File icons in all columns**: No icons yet in any column.
- [ ] **NC theme color matching**: Selection highlight uses system blue/grey rather than NC's theme-specific colors (FilePanelsBriefFocusedActive/InactiveItemBackgroundColor).
- [ ] **Auto-fit column widths**: Size columns to fit their longest filename (like Finder's recent addition). Could be on-demand (double-click divider) or automatic.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| VFS performance on ancestor columns | N directory listings on initial display | Cache VFSListings; lazy-load; ancestors are read-only snapshots |
| Network VFS latency (SFTP, WebDAV) | Column browser over network could be slow | Show spinner per column; load ancestors asynchronously |
| Deep paths (20+ levels) | Many columns, horizontal scroll gets long | Same as Finder — horizontal scroll. Could also collapse early ancestors |
| Upstream merge conflicts | Rebasing fork against new NC releases | Presentation protocol is stable; changes are isolated to new files + small touchpoints |
| Build system complexity | Adding files to Xcode project can be fiddly | Study how Gallery mode was added (Dec 2025) as the most recent precedent |

## Reference: NC Codebase Stats

- **Total:** ~460k lines of C++/Obj-C++
- **Language:** C++20 with Objective-C++ for AppKit integration
- **Panel module:** `Source/Panel/` (data model, filtering, history — view-agnostic)
- **Panel views:** `Source/NimbleCommander/.../States/FilePanels/` (Brief/, List/, Gallery/)
- **Repo:** cloned to `/Users/jbradley/Dropbox/6_computing/tools/nimble-commander/`
