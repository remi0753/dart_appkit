#ifndef DART_APPKIT_BRIDGE_SRC_APPKIT_OBJECTS_H_
#define DART_APPKIT_BRIDGE_SRC_APPKIT_OBJECTS_H_

#import <AppKit/AppKit.h>

#include "dart_appkit.h"

@interface DaTextView : NSView

@property(nonatomic, copy) NSString* displayText;

@end

@interface DaWindow : NSWindow

@property(nonatomic, assign) DaHandle daHandle;

- (void)daPostInputEvent:(NSEvent*)event;

@end

@interface DaWindowOwner : NSObject <NSWindowDelegate>

@property(nonatomic, strong, readonly) DaWindow* window;
@property(nonatomic, assign) DaHandle daHandle;

- (instancetype)initWithWindow:(DaWindow*)window;

@end

#endif  // DART_APPKIT_BRIDGE_SRC_APPKIT_OBJECTS_H_
