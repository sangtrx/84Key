#pragma once

// InputController.mm inherited three AppKit conveniences from OpenKey. The
// always-on SangKeyAgent deliberately does not link AppKit, so its header search
// path resolves <Cocoa/Cocoa.h> to this narrow adapter instead. Macro aliases
// keep the proven event/engine implementation byte-for-byte while avoiding
// defining classes in Apple's NS* namespace.

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

#define NSWorkspace SangKeyWorkspaceCompat
#define NSRunningApplication SangKeyRunningApplicationCompat
#define NSEvent SangKeyEventCompat

NS_ASSUME_NONNULL_BEGIN

@interface SangKeyRunningApplicationCompat : NSObject
+ (nullable instancetype)runningApplicationWithProcessIdentifier:(pid_t)pid;
@property (nonatomic, readonly, nullable) NSString *bundleIdentifier;
@end

@interface SangKeyWorkspaceCompat : NSObject
+ (instancetype)sharedWorkspace;
@property (nonatomic, readonly, nullable) SangKeyRunningApplicationCompat *frontmostApplication;
@end

@interface SangKeyEventCompat : NSObject
+ (nullable instancetype)eventWithCGEvent:(CGEventRef)event;
@property (nonatomic, readonly, nullable) NSString *charactersIgnoringModifiers;
@end

NS_ASSUME_NONNULL_END
