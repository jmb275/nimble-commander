// Copyright (C) 2026 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

namespace nc::panel {

struct PanelColumnBrowserLayout {
    short column_width = 200;
    bool show_icons = true;
    bool operator==(const PanelColumnBrowserLayout &_rhs) const noexcept = default;
};

} // namespace nc::panel
