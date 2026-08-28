#import "SangKeyPreferences.h"

NSString * const SangKeyPreferencesDomain = @"com.sangtrx.sangkey";
CFStringRef const SangKeyPreferencesChangedDarwinNotification = CFSTR("com.sangtrx.sangkey.preferences-changed");

NSDictionary<NSString *, NSNumber *> *SangKeyDefaultPreferences(void) {
    static NSDictionary<NSString *, NSNumber *> *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = @{
            @"agentDesiredEnabled": @1,
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
            @"vUseMacroInEnglishMode": @0,
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
        };
    });
    return defaults;
}

static CFTypeRef CopyPreferenceValue(NSString *key) {
    return CFPreferencesCopyValue((__bridge CFStringRef)key,
                                  (__bridge CFStringRef)SangKeyPreferencesDomain,
                                  kCFPreferencesCurrentUser,
                                  kCFPreferencesAnyHost);
}

NSInteger SangKeyPreferenceInteger(NSString *key) {
    CFTypeRef raw = CopyPreferenceValue(key);
    if (raw != NULL) {
        NSInteger result = 0;
        if (CFGetTypeID(raw) == CFNumberGetTypeID()) {
            result = [(__bridge NSNumber *)raw integerValue];
            CFRelease(raw);
            return result;
        }
        if (CFGetTypeID(raw) == CFBooleanGetTypeID()) {
            result = CFBooleanGetValue((CFBooleanRef)raw) ? 1 : 0;
            CFRelease(raw);
            return result;
        }
        CFRelease(raw);
    }
    NSNumber *fallback = SangKeyDefaultPreferences()[key];
    return fallback != nil ? fallback.integerValue : 0;
}

BOOL SangKeyPreferenceBool(NSString *key) {
    return SangKeyPreferenceInteger(key) != 0;
}

static void SetPreferenceValue(NSString *key, NSNumber *value) {
    CFPreferencesSetValue((__bridge CFStringRef)key,
                          (__bridge CFPropertyListRef)value,
                          (__bridge CFStringRef)SangKeyPreferencesDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)SangKeyPreferencesDomain,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesAnyHost);
    SangKeyPostPreferencesChanged();
}

void SangKeySetPreferenceInteger(NSString *key, NSInteger value) {
    SetPreferenceValue(key, @(value));
}

void SangKeySetPreferenceBool(NSString *key, BOOL value) {
    SetPreferenceValue(key, @(value ? 1 : 0));
}

NSDictionary<NSString *, NSNumber *> *SangKeyCurrentEngineOptions(void) {
    NSArray<NSString *> *keys = @[
        @"vLanguage", @"vInputType", @"vCodeTable", @"vFreeMark",
        @"vCheckSpelling", @"vUseModernOrthography", @"vQuickTelex",
        @"vRestoreIfWrongSpelling", @"vFixRecommendBrowser", @"vFixWebContentEditor",
        @"vUseMacro", @"vUseMacroInEnglishMode", @"vUseSmartSwitchKey",
        @"vUpperCaseFirstChar", @"vAllowConsonantZFWJ", @"vQuickStartConsonant",
        @"vQuickEndConsonant", @"vAutoDetectEnglish", @"vOtherLanguage",
        @"vFixSpotlight", @"vSendKeyStepByStep", @"vFixChromiumBrowser",
        @"vPerformLayoutCompat", @"vSwitchKeyStatus"
    ];
    NSMutableDictionary<NSString *, NSNumber *> *snapshot =
        [NSMutableDictionary dictionaryWithCapacity:keys.count];
    for (NSString *key in keys) {
        snapshot[key] = @(SangKeyPreferenceInteger(key));
    }
    return snapshot;
}

void SangKeyPostPreferencesChanged(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         SangKeyPreferencesChangedDarwinNotification,
                                         NULL,
                                         NULL,
                                         true);
}
