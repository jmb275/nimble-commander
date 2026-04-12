// Copyright (C) 2026 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#include "../PanelViewImplementationProtocol.h"
#include "Layout.h"
#include <VFSIcon/IconRepository.h>
#include <VFS/VFS.h>

@class PanelView;

// Holds a lightweight snapshot of a single ancestor directory for display in a column.
struct AncestorColumn {
    VFSListingPtr listing;
    std::string path;
    std::string highlighted_entry; // entry name to highlight (child dir we came from)
    std::vector<unsigned> sorted_indices; // sorted + filtered indices into listing
    int highlighted_row = -1; // pre-computed row index for the highlighted entry
};

// Holds the preview column data — directory contents shown to the right of the active column.
struct PreviewColumn {
    VFSListingPtr listing;
    std::string path;
    std::vector<unsigned> sorted_indices;
};

@interface NCPanelColumnBrowserView
    : NSView <NCPanelViewPresentationProtocol, NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)_frame NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)_frame
               iconRepository:(nc::vfsicon::IconRepository &)_ir;

@property(nonatomic) nc::panel::PanelColumnBrowserLayout columnBrowserLayout;

@property(nonatomic, readonly) PanelView *panelView;

@end
