#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SangKeyPreferencesDomain;
extern CFStringRef const SangKeyPreferencesChangedDarwinNotification;

/// Canonical defaults shared by the ephemeral launcher and the headless agent.
NSDictionary<NSString *, NSNumber *> *SangKeyDefaultPreferences(void);

/// Read one integer from the explicit SangKey preference domain. Missing values
/// fall back to SangKeyDefaultPreferences rather than either process's bundle id.
NSInteger SangKeyPreferenceInteger(NSString *key);
BOOL SangKeyPreferenceBool(NSString *key);

/// Persist a value for the current user/all-hosts SangKey domain and notify the
/// headless agent through the Darwin notification center. No XPC/network/daemon
/// IPC is involved.
void SangKeySetPreferenceInteger(NSString *key, NSInteger value);
void SangKeySetPreferenceBool(NSString *key, BOOL value);

/// Snapshot exactly the engine/macOS-local option keys understood by
/// InputController::applyEngineOptions:.
NSDictionary<NSString *, NSNumber *> *SangKeyCurrentEngineOptions(void);

/// Post a no-payload cross-process change notification. Callers that receive it
/// re-read the explicit preference domain.
void SangKeyPostPreferencesChanged(void);

NS_ASSUME_NONNULL_END
