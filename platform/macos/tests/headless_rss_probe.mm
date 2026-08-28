#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <Security/Security.h>

#include <fstream>
#include <vector>
#include <unistd.h>

#include "EnglishDetect.h"

static std::vector<Byte> readFile(const char *path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) return {};
    stream.seekg(0, std::ios::end);
    std::streamoff length = stream.tellg();
    stream.seekg(0, std::ios::beg);
    if (length <= 0) return {};
    std::vector<Byte> bytes(static_cast<size_t>(length));
    stream.read(reinterpret_cast<char *>(bytes.data()), length);
    if (!stream) return {};
    return bytes;
}

int main(void) {
    @autoreleasepool {
        // Keep the same kind of lightweight preference/string/collection state a
        // real headless SangKey agent would need, but intentionally never touch
        // NSApplication, NSWorkspace, NSEvent, NSRunningApplication or AppKit.
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults registerDefaults:@{
            @"vLanguage": @1,
            @"vInputType": @0,
            @"vAutoDetectEnglish": @1,
            @"vCheckSpelling": @1,
        }];

        NSArray<NSString *> *browserIdentifiers = @[
            @"com.google.Chrome", @"org.chromium.Chromium", @"com.brave.Browser",
            @"com.microsoft.Edge", @"org.mozilla.firefox", @"com.apple.Safari"
        ];
        if (browserIdentifiers.count == 0 || [defaults integerForKey:@"vLanguage"] < 0) {
            return 2;
        }

        std::vector<Byte> english = readFile("core/data/english_words.dat");
        std::vector<Byte> vietnamese = readFile("core/data/viet_telex.dat");
        if (english.empty() || vietnamese.empty()) return 3;
        initEnglishDict(english.data(), static_cast<int>(english.size()));
        initVietByTelexDict(vietnamese.data(), static_cast<int>(vietnamese.size()));
        english.clear();
        english.shrink_to_fit();
        vietnamese.clear();
        vietnamese.shrink_to_fit();
        if (!isEnglishDictReady()) return 4;

        // Force-load the exact non-AppKit system frameworks a practical agent
        // needs for event taps, keyboard input-source state and signed-process
        // identification. These calls do not request Accessibility permission.
        CGEventSourceRef eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        TISInputSourceRef inputSource = TISCopyCurrentKeyboardInputSource();
        SecCodeRef selfCode = NULL;
        (void)SecCodeCopySelf(kSecCSDefaultFlags, &selfCode);

        fprintf(stderr, "SangKey headless probe ready; dictionaries=%s\n",
                isEnglishDictReady() ? "yes" : "no");

        // No AppKit run loop. The production headless agent would block in the
        // CFRunLoop that owns its CGEventTap source; sleep is enough for an RSS
        // feasibility measurement without asking TCC for keyboard access.
        for (;;) sleep(60);

        if (eventSource) CFRelease(eventSource);
        if (inputSource) CFRelease(inputSource);
        if (selfCode) CFRelease(selfCode);
    }
    return 0;
}
