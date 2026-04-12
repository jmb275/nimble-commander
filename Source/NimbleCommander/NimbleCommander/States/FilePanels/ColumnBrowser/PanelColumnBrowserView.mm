// Copyright (C) 2026 Michael Kazakov. Subject to GNU General Public License version 3.
#include "PanelColumnBrowserView.h"
#include "../PanelView.h"
#include <Panel/PanelData.h>
#include <Panel/Log.h>
#include <Utility/ObjCpp.h>

using namespace nc;
using namespace nc::panel;

@implementation NCPanelColumnBrowserView {
    data::Model *m_Data;
    PanelColumnBrowserLayout m_Layout;
    int m_CursorPosition;
    __weak PanelView *m_PanelView;
    vfsicon::IconRepository *m_IconRepository;
}

- (instancetype)initWithFrame:(NSRect)_frame
               iconRepository:(nc::vfsicon::IconRepository &)_ir
{
    self = [super initWithFrame:_frame];
    if( !self )
        return nil;

    m_Data = nullptr;
    m_CursorPosition = -1;
    m_IconRepository = &_ir;

    return self;
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    if( PanelView *panel_view = nc::objc_cast<PanelView>(self.superview) )
        m_PanelView = panel_view;
}

- (int)itemsInColumn
{
    // For column browser, Left/Right navigate between columns, not within items.
    // Return 1 so PanelView's Left/Right handling moves by single items,
    // which we'll override with column navigation later.
    return 1;
}

- (int)maxNumberOfVisibleItems
{
    if( !m_Data )
        return 0;
    // Rough estimate based on view height and a ~20px row height
    const auto height = self.bounds.size.height;
    return std::max(1, static_cast<int>(height / 20.0));
}

- (int)cursorPosition
{
    return m_CursorPosition;
}

- (void)setCursorPosition:(int)_cursor_position
{
    Log::Trace("[PanelColumnBrowserView setCursorPosition:{}]", _cursor_position);
    m_CursorPosition = _cursor_position;
}

- (void)onDataChanged
{
    Log::Trace("[PanelColumnBrowserView dataChanged]");
    dispatch_assert_main_queue();
    [self setNeedsDisplay:YES];
}

- (void)onVolatileDataChanged
{
    Log::Trace("[PanelColumnBrowserView onVolatileDataChanged]");
    dispatch_assert_main_queue();
}

- (void)setData:(data::Model *)_data
{
    Log::Trace("[PanelColumnBrowserView setData:{}]", static_cast<void *>(_data));
    m_Data = _data;
}

- (bool)isItemVisible:(int)_sorted_item_index
{
    if( !m_Data || _sorted_item_index < 0 ||
        _sorted_item_index >= static_cast<int>(m_Data->SortedDirectoryEntries().size()) )
        return false;
    // Stub: report all items as visible for now
    return true;
}

- (void)setupFieldEditor:(NCPanelViewFieldEditor *)_editor forItemAtIndex:(int)_sorted_item_index
{
    // Stub: field editor support will come in Phase 2
}

- (std::optional<NSRect>)frameOfItemAtIndex:(int)_sorted_item_index
{
    // Stub: no per-item frame geometry yet
    return std::nullopt;
}

- (PanelColumnBrowserLayout)columnBrowserLayout
{
    return m_Layout;
}

- (void)setColumnBrowserLayout:(nc::panel::PanelColumnBrowserLayout)_layout
{
    if( m_Layout == _layout )
        return;
    m_Layout = _layout;
    [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque
{
    return YES;
}

- (void)drawRect:(NSRect)_dirty_rect
{
    // Temporary: draw a dark background so we can see the view is active
    [[NSColor colorWithCalibratedWhite:0.15 alpha:1.0] set];
    NSRectFill(_dirty_rect);

    // Draw a label so we know it's working
    NSDictionary *attrs = @{
        NSForegroundColorAttributeName : [NSColor whiteColor],
        NSFontAttributeName : [NSFont systemFontOfSize:14.0]
    };
    NSString *label = @"Column Browser (stub)";
    [label drawAtPoint:NSMakePoint(20, self.bounds.size.height - 30) withAttributes:attrs];
}

- (PanelView *)panelView
{
    return m_PanelView;
}

@end
