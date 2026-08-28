#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

#include <mach-o/dyld.h>
#include <limits.h>

#import "InputController.h"
#import "SangKeyPreferences.h"
#include "EnglishDetect.h"

namespace {

NSString *AgentResourceDirectory(void) {
    uint32_t size = PATH_MAX;
    char path[PATH_MAX] = {0};
    if (_NSGetExecutablePath(path, &size) != 0) return nil;
    NSString *executable = [[[NSString alloc] initWithUTF8String:path] stringByStandardizingPath];
    return [executable stringByDeletingLastPathComponent];
}

BOOL LoadDictionaries(NSString *resourceDirectory) {
    if (resourceDirectory == nil) return NO;
    NSString *englishPath = [resourceDirectory stringByAppendingPathComponent:@"english_words.dat"];
    NSString *vietnamesePath = [resourceDirectory stringByAppendingPathComponent:@"viet_telex.dat"];
    NSData *english = [NSData dataWithContentsOfFile:englishPath options:NSDataReadingMappedIfSafe error:nil];
    NSData *vietnamese = [NSData dataWithContentsOfFile:vietnamesePath options:NSDataReadingMappedIfSafe error:nil];
    if (english == nil || vietnamese == nil) return NO;
    initEnglishDict((const Byte *)english.bytes, (int)english.length);
    initVietByTelexDict((const Byte *)vietnamese.bytes, (int)vietnamese.length);
    return isEnglishDictReady() ? YES : NO;
}

void PreferencesChanged(CFNotificationCenterRef center,
                        void *observer,
                        CFNotificationName name,
                        const void *object,
                        CFDictionaryRef userInfo) {
    (void)center;
    (void)name;
    (void)object;
    (void)userInfo;
    InputController *input = (__bridge InputController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [input applyEngineOptions:SangKeyCurrentEngineOptions()];
    });
}

void ScheduleAccessibilityRetry(InputController *input, NSTimeInterval delay) {
    // Accessibility approval is human-paced. Retrying CGEventTapCreate every
    // second forever only creates needless wakeups while System Settings is open.
    // Back off quickly, cap at 15 s, and stop scheduling as soon as the tap works.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([input isRunning]) return;
        if ([input start]) return;
        NSTimeInterval nextDelay = MIN(delay * 2.0, 15.0);
        ScheduleAccessibilityRetry(input, nextDelay);
    });
}

} // namespace

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        unsetenv("KEY84_TRACE");

        InputController *input = [InputController new];
        [input applyEngineOptions:SangKeyCurrentEngineOptions()];

        NSString *resources = AgentResourceDirectory();
        if (!LoadDictionaries(resources)) {
            NSLog(@"SangKeyAgent: dictionary load failed from %@", resources ?: @"<unknown>");
            return 3;
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)input,
                                        PreferencesChanged,
                                        SangKeyPreferencesChangedDarwinNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        id languageObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:Key84LanguageDidToggleNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            NSNumber *language = note.userInfo[@"language"];
            if (language != nil) SangKeySetPreferenceInteger(@"vLanguage", language.integerValue);
        }];

        BOOL ciSmoke = getenv("SANGKEY_AGENT_CI_SMOKE") != NULL;
        if (ciSmoke) {
            fprintf(stderr, "SangKeyAgent CI smoke ready; dictionaries=yes; AppKit=no\n");
        } else {
            if (![input start]) {
                // Prompt from the process that actually owns the event tap so TCC
                // authorizes the correct code identity rather than the ephemeral
                // launcher process.
                [input requestAccessibilityPermission];
                ScheduleAccessibilityRetry(input, 1.0);
            }
        }

        [[NSRunLoop mainRunLoop] run];

        [[NSNotificationCenter defaultCenter] removeObserver:languageObserver];
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                           (__bridge const void *)input,
                                           SangKeyPreferencesChangedDarwinNotification,
                                           NULL);
        [input stop];
    }
    return 0;
}
