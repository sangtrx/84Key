#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>

#import "SangKeyPreferences.h"

static NSString * const kRepoReleases = @"https://github.com/sangtrx/SangKey/releases/latest";
static NSString * const kAgentPlist = @"com.sangtrx.sangkey.agent.plist";

@interface SangKeyAppDelegate : NSObject <NSApplicationDelegate>
- (void)rebuildMenu;
@end

static void LauncherPreferencesChanged(CFNotificationCenterRef center,
                                       void *observer,
                                       CFNotificationName name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    (void)center;
    (void)name;
    (void)object;
    (void)userInfo;
    SangKeyAppDelegate *delegate = (__bridge SangKeyAppDelegate *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate rebuildMenu];
    });
}

@implementation SangKeyAppDelegate {
    NSStatusItem *_statusItem;
    NSMenu *_menu;
    SMAppService *_agentService;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    _agentService = [SMAppService agentServiceWithPlistName:kAgentPlist];
    [self ensureAgentRegistered];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)self,
                                    LauncherPreferencesChanged,
                                    SangKeyPreferencesChangedDarwinNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _menu = [NSMenu new];
    _statusItem.menu = _menu;
    [self rebuildMenu];

    // Make the ephemeral control panel discoverable when launched from Finder.
    // The menu can be closed immediately; SangKeyAgent continues independently.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_statusItem.button performClick:nil];
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       SangKeyPreferencesChangedDarwinNotification,
                                       NULL);
}

- (void)ensureAgentRegistered {
    if (_agentService.status != SMAppServiceStatusNotRegistered) return;
    NSError *error = nil;
    if (![_agentService registerAndReturnError:&error]) {
        NSLog(@"SangKey: unable to register agent: %@", error);
    }
}

- (NSString *)agentStatusText {
    switch (_agentService.status) {
        case SMAppServiceStatusEnabled: return @"Bộ gõ nền: Đang bật";
        case SMAppServiceStatusRequiresApproval: return @"Bộ gõ nền: Cần cho phép";
        case SMAppServiceStatusNotRegistered: return @"Bộ gõ nền: Đang tắt";
        case SMAppServiceStatusNotFound: return @"Bộ gõ nền: Không tìm thấy";
    }
    return @"Bộ gõ nền: Không rõ trạng thái";
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    return item;
}

- (NSMenuItem *)toggleItem:(NSString *)title key:(NSString *)key action:(SEL)action {
    NSMenuItem *item = [self item:title action:action];
    item.state = SangKeyPreferenceBool(key) ? NSControlStateValueOn : NSControlStateValueOff;
    return item;
}

- (void)rebuildMenu {
    if (_menu == nil || _statusItem == nil) return;

    NSInteger language = SangKeyPreferenceInteger(@"vLanguage");
    _statusItem.button.title = language == 1 ? @"V" : @"E";
    _statusItem.button.toolTip = @"SangKey Control — có thể đóng mà bộ gõ vẫn chạy";

    [_menu removeAllItems];

    NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:[self agentStatusText] action:nil keyEquivalent:@""];
    status.enabled = NO;
    [_menu addItem:status];

    if (_agentService.status == SMAppServiceStatusRequiresApproval) {
        [_menu addItem:[self item:@"Cho phép chạy nền…" action:@selector(openLoginItems:)]];
    } else if (_agentService.status == SMAppServiceStatusNotRegistered) {
        [_menu addItem:[self item:@"Bật bộ gõ nền" action:@selector(enableAgent:)]];
    } else if (_agentService.status == SMAppServiceStatusEnabled) {
        [_menu addItem:[self item:@"Tắt bộ gõ nền" action:@selector(disableAgent:)]];
    }

    [_menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *vi = [self item:@"Tiếng Việt" action:@selector(useVietnamese:)];
    vi.state = language == 1 ? NSControlStateValueOn : NSControlStateValueOff;
    [_menu addItem:vi];
    NSMenuItem *en = [self item:@"English" action:@selector(useEnglish:)];
    en.state = language == 0 ? NSControlStateValueOn : NSControlStateValueOff;
    [_menu addItem:en];

    NSMenu *inputMenu = [NSMenu new];
    NSArray<NSString *> *inputNames = @[@"Telex", @"VNI", @"Simple Telex 1", @"Simple Telex 2"];
    NSInteger currentInput = SangKeyPreferenceInteger(@"vInputType");
    for (NSInteger index = 0; index < (NSInteger)inputNames.count; index++) {
        NSMenuItem *input = [self item:inputNames[index] action:@selector(selectInputMethod:)];
        input.tag = index;
        input.state = currentInput == index ? NSControlStateValueOn : NSControlStateValueOff;
        [inputMenu addItem:input];
    }
    NSMenuItem *inputRoot = [[NSMenuItem alloc] initWithTitle:@"Kiểu gõ" action:nil keyEquivalent:@""];
    inputRoot.submenu = inputMenu;
    [_menu addItem:inputRoot];

    NSMenu *smartMenu = [NSMenu new];
    [smartMenu addItem:[self toggleItem:@"Tự động nhận diện tiếng Anh" key:@"vAutoDetectEnglish" action:@selector(toggleAutoEnglish:)]];
    [smartMenu addItem:[self toggleItem:@"Kiểm tra chính tả" key:@"vCheckSpelling" action:@selector(toggleSpelling:)]];
    [smartMenu addItem:[self toggleItem:@"Chính tả hiện đại" key:@"vUseModernOrthography" action:@selector(toggleModern:)]];
    NSMenuItem *smartRoot = [[NSMenuItem alloc] initWithTitle:@"Gõ thông minh" action:nil keyEquivalent:@""];
    smartRoot.submenu = smartMenu;
    [_menu addItem:smartRoot];

    NSMenu *compatMenu = [NSMenu new];
    [compatMenu addItem:[self toggleItem:@"Spotlight" key:@"vFixSpotlight" action:@selector(toggleSpotlight:)]];
    [compatMenu addItem:[self toggleItem:@"Trình duyệt / Google Docs" key:@"vFixWebContentEditor" action:@selector(toggleWebEditor:)]];
    NSMenuItem *compatRoot = [[NSMenuItem alloc] initWithTitle:@"Tương thích" action:nil keyEquivalent:@""];
    compatRoot.submenu = compatMenu;
    [_menu addItem:compatRoot];

    [_menu addItem:[NSMenuItem separatorItem]];
    [_menu addItem:[self item:@"Mở quyền Trợ năng…" action:@selector(openAccessibility:)]];
    [_menu addItem:[self item:@"Mở Login Items…" action:@selector(openLoginItems:)]];
    [_menu addItem:[self item:@"Kiểm tra cập nhật…" action:@selector(checkUpdates:)]];

    [_menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *close = [[NSMenuItem alloc] initWithTitle:@"Đóng bảng điều khiển (bộ gõ vẫn chạy)"
                                                   action:@selector(quitControlPanel:)
                                            keyEquivalent:@"q"];
    close.target = self;
    [_menu addItem:close];
}

- (void)setInteger:(NSInteger)value key:(NSString *)key {
    SangKeySetPreferenceInteger(key, value);
    [self rebuildMenu];
}

- (void)setBool:(BOOL)value key:(NSString *)key {
    SangKeySetPreferenceBool(key, value);
    [self rebuildMenu];
}

- (void)useVietnamese:(id)sender { (void)sender; [self setInteger:1 key:@"vLanguage"]; }
- (void)useEnglish:(id)sender { (void)sender; [self setInteger:0 key:@"vLanguage"]; }
- (void)selectInputMethod:(NSMenuItem *)sender { [self setInteger:sender.tag key:@"vInputType"]; }
- (void)toggleAutoEnglish:(id)sender { (void)sender; [self setBool:!SangKeyPreferenceBool(@"vAutoDetectEnglish") key:@"vAutoDetectEnglish"]; }
- (void)toggleSpelling:(id)sender { (void)sender; [self setBool:!SangKeyPreferenceBool(@"vCheckSpelling") key:@"vCheckSpelling"]; }
- (void)toggleModern:(id)sender { (void)sender; [self setBool:!SangKeyPreferenceBool(@"vUseModernOrthography") key:@"vUseModernOrthography"]; }
- (void)toggleSpotlight:(id)sender { (void)sender; [self setBool:!SangKeyPreferenceBool(@"vFixSpotlight") key:@"vFixSpotlight"]; }
- (void)toggleWebEditor:(id)sender { (void)sender; [self setBool:!SangKeyPreferenceBool(@"vFixWebContentEditor") key:@"vFixWebContentEditor"]; }

- (void)enableAgent:(id)sender {
    (void)sender;
    NSError *error = nil;
    if (![_agentService registerAndReturnError:&error]) {
        NSLog(@"SangKey: enable agent failed: %@", error);
    }
    [self rebuildMenu];
}

- (void)disableAgent:(id)sender {
    (void)sender;
    NSError *error = nil;
    if (![_agentService unregisterAndReturnError:&error]) {
        NSLog(@"SangKey: disable agent failed: %@", error);
    }
    [self rebuildMenu];
}

- (void)openAccessibility:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (url != nil) [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openLoginItems:(id)sender {
    (void)sender;
    [SMAppService openSystemSettingsLoginItems];
}

- (void)checkUpdates:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:kRepoReleases];
    if (url != nil) [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)quitControlPanel:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        SangKeyAppDelegate *delegate = [SangKeyAppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
