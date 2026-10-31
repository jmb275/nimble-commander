// Copyright (C) 2026 Justin Bradley. Subject to GNU General Public License version 3.
#include "Tests.h"
#include <NimbleCommander/Core/ServicesHandler.h>
#include <NimbleCommander/States/FilePanels/PanelController.h>
#include <Config/ConfigImpl.h>
#include <Config/NonPersistentOverwritesStorage.h>

// Only implement the selectors used by ServicesHandler, without opening AppKit windows.
@interface ServicesHandlerTestPanel : NSObject
@property(nonatomic) std::shared_ptr<nc::panel::DirectoryChangeRequest> request;
- (std::expected<void, nc::Error>)GoToDirWithContext:(std::shared_ptr<nc::panel::DirectoryChangeRequest>)_request;
@end

@implementation ServicesHandlerTestPanel
@synthesize request;
- (std::expected<void, nc::Error>)GoToDirWithContext:(std::shared_ptr<nc::panel::DirectoryChangeRequest>)_request
{
    self.request = std::move(_request);
    return {};
}
@end

@interface ServicesHandlerTestHolder : NSObject
@property(nonatomic) NSObject *tab;
@end

@implementation ServicesHandlerTestHolder
@synthesize tab;
- (NSTabView *)tabView
{
    return static_cast<NSTabView *>(static_cast<id>(self.tab));
}
@end

@interface ServicesHandlerTestState : NSObject
@property(nonatomic) ServicesHandlerTestPanel *leftPanelController;
@property(nonatomic) ServicesHandlerTestPanel *rightPanelController;
@property(nonatomic) ServicesHandlerTestPanel *activePanelController;
@property(nonatomic) ServicesHandlerTestHolder *leftTabbedHolder;
@property(nonatomic) ServicesHandlerTestHolder *rightTabbedHolder;
@property(nonatomic) NSMutableArray<ServicesHandlerTestPanel *> *createdPanels;
@property(nonatomic) NSTabView *spawnedTab;
@property(nonatomic) bool loadedExistingListing;
@property(nonatomic) bool activated;
@end

@implementation ServicesHandlerTestState
@synthesize leftPanelController, rightPanelController, activePanelController, leftTabbedHolder, rightTabbedHolder;
@synthesize createdPanels, spawnedTab, loadedExistingListing, activated;
- (PanelController *)spawnNewTabInTabView:(NSTabView *)_tab
                     autoDirectoryLoading:(bool)_load
                         activateNewPanel:(bool)_activate
{
    self.spawnedTab = _tab;
    self.loadedExistingListing = _load;
    self.activated = _activate;
    const auto panel = [ServicesHandlerTestPanel new];
    [self.createdPanels addObject:panel];
    if( _tab == self.leftTabbedHolder.tabView )
        self.leftPanelController = panel;
    else if( _tab == self.rightTabbedHolder.tabView )
        self.rightPanelController = panel;
    if( _activate )
        self.activePanelController = panel;
    return static_cast<PanelController *>(static_cast<id>(panel));
}
@end

@interface ServicesHandlerTestWindow : NSObject
@property(nonatomic) ServicesHandlerTestState *filePanelsState;
@end
@implementation ServicesHandlerTestWindow
@synthesize filePanelsState;
@end

namespace {
const auto g_Option = "filePanel.general.openExternalRequestsInNewTab";

class TestNativeHost : public VFSHost
{
public:
    TestNativeHost() : VFSHost("", {}, "test-native") {}
    bool IsNativeFS() const noexcept override { return true; }
    bool IsDirectory(std::string_view _path, unsigned long, const VFSCancelChecker &) override
    {
        return _path == "/example/folder" || _path == "/";
    }
};

struct Fixture {
    nc::config::ConfigImpl config{R"({"filePanel":{"general":{"openExternalRequestsInNewTab":false}}})",
                                  std::make_shared<nc::config::NonPersistentOverwritesStorage>("")};
    std::shared_ptr<TestNativeHost> host = std::make_shared<TestNativeHost>();
    ServicesHandlerTestPanel *left = [ServicesHandlerTestPanel new];
    ServicesHandlerTestPanel *right = [ServicesHandlerTestPanel new];
    ServicesHandlerTestState *state = [ServicesHandlerTestState new];
    ServicesHandlerTestWindow *window = [ServicesHandlerTestWindow new];
    nc::core::ServicesHandler handler{
        [window = window] { return static_cast<NCMainWindowController *>(static_cast<id>(window)); },
        host,
        config};

    Fixture()
    {
        window.filePanelsState = state;
        state.leftPanelController = left;
        state.rightPanelController = right;
        state.activePanelController = left;
        state.leftTabbedHolder = [ServicesHandlerTestHolder new];
        state.rightTabbedHolder = [ServicesHandlerTestHolder new];
        state.leftTabbedHolder.tab = [NSObject new];
        state.rightTabbedHolder.tab = [NSObject new];
        state.createdPanels = [NSMutableArray new];
    }
};
} // namespace

#define PREFIX "ServicesHandler "

TEST_CASE(PREFIX "external requests keep using the current panel by default")
{
    Fixture f;
    f.handler.OpenFiles(@[@"/example/a file.md"]);
    REQUIRE(f.left.request);
    CHECK(f.left.request->RequestedDirectory == "/example");
    CHECK(f.left.request->RequestFocusedEntry == "a file.md");
    CHECK(f.state.createdPanels.count == 0);
    CHECK_FALSE(f.right.request);
}

TEST_CASE(PREFIX "reveals create a tab on the active side without changing either original panel")
{
    Fixture f;
    f.config.Set(g_Option, true);
    const bool right_active = GENERATE(false, true);
    f.state.activePanelController = right_active ? f.right : f.left;
    f.handler.OpenFiles(@[@"/example/a file.md", @"/example/other.md"]);
    REQUIRE(f.state.createdPanels.count == 1);
    const auto panel = f.state.createdPanels[0];
    REQUIRE(panel.request);
    CHECK(panel.request->RequestedDirectory == "/example");
    CHECK(panel.request->RequestFocusedEntry == "a file.md");
    CHECK(panel.request->RequestSelectedEntries == std::vector<std::string>{"a file.md", "other.md"});
    CHECK(panel.request->VFS == f.host);
    CHECK(panel.request->InitiatedByUser);
    CHECK(f.state.spawnedTab == (right_active ? f.state.rightTabbedHolder.tabView : f.state.leftTabbedHolder.tabView));
    CHECK(f.state.activePanelController == panel);
    CHECK(f.state.activated);
    CHECK_FALSE(f.state.loadedExistingListing);
    CHECK_FALSE(f.left.request);
    CHECK_FALSE(f.right.request);
}

TEST_CASE(PREFIX "opening folders uses the same new-tab preference")
{
    Fixture f;
    const bool enabled = GENERATE(false, true);
    f.config.Set(g_Option, enabled);
    f.handler.OpenFiles(@[@"/example/folder"]);
    const auto panel = enabled ? f.state.createdPanels.firstObject : f.left;
    REQUIRE(panel);
    REQUIRE(panel.request);
    CHECK(panel.request->RequestedDirectory == "/example/folder");
    CHECK(panel.request->RequestFocusedEntry.empty());
    CHECK(f.state.createdPanels.count == (enabled ? 1 : 0));
    CHECK_FALSE(f.right.request);
}

TEST_CASE(PREFIX "successive requests preserve earlier tabs and the preference can change without restarting")
{
    Fixture f;
    f.config.Set(g_Option, true);
    f.handler.OpenFiles(@[@"/first/a.md"]);
    f.handler.OpenFiles(@[@"/second/b.md"]);
    REQUIRE(f.state.createdPanels.count == 2);
    CHECK(f.state.createdPanels[0].request->RequestedDirectory == "/first");
    CHECK(f.state.createdPanels[1].request->RequestedDirectory == "/second");
    CHECK_FALSE(f.left.request);
    f.config.Set(g_Option, false);
    f.handler.OpenFiles(@[@"/third/c.md"]);
    CHECK(f.state.createdPanels.count == 2);
    CHECK(f.state.createdPanels[0].request->RequestedDirectory == "/first");
    CHECK(f.state.createdPanels[1].request->RequestedDirectory == "/third");
}

TEST_CASE(PREFIX "empty requests and missing windows or active panels are harmless")
{
    Fixture f;
    f.config.Set(g_Option, true);
    SECTION("empty request")
    {
        f.handler.OpenFiles(@[]);
    }
    SECTION("Cocoa placeholder")
    {
        f.handler.OpenFiles(@[@"YES"]);
    }
    SECTION("missing panel")
    {
        f.state.activePanelController = nil;
        f.handler.OpenFiles(@[@"/example/a.md"]);
    }
    SECTION("missing window")
    {
        nc::core::ServicesHandler handler{[] { return nil; }, f.host, f.config};
        handler.OpenFiles(@[@"/example/a.md"]);
    }
    CHECK(f.state.createdPanels.count == 0);
    CHECK_FALSE(f.left.request);
    CHECK_FALSE(f.right.request);
}
