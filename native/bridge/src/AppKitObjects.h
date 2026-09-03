#ifndef DART_APPKIT_BRIDGE_SRC_APPKIT_OBJECTS_H_
#define DART_APPKIT_BRIDGE_SRC_APPKIT_OBJECTS_H_

#import <AppKit/AppKit.h>

#include "dart_appkit.h"

@interface DaView : NSView

@end

@interface DaTextView : DaView

@property(nonatomic, copy) NSString* displayText;

@end

@interface DaWindow : NSWindow

@property(nonatomic, assign) DaHandle daHandle;

- (void)daPostInputEvent:(NSEvent*)event;

@end

@interface DaWindowOwner : NSObject <NSWindowDelegate> {
 @private
  BOOL _hasFocusState;
  BOOL _lastFocusState;
  BOOL _hasVisibilityState;
  BOOL _lastVisibilityState;
  BOOL _hasOcclusionState;
  BOOL _lastOcclusionState;
  BOOL _hasBackingScale;
  double _lastBackingScale;
  BOOL _hasScreenState;
  BOOL _lastScreenPresent;
  int64_t _lastScreenId;
  NSRect _lastScreenFrame;
  NSRect _lastVisibleScreenFrame;
}

@property(nonatomic, strong, readonly) DaWindow* window;
@property(nonatomic, assign) DaHandle daHandle;

- (instancetype)initWithWindow:(DaWindow*)window;
- (void)daPostCurrentWindowState;
- (void)daPostFocusState:(BOOL)isFocused;
- (void)daPostVisibilityState:(BOOL)isVisible;
- (void)daPostOcclusionState:(BOOL)isOccluded;
- (void)daPostBackingScaleFactor:(double)scaleFactor;
- (void)daPostScreen:(NSScreen*)screen;

@end

#endif  // DART_APPKIT_BRIDGE_SRC_APPKIT_OBJECTS_H_
