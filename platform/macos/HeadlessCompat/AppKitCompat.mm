#import "Cocoa/Cocoa.h"

#import <Carbon/Carbon.h>
#import <Security/Security.h>

namespace {

NSString *SigningIdentifierForPID(pid_t pid) {
    if (pid <= 0) return nil;

    NSDictionary *attributes = @{
        (__bridge NSString *)kSecGuestAttributePid: @(pid)
    };
    SecCodeRef code = NULL;
    OSStatus guestStatus = SecCodeCopyGuestWithAttributes(NULL,
                                                           (__bridge CFDictionaryRef)attributes,
                                                           kSecCSDefaultFlags,
                                                           &code);
    if (guestStatus != errSecSuccess || code == NULL) return nil;

    CFDictionaryRef information = NULL;
    OSStatus infoStatus = SecCodeCopySigningInformation(code,
                                                         kSecCSSigningInformation,
                                                         &information);
    CFRelease(code);
    if (infoStatus != errSecSuccess || information == NULL) return nil;

    NSString *identifier = [(__bridge NSDictionary *)information objectForKey:(__bridge NSString *)kSecCodeInfoIdentifier];
    NSString *result = [identifier copy];
    CFRelease(information);
    return result;
}

NSString *CharactersIgnoringModifiers(CGEventRef event) {
    if (event == NULL) return nil;

    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    if (source == NULL) return nil;

    CFDataRef layoutData = (CFDataRef)TISGetInputSourceProperty(source,
                                                                kTISPropertyUnicodeKeyLayoutData);
    if (layoutData == NULL || CFDataGetLength(layoutData) == 0) {
        CFRelease(source);
        return nil;
    }

    const UCKeyboardLayout *layout =
        reinterpret_cast<const UCKeyboardLayout *>(CFDataGetBytePtr(layoutData));
    CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event,
                                                               kCGKeyboardEventKeycode);

    // Match NSEvent.charactersIgnoringModifiers: retain Shift/Caps semantics but
    // ignore Command/Control/Option when translating the physical key.
    CGEventFlags flags = CGEventGetFlags(event);
    UInt32 modifiers = 0;
    if (flags & kCGEventFlagMaskShift) modifiers |= shiftKey;
    if (flags & kCGEventFlagMaskAlphaShift) modifiers |= alphaLock;

    UInt32 deadKeyState = 0;
    UniChar chars[8] = {0};
    UniCharCount length = 0;
    OSStatus status = UCKeyTranslate(layout,
                                     keyCode,
                                     kUCKeyActionDown,
                                     (modifiers >> 8) & 0xFF,
                                     LMGetKbdType(),
                                     kUCKeyTranslateNoDeadKeysBit,
                                     &deadKeyState,
                                     sizeof(chars) / sizeof(chars[0]),
                                     &length,
                                     chars);
    CFRelease(source);
    if (status != noErr || length == 0) return nil;
    return [NSString stringWithCharacters:chars length:length];
}

} // namespace

@implementation SangKeyRunningApplicationCompat {
    pid_t _pid;
}

+ (instancetype)runningApplicationWithProcessIdentifier:(pid_t)pid {
    if (pid <= 0) return nil;
    SangKeyRunningApplicationCompat *app = [SangKeyRunningApplicationCompat new];
    app->_pid = pid;
    return app;
}

- (NSString *)bundleIdentifier {
    return SigningIdentifierForPID(_pid);
}

@end

@implementation SangKeyWorkspaceCompat

+ (instancetype)sharedWorkspace {
    static SangKeyWorkspaceCompat *workspace;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        workspace = [SangKeyWorkspaceCompat new];
    });
    return workspace;
}

- (SangKeyRunningApplicationCompat *)frontmostApplication {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ProcessSerialNumber psn = {0, kNoProcess};
    if (GetFrontProcess(&psn) != noErr) return nil;
    pid_t pid = 0;
    if (GetProcessPID(&psn, &pid) != noErr || pid <= 0) return nil;
#pragma clang diagnostic pop
    return [SangKeyRunningApplicationCompat runningApplicationWithProcessIdentifier:pid];
}

@end

@implementation SangKeyEventCompat {
    NSString *_charactersIgnoringModifiers;
}

+ (instancetype)eventWithCGEvent:(CGEventRef)event {
    NSString *characters = CharactersIgnoringModifiers(event);
    if (characters == nil) return nil;
    SangKeyEventCompat *result = [SangKeyEventCompat new];
    result->_charactersIgnoringModifiers = [characters copy];
    return result;
}

- (NSString *)charactersIgnoringModifiers {
    return _charactersIgnoringModifiers;
}

@end
