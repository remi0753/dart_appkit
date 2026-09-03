#include "AppKitObjects.h"

#include <cmath>
#include <limits>
#include <string>

#include "BridgeInternal.h"

namespace {

std::string Utf8Bytes(NSString* value) {
  if (value == nil) {
    return {};
  }
  NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil || data.length == 0) {
    return {};
  }
  return std::string(static_cast<const char*>(data.bytes), data.length);
}

bool MouseEventType(NSEventType type, DaEventType* out_type) {
  switch (type) {
    case NSEventTypeLeftMouseDown:
    case NSEventTypeRightMouseDown:
    case NSEventTypeOtherMouseDown:
      *out_type = DA_EVENT_MOUSE_DOWN;
      return true;
    case NSEventTypeLeftMouseUp:
    case NSEventTypeRightMouseUp:
    case NSEventTypeOtherMouseUp:
      *out_type = DA_EVENT_MOUSE_UP;
      return true;
    case NSEventTypeMouseMoved:
      *out_type = DA_EVENT_MOUSE_MOVED;
      return true;
    case NSEventTypeLeftMouseDragged:
    case NSEventTypeRightMouseDragged:
    case NSEventTypeOtherMouseDragged:
      *out_type = DA_EVENT_MOUSE_DRAGGED;
      return true;
    default:
      return false;
  }
}

}  // namespace

@implementation DaView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

@end

@implementation DaTextView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    _displayText = @"";
  }
  return self;
}

- (void)setDisplayText:(NSString*)displayText {
  _displayText = [displayText copy];
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  [NSColor.windowBackgroundColor setFill];
  NSRectFill(dirtyRect);

  NSDictionary<NSAttributedStringKey, id>* attributes = @{
    NSFontAttributeName :
        [NSFont monospacedSystemFontOfSize:18.0 weight:NSFontWeightRegular],
    NSForegroundColorAttributeName : NSColor.labelColor,
  };
  const NSRect textRect = NSInsetRect(self.bounds, 20.0, 20.0);
  [self.displayText drawWithRect:textRect
                         options:NSStringDrawingUsesLineFragmentOrigin |
                                 NSStringDrawingUsesFontLeading
                      attributes:attributes];
}

@end

@implementation DaWindow

- (BOOL)canBecomeKeyWindow {
  return YES;
}

- (void)sendEvent:(NSEvent*)event {
  [self daPostInputEvent:event];
  [super sendEvent:event];
}

- (void)daPostInputEvent:(NSEvent*)event {
  if (self.daHandle == 0 || event == nil) {
    return;
  }

  dart_appkit::NativeEvent native_event;
  native_event.window = self.daHandle;
  native_event.monotonic_nanos = dart_appkit::MonotonicNanos();
  native_event.modifiers =
      static_cast<int64_t>(dart_appkit::StableModifiers(event.modifierFlags));

  DaEventType mouse_type = DA_EVENT_MOUSE_MOVED;
  if (MouseEventType(event.type, &mouse_type)) {
    native_event.type = mouse_type;
    NSView* content_view = self.contentView;
    NSPoint point = event.locationInWindow;
    if (content_view != nil) {
      point = [content_view convertPoint:point fromView:nil];
      if (!content_view.isFlipped) {
        point.y = NSHeight(content_view.bounds) - point.y;
      }
    }
    native_event.x = point.x;
    native_event.y = point.y;
    native_event.button = event.type == NSEventTypeMouseMoved
                              ? -1
                              : static_cast<int64_t>(event.buttonNumber);
    native_event.click_count = static_cast<int64_t>(event.clickCount);
    dart_appkit::PostEvent(native_event);
    return;
  }

  if (event.type == NSEventTypeKeyDown || event.type == NSEventTypeKeyUp) {
    native_event.type =
        event.type == NSEventTypeKeyDown ? DA_EVENT_KEY_DOWN : DA_EVENT_KEY_UP;
    native_event.key_code = static_cast<int64_t>(event.keyCode);
    native_event.is_repeat = event.isARepeat;
    native_event.characters = Utf8Bytes(event.characters);
    native_event.characters_ignoring_modifiers =
        Utf8Bytes(event.charactersIgnoringModifiers);
    dart_appkit::PostEvent(native_event);
  }
}

@end

@implementation DaWindowOwner

- (instancetype)initWithWindow:(DaWindow*)window {
  self = [super init];
  if (self != nil) {
    _window = window;
  }
  return self;
}

- (void)daPostFocusState:(BOOL)isFocused {
  if (self.daHandle == 0 || (_hasFocusState && _lastFocusState == isFocused)) {
    return;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_FOCUS_CHANGED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.state = isFocused;
  if (dart_appkit::PostEvent(event)) {
    _hasFocusState = YES;
    _lastFocusState = isFocused;
  }
}

- (void)daPostVisibilityState:(BOOL)isVisible {
  if (self.daHandle == 0 ||
      (_hasVisibilityState && _lastVisibilityState == isVisible)) {
    return;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_VISIBILITY_CHANGED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.state = isVisible;
  if (dart_appkit::PostEvent(event)) {
    _hasVisibilityState = YES;
    _lastVisibilityState = isVisible;
  }
}

- (void)daPostOcclusionState:(BOOL)isOccluded {
  if (self.daHandle == 0 ||
      (_hasOcclusionState && _lastOcclusionState == isOccluded)) {
    return;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_OCCLUSION_CHANGED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.state = isOccluded;
  if (dart_appkit::PostEvent(event)) {
    _hasOcclusionState = YES;
    _lastOcclusionState = isOccluded;
  }
}

- (void)daPostBackingScaleFactor:(double)scaleFactor {
  if (self.daHandle == 0 || !std::isfinite(scaleFactor) || scaleFactor <= 0.0 ||
      (_hasBackingScale && _lastBackingScale == scaleFactor)) {
    return;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_BACKING_SCALE_CHANGED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.backing_scale_factor = scaleFactor;
  if (dart_appkit::PostEvent(event)) {
    _hasBackingScale = YES;
    _lastBackingScale = scaleFactor;
  }
}

- (void)daPostScreen:(NSScreen*)screen {
  BOOL hasScreen = NO;
  int64_t screenId = 0;
  NSRect screenFrame = NSZeroRect;
  NSRect visibleScreenFrame = NSZeroRect;
  if (screen != nil) {
    NSNumber* screenNumber =
        screen.deviceDescription[(NSDeviceDescriptionKey) @"NSScreenNumber"];
    const unsigned long long candidate = screenNumber.unsignedLongLongValue;
    const NSRect candidateFrame = screen.frame;
    const NSRect candidateVisibleFrame = screen.visibleFrame;
    const bool validFrames = std::isfinite(candidateFrame.origin.x) &&
                             std::isfinite(candidateFrame.origin.y) &&
                             std::isfinite(candidateFrame.size.width) &&
                             std::isfinite(candidateFrame.size.height) &&
                             candidateFrame.size.width > 0.0 &&
                             candidateFrame.size.height > 0.0 &&
                             std::isfinite(candidateVisibleFrame.origin.x) &&
                             std::isfinite(candidateVisibleFrame.origin.y) &&
                             std::isfinite(candidateVisibleFrame.size.width) &&
                             std::isfinite(candidateVisibleFrame.size.height) &&
                             candidateVisibleFrame.size.width > 0.0 &&
                             candidateVisibleFrame.size.height > 0.0;
    if (screenNumber != nil && candidate > 0 &&
        candidate <= std::numeric_limits<uint32_t>::max() && validFrames) {
      hasScreen = YES;
      screenId = static_cast<int64_t>(candidate);
      screenFrame = candidateFrame;
      visibleScreenFrame = candidateVisibleFrame;
    }
  }

  if (self.daHandle == 0 ||
      (_hasScreenState && _lastScreenPresent == hasScreen &&
       _lastScreenId == screenId &&
       NSEqualRects(_lastScreenFrame, screenFrame) &&
       NSEqualRects(_lastVisibleScreenFrame, visibleScreenFrame))) {
    return;
  }

  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_SCREEN_CHANGED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.has_screen = hasScreen;
  event.screen_id = screenId;
  event.screen_x = screenFrame.origin.x;
  event.screen_y = screenFrame.origin.y;
  event.screen_width = screenFrame.size.width;
  event.screen_height = screenFrame.size.height;
  event.visible_screen_x = visibleScreenFrame.origin.x;
  event.visible_screen_y = visibleScreenFrame.origin.y;
  event.visible_screen_width = visibleScreenFrame.size.width;
  event.visible_screen_height = visibleScreenFrame.size.height;
  if (dart_appkit::PostEvent(event)) {
    _hasScreenState = YES;
    _lastScreenPresent = hasScreen;
    _lastScreenId = screenId;
    _lastScreenFrame = screenFrame;
    _lastVisibleScreenFrame = visibleScreenFrame;
  }
}

- (void)daPostCurrentWindowState {
  [self daPostFocusState:self.window.isKeyWindow];
  [self daPostVisibilityState:self.window.isVisible &&
                              !self.window.isMiniaturized];
  [self daPostOcclusionState:(self.window.occlusionState &
                              NSWindowOcclusionStateVisible) == 0];
  [self daPostBackingScaleFactor:self.window.backingScaleFactor];
  [self daPostScreen:self.window.screen];
}

- (void)windowDidBecomeKey:(NSNotification*)notification {
  (void)notification;
  [self daPostFocusState:YES];
}

- (void)windowDidResignKey:(NSNotification*)notification {
  (void)notification;
  [self daPostFocusState:NO];
}

- (void)windowDidMiniaturize:(NSNotification*)notification {
  (void)notification;
  [self daPostVisibilityState:NO];
}

- (void)windowDidDeminiaturize:(NSNotification*)notification {
  (void)notification;
  [self daPostVisibilityState:self.window.isVisible];
}

- (void)windowDidChangeOcclusionState:(NSNotification*)notification {
  (void)notification;
  [self daPostOcclusionState:(self.window.occlusionState &
                              NSWindowOcclusionStateVisible) == 0];
}

- (void)windowDidChangeBackingProperties:(NSNotification*)notification {
  (void)notification;
  [self daPostBackingScaleFactor:self.window.backingScaleFactor];
}

- (void)windowDidChangeScreen:(NSNotification*)notification {
  (void)notification;
  [self daPostScreen:self.window.screen];
}

- (void)windowWillClose:(NSNotification*)notification {
  (void)notification;
  if (self.daHandle == 0) {
    return;
  }
  [self daPostFocusState:NO];
  [self daPostVisibilityState:NO];
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_CLOSED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  dart_appkit::PostEvent(event);
}

- (void)windowDidResize:(NSNotification*)notification {
  (void)notification;
  if (self.daHandle == 0) {
    return;
  }
  const NSSize size = self.window.contentView.bounds.size;
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_RESIZED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.width = size.width;
  event.height = size.height;
  dart_appkit::PostEvent(event);
}

@end
