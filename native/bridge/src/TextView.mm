#include "AppKitObjects.h"

#include <algorithm>
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

bool StableScrollPhase(NSEventPhase phase, int64_t* out_phase) {
  switch (phase) {
    case NSEventPhaseNone:
      *out_phase = DA_SCROLL_PHASE_NONE;
      return true;
    case NSEventPhaseBegan:
      *out_phase = DA_SCROLL_PHASE_BEGAN;
      return true;
    case NSEventPhaseStationary:
      *out_phase = DA_SCROLL_PHASE_STATIONARY;
      return true;
    case NSEventPhaseChanged:
      *out_phase = DA_SCROLL_PHASE_CHANGED;
      return true;
    case NSEventPhaseEnded:
      *out_phase = DA_SCROLL_PHASE_ENDED;
      return true;
    case NSEventPhaseCancelled:
      *out_phase = DA_SCROLL_PHASE_CANCELLED;
      return true;
    case NSEventPhaseMayBegin:
      *out_phase = DA_SCROLL_PHASE_MAY_BEGIN;
      return true;
    default:
      return false;
  }
}

NSPoint ContentViewPoint(NSWindow* window, NSEvent* event) {
  NSView* content_view = window.contentView;
  NSPoint point = event.locationInWindow;
  if (content_view != nil) {
    point = [content_view convertPoint:point fromView:nil];
    if (!content_view.isFlipped) {
      point.y = NSHeight(content_view.bounds) - point.y;
    }
  }
  return point;
}

}  // namespace

@implementation DaView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.daAcceptsFirstResponder = YES;
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)acceptsFirstResponder {
  return self.daAcceptsFirstResponder;
}

@end

@implementation DaSplitView {
  DaSplitAxis _daAxis;
  double _daFraction;
  double _daFirstMinimumExtent;
  double _daSecondMinimumExtent;
  DaSplitZoomedChild _daZoomedChild;
  BOOL _daApplyingLayout;
}

@synthesize daAxis = _daAxis;
@synthesize daFraction = _daFraction;
@synthesize daFirstMinimumExtent = _daFirstMinimumExtent;
@synthesize daSecondMinimumExtent = _daSecondMinimumExtent;
@synthesize daZoomedChild = _daZoomedChild;

- (instancetype)initWithAxis:(DaSplitAxis)axis {
  self = [super initWithFrame:NSZeroRect];
  if (self != nil) {
    _daAxis = axis;
    _daFraction = 0.5;
    _daFirstMinimumExtent = 0.0;
    _daSecondMinimumExtent = 0.0;
    _daZoomedChild = DA_SPLIT_ZOOM_NONE;
    _daApplyingLayout = NO;
    self.vertical = axis == DA_SPLIT_AXIS_HORIZONTAL;
    self.dividerStyle = NSSplitViewDividerStyleThin;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.delegate = self;
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)daSetFirstView:(NSView*)firstView secondView:(NSView*)secondView {
  if (firstView == nil || secondView == nil || firstView == secondView ||
      firstView == self || secondView == self ||
      [self isDescendantOf:firstView] || [self isDescendantOf:secondView]) {
    return NO;
  }
  for (NSView* subview in self.subviews.copy) {
    [subview removeFromSuperview];
  }
  [self addArrangedSubview:firstView];
  [self addArrangedSubview:secondView];
  [self daApplyLayout];
  return YES;
}

- (void)daSetFraction:(double)fraction
    firstMinimumExtent:(double)firstMinimumExtent
   secondMinimumExtent:(double)secondMinimumExtent {
  _daFraction = fraction;
  _daFirstMinimumExtent = firstMinimumExtent;
  _daSecondMinimumExtent = secondMinimumExtent;
  [self daApplyLayout];
}

- (void)daEqualize {
  _daFraction = 0.5;
  [self daApplyLayout];
}

- (void)daSetZoomedChild:(DaSplitZoomedChild)zoomedChild {
  _daZoomedChild = zoomedChild;
  [self daApplyLayout];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
  (void)oldSize;
  [self daApplyLayout];
}

- (void)daApplyLayout {
  if (self.subviews.count != 2 || _daApplyingLayout) {
    return;
  }
  NSView* first = self.subviews[0];
  NSView* second = self.subviews[1];
  if (_daZoomedChild != DA_SPLIT_ZOOM_NONE) {
    first.hidden = _daZoomedChild != DA_SPLIT_ZOOM_FIRST;
    second.hidden = _daZoomedChild != DA_SPLIT_ZOOM_SECOND;
    NSView* visible = _daZoomedChild == DA_SPLIT_ZOOM_FIRST ? first : second;
    visible.frame = self.bounds;
    return;
  }
  first.hidden = NO;
  second.hidden = NO;
  const double axis_extent = self.isVertical ? NSWidth(self.bounds)
                                             : NSHeight(self.bounds);
  const double usable_extent = axis_extent - self.dividerThickness;
  if (usable_extent <= 0.0) {
    return;
  }
  const double maximum_first =
      std::max(0.0, usable_extent - _daSecondMinimumExtent);
  const double minimum_first =
      std::min(_daFirstMinimumExtent, maximum_first);
  const double desired_first = usable_extent * _daFraction;
  const double first_extent =
      std::clamp(desired_first, minimum_first, maximum_first);
  _daApplyingLayout = YES;
  if (self.isVertical) {
    first.frame = NSMakeRect(NSMinX(self.bounds), NSMinY(self.bounds),
                             first_extent, NSHeight(self.bounds));
    second.frame = NSMakeRect(
        NSMinX(self.bounds) + first_extent + self.dividerThickness,
        NSMinY(self.bounds), usable_extent - first_extent,
        NSHeight(self.bounds));
  } else {
    first.frame = NSMakeRect(NSMinX(self.bounds), NSMinY(self.bounds),
                             NSWidth(self.bounds), first_extent);
    second.frame = NSMakeRect(
        NSMinX(self.bounds),
        NSMinY(self.bounds) + first_extent + self.dividerThickness,
        NSWidth(self.bounds), usable_extent - first_extent);
  }
  _daApplyingLayout = NO;
}

- (CGFloat)splitView:(NSSplitView*)splitView
    constrainMinCoordinate:(CGFloat)proposedMinimumPosition
         ofSubviewAt:(NSInteger)dividerIndex {
  (void)proposedMinimumPosition;
  if (splitView != self || dividerIndex != 0) {
    return proposedMinimumPosition;
  }
  const double origin = self.isVertical ? NSMinX(self.bounds)
                                        : NSMinY(self.bounds);
  return origin + _daFirstMinimumExtent;
}

- (CGFloat)splitView:(NSSplitView*)splitView
    constrainMaxCoordinate:(CGFloat)proposedMaximumPosition
         ofSubviewAt:(NSInteger)dividerIndex {
  (void)proposedMaximumPosition;
  if (splitView != self || dividerIndex != 0) {
    return proposedMaximumPosition;
  }
  const double maximum = self.isVertical
                             ? NSMaxX(self.bounds)
                             : NSMaxY(self.bounds);
  return maximum - self.dividerThickness - _daSecondMinimumExtent;
}

- (BOOL)splitView:(NSSplitView*)splitView
    canCollapseSubview:(NSView*)subview {
  (void)splitView;
  (void)subview;
  return NO;
}

- (void)splitViewDidResizeSubviews:(NSNotification*)notification {
  if (notification.object != self || _daApplyingLayout ||
      _daZoomedChild != DA_SPLIT_ZOOM_NONE || self.subviews.count != 2) {
    return;
  }
  const double axis_extent = self.isVertical ? NSWidth(self.bounds)
                                             : NSHeight(self.bounds);
  const double usable_extent = axis_extent - self.dividerThickness;
  if (usable_extent <= 0.0) {
    return;
  }
  NSView* first = self.subviews[0];
  const double first_extent =
      self.isVertical ? NSWidth(first.frame) : NSHeight(first.frame);
  _daFraction = std::clamp(first_extent / usable_extent, 0.0, 1.0);
}

@end

@implementation DaTextView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    _displayText = @"";
    _daFont =
        [NSFont monospacedSystemFontOfSize:18.0 weight:NSFontWeightRegular];
    _daPadding = NSEdgeInsetsMake(20.0, 20.0, 20.0, 20.0);
    _daForegroundColor = NSColor.labelColor;
    _daBackgroundColor = NSColor.windowBackgroundColor;
  }
  return self;
}

- (void)setDisplayText:(NSString*)displayText {
  _displayText = [displayText copy];
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  [self.daBackgroundColor setFill];
  NSRectFill(dirtyRect);

  NSDictionary<NSAttributedStringKey, id>* attributes = @{
    NSFontAttributeName : self.daFont,
    NSForegroundColorAttributeName : self.daForegroundColor,
  };
  const NSEdgeInsets padding = self.daPadding;
  const NSRect bounds = self.bounds;
  const NSRect textRect = NSMakeRect(
      NSMinX(bounds) + padding.left, NSMinY(bounds) + padding.top,
      std::max<CGFloat>(0.0, NSWidth(bounds) - padding.left - padding.right),
      std::max<CGFloat>(0.0,
                        NSHeight(bounds) - padding.top - padding.bottom));
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
  const BOOL isKeyEvent = event.type == NSEventTypeKeyDown ||
                          event.type == NSEventTypeKeyUp;
  if (isKeyEvent &&
      self.daKeyEventRouting != DA_KEY_EVENT_ROUTING_DART_AND_APPKIT &&
      event.type == NSEventTypeKeyDown) {
    NSMenu* mainMenu = NSApp.mainMenu;
    if (mainMenu != nil && [mainMenu performKeyEquivalent:event]) {
      return;
    }
  }
  if (isKeyEvent && self.daKeyEventRouting == DA_KEY_EVENT_ROUTING_DART_ONLY) {
    [self daPostInputEvent:event];
    return;
  }
  if (!isKeyEvent ||
      self.daKeyEventRouting != DA_KEY_EVENT_ROUTING_APPKIT_ONLY) {
    [self daPostInputEvent:event];
  }
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

  if (event.type == NSEventTypeScrollWheel) {
    int64_t phase = DA_SCROLL_PHASE_NONE;
    int64_t momentum_phase = DA_SCROLL_PHASE_NONE;
    if (!StableScrollPhase(event.phase, &phase) ||
        !StableScrollPhase(event.momentumPhase, &momentum_phase)) {
      return;
    }
    native_event.type = DA_EVENT_SCROLL_WHEEL;
    const NSPoint point = ContentViewPoint(self, event);
    native_event.x = point.x;
    native_event.y = point.y;
    native_event.scrolling_delta_x = event.scrollingDeltaX;
    native_event.scrolling_delta_y = event.scrollingDeltaY;
    native_event.has_precise_scrolling_deltas =
        event.hasPreciseScrollingDeltas;
    native_event.scroll_phase = phase;
    native_event.momentum_phase = momentum_phase;
    native_event.direction_inverted_from_device =
        event.isDirectionInvertedFromDevice;
    dart_appkit::PostEvent(native_event);
    return;
  }

  DaEventType mouse_type = DA_EVENT_MOUSE_MOVED;
  if (MouseEventType(event.type, &mouse_type)) {
    native_event.type = mouse_type;
    const NSPoint point = ContentViewPoint(self, event);
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

- (BOOL)daSetDefersCloseRequests:(BOOL)enabled {
  if (!enabled && _pendingCloseOperationId > 0) {
    return NO;
  }
  _defersCloseRequests = enabled;
  return YES;
}

- (int64_t)daPendingCloseOperationId {
  return _pendingCloseOperationId;
}

- (BOOL)daReplyToCloseRequest:(int64_t)operationId allow:(BOOL)allow {
  if (operationId <= 0 || operationId != _pendingCloseOperationId) {
    return NO;
  }
  _pendingCloseOperationId = 0;
  if (allow) {
    [self daCloseProgrammatically];
  }
  return YES;
}

- (void)daCloseProgrammatically {
  _pendingCloseOperationId = 0;
  [self.window close];
}

- (BOOL)windowShouldClose:(NSWindow*)sender {
  (void)sender;
  if (!_defersCloseRequests) {
    return YES;
  }
  if (_pendingCloseOperationId > 0) {
    return NO;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_CLOSE_REQUESTED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.operation_id = dart_appkit::NextOperationId();
  _pendingCloseOperationId = event.operation_id;
  if (!dart_appkit::PostEvent(event)) {
    _pendingCloseOperationId = 0;
    return YES;
  }
  return NO;
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

- (void)daPostFrame:(NSRect)frame {
  const bool valid = std::isfinite(frame.origin.x) &&
                     std::isfinite(frame.origin.y) &&
                     std::isfinite(frame.size.width) &&
                     std::isfinite(frame.size.height) &&
                     frame.size.width > 0.0 && frame.size.height > 0.0;
  if (self.daHandle == 0 || !valid ||
      (_hasFrameState && NSEqualRects(_lastFrame, frame))) {
    return;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_FRAME_CHANGED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.x = frame.origin.x;
  event.y = frame.origin.y;
  event.width = frame.size.width;
  event.height = frame.size.height;
  if (dart_appkit::PostEvent(event)) {
    _hasFrameState = YES;
    _lastFrame = frame;
  }
}

- (void)daPostFullscreenState:(BOOL)isFullscreen {
  if (self.daHandle == 0 ||
      (_hasFullscreenState && _lastFullscreenState == isFullscreen)) {
    return;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_WINDOW_FULLSCREEN_CHANGED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.state = isFullscreen;
  if (dart_appkit::PostEvent(event)) {
    _hasFullscreenState = YES;
    _lastFullscreenState = isFullscreen;
  }
}

- (BOOL)daSetFullscreen:(BOOL)enabled {
  const BOOL current =
      (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
  if (_fullscreenTransitionPending) {
    return _pendingFullscreenTarget == enabled;
  }
  if (current == enabled) {
    [self daPostFullscreenState:current];
    return YES;
  }
  _fullscreenTransitionPending = YES;
  _pendingFullscreenTarget = enabled;
  [self.window toggleFullScreen:nil];
  return YES;
}

- (void)daPostCurrentWindowState {
  [self daPostFocusState:self.window.isKeyWindow];
  [self daPostVisibilityState:self.window.isVisible &&
                              !self.window.isMiniaturized];
  [self daPostOcclusionState:(self.window.occlusionState &
                              NSWindowOcclusionStateVisible) == 0];
  [self daPostBackingScaleFactor:self.window.backingScaleFactor];
  [self daPostScreen:self.window.screen];
  [self daPostFrame:self.window.frame];
  [self daPostFullscreenState:
            (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0];
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

- (void)windowDidMove:(NSNotification*)notification {
  (void)notification;
  if (!_fullscreenTransitionPending) {
    [self daPostFrame:self.window.frame];
  }
}

- (void)windowWillEnterFullScreen:(NSNotification*)notification {
  (void)notification;
  _fullscreenTransitionPending = YES;
  _pendingFullscreenTarget = YES;
}

- (void)windowWillExitFullScreen:(NSNotification*)notification {
  (void)notification;
  _fullscreenTransitionPending = YES;
  _pendingFullscreenTarget = NO;
}

- (void)windowDidEnterFullScreen:(NSNotification*)notification {
  (void)notification;
  _fullscreenTransitionPending = NO;
  [self daPostFullscreenState:YES];
  [self daPostFrame:self.window.frame];
}

- (void)windowDidExitFullScreen:(NSNotification*)notification {
  (void)notification;
  _fullscreenTransitionPending = NO;
  [self daPostFullscreenState:NO];
  [self daPostFrame:self.window.frame];
}

- (void)windowDidFailToEnterFullScreen:(NSWindow*)window {
  (void)window;
  _fullscreenTransitionPending = NO;
  [self daPostFullscreenState:NO];
  [self daPostFrame:self.window.frame];
}

- (void)windowDidFailToExitFullScreen:(NSWindow*)window {
  (void)window;
  _fullscreenTransitionPending = NO;
  [self daPostFullscreenState:YES];
  [self daPostFrame:self.window.frame];
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
  if (!_fullscreenTransitionPending) {
    [self daPostFrame:self.window.frame];
  }
}

@end
