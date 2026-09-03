#include "AppKitObjects.h"

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

@implementation DaTextView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    _displayText = @"";
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

- (void)windowWillClose:(NSNotification*)notification {
  (void)notification;
  if (self.daHandle == 0) {
    return;
  }
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
