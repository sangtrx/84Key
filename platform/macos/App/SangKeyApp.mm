#import <Cocoa/Cocoa.h>
#import "InputController.h"

@interface SangKeyAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation SangKeyAppDelegate {
    InputController *_input;
    NSStatusItem *_statusItem;
    NSMenu *_menu;
    NSTimer *_permissionTimer;
    id _languageObserver;
    NSUserDefaults *_defaults;
}

static NSString * const kRepoReleases = @"https://github.com/sangtrx/SangKey/releases/latest";

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    unsetenv("KEY84_TRACE");

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    _defaults = [NSUserDefaults standardUserDefaults];
    [_defaults registerDefaults:@{
        @"vLanguage": @1,
        @"vInputType": @0,
        @"vCodeTable": @0,
        @"vFreeMark": @0,
        @"vCheckSpelling": @1,
        @"vUseModernOrthography": @1,
        @"vQuickTelex": @0,
        @"vRestoreIfWrongSpelling": @0,
        @"vFixRecommendBrowser": @0,
        @"vFixWebContentEditor": @1,
        @"vUseMacro": @0,
        @"vUseSmartSwitchKey": @0,
        @"vUpperCaseFirstChar": @0,
        @"vAllowConsonantZFWJ": @0,
        @"vQuickStartConsonant": @0,
        @"vQuickEndConsonant": @0,
        @"vAutoDetectEnglish": @1,
        @"vOtherLanguage": @0,
        @"vFixSpotlight": @1,
        @"vSendKeyStepByStep": @0,
        @"vFixChromiumBrowser": @0,
        @"vPerformLayoutCompat": @0,
        @"vSwitchKeyStatus": @0x531,
    }];

    _input = [InputController new];
    [self applyAllOptions];
    BOOL dictionariesReady = [_input loadDictionaries];
    NSLog(@"SangKey dictionaries loaded = %@", dictionariesReady ? @"YES" : @"NO");

    __weak SangKeyAppDelegate *weakSelf = self;
    _languageObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:Key84LanguageDidToggleNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        NSNumber *language = note.userInfo[@"language"];
        if (language != nil) {
            [weakSelf->_defaults setInteger:language.integerValue forKey:@"vLanguage"];
            [weakSelf rebuildMenu];
        }
    }];

    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _menu = [NSMenu new];
    _statusItem.menu = _menu;

    [self tryStartInput];
    [self rebuildMenu];

    if (![_input isRunning]) {
        [self presentAccessibilityAlert];
        [self startPermissionPolling];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [_permissionTimer invalidate];
    _permissionTimer = nil;
    if (_languageObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:_languageObserver];
        _languageObserver = nil;
    }
    [_input stop];
}

- (void)applyAllOptions {
    NSArray<NSString *> *keys = @[
        @"vLanguage", @"vInputType", @"vCodeTable", @"vFreeMark",
        @"vCheckSpelling", @"vUseModernOrthography", @"vQuickTelex",
        @"vRestoreIfWrongSpelling", @"vFixRecommendBrowser", @"vFixWebContentEditor",
        @"vUseMacro", @"vUseSmartSwitchKey", @"vUpperCaseFirstChar",
        @"vAllowConsonantZFWJ", @"vQuickStartConsonant", @"vQuickEndConsonant",
        @"vAutoDetectEnglish", @"vOtherLanguage", @"vFixSpotlight",
        @"vSendKeyStepByStep", @"vFixChromiumBrowser", @"vPerformLayoutCompat",
        @"vSwitchKeyStatus"
    ];
    NSMutableDictionary<NSString *, NSNumber *> *options = [NSMutableDictionary dictionaryWithCapacity:keys.count];
    for (NSString *key in keys) {
        options[key] = @([_defaults integerForKey:key]);
    }
    [_input applyEngineOptions:options];
}

- (void)setEngineInteger:(NSInteger)value key:(NSString *)key {
    [_defaults setInteger:value forKey:key];
    [_input applyEngineOptions:@{key: @(value)}];
    [self rebuildMenu];
}

- (void)setEngineBool:(BOOL)value key:(NSString *)key {
    [self setEngineInteger:(value ? 1 : 0) key:key];
}

- (void)tryStartInput {
    if (![_input isRunning]) {
        [_input start];
    }
    if ([_input isRunning]) {
        [_permissionTimer invalidate];
        _permissionTimer = nil;
    }
}

- (void)startPermissionPolling {
    if (_permissionTimer != nil) return;
    _permissionTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(permissionTick:)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)permissionTick:(NSTimer *)timer {
    (void)timer;
    BOOL wasRunning = [_input isRunning];
    [self tryStartInput];
    if (!wasRunning || [_input isRunning]) {
        [self rebuildMenu];
    }
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    return item;
}

- (NSMenuItem *)toggleItem:(NSString *)title key:(NSString *)key action:(SEL)action {
    NSMenuItem *item = [self item:title action:action];
    item.state = [_defaults boolForKey:key] ? NSControlStateValueOn : NSControlStateValueOff;
    return item;
}

- (void)rebuildMenu {
    if (_menu == nil || _statusItem == nil) return;

    NSInteger language = [_defaults integerForKey:@"vLanguage"];
    BOOL running = [_input isRunning];
    _statusItem.button.title = running ? (language == 1 ? @"V" : @"E") : @"!";
    _statusItem.button.toolTip = running ? @"SangKey" : @"SangKey cần quyền Trợ năng";

    [_menu removeAllItems];
    if (!running) {
        [_menu addItem:[self item:@"Cần quyền Trợ năng…" action:@selector(openAccessibility:)]];
        [_menu addItem:[NSMenuItem separatorItem]];
    }

    NSMenuItem *vi = [self item:@"Tiếng Việt" action:@selector(useVietnamese:)];
    vi.state = language == 1 ? NSControlStateValueOn : NSControlStateValueOff;
    [_menu addItem:vi];
    NSMenuItem *en = [self item:@"English" action:@selector(useEnglish:)];
    en.state = language == 0 ? NSControlStateValueOn : NSControlStateValueOff;
    [_menu addItem:en];

    [_menu addItem:[NSMenuItem separatorItem]];

    NSMenu *inputMenu = [NSMenu new];
    NSArray<NSString *> *inputNames = @[@"Telex", @"VNI", @"Simple Telex 1", @"Simple Telex 2"];
    NSInteger currentInput = [_defaults integerForKey:@"vInputType"];
    for (NSInteger index = 0; index < (NSInteger)inputNames.count; index++) {
        NSMenuItem *item = [self item:inputNames[index] action:@selector(selectInputMethod:)];
        item.tag = index;
        item.state = currentInput == index ? NSControlStateValueOn : NSControlStateValueOff;
        [inputMenu addItem:item];
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
    [_menu addItem:[self item:@"Kiểm tra cập nhật…" action:@selector(checkUpdates:)]];
    [_menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Thoát SangKey" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [_menu addItem:quit];
}

- (void)presentAccessibilityAlert {
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"Cho phép SangKey xử lý bàn phím";
    alert.informativeText = @"SangKey cần quyền Trợ năng để gõ tiếng Việt trên toàn hệ thống. Nội dung gõ được xử lý cục bộ và không gửi ra mạng.";
    [alert addButtonWithTitle:@"Mở Cài đặt Trợ năng"];
    [alert addButtonWithTitle:@"Để sau"];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self openAccessibility:nil];
    }
}

- (void)useVietnamese:(id)sender { (void)sender; [self setEngineInteger:1 key:@"vLanguage"]; }
- (void)useEnglish:(id)sender { (void)sender; [self setEngineInteger:0 key:@"vLanguage"]; }
- (void)selectInputMethod:(NSMenuItem *)sender { [self setEngineInteger:sender.tag key:@"vInputType"]; }
- (void)toggleAutoEnglish:(id)sender { (void)sender; [self setEngineBool:![_defaults boolForKey:@"vAutoDetectEnglish"] key:@"vAutoDetectEnglish"]; }
- (void)toggleSpelling:(id)sender { (void)sender; [self setEngineBool:![_defaults boolForKey:@"vCheckSpelling"] key:@"vCheckSpelling"]; }
- (void)toggleModern:(id)sender { (void)sender; [self setEngineBool:![_defaults boolForKey:@"vUseModernOrthography"] key:@"vUseModernOrthography"]; }
- (void)toggleSpotlight:(id)sender { (void)sender; [self setEngineBool:![_defaults boolForKey:@"vFixSpotlight"] key:@"vFixSpotlight"]; }
- (void)toggleWebEditor:(id)sender { (void)sender; [self setEngineBool:![_defaults boolForKey:@"vFixWebContentEditor"] key:@"vFixWebContentEditor"]; }

- (void)openAccessibility:(id)sender {
    (void)sender;
    [_input requestAccessibilityPermission];
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (url != nil) [[NSWorkspace sharedWorkspace] openURL:url];
    [self startPermissionPolling];
}

- (void)checkUpdates:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:kRepoReleases];
    if (url != nil) [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)quit:(id)sender {
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
