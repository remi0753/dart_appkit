#ifndef DART_APPKIT_BRIDGE_SRC_APPKIT_OBJECTS_H_
#define DART_APPKIT_BRIDGE_SRC_APPKIT_OBJECTS_H_

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

#include "dart_appkit.h"

@interface DaView : NSView

@property(nonatomic, assign) BOOL daAcceptsFirstResponder;

@end

@interface DaGlobalHotKeyOwner : NSObject {
 @private
  EventHotKeyRef _hotKeyRef;
  UInt32 _daIdentifier;
  BOOL _preparedForRelease;
}

@property(nonatomic, assign) DaHandle daHandle;
@property(nonatomic, assign, readonly) UInt32 daIdentifier;

- (instancetype)initWithKeyCode:(UInt32)keyCode
                      modifiers:(UInt32)modifiers
                      exclusive:(BOOL)exclusive
                          status:(OSStatus*)status;
- (void)daPostPressed;
- (void)daPrepareForRelease;

@end

@interface DaTextView : DaView

@property(nonatomic, copy) NSString* displayText;
@property(nonatomic, strong) NSFont* daFont;
@property(nonatomic, assign) NSEdgeInsets daPadding;
@property(nonatomic, strong) NSColor* daForegroundColor;
@property(nonatomic, strong) NSColor* daBackgroundColor;

@end

@interface DaTextEditor : DaView

@property(nonatomic, strong, readonly) NSScrollView* daScrollView;
@property(nonatomic, strong, readonly) NSTextView* daTextView;
@property(nonatomic, strong) NSFont* daFont;
@property(nonatomic, assign) NSEdgeInsets daPadding;
@property(nonatomic, strong) NSColor* daForegroundColor;
@property(nonatomic, strong) NSColor* daBackgroundColor;
@property(nonatomic, assign, readonly) BOOL daHasLineHighlight;
@property(nonatomic, assign, readonly) NSUInteger daLineHighlightLocation;
@property(nonatomic, strong, readonly) NSColor* daLineHighlightColor;

- (void)daApplyPresentation;
- (void)daSetLineHighlightAtLocation:(NSUInteger)location
                               color:(NSColor*)color;
- (void)daClearLineHighlight;
- (NSRect)daLineHighlightRect;

@end

@interface DaSplitView : NSSplitView <NSSplitViewDelegate>

@property(nonatomic, assign, readonly) DaSplitAxis daAxis;
@property(nonatomic, assign, readonly) double daFraction;
@property(nonatomic, assign, readonly) double daFirstMinimumExtent;
@property(nonatomic, assign, readonly) double daSecondMinimumExtent;
@property(nonatomic, assign, readonly) DaSplitZoomedChild daZoomedChild;

- (instancetype)initWithAxis:(DaSplitAxis)axis;
- (BOOL)daSetFirstView:(NSView*)firstView secondView:(NSView*)secondView;
- (void)daSetFraction:(double)fraction
    firstMinimumExtent:(double)firstMinimumExtent
   secondMinimumExtent:(double)secondMinimumExtent;
- (void)daEqualize;
- (void)daSetZoomedChild:(DaSplitZoomedChild)zoomedChild;

@end

@interface DaWindow : NSWindow

@property(nonatomic, assign) DaHandle daHandle;
@property(nonatomic, assign) DaKeyEventRouting daKeyEventRouting;

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
  BOOL _hasFrameState;
  NSRect _lastFrame;
  BOOL _hasFullscreenState;
  BOOL _lastFullscreenState;
  BOOL _fullscreenTransitionPending;
  BOOL _pendingFullscreenTarget;
  BOOL _defersCloseRequests;
  int64_t _pendingCloseOperationId;
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
- (void)daPostFrame:(NSRect)frame;
- (void)daPostFullscreenState:(BOOL)isFullscreen;
- (BOOL)daSetFullscreen:(BOOL)enabled;
- (BOOL)daSetDefersCloseRequests:(BOOL)enabled;
- (int64_t)daPendingCloseOperationId;
- (BOOL)daReplyToCloseRequest:(int64_t)operationId allow:(BOOL)allow;
- (void)daCloseProgrammatically;

@end

@interface DaMenuItemOwner : NSObject {
 @private
  NSMenuItem* _item;
  BOOL _separator;
}

@property(nonatomic, strong, readonly) NSMenuItem* item;
@property(nonatomic, assign) DaHandle daHandle;
@property(nonatomic, assign, readonly, getter=isSeparator) BOOL separator;

- (instancetype)initWithTitle:(NSString*)title
                keyEquivalent:(NSString*)keyEquivalent
                    modifiers:(NSEventModifierFlags)modifiers;
- (instancetype)initSeparator;
- (void)daPerformAction:(id)sender;
- (void)daPrepareForRelease;

@end

namespace dart_appkit {

using ExternalUrlOpenFunction = bool (*)(NSURL* url);

int32_t OpenAllowedExternalUrl(NSString* value,
                               ExternalUrlOpenFunction opener,
                               int32_t* out_opened);
int32_t OpenExternalUrlWithPolicy(NSString* value, NSString* expected_scheme,
                                  uint64_t policy_flags,
                                  ExternalUrlOpenFunction opener,
                                  int32_t* out_opened);

int32_t ReadPasteboardText(NSPasteboard* pasteboard,
                           DaPasteboardText* out_snapshot);
int32_t ReadPasteboardTextWithLimit(NSPasteboard* pasteboard,
                                    size_t maximum_utf8_bytes,
                                    DaPasteboardText* out_snapshot);
int32_t WritePasteboardText(NSPasteboard* pasteboard, const char* text,
                            size_t text_length, int64_t* out_change_count);
int32_t ClearPasteboard(NSPasteboard* pasteboard, int64_t* out_change_count);
int32_t GetPasteboardChangeCount(NSPasteboard* pasteboard,
                                 int64_t* out_change_count);

}  // namespace dart_appkit

#endif  // DART_APPKIT_BRIDGE_SRC_APPKIT_OBJECTS_H_
