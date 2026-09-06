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
