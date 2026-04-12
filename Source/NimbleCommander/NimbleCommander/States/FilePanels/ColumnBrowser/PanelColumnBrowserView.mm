// Copyright (C) 2026 Michael Kazakov. Subject to GNU General Public License version 3.
#include "PanelColumnBrowserView.h"
#include "../PanelView.h"
#include "../PanelControllerActionsDispatcher.h"
#include <NimbleCommander/Core/Theming/Theme.h>
#include <NimbleCommander/Core/Theming/ThemesManager.h>
#include <NimbleCommander/Bootstrap/AppDelegate.h>
#include <Panel/PanelData.h>
#include <Panel/Log.h>
#include <Utility/ObjCpp.h>
#include <Utility/StringExtras.h>
#include <atomic>

using namespace nc;
using namespace nc::panel;

static const CGFloat g_RowHeight = 20.0;
static const CGFloat g_ColumnDividerWidth = 1.0;
static NSString *const g_AncestorCellID = @"AncestorCell";
static NSString *const g_ActiveCellID = @"ActiveCell";
static NSString *const g_PreviewCellID = @"PreviewCell";
static const NSInteger g_PreviewColumnTag = -2;

// Subclass NSTableView to prevent it from consuming keyboard events.
// All keyboard input should flow through PanelView's responder chain.
@interface NCColumnBrowserTableView : NSTableView
@end

@implementation NCColumnBrowserTableView
- (void)keyDown:(NSEvent *)_event
{
    // Forward all key events up the responder chain instead of handling them.
    // PanelView handles cursor movement, Enter, Backspace, etc.
    [self.nextResponder keyDown:_event];
}

- (BOOL)acceptsFirstResponder
{
    return NO;
}
@end

// Custom row view that forces the emphasized (blue) selection appearance
// even when the table view is not the first responder.
@interface NCColumnBrowserRowView : NSTableRowView
@property(nonatomic) bool forceEmphasized;
@end

@implementation NCColumnBrowserRowView
@synthesize forceEmphasized = _forceEmphasized;

- (void)setEmphasized:(BOOL)_emphasized
{
    // Override: always use our controlled value rather than the system's
    [super setEmphasized:_forceEmphasized];
}

- (void)setForceEmphasized:(bool)_force
{
    _forceEmphasized = _force;
    [super setEmphasized:_force];
}
@end

@implementation NCPanelColumnBrowserView {
    data::Model *m_Data;
    PanelColumnBrowserLayout m_Layout;
    int m_CursorPosition;
    bool m_ColumnsBuilt;
    __weak PanelView *m_PanelView;
    vfsicon::IconRepository *m_IconRepository;

    // The horizontal scroll view containing all columns
    NSScrollView *m_HorizontalScrollView;
    NSView *m_ColumnsContainer; // document view of the scroll view

    // Active (rightmost) column — backed by m_Data
    NSScrollView *m_ActiveColumnScrollView;
    NCColumnBrowserTableView *m_ActiveColumnTableView;

    // Ancestor columns — lightweight listing snapshots
    std::vector<AncestorColumn> m_AncestorColumns;
    std::vector<NSScrollView *> m_AncestorColumnScrollViews;
    std::vector<NCColumnBrowserTableView *> m_AncestorColumnTableViews;

    // Preview column — shows contents of directory under cursor
    NSScrollView *m_PreviewColumnScrollView;
    NCColumnBrowserTableView *m_PreviewColumnTableView;
    std::optional<PreviewColumn> m_PreviewColumn;
    std::shared_ptr<std::atomic<bool>> m_PreviewCancelFlag;

    bool m_PanelActive;
}

- (instancetype)initWithFrame:(NSRect)_frame
               iconRepository:(nc::vfsicon::IconRepository &)_ir
{
    self = [super initWithFrame:_frame];
    if( !self )
        return nil;

    m_Data = nullptr;
    m_CursorPosition = -1;
    m_ColumnsBuilt = false;
    m_PanelActive = false;
    m_IconRepository = &_ir;

    // Outer horizontal scroll view
    m_HorizontalScrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    m_HorizontalScrollView.translatesAutoresizingMaskIntoConstraints = false;
    m_HorizontalScrollView.hasHorizontalScroller = YES;
    m_HorizontalScrollView.hasVerticalScroller = NO;
    m_HorizontalScrollView.autohidesScrollers = YES;
    m_HorizontalScrollView.drawsBackground = YES;
    m_HorizontalScrollView.backgroundColor = nc::CurrentTheme().FilePanelsBriefRegularEvenRowBackgroundColor();

    m_ColumnsContainer = [[NSView alloc] initWithFrame:self.bounds];
    m_HorizontalScrollView.documentView = m_ColumnsContainer;

    [self addSubview:m_HorizontalScrollView];

    // Pin the scroll view to our bounds
    NSDictionary *views = NSDictionaryOfVariableBindings(m_HorizontalScrollView);
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-(0)-[m_HorizontalScrollView]-(0)-|"
                                                                 options:0
                                                                 metrics:nil
                                                                   views:views]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(0)-[m_HorizontalScrollView]-(0)-|"
                                                                 options:0
                                                                 metrics:nil
                                                                   views:views]];

    // Create the active and preview column table views (not yet placed — rebuildColumns handles placement)
    [self createActiveColumn];
    [self createPreviewColumn];

    return self;
}

- (void)createActiveColumn
{
    const CGFloat column_width = m_Layout.column_width > 0 ? m_Layout.column_width : 200;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.width = column_width;
    col.resizingMask = NSTableColumnNoResizing;

    m_ActiveColumnTableView = [[NCColumnBrowserTableView alloc] initWithFrame:NSZeroRect];
    m_ActiveColumnTableView.headerView = nil;
    m_ActiveColumnTableView.rowHeight = g_RowHeight;
    m_ActiveColumnTableView.intercellSpacing = NSMakeSize(0, 0);
    m_ActiveColumnTableView.usesAlternatingRowBackgroundColors = YES;
    m_ActiveColumnTableView.style = NSTableViewStyleFullWidth;
    m_ActiveColumnTableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    m_ActiveColumnTableView.dataSource = self;
    m_ActiveColumnTableView.delegate = self;
    m_ActiveColumnTableView.tag = -1; // tag -1 = active column
    m_ActiveColumnTableView.allowsEmptySelection = YES;
    m_ActiveColumnTableView.allowsMultipleSelection = NO;
    [m_ActiveColumnTableView addTableColumn:col];

    m_ActiveColumnScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    m_ActiveColumnScrollView.hasVerticalScroller = YES;
    m_ActiveColumnScrollView.hasHorizontalScroller = NO;
    m_ActiveColumnScrollView.autohidesScrollers = YES;
    m_ActiveColumnScrollView.drawsBackground = YES;
    m_ActiveColumnScrollView.backgroundColor = nc::CurrentTheme().FilePanelsBriefRegularEvenRowBackgroundColor();
    m_ActiveColumnScrollView.documentView = m_ActiveColumnTableView;
}

- (void)createPreviewColumn
{
    const CGFloat column_width = m_Layout.column_width > 0 ? m_Layout.column_width : 200;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.width = column_width;
    col.resizingMask = NSTableColumnNoResizing;

    m_PreviewColumnTableView = [[NCColumnBrowserTableView alloc] initWithFrame:NSZeroRect];
    m_PreviewColumnTableView.headerView = nil;
    m_PreviewColumnTableView.rowHeight = g_RowHeight;
    m_PreviewColumnTableView.intercellSpacing = NSMakeSize(0, 0);
    m_PreviewColumnTableView.usesAlternatingRowBackgroundColors = YES;
    m_PreviewColumnTableView.style = NSTableViewStyleFullWidth;
    m_PreviewColumnTableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    m_PreviewColumnTableView.dataSource = self;
    m_PreviewColumnTableView.delegate = self;
    m_PreviewColumnTableView.tag = g_PreviewColumnTag;
    m_PreviewColumnTableView.allowsEmptySelection = YES;
    m_PreviewColumnTableView.allowsMultipleSelection = NO;
    m_PreviewColumnTableView.focusRingType = NSFocusRingTypeNone;
    [m_PreviewColumnTableView addTableColumn:col];

    m_PreviewColumnScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    m_PreviewColumnScrollView.hasVerticalScroller = YES;
    m_PreviewColumnScrollView.hasHorizontalScroller = NO;
    m_PreviewColumnScrollView.autohidesScrollers = YES;
    m_PreviewColumnScrollView.drawsBackground = YES;
    m_PreviewColumnScrollView.backgroundColor = nc::CurrentTheme().FilePanelsBriefRegularEvenRowBackgroundColor();
    m_PreviewColumnScrollView.documentView = m_PreviewColumnTableView;
}

- (NCColumnBrowserTableView *)createAncestorTableViewWithTag:(NSInteger)_tag
{
    const CGFloat column_width = m_Layout.column_width > 0 ? m_Layout.column_width : 200;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.width = column_width;
    col.resizingMask = NSTableColumnNoResizing;

    NCColumnBrowserTableView *tv = [[NCColumnBrowserTableView alloc] initWithFrame:NSZeroRect];
    tv.headerView = nil;
    tv.rowHeight = g_RowHeight;
    tv.intercellSpacing = NSMakeSize(0, 0);
    tv.usesAlternatingRowBackgroundColors = YES;
    tv.style = NSTableViewStyleFullWidth;
    tv.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    tv.dataSource = self;
    tv.delegate = self;
    tv.tag = _tag;
    tv.allowsEmptySelection = YES;
    tv.allowsMultipleSelection = NO;
    tv.focusRingType = NSFocusRingTypeNone;
    [tv addTableColumn:col];
    return tv;
}

#pragma mark - Layout

- (void)rebuildColumns
{
    dispatch_assert_main_queue();

    // Remove all existing column views from the container
    for( NSView *sub in [m_ColumnsContainer.subviews copy] )
        [sub removeFromSuperview];

    m_AncestorColumnScrollViews.clear();
    m_AncestorColumnTableViews.clear();

    const CGFloat column_width = m_Layout.column_width > 0 ? m_Layout.column_width : 200;
    const bool has_preview = m_PreviewColumn.has_value();
    const CGFloat total_columns = static_cast<CGFloat>(m_AncestorColumns.size() + 1 + (has_preview ? 1 : 0));
    const CGFloat total_width = total_columns * (column_width + g_ColumnDividerWidth);
    const CGFloat container_height = m_HorizontalScrollView.contentSize.height;

    m_ColumnsContainer.frame = NSMakeRect(0, 0, std::max(total_width, m_HorizontalScrollView.contentSize.width),
                                          container_height);

    CGFloat x = 0;

    // Create ancestor columns left to right
    for( size_t i = 0; i < m_AncestorColumns.size(); ++i ) {
        NCColumnBrowserTableView *tv = [self createAncestorTableViewWithTag:static_cast<NSInteger>(i)];
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(x, 0, column_width, container_height)];
        sv.hasVerticalScroller = YES;
        sv.hasHorizontalScroller = NO;
        sv.autohidesScrollers = YES;
        sv.drawsBackground = YES;
        sv.backgroundColor = nc::CurrentTheme().FilePanelsBriefRegularEvenRowBackgroundColor();
        sv.documentView = tv;

        [m_ColumnsContainer addSubview:sv];
        m_AncestorColumnScrollViews.push_back(sv);
        m_AncestorColumnTableViews.push_back(tv);

        [tv reloadData];

        // Set the initial selection for the highlighted entry
        const auto &ancestor = m_AncestorColumns[i];
        if( ancestor.highlighted_row >= 0 ) {
            [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:ancestor.highlighted_row]
                byExtendingSelection:NO];
            [tv scrollRowToVisible:ancestor.highlighted_row];
        }

        x += column_width;

        // Draw a divider
        NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(x, 0, g_ColumnDividerWidth, container_height)];
        divider.boxType = NSBoxSeparator;
        [m_ColumnsContainer addSubview:divider];
        x += g_ColumnDividerWidth;
    }

    // Place the active column
    m_ActiveColumnScrollView.frame = NSMakeRect(x, 0, column_width, container_height);
    [m_ColumnsContainer addSubview:m_ActiveColumnScrollView];
    [m_ActiveColumnTableView reloadData];
    x += column_width;

    // Place the preview column if we have preview data
    if( has_preview ) {
        NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(x, 0, g_ColumnDividerWidth, container_height)];
        divider.boxType = NSBoxSeparator;
        [m_ColumnsContainer addSubview:divider];
        x += g_ColumnDividerWidth;

        m_PreviewColumnScrollView.frame = NSMakeRect(x, 0, column_width, container_height);
        [m_ColumnsContainer addSubview:m_PreviewColumnScrollView];
        [m_PreviewColumnTableView reloadData];
    }

    // Scroll to show the active column + preview column
    if( has_preview && m_PreviewColumnScrollView.superview == m_ColumnsContainer ) {
        // Show a rect spanning active + preview so both are visible
        NSRect visible_rect = NSUnionRect(m_ActiveColumnScrollView.frame, m_PreviewColumnScrollView.frame);
        [m_ColumnsContainer scrollRectToVisible:visible_rect];
    }
    else {
        [m_ColumnsContainer scrollRectToVisible:m_ActiveColumnScrollView.frame];
    }

    m_ColumnsBuilt = true;

    // Restore cursor selection in active column
    if( m_CursorPosition >= 0 && m_Data &&
        m_CursorPosition < static_cast<int>(m_Data->SortedDirectoryEntries().size()) ) {
        [m_ActiveColumnTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:m_CursorPosition]
                             byExtendingSelection:NO];
        [m_ActiveColumnTableView scrollRowToVisible:m_CursorPosition];
    }
}

- (void)highlightEntryInAncestorColumn:(size_t)_col_index
{
    if( _col_index >= m_AncestorColumns.size() )
        return;

    const auto &ancestor = m_AncestorColumns[_col_index];
    NCColumnBrowserTableView *tv = m_AncestorColumnTableViews[_col_index];

    if( ancestor.highlighted_entry.empty() || !ancestor.listing )
        return;

    // Find the row for the highlighted entry in the sorted indices
    for( size_t i = 0; i < ancestor.sorted_indices.size(); ++i ) {
        if( ancestor.listing->Filename(ancestor.sorted_indices[i]) == ancestor.highlighted_entry ) {
            [tv selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [tv scrollRowToVisible:static_cast<NSInteger>(i)];
            return;
        }
    }
}

#pragma mark - Ancestor Column Loading

- (void)loadAncestorColumnsAsync
{
    if( !m_Data || !m_Data->Listing().HasCommonHost() )
        return;
    const auto &listing = m_Data->Listing();
    if( !listing.IsUniform() )
        return;

    // Capture what we need from m_Data on the main thread
    auto host = listing.Host();
    std::string current_dir = m_Data->DirectoryPathWithTrailingSlash();
    bool show_hidden = m_Data->HardFiltering().show_hidden;

    __weak NCPanelColumnBrowserView *weak_self = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        auto ancestors = [NCPanelColumnBrowserView fetchAncestorsForDir:current_dir
                                                                   host:host
                                                             showHidden:show_hidden];
        dispatch_async(dispatch_get_main_queue(), ^{
            if( auto strong_self = weak_self ) {
                strong_self->m_AncestorColumns = std::move(ancestors);
                [strong_self rebuildColumns];
            }
        });
    });
}

+ (void)buildSortedIndices:(AncestorColumn &)_col showHidden:(bool)_show_hidden
{
    const auto &listing = *_col.listing;
    const auto count = listing.Count();
    _col.sorted_indices.clear();
    _col.sorted_indices.reserve(count);

    for( unsigned i = 0; i < count; ++i ) {
        if( !_show_hidden && listing.IsHidden(i) )
            continue;
        _col.sorted_indices.push_back(i);
    }

    // Sort: directories first, then alphabetically by name (case-insensitive)
    std::sort(_col.sorted_indices.begin(), _col.sorted_indices.end(), [&listing](unsigned a, unsigned b) {
        const bool a_dir = listing.IsDir(a);
        const bool b_dir = listing.IsDir(b);
        if( a_dir != b_dir )
            return a_dir; // directories first

        const auto &a_name = listing.Filename(a);
        const auto &b_name = listing.Filename(b);
        return strcasecmp(a_name.c_str(), b_name.c_str()) < 0;
    });

    // Pre-compute highlighted row index
    _col.highlighted_row = -1;
    if( !_col.highlighted_entry.empty() ) {
        for( size_t i = 0; i < _col.sorted_indices.size(); ++i ) {
            if( listing.Filename(_col.sorted_indices[i]) == _col.highlighted_entry ) {
                _col.highlighted_row = static_cast<int>(i);
                break;
            }
        }
    }
}

+ (std::vector<AncestorColumn>)fetchAncestorsForDir:(const std::string &)_current_dir
                                                host:(const std::shared_ptr<VFSHost> &)_host
                                          showHidden:(bool)_show_hidden
{
    std::vector<AncestorColumn> ancestors;
    std::string child_name;

    // Extract the current directory's name for the first parent's highlight
    {
        std::string trimmed = _current_dir;
        if( trimmed.size() > 1 && trimmed.back() == '/' )
            trimmed.pop_back();
        auto pos = trimmed.rfind('/');
        if( pos != std::string::npos )
            child_name = trimmed.substr(pos + 1);
    }

    std::string walk_dir = _current_dir;
    while( true ) {
        if( walk_dir == "/" || walk_dir.empty() )
            break;

        // Strip trailing slash, then find parent
        std::string trimmed = walk_dir;
        if( trimmed.size() > 1 && trimmed.back() == '/' )
            trimmed.pop_back();
        auto pos = trimmed.rfind('/');
        if( pos == std::string::npos )
            break;

        std::string parent_dir = trimmed.substr(0, pos + 1); // includes trailing /

        auto result = _host->FetchDirectoryListing(parent_dir, VFSFlags::F_NoDotDot);
        if( !result || !*result )
            break;

        AncestorColumn col;
        col.listing = std::move(*result);
        col.path = parent_dir;
        col.highlighted_entry = child_name;
        [self buildSortedIndices:col showHidden:_show_hidden];
        ancestors.push_back(std::move(col));

        // Prepare for next level up
        child_name = trimmed.substr(pos + 1);
        walk_dir = parent_dir;
    }

    // Reverse so root is leftmost
    std::reverse(ancestors.begin(), ancestors.end());
    return ancestors;
}

#pragma mark - Protocol Implementation

- (void)dealloc
{
    if( m_PanelView )
        [m_PanelView removeObserver:self forKeyPath:@"active"];
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    if( PanelView *panel_view = nc::objc_cast<PanelView>(self.superview) ) {
        m_PanelView = panel_view;
        [panel_view addObserver:self forKeyPath:@"active" options:0 context:nullptr];
        m_PanelActive = panel_view.active;
    }
}

- (void)observeValueForKeyPath:(NSString *)_key_path
                      ofObject:(id)_object
                        change:(NSDictionary *)_change
                       context:(void *)_context
{
    if( [_key_path isEqualToString:@"active"] ) {
        m_PanelActive = m_PanelView.active;
        [self updateSelectionEmphasis];
    }
}

- (void)updateSelectionEmphasis
{
    // Update the active column's row views and force redraw
    [m_ActiveColumnTableView enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rv, [[maybe_unused]] NSInteger row) {
        if( auto *crv = nc::objc_cast<NCColumnBrowserRowView>(rv) ) {
            crv.forceEmphasized = m_PanelActive;
            [crv setNeedsDisplay:YES];
        }
    }];
}

- (int)itemsInColumn
{
    return 1;
}

- (int)maxNumberOfVisibleItems
{
    if( !m_Data )
        return 0;
    const auto height = self.bounds.size.height;
    return std::max(1, static_cast<int>(height / g_RowHeight));
}

- (int)cursorPosition
{
    return m_CursorPosition;
}

- (void)setCursorPosition:(int)_cursor_position
{
    Log::Trace("[PanelColumnBrowserView setCursorPosition:{}]", _cursor_position);
    m_CursorPosition = _cursor_position;

    if( !m_Data )
        return;

    if( _cursor_position >= 0 &&
        _cursor_position < static_cast<int>(m_Data->SortedDirectoryEntries().size()) ) {
        [m_ActiveColumnTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:_cursor_position]
                             byExtendingSelection:NO];
        [m_ActiveColumnTableView scrollRowToVisible:_cursor_position];
    }
    else {
        [m_ActiveColumnTableView deselectAll:nil];
    }

    [self updatePreviewForCursorPosition];
}

- (void)onDataChanged
{
    Log::Trace("[PanelColumnBrowserView dataChanged]");
    dispatch_assert_main_queue();
    assert(m_Data);

    // Reset preview to empty (column stays visible but blank until cursor triggers a new fetch)
    if( m_PreviewCancelFlag )
        m_PreviewCancelFlag->store(true);
    m_PreviewColumn = PreviewColumn{};

    // Show the active column immediately, then load ancestors in background
    [self rebuildColumns];
    [self loadAncestorColumnsAsync];
}

- (void)onVolatileDataChanged
{
    Log::Trace("[PanelColumnBrowserView onVolatileDataChanged]");
    dispatch_assert_main_queue();
}

- (void)onDataSortingHasChanged
{
    Log::Trace("[PanelColumnBrowserView onDataSortingHasChanged]");
    dispatch_assert_main_queue();
    // Sorting changed — rebuild ancestors with new sort settings
    [self loadAncestorColumnsAsync];
}

- (void)setData:(data::Model *)_data
{
    Log::Trace("[PanelColumnBrowserView setData:{}]", static_cast<void *>(_data));
    m_Data = _data;

    // When data is first set (during layout switch), trigger a full build.
    // onDataChanged won't fire because the data hasn't "changed" — it was just assigned.
    if( m_Data && !m_ColumnsBuilt ) {
        m_PreviewColumn = PreviewColumn{}; // always have a preview column
        [self rebuildColumns];
        [self loadAncestorColumnsAsync];
    }
}

- (bool)isItemVisible:(int)_sorted_item_index
{
    if( !m_Data || _sorted_item_index < 0 ||
        _sorted_item_index >= static_cast<int>(m_Data->SortedDirectoryEntries().size()) )
        return false;

    const auto visible_rect = m_ActiveColumnScrollView.documentVisibleRect;
    const auto row_rect = [m_ActiveColumnTableView rectOfRow:_sorted_item_index];
    return NSIntersectsRect(visible_rect, row_rect);
}

- (void)setupFieldEditor:(NCPanelViewFieldEditor *)_editor forItemAtIndex:(int)_sorted_item_index
{
    // TODO: Phase 2
}

- (std::optional<NSRect>)frameOfItemAtIndex:(int)_sorted_item_index
{
    if( _sorted_item_index < 0 || !m_Data ||
        _sorted_item_index >= static_cast<int>(m_Data->SortedDirectoryEntries().size()) )
        return std::nullopt;

    NSRect row_rect = [m_ActiveColumnTableView rectOfRow:_sorted_item_index];
    return [self convertRect:row_rect fromView:m_ActiveColumnTableView];
}

- (PanelColumnBrowserLayout)columnBrowserLayout
{
    return m_Layout;
}

- (void)setColumnBrowserLayout:(nc::panel::PanelColumnBrowserLayout)_layout
{
    m_Layout = _layout;
    if( m_Data )
        [self rebuildColumns];
}

- (BOOL)isOpaque
{
    return YES;
}

- (PanelView *)panelView
{
    return m_PanelView;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)_table_view
{
    const auto tag = _table_view.tag;
    if( tag == -1 ) {
        // Active column
        return m_Data ? static_cast<NSInteger>(m_Data->SortedDirectoryEntries().size()) : 0;
    }
    else if( tag == g_PreviewColumnTag ) {
        // Preview column
        return m_PreviewColumn ? static_cast<NSInteger>(m_PreviewColumn->sorted_indices.size()) : 0;
    }
    else {
        // Ancestor column — use sorted/filtered indices
        const auto idx = static_cast<size_t>(tag);
        if( idx < m_AncestorColumns.size() )
            return static_cast<NSInteger>(m_AncestorColumns[idx].sorted_indices.size());
        return 0;
    }
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)_table_view viewForTableColumn:(NSTableColumn *)_column row:(NSInteger)_row
{
    const auto tag = _table_view.tag;
    NSString *cell_id = (tag == -1) ? g_ActiveCellID : (tag == g_PreviewColumnTag ? g_PreviewCellID : g_AncestorCellID);

    NSTableCellView *cell = [_table_view makeViewWithIdentifier:cell_id owner:nil];
    if( !cell ) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = cell_id;

        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.translatesAutoresizingMaskIntoConstraints = false;
        tf.font = nc::CurrentTheme().FilePanelsBriefFont();
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.cell.truncatesLastVisibleLine = YES;
        [cell addSubview:tf];
        cell.textField = tf;

        [NSLayoutConstraint activateConstraints:@[
            [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    NSString *filename = @"";

    if( tag == -1 && m_Data ) {
        // Active column
        if( VFSListingItem item = m_Data->EntryAtSortPosition(static_cast<int>(_row)) )
            filename = item.FilenameNS();
    }
    else if( tag == g_PreviewColumnTag && m_PreviewColumn ) {
        // Preview column
        if( static_cast<size_t>(_row) < m_PreviewColumn->sorted_indices.size() ) {
            const auto raw_idx = m_PreviewColumn->sorted_indices[static_cast<size_t>(_row)];
            filename = [NSString stringWithUTF8StdString:m_PreviewColumn->listing->Filename(raw_idx)];
        }
    }
    else {
        // Ancestor column
        const auto idx = static_cast<size_t>(tag);
        if( idx < m_AncestorColumns.size() && m_AncestorColumns[idx].listing ) {
            const auto &col = m_AncestorColumns[idx];
            if( static_cast<size_t>(_row) < col.sorted_indices.size() ) {
                const auto raw_idx = col.sorted_indices[static_cast<size_t>(_row)];
                filename = [NSString stringWithUTF8StdString:col.listing->Filename(raw_idx)];
            }
        }
    }

    cell.textField.stringValue = filename;
    cell.textField.textColor = [NSColor labelColor];

    return cell;
}

- (NSTableRowView *)tableView:(NSTableView *)_table_view rowViewForRow:(NSInteger)_row
{
    NCColumnBrowserRowView *row_view = [[NCColumnBrowserRowView alloc] init];
    // Active column gets blue emphasis when panel is active; ancestor columns always grey (like Finder)
    row_view.forceEmphasized = (_table_view.tag == -1) && m_PanelActive;
    return row_view;
}

- (void)tableViewSelectionDidChange:(NSNotification *)_notification
{
    NSTableView *tv = _notification.object;
    if( tv.tag != -1 )
        return; // ignore ancestor column selection changes

    const auto row = tv.selectedRow;
    if( row >= 0 && row != m_CursorPosition ) {
        // Notify PanelView of cursor position change via mouse click
        [m_PanelView panelItem:static_cast<int>(row) mouseDown:[NSApp currentEvent]];
    }
}

#pragma mark - Preview Column

- (void)updatePreviewForCursorPosition
{
    // Cancel any in-flight preview fetch
    if( m_PreviewCancelFlag )
        m_PreviewCancelFlag->store(true);

    if( !m_Data || m_CursorPosition < 0 ) {
        [self clearPreview];
        return;
    }

    VFSListingItem item = m_Data->EntryAtSortPosition(m_CursorPosition);
    if( !item || !item.IsDir() || item.IsDotDot() ) {
        // Not a directory — show an empty preview column (placeholder)
        m_PreviewColumn = PreviewColumn{};
        [self rebuildPreviewColumn];
        return;
    }

    // Capture what we need for the async fetch
    std::string dir_path = item.Path();
    if( dir_path.back() != '/' )
        dir_path += '/';
    auto host = item.Host();
    bool show_hidden = m_Data->HardFiltering().show_hidden;

    // Create a new cancellation flag for this fetch
    auto cancel_flag = std::make_shared<std::atomic<bool>>(false);
    m_PreviewCancelFlag = cancel_flag;

    __weak NCPanelColumnBrowserView *weak_self = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if( cancel_flag->load() )
            return;

        VFSCancelChecker checker = [cancel_flag] { return cancel_flag->load(); };
        auto result = host->FetchDirectoryListing(dir_path, VFSFlags::F_NoDotDot, checker);

        if( cancel_flag->load() || !result || !*result )
            return;

        // Build sorted indices on the background thread
        PreviewColumn preview;
        preview.listing = std::move(*result);
        preview.path = dir_path;

        const auto &listing = *preview.listing;
        const auto count = listing.Count();
        preview.sorted_indices.reserve(count);
        for( unsigned i = 0; i < count; ++i ) {
            if( !show_hidden && listing.IsHidden(i) )
                continue;
            preview.sorted_indices.push_back(i);
        }
        std::sort(preview.sorted_indices.begin(), preview.sorted_indices.end(),
                  [&listing](unsigned a, unsigned b) {
                      const bool a_dir = listing.IsDir(a);
                      const bool b_dir = listing.IsDir(b);
                      if( a_dir != b_dir )
                          return a_dir;
                      return strcasecmp(listing.Filename(a).c_str(), listing.Filename(b).c_str()) < 0;
                  });

        if( cancel_flag->load() )
            return;

        dispatch_async(dispatch_get_main_queue(), ^{
            if( cancel_flag->load() )
                return;
            auto strong_self = weak_self;
            if( !strong_self )
                return;

            strong_self->m_PreviewColumn = std::move(preview);
            [strong_self rebuildPreviewColumn];
        });
    });
}

- (void)clearPreview
{
    if( m_PreviewCancelFlag )
        m_PreviewCancelFlag->store(true);

    if( m_PreviewColumn ) {
        m_PreviewColumn.reset();
        [m_PreviewColumnScrollView removeFromSuperview];
        // Shrink the container
        const CGFloat column_width = m_Layout.column_width > 0 ? m_Layout.column_width : 200;
        const CGFloat total_columns = static_cast<CGFloat>(m_AncestorColumns.size() + 1);
        const CGFloat total_width = total_columns * (column_width + g_ColumnDividerWidth);
        m_ColumnsContainer.frame = NSMakeRect(0, 0,
                                              std::max(total_width, m_HorizontalScrollView.contentSize.width),
                                              m_HorizontalScrollView.contentSize.height);
    }
}

- (void)rebuildPreviewColumn
{
    dispatch_assert_main_queue();

    if( !m_PreviewColumn ) {
        [m_PreviewColumnScrollView removeFromSuperview];
        return;
    }

    const CGFloat column_width = m_Layout.column_width > 0 ? m_Layout.column_width : 200;
    const CGFloat container_height = m_HorizontalScrollView.contentSize.height;

    // Calculate where the preview column goes (after active column + divider)
    const CGFloat active_end = m_ActiveColumnScrollView.frame.origin.x + m_ActiveColumnScrollView.frame.size.width;

    // Ensure container is wide enough
    const CGFloat needed_width = active_end + g_ColumnDividerWidth + column_width;
    if( m_ColumnsContainer.frame.size.width < needed_width )
        m_ColumnsContainer.frame = NSMakeRect(0, 0,
                                              std::max(needed_width, m_HorizontalScrollView.contentSize.width),
                                              container_height);

    // Add divider if not already there
    // (simple approach: just place it fresh each time)
    CGFloat x = active_end;

    // Check if preview scroll view is already in the container
    if( m_PreviewColumnScrollView.superview != m_ColumnsContainer ) {
        NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(x, 0, g_ColumnDividerWidth, container_height)];
        divider.boxType = NSBoxSeparator;
        [m_ColumnsContainer addSubview:divider];
        [m_ColumnsContainer addSubview:m_PreviewColumnScrollView];
    }

    x += g_ColumnDividerWidth;
    m_PreviewColumnScrollView.frame = NSMakeRect(x, 0, column_width, container_height);
    [m_PreviewColumnTableView reloadData];

    // Scroll to ensure the preview column is visible
    NSRect visible_rect = NSUnionRect(m_ActiveColumnScrollView.frame, m_PreviewColumnScrollView.frame);
    [m_ColumnsContainer scrollRectToVisible:visible_rect];
}

#pragma mark - Column Navigation (Left/Right)

- (bool)onMoveLeft:(NSEvent *)_event
{
    // Left arrow = go to parent directory (same as Backspace)
    NCPanelControllerActionsDispatcher *dispatcher = m_PanelView.actionsDispatcher;
    if( dispatcher )
        [dispatcher OnGoToUpperDirectory:_event];
    return true;
}

- (bool)onMoveRight:(NSEvent *)_event
{
    // Right arrow = enter directory (same as Enter, but only for directories)
    if( !m_Data || m_CursorPosition < 0 )
        return true;

    if( VFSListingItem item = m_Data->EntryAtSortPosition(m_CursorPosition) ) {
        if( item.IsDir() ) {
            NCPanelControllerActionsDispatcher *dispatcher = m_PanelView.actionsDispatcher;
            if( dispatcher )
                [dispatcher OnGoIntoDirectory:_event];
        }
    }
    return true;
}

#pragma mark - Scrolling

- (void)onPageUp:(NSEvent *)_event
{
    const auto visible = [self maxNumberOfVisibleItems];
    if( m_CursorPosition > 0 ) {
        const int new_pos = std::max(0, m_CursorPosition - visible);
        [m_PanelView panelItem:new_pos mouseDown:_event];
    }
}

- (void)onPageDown:(NSEvent *)_event
{
    if( !m_Data )
        return;
    const auto visible = [self maxNumberOfVisibleItems];
    const auto count = static_cast<int>(m_Data->SortedDirectoryEntries().size());
    if( m_CursorPosition < count - 1 ) {
        const int new_pos = std::min(count - 1, m_CursorPosition + visible);
        [m_PanelView panelItem:new_pos mouseDown:_event];
    }
}

- (void)onScrollToBeginning:(NSEvent *)_event
{
    if( m_Data && !m_Data->SortedDirectoryEntries().empty() )
        [m_PanelView panelItem:0 mouseDown:_event];
}

- (void)onScrollToEnd:(NSEvent *)_event
{
    if( !m_Data )
        return;
    const auto count = static_cast<int>(m_Data->SortedDirectoryEntries().size());
    if( count > 0 )
        [m_PanelView panelItem:count - 1 mouseDown:_event];
}

@end
