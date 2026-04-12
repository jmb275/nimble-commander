// Copyright (C) 2026 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#include "../PanelViewImplementationProtocol.h"
#include "Layout.h"
#include <VFSIcon/IconRepository.h>

@class PanelView;

@interface NCPanelColumnBrowserView : NSView <NCPanelViewPresentationProtocol>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)_frame NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)_frame
               iconRepository:(nc::vfsicon::IconRepository &)_ir;

@property(nonatomic) nc::panel::PanelColumnBrowserLayout columnBrowserLayout;

@property(nonatomic, readonly) PanelView *panelView;

@end
