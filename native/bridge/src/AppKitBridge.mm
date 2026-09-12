#include "dart_appkit.h"

#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "AppKitObjects.h"
#include "BridgeInternal.h"
#include "CustomViewRegistry.h"
#include "ObjectRegistry.h"

@class DaQuickLookRequestOwner;
@class DaServicesTextRequestor;
@class DaDropDestinationOwner;
@class DaDropDestinationSession;

namespace {

int g_application_appearance_observation_context = 0;
constexpr OSType kDaGlobalHotKeySignature = 'DAHK';
EventHandlerRef g_global_hot_key_event_handler = nullptr;
EventHandlerUPP g_global_hot_key_event_handler_upp = nullptr;
NSMutableDictionary<NSNumber*, NSNumber*>* g_global_hot_key_handles = nil;
UInt32 g_next_global_hot_key_identifier = 1;
DaHandle g_secure_event_input_handle = 0;
NSHashTable<NSView*>* g_context_menu_views = nil;
NSMutableArray<DaQuickLookRequestOwner*>* g_quick_look_request_owners = nil;
id g_quick_look_event_monitor = nil;
NSMutableArray<DaServicesTextRequestor*>* g_services_text_requestors = nil;
NSMutableArray<DaDropDestinationOwner*>* g_drop_destination_owners = nil;
NSMapTable<NSWindow*, DaDropDestinationSession*>* g_drop_sessions = nil;

int32_t EnableSecureEventInputWithSystem() {
  return static_cast<int32_t>(EnableSecureEventInput());
}

int32_t DisableSecureEventInputWithSystem() {
  return static_cast<int32_t>(DisableSecureEventInput());
}

bool IsSecureEventInputEnabledWithSystem() {
  return IsSecureEventInputEnabled() != 0;
}

bool IsApplicationActiveWithSystem() {
  return NSApp != nil && NSApp.isActive;
}

dart_appkit::SecureEventInputStatusHandler
    g_secure_event_input_enable_handler = EnableSecureEventInputWithSystem;
dart_appkit::SecureEventInputStatusHandler
    g_secure_event_input_disable_handler = DisableSecureEventInputWithSystem;
dart_appkit::SecureEventInputEnabledHandler
    g_secure_event_input_enabled_handler = IsSecureEventInputEnabledWithSystem;
dart_appkit::ApplicationActiveQuery g_application_active_query =
    IsApplicationActiveWithSystem;

OSStatus HandleGlobalHotKeyEvent(EventHandlerCallRef next_handler,
                                 EventRef event,
                                 void* context) {
  (void)next_handler;
  (void)context;
  EventHotKeyID identity{};
  const OSStatus status = GetEventParameter(
      event, kEventParamDirectObject, typeEventHotKeyID, nullptr,
      sizeof(identity), nullptr, &identity);
  if (status != noErr || identity.signature != kDaGlobalHotKeySignature) {
    return eventNotHandledErr;
  }
  NSNumber* handle_number = g_global_hot_key_handles[@(identity.id)];
  if (handle_number == nil) {
    return eventNotHandledErr;
  }
  dart_appkit::NativeEvent native_event;
  native_event.type = DA_EVENT_GLOBAL_HOT_KEY_PRESSED;
  native_event.window = handle_number.unsignedLongLongValue;
  native_event.monotonic_nanos = dart_appkit::MonotonicNanos();
  (void)dart_appkit::PostEvent(native_event);
  return noErr;
}

OSStatus EnsureGlobalHotKeyEventHandler() {
  if (g_global_hot_key_event_handler != nullptr) {
    return noErr;
  }
  const EventTypeSpec event_type = {
      kEventClassKeyboard,
      kEventHotKeyPressed,
  };
  g_global_hot_key_event_handler_upp =
      NewEventHandlerUPP(HandleGlobalHotKeyEvent);
  const OSStatus status = InstallApplicationEventHandler(
      g_global_hot_key_event_handler_upp, 1, &event_type, nullptr,
      &g_global_hot_key_event_handler);
  if (status != noErr) {
    DisposeEventHandlerUPP(g_global_hot_key_event_handler_upp);
    g_global_hot_key_event_handler_upp = nullptr;
  }
  return status;
}

void StopGlobalHotKeyEventHandlerIfUnused() {
  if (g_global_hot_key_handles.count != 0 ||
      g_global_hot_key_event_handler == nullptr) {
    return;
  }
  RemoveEventHandler(g_global_hot_key_event_handler);
  g_global_hot_key_event_handler = nullptr;
  DisposeEventHandlerUPP(g_global_hot_key_event_handler_upp);
  g_global_hot_key_event_handler_upp = nullptr;
  g_global_hot_key_handles = nil;
}

void StopGlobalHotKeyInfrastructure() {
  [g_global_hot_key_handles removeAllObjects];
  g_global_hot_key_handles = nil;
  if (g_global_hot_key_event_handler != nullptr) {
    RemoveEventHandler(g_global_hot_key_event_handler);
    g_global_hot_key_event_handler = nullptr;
  }
  if (g_global_hot_key_event_handler_upp != nullptr) {
    DisposeEventHandlerUPP(g_global_hot_key_event_handler_upp);
    g_global_hot_key_event_handler_upp = nullptr;
  }
}

bool DaApplicationUsesDarkAppearance(NSApplication* application) {
  if (application == nil) {
    return false;
  }
  NSAppearanceName match =
      [application.effectiveAppearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua,
        NSAppearanceNameDarkAqua,
      ]];
  return [match isEqualToString:NSAppearanceNameDarkAqua];
}

}  // namespace

@interface DaApplicationAppearanceObserver : NSObject {
 @private
  __weak NSApplication* _application;
  BOOL _observing;
  BOOL _lastIsDark;
}

- (instancetype)initWithApplication:(NSApplication*)application;
- (void)stop;

@end

@interface DaSecureInputIndicatorView : NSView {
 @private
  NSTextField* _label;
}

@property(nonatomic, assign) DaSecureInputIndicatorState daState;

@end

@interface DaQuickLookRequestOwner : NSObject

@property(nonatomic, weak) NSView* view;
@property(nonatomic, assign) DaHandle daHandle;
@property(nonatomic, assign) NSInteger previousPressureStage;

@end

@interface DaServicesTextRequestor : NSObject <NSServicesMenuRequestor>

@property(nonatomic, weak) NSView* view;
@property(nonatomic, assign) DaHandle daHandle;
@property(nonatomic, copy) NSString* selectionText;
@property(nonatomic, assign) BOOL acceptsReturnedText;
@property(nonatomic, assign) NSUInteger maximumReturnedTextUtf8Bytes;

@end

@interface DaDropDestinationOwner : NSObject

@property(nonatomic, weak) NSView* view;
@property(nonatomic, assign) DaHandle daHandle;
@property(nonatomic, assign) BOOL acceptsPlainText;
@property(nonatomic, assign) BOOL acceptsFileUrls;
@property(nonatomic, assign) NSUInteger maximumTextUtf8Bytes;
@property(nonatomic, assign) NSUInteger maximumFileUrlCount;
@property(nonatomic, assign) NSUInteger maximumFileUrlUtf8Bytes;
@property(nonatomic, assign) NSUInteger maximumTotalFileUrlUtf8Bytes;

@end

@interface DaDropDestinationSession : NSObject

@property(nonatomic, weak) DaDropDestinationOwner* owner;
@property(nonatomic, assign) NSInteger sequenceNumber;
@property(nonatomic, assign) DaDropContentKind contentKind;

@end

@implementation DaGlobalHotKeyOwner

@synthesize daIdentifier = _daIdentifier;

- (instancetype)initWithKeyCode:(UInt32)keyCode
                      modifiers:(UInt32)modifiers
                      exclusive:(BOOL)exclusive
                          status:(OSStatus*)status {
  self = [super init];
  if (self == nil) {
    if (status != nullptr) {
      *status = memFullErr;
    }
    return nil;
  }
  if (g_global_hot_key_handles == nil) {
    g_global_hot_key_handles = [[NSMutableDictionary alloc] init];
  }
  const OSStatus handler_status = EnsureGlobalHotKeyEventHandler();
  if (handler_status != noErr) {
    if (status != nullptr) {
      *status = handler_status;
    }
    StopGlobalHotKeyEventHandlerIfUnused();
    return nil;
  }
  UInt32 identifier = g_next_global_hot_key_identifier++;
  if (identifier == 0) {
    identifier = g_next_global_hot_key_identifier++;
  }
  const EventHotKeyID identity = {
      kDaGlobalHotKeySignature,
      identifier,
  };
  const OptionBits options = exclusive ? kEventHotKeyExclusive : 0;
  const OSStatus registration_status = RegisterEventHotKey(
      keyCode, modifiers, identity, GetApplicationEventTarget(), options,
      &_hotKeyRef);
  if (registration_status != noErr) {
    if (status != nullptr) {
      *status = registration_status;
    }
    StopGlobalHotKeyEventHandlerIfUnused();
    return nil;
  }
  _daIdentifier = identifier;
  _preparedForRelease = NO;
  if (status != nullptr) {
    *status = noErr;
  }
  return self;
}

- (void)setDaHandle:(DaHandle)daHandle {
  _daHandle = daHandle;
  if (_daIdentifier != 0 && daHandle != 0) {
    g_global_hot_key_handles[@(_daIdentifier)] = @(daHandle);
  }
}

- (void)daPostPressed {
  if (_preparedForRelease || _daHandle == 0) {
    return;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_GLOBAL_HOT_KEY_PRESSED;
  event.window = _daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  (void)dart_appkit::PostEvent(event);
}

- (void)daPrepareForRelease {
  if (_preparedForRelease) {
    return;
  }
  _preparedForRelease = YES;
  if (_daIdentifier != 0) {
    [g_global_hot_key_handles removeObjectForKey:@(_daIdentifier)];
  }
  _daHandle = 0;
  _daIdentifier = 0;
  if (_hotKeyRef != nullptr) {
    UnregisterEventHotKey(_hotKeyRef);
    _hotKeyRef = nullptr;
  }
  StopGlobalHotKeyEventHandlerIfUnused();
}

- (void)dealloc {
  [self daPrepareForRelease];
}

@end

@implementation DaSecureEventInputOwner

@synthesize daDesired = _desired;
@synthesize daOwnedEnabled = _ownedEnabled;
@synthesize daLastOSStatus = _lastOSStatus;

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _desired = NO;
    _ownedEnabled = NO;
    _preparedForRelease = NO;
    _lastOSStatus = noErr;
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(daApplicationActivationChanged:)
                   name:NSApplicationDidBecomeActiveNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(daApplicationActivationChanged:)
                   name:NSApplicationDidResignActiveNotification
                 object:nil];
  }
  return self;
}

- (int32_t)daApplyForCurrentApplicationActivity {
  if (_preparedForRelease) {
    return noErr;
  }
  const BOOL target_enabled =
      _desired && g_application_active_query != nullptr &&
      g_application_active_query();
  if (target_enabled == _ownedEnabled) {
    _lastOSStatus = noErr;
    return noErr;
  }
  dart_appkit::SecureEventInputStatusHandler handler = target_enabled
      ? g_secure_event_input_enable_handler
      : g_secure_event_input_disable_handler;
  const int32_t status = handler == nullptr ? paramErr : handler();
  _lastOSStatus = status;
  if (status == noErr) {
    _ownedEnabled = target_enabled;
  }
  return status;
}

- (int32_t)daSetDesired:(BOOL)desired {
  _desired = desired;
  return [self daApplyForCurrentApplicationActivity];
}

- (void)daApplicationActivationChanged:(NSNotification*)notification {
  (void)notification;
  (void)[self daApplyForCurrentApplicationActivity];
}

- (void)daPrepareForRelease {
  if (_preparedForRelease) {
    return;
  }
  [NSNotificationCenter.defaultCenter removeObserver:self];
  _desired = NO;
  if (_ownedEnabled) {
    const int32_t status = g_secure_event_input_disable_handler == nullptr
                               ? paramErr
                               : g_secure_event_input_disable_handler();
    _lastOSStatus = status;
    if (status == noErr) {
      _ownedEnabled = NO;
    }
  }
  _preparedForRelease = YES;
  _daHandle = 0;
  g_secure_event_input_handle = 0;
}

- (void)dealloc {
  [self daPrepareForRelease];
}

@end

@implementation DaSecureInputIndicatorView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 5.0;
    self.layer.backgroundColor =
        [NSColor.controlBackgroundColor colorWithAlphaComponent:0.92].CGColor;
    self.layer.borderColor =
        [NSColor.separatorColor colorWithAlphaComponent:0.8].CGColor;
    self.layer.borderWidth = 1.0;
    _label = [NSTextField labelWithString:@""];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = [NSFont monospacedSystemFontOfSize:10.0
                                             weight:NSFontWeightSemibold];
    _label.textColor = NSColor.labelColor;
    [self addSubview:_label];
    [NSLayoutConstraint activateConstraints:@[
      [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                          constant:7.0],
      [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                           constant:-7.0],
      [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:4.0],
      [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor
                                          constant:-4.0],
    ]];
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityGroupRole];
    [self setAccessibilityIdentifier:@"dart_appkit.secure_input_indicator"];
  }
  return self;
}

- (BOOL)acceptsFirstResponder {
  return NO;
}

- (NSView*)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

- (void)setDaState:(DaSecureInputIndicatorState)state {
  _daState = state;
  NSString* mode = state == DA_SECURE_INPUT_INDICATOR_MANUAL ? @"MANUAL"
                                                             : @"AUTO";
  _label.stringValue = [NSString stringWithFormat:@"SECURE %@", mode];
  [self setAccessibilityLabel:
            [NSString stringWithFormat:@"Secure Keyboard Entry — %@",
                                       state == DA_SECURE_INPUT_INDICATOR_MANUAL
                                           ? @"Manual"
                                           : @"Automatic"]];
  [self setAccessibilityHelp:
            @"Keyboard input is protected from other applications."];
}

@end

@implementation DaQuickLookRequestOwner
@end

@implementation DaServicesTextRequestor

- (BOOL)writeSelectionToPasteboard:(NSPasteboard*)pasteboard
                             types:(NSArray<NSPasteboardType>*)types {
  NSString* selection = self.selectionText;
  if (selection == nil || pasteboard == nil ||
      ![types containsObject:NSPasteboardTypeString]) {
    return NO;
  }
  [pasteboard clearContents];
  return [pasteboard setString:selection forType:NSPasteboardTypeString];
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard*)pasteboard {
  if (!self.acceptsReturnedText || self.view == nil || self.daHandle == 0 ||
      pasteboard == nil) {
    return NO;
  }
  DaPasteboardText snapshot{};
  if (dart_appkit::ReadPasteboardTextWithLimit(
          pasteboard, self.maximumReturnedTextUtf8Bytes, &snapshot) !=
          DA_STATUS_OK ||
      snapshot.has_text == 0) {
    return NO;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_VIEW_SERVICES_TEXT_RECEIVED;
  event.window = self.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  if (snapshot.text_length != 0) {
    event.characters.assign(snapshot.text, snapshot.text_length);
  }
  return dart_appkit::PostEvent(event);
}

@end

@implementation DaDropDestinationOwner
@end

@implementation DaDropDestinationSession
@end

namespace {

DaServicesTextRequestor* ServicesTextRequestorForView(NSView* view) {
  for (DaServicesTextRequestor* requestor in
       [g_services_text_requestors copy]) {
    NSView* candidate = requestor.view;
    if (candidate == nil) {
      [g_services_text_requestors removeObject:requestor];
    } else if (candidate == view) {
      return requestor;
    }
  }
  if (g_services_text_requestors.count == 0) {
    g_services_text_requestors = nil;
  }
  return nil;
}

void RemoveServicesTextRequestorForView(NSView* view) {
  DaServicesTextRequestor* requestor = ServicesTextRequestorForView(view);
  if (requestor != nil) {
    requestor.daHandle = 0;
    requestor.view = nil;
    requestor.selectionText = nil;
    [g_services_text_requestors removeObject:requestor];
  }
  if (g_services_text_requestors.count == 0) {
    g_services_text_requestors = nil;
  }
}

DaDropDestinationOwner* DropDestinationOwnerForView(NSView* view) {
  for (DaDropDestinationOwner* owner in [g_drop_destination_owners copy]) {
    NSView* candidate = owner.view;
    if (candidate == nil) {
      [g_drop_destination_owners removeObject:owner];
    } else if (candidate == view) {
      return owner;
    }
  }
  if (g_drop_destination_owners.count == 0) {
    g_drop_destination_owners = nil;
  }
  return nil;
}

void ClearDropSessionsForOwner(DaDropDestinationOwner* owner) {
  if (owner == nil || g_drop_sessions == nil) {
    return;
  }
  for (NSWindow* window in g_drop_sessions.keyEnumerator.allObjects) {
    if ([g_drop_sessions objectForKey:window].owner == owner) {
      [g_drop_sessions removeObjectForKey:window];
    }
  }
  if (g_drop_sessions.count == 0) {
    g_drop_sessions = nil;
  }
}

void RemoveDropDestinationOwnerForView(NSView* view) {
  DaDropDestinationOwner* owner = DropDestinationOwnerForView(view);
  if (owner != nil) {
    ClearDropSessionsForOwner(owner);
    owner.daHandle = 0;
    owner.view = nil;
    [g_drop_destination_owners removeObject:owner];
  }
  if (g_drop_destination_owners.count == 0) {
    g_drop_destination_owners = nil;
  }
}

bool PasteboardOffersType(NSPasteboard* pasteboard, NSPasteboardType type) {
  return pasteboard != nil &&
         [pasteboard availableTypeFromArray:@[ type ]] != nil;
}

DaDropDestinationOwner* ResolveDropDestination(
    NSWindow* window, id<NSDraggingInfo> sender,
    DaDropContentKind* out_content_kind, NSPoint* out_local_point) {
  if (window == nil || sender == nil ||
      ([sender draggingSourceOperationMask] & NSDragOperationCopy) == 0) {
    return nil;
  }
  NSPasteboard* pasteboard = [sender draggingPasteboard];
  const bool offers_file_urls =
      PasteboardOffersType(pasteboard, NSPasteboardTypeFileURL);
  const bool offers_plain_text =
      PasteboardOffersType(pasteboard, NSPasteboardTypeString);
  if (!offers_file_urls && !offers_plain_text) {
    return nil;
  }
  NSView* content_view = window.contentView;
  if (content_view == nil) {
    return nil;
  }
  const NSPoint location = [sender draggingLocation];
  if (!std::isfinite(location.x) || !std::isfinite(location.y)) {
    return nil;
  }
  DaDropDestinationOwner* best = nil;
  DaDropContentKind best_kind = DA_DROP_CONTENT_PLAIN_TEXT;
  NSPoint best_local_point = NSZeroPoint;
  NSUInteger best_depth = 0;
  for (DaDropDestinationOwner* owner in
       [g_drop_destination_owners copy]) {
    NSView* view = owner.view;
    if (view == nil) {
      [g_drop_destination_owners removeObject:owner];
      continue;
    }
    DaDropContentKind kind = DA_DROP_CONTENT_PLAIN_TEXT;
    if (offers_file_urls && owner.acceptsFileUrls) {
      kind = DA_DROP_CONTENT_FILE_URLS;
    } else if (!offers_plain_text || !owner.acceptsPlainText) {
      continue;
    }
    const NSPoint local_point = [view convertPoint:location fromView:nil];
    if (!std::isfinite(local_point.x) || !std::isfinite(local_point.y) ||
        !NSPointInRect(local_point, view.bounds) || view.isHidden ||
        view.alphaValue <= 0.0 || view.window != window) {
      continue;
    }
    NSUInteger depth = 0;
    NSView* cursor = view;
    bool visible_in_ancestry = true;
    while (cursor != nil && cursor != content_view) {
      const NSPoint cursor_point =
          [cursor convertPoint:location fromView:nil];
      if (!std::isfinite(cursor_point.x) || !std::isfinite(cursor_point.y) ||
          !NSPointInRect(cursor_point, cursor.bounds) || cursor.isHidden ||
          cursor.alphaValue <= 0.0) {
        visible_in_ancestry = false;
        break;
      }
      cursor = cursor.superview;
      ++depth;
    }
    if (visible_in_ancestry && cursor == content_view &&
        (best == nil || depth > best_depth)) {
      best = owner;
      best_kind = kind;
      best_local_point = local_point;
      best_depth = depth;
    }
  }
  if (best != nil && out_content_kind != nullptr) {
    *out_content_kind = best_kind;
  }
  if (best != nil && out_local_point != nullptr) {
    *out_local_point = best_local_point;
  }
  return best;
}

void ClearDropSession(NSWindow* window) {
  [g_drop_sessions removeObjectForKey:window];
  if (g_drop_sessions.count == 0) {
    g_drop_sessions = nil;
  }
}

void SetDropSession(NSWindow* window, DaDropDestinationOwner* owner,
                    NSInteger sequence_number, DaDropContentKind kind) {
  if (g_drop_sessions == nil) {
    g_drop_sessions = [NSMapTable weakToStrongObjectsMapTable];
  }
  DaDropDestinationSession* session = [[DaDropDestinationSession alloc] init];
  session.owner = owner;
  session.sequenceNumber = sequence_number;
  session.contentKind = kind;
  [g_drop_sessions setObject:session forKey:window];
}

DaDropDestinationOwner* ResolveActiveDropDestination(
    NSWindow* window, id<NSDraggingInfo> sender,
    DaDropContentKind* out_content_kind, NSPoint* out_local_point) {
  DaDropDestinationSession* session = [g_drop_sessions objectForKey:window];
  if (session == nil || session.owner == nil ||
      session.sequenceNumber != [sender draggingSequenceNumber]) {
    return nil;
  }
  DaDropContentKind kind = DA_DROP_CONTENT_PLAIN_TEXT;
  NSPoint local_point = NSZeroPoint;
  DaDropDestinationOwner* owner = ResolveDropDestination(
      window, sender, &kind, &local_point);
  if (owner == nil || owner != session.owner || kind != session.contentKind) {
    return nil;
  }
  if (out_content_kind != nullptr) {
    *out_content_kind = kind;
  }
  if (out_local_point != nullptr) {
    *out_local_point = local_point;
  }
  return owner;
}

void AppendUint32LittleEndian(std::string* output, uint32_t value) {
  output->push_back(static_cast<char>(value & 0xffu));
  output->push_back(static_cast<char>((value >> 8) & 0xffu));
  output->push_back(static_cast<char>((value >> 16) & 0xffu));
  output->push_back(static_cast<char>((value >> 24) & 0xffu));
}

bool CopyDropFileUrlPacket(NSPasteboard* pasteboard,
                           DaDropDestinationOwner* owner,
                           std::string* out_packet) {
  const NSInteger initial_change_count = pasteboard.changeCount;
  NSArray<NSPasteboardItem*>* items = pasteboard.pasteboardItems;
  if (items.count == 0 || items.count > owner.maximumFileUrlCount ||
      items.count > DA_DROP_FILE_URL_MAX_COUNT) {
    return false;
  }
  std::vector<std::string> urls;
  urls.reserve(items.count);
  size_t total_url_bytes = 0;
  for (NSPasteboardItem* item in items) {
    NSString* value = [item stringForType:NSPasteboardTypeFileURL];
    NSURL* url = value == nil ? nil : [NSURL URLWithString:value];
    NSString* host = url.host;
    const bool local_host = host == nil || host.length == 0 ||
                            [host caseInsensitiveCompare:@"localhost"] ==
                                NSOrderedSame;
    if (url == nil || !url.isFileURL || url.baseURL != nil || !local_host ||
        url.user != nil || url.password != nil || url.port != nil ||
        url.query != nil || url.fragment != nil || url.path.length == 0 ||
        ![url.path hasPrefix:@"/"]) {
      return false;
    }
    NSURL* normalized = url.URLByStandardizingPath;
    NSData* bytes = [normalized.absoluteString
        dataUsingEncoding:NSUTF8StringEncoding
     allowLossyConversion:NO];
    if (bytes == nil || bytes.length == 0 ||
        bytes.length > owner.maximumFileUrlUtf8Bytes ||
        bytes.length > DA_DROP_FILE_URL_MAX_UTF8_BYTES ||
        total_url_bytes >
            owner.maximumTotalFileUrlUtf8Bytes - bytes.length) {
      return false;
    }
    total_url_bytes += bytes.length;
    urls.emplace_back(static_cast<const char*>(bytes.bytes), bytes.length);
  }
  if (total_url_bytes > owner.maximumTotalFileUrlUtf8Bytes ||
      total_url_bytes > DA_DROP_FILE_URL_TOTAL_MAX_UTF8_BYTES ||
      pasteboard.changeCount != initial_change_count) {
    return false;
  }
  const size_t packet_size = sizeof(uint32_t) +
                             urls.size() * sizeof(uint32_t) +
                             total_url_bytes;
  if (packet_size > DA_DROP_FILE_URL_PACKET_MAX_BYTES) {
    return false;
  }
  out_packet->clear();
  out_packet->reserve(packet_size);
  AppendUint32LittleEndian(out_packet, static_cast<uint32_t>(urls.size()));
  for (const std::string& url : urls) {
    AppendUint32LittleEndian(out_packet, static_cast<uint32_t>(url.size()));
    out_packet->append(url);
  }
  return true;
}

DaQuickLookRequestOwner* QuickLookOwnerForHandle(DaHandle handle) {
  for (DaQuickLookRequestOwner* owner in
       [g_quick_look_request_owners copy]) {
    if (owner.view == nil) {
      [g_quick_look_request_owners removeObject:owner];
    } else if (owner.daHandle == handle) {
      return owner;
    }
  }
  return nil;
}

DaQuickLookRequestOwner* QuickLookOwnerForView(NSView* view) {
  for (DaQuickLookRequestOwner* owner in
       [g_quick_look_request_owners copy]) {
    NSView* candidate = owner.view;
    if (candidate == nil) {
      [g_quick_look_request_owners removeObject:owner];
    } else if (candidate == view) {
      return owner;
    }
  }
  return nil;
}

void StopQuickLookMonitorIfUnused() {
  if (g_quick_look_request_owners.count != 0 ||
      g_quick_look_event_monitor == nil) {
    return;
  }
  [NSEvent removeMonitor:g_quick_look_event_monitor];
  g_quick_look_event_monitor = nil;
  g_quick_look_request_owners = nil;
}

bool DispatchQuickLookPressure(DaQuickLookRequestOwner* owner, NSPoint point,
                               NSInteger stage) {
  if (owner == nil || owner.view == nil || stage < 0 || stage > 2 ||
      !std::isfinite(point.x) || !std::isfinite(point.y)) {
    return false;
  }
  if (stage < 2) {
    owner.previousPressureStage = stage;
    return false;
  }
  if (owner.previousPressureStage >= 2) {
    return false;
  }
  owner.previousPressureStage = stage;
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_VIEW_QUICK_LOOK_REQUESTED;
  event.window = owner.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.x = point.x;
  event.y = point.y;
  return dart_appkit::PostEvent(event);
}

DaQuickLookRequestOwner* QuickLookOwnerUnderEvent(NSEvent* event,
                                                  NSPoint* out_point) {
  NSWindow* window = event.window;
  NSView* content_view = window.contentView;
  if (window == nil || content_view == nil) {
    return nil;
  }
  const NSPoint content_point =
      [content_view convertPoint:event.locationInWindow fromView:nil];
  NSView* hit = [content_view hitTest:content_point];
  if (hit == nil) {
    return nil;
  }
  DaQuickLookRequestOwner* best = nil;
  NSUInteger best_depth = NSUIntegerMax;
  for (DaQuickLookRequestOwner* owner in
       [g_quick_look_request_owners copy]) {
    NSView* view = owner.view;
    if (view == nil) {
      [g_quick_look_request_owners removeObject:owner];
      continue;
    }
    if (view.window != window ||
        (view != hit && ![hit isDescendantOf:view])) {
      continue;
    }
    NSUInteger depth = 0;
    NSView* cursor = hit;
    while (cursor != nil && cursor != view) {
      cursor = cursor.superview;
      ++depth;
    }
    if (cursor == view && depth < best_depth) {
      best = owner;
      best_depth = depth;
    }
  }
  if (best != nil && out_point != nullptr) {
    *out_point = [best.view convertPoint:event.locationInWindow fromView:nil];
  }
  StopQuickLookMonitorIfUnused();
  return best;
}

NSEvent* HandleQuickLookLocalEvent(NSEvent* event) {
  if (event.type == NSEventTypeLeftMouseUp) {
    for (DaQuickLookRequestOwner* owner in g_quick_look_request_owners) {
      if (owner.view.window == event.window) {
        owner.previousPressureStage = 0;
      }
    }
    return event;
  }
  if (event.type != NSEventTypePressure) {
    return event;
  }
  NSPoint point = NSZeroPoint;
  DaQuickLookRequestOwner* owner = QuickLookOwnerUnderEvent(event, &point);
  (void)DispatchQuickLookPressure(owner, point, event.stage);
  return event;
}

void EnsureQuickLookMonitor() {
  if (g_quick_look_event_monitor != nil) {
    return;
  }
  g_quick_look_event_monitor = [NSEvent
      addLocalMonitorForEventsMatchingMask:(NSEventMaskPressure |
                                            NSEventMaskLeftMouseUp)
                                  handler:^NSEvent*(NSEvent* event) {
                                    return HandleQuickLookLocalEvent(event);
                                  }];
}

void RemoveQuickLookOwnerForView(NSView* view) {
  DaQuickLookRequestOwner* owner = QuickLookOwnerForView(view);
  if (owner != nil) {
    owner.daHandle = 0;
    owner.view = nil;
    [g_quick_look_request_owners removeObject:owner];
  }
  StopQuickLookMonitorIfUnused();
}

}  // namespace

id DaServicesTextRequestorForWindow(NSWindow* window,
                                    NSPasteboardType send_type,
                                    NSPasteboardType return_type) {
  if (window == nil || (send_type == nil && return_type == nil)) {
    return nil;
  }
  NSResponder* first_responder = window.firstResponder;
  if (![first_responder isKindOfClass:NSView.class]) {
    return nil;
  }
  NSView* responder_view = static_cast<NSView*>(first_responder);
  DaServicesTextRequestor* best = nil;
  NSUInteger best_depth = NSUIntegerMax;
  for (DaServicesTextRequestor* requestor in
       [g_services_text_requestors copy]) {
    NSView* view = requestor.view;
    if (view == nil) {
      [g_services_text_requestors removeObject:requestor];
      continue;
    }
    const BOOL send_supported =
        send_type == nil ||
        ([send_type isEqualToString:NSPasteboardTypeString] &&
         requestor.selectionText != nil);
    const BOOL return_supported =
        return_type == nil ||
        ([return_type isEqualToString:NSPasteboardTypeString] &&
         requestor.acceptsReturnedText);
    if (!send_supported || !return_supported || view.window != window ||
        (view != responder_view &&
         ![responder_view isDescendantOf:view])) {
      continue;
    }
    NSUInteger depth = 0;
    NSView* cursor = responder_view;
    while (cursor != nil && cursor != view) {
      cursor = cursor.superview;
      ++depth;
    }
    if (cursor == view && depth < best_depth) {
      best = requestor;
      best_depth = depth;
    }
  }
  if (g_services_text_requestors.count == 0) {
    g_services_text_requestors = nil;
  }
  return best;
}

NSDragOperation DaDropDraggingUpdated(NSWindow* window,
                                      id<NSDraggingInfo> sender) {
  DaDropContentKind kind = DA_DROP_CONTENT_PLAIN_TEXT;
  DaDropDestinationOwner* owner =
      ResolveDropDestination(window, sender, &kind, nullptr);
  if (owner == nil) {
    ClearDropSession(window);
    return NSDragOperationNone;
  }
  SetDropSession(window, owner, [sender draggingSequenceNumber], kind);
  return NSDragOperationCopy;
}

void DaDropDraggingExited(NSWindow* window, id<NSDraggingInfo> sender) {
  (void)sender;
  ClearDropSession(window);
}

BOOL DaDropPrepareForOperation(NSWindow* window, id<NSDraggingInfo> sender) {
  return ResolveActiveDropDestination(window, sender, nullptr, nullptr) != nil;
}

BOOL DaDropPerformOperation(NSWindow* window, id<NSDraggingInfo> sender) {
  DaDropContentKind kind = DA_DROP_CONTENT_PLAIN_TEXT;
  NSPoint local_point = NSZeroPoint;
  DaDropDestinationOwner* owner = ResolveActiveDropDestination(
      window, sender, &kind, &local_point);
  if (owner == nil) {
    ClearDropSession(window);
    return NO;
  }
  std::string payload;
  NSPasteboard* pasteboard = [sender draggingPasteboard];
  if (kind == DA_DROP_CONTENT_PLAIN_TEXT) {
    DaPasteboardText snapshot{};
    if (dart_appkit::ReadPasteboardTextWithLimit(
            pasteboard, owner.maximumTextUtf8Bytes, &snapshot) !=
            DA_STATUS_OK ||
        snapshot.has_text == 0) {
      ClearDropSession(window);
      return NO;
    }
    if (snapshot.text_length != 0) {
      payload.assign(snapshot.text, snapshot.text_length);
    }
  } else if (kind == DA_DROP_CONTENT_FILE_URLS) {
    if (!CopyDropFileUrlPacket(pasteboard, owner, &payload)) {
      ClearDropSession(window);
      return NO;
    }
  } else {
    ClearDropSession(window);
    return NO;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_VIEW_DROP_PERFORMED;
  event.window = owner.daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  event.x = local_point.x;
  event.y = local_point.y;
  event.drop_content_kind = kind;
  event.characters = std::move(payload);
  ClearDropSession(window);
  return dart_appkit::PostEvent(event) ? YES : NO;
}

void DaDropDraggingEnded(NSWindow* window, id<NSDraggingInfo> sender) {
  (void)sender;
  ClearDropSession(window);
}

@implementation DaApplicationAppearanceObserver

- (instancetype)initWithApplication:(NSApplication*)application {
  self = [super init];
  if (self != nil) {
    _application = application;
    _lastIsDark = DaApplicationUsesDarkAppearance(application);
    [application addObserver:self
                  forKeyPath:@"effectiveAppearance"
                     options:0
                     context:&g_application_appearance_observation_context];
    _observing = YES;
  }
  return self;
}

- (void)stop {
  NSApplication* application = _application;
  if (!_observing || application == nil) {
    _observing = NO;
    return;
  }
  _observing = NO;
  [application removeObserver:self
                   forKeyPath:@"effectiveAppearance"
                      context:&g_application_appearance_observation_context];
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id>*)change
                       context:(void*)context {
  (void)keyPath;
  (void)object;
  (void)change;
  if (context != &g_application_appearance_observation_context) {
    [super observeValueForKeyPath:keyPath
                         ofObject:object
                           change:change
                          context:context];
    return;
  }
  NSApplication* application = _application;
  if (!_observing || application == nil) {
    return;
  }
  const BOOL is_dark = DaApplicationUsesDarkAppearance(application);
  if (is_dark == _lastIsDark) {
    return;
  }
  _lastIsDark = is_dark;
  dart_appkit::PostApplicationAppearanceChanged(is_dark);
}

- (void)dealloc {
  [self stop];
}

@end

@implementation DaMenuItemOwner

@synthesize item = _item;
@synthesize separator = _separator;

- (instancetype)initWithTitle:(NSString*)title
                keyEquivalent:(NSString*)keyEquivalent
                    modifiers:(NSEventModifierFlags)modifiers {
  self = [super init];
  if (self != nil) {
    _separator = NO;
    _item = [[NSMenuItem alloc] initWithTitle:title
                                       action:@selector(daPerformAction:)
                                keyEquivalent:keyEquivalent];
    _item.keyEquivalentModifierMask = modifiers;
    _item.target = self;
  }
  return self;
}

- (instancetype)initSeparator {
  self = [super init];
  if (self != nil) {
    _separator = YES;
    _item = [NSMenuItem separatorItem];
  }
  return self;
}

- (void)daPerformAction:(id)sender {
  (void)sender;
  if (_separator || _daHandle == 0) {
    return;
  }
  dart_appkit::NativeEvent event;
  event.type = DA_EVENT_MENU_ITEM_INVOKED;
  event.window = _daHandle;
  event.monotonic_nanos = dart_appkit::MonotonicNanos();
  (void)dart_appkit::PostEvent(event);
}

- (void)daPrepareForRelease {
  _daHandle = 0;
  _item.enabled = NO;
  _item.target = nil;
  _item.action = nil;
}

@end

namespace dart_appkit {
namespace {

struct ErrorState {
  int32_t code = DA_STATUS_OK;
  std::string message;
};

thread_local ErrorState g_last_error;
thread_local std::string g_pasteboard_text;
thread_local std::string g_text_editor_snapshot;
std::atomic<bool> g_accept_async_releases{true};
std::atomic<uint64_t> g_async_release_epoch{1};
bool g_defers_application_termination_requests = false;
int64_t g_pending_application_termination_operation_id = 0;
bool g_programmatic_application_termination = false;
DaApplicationAppearanceObserver* g_application_appearance_observer = nil;
NSMutableDictionary<NSString*, NSNumber*>* g_pending_user_notifications = nil;
uint64_t g_next_user_notification_token = 1;
constexpr NSUInteger kMaximumPendingUserNotifications = 256;
constexpr uint64_t kStableModifierMask =
    DA_MODIFIER_CAPS_LOCK | DA_MODIFIER_SHIFT | DA_MODIFIER_CONTROL |
    DA_MODIFIER_OPTION | DA_MODIFIER_COMMAND | DA_MODIFIER_NUMERIC_PAD |
    DA_MODIFIER_FUNCTION;

bool HandleUserNotificationWithSystem(
    UserNotificationOperation operation, std::string_view identifier,
    std::string_view title, std::string_view body, void* context);
UserNotificationHandler g_user_notification_handler =
    HandleUserNotificationWithSystem;
void* g_user_notification_context = nullptr;
DefinitionPresentationHandler g_definition_presentation_handler = nullptr;
void* g_definition_presentation_context = nullptr;

bool IsAsciiSchemeCharacter(unichar unit, bool first) {
  const bool alpha = (unit >= 'A' && unit <= 'Z') ||
                     (unit >= 'a' && unit <= 'z');
  if (first) {
    return alpha;
  }
  return alpha || (unit >= '0' && unit <= '9') || unit == '+' || unit == '-' ||
         unit == '.';
}

bool IsUnsafeUrlCodeUnit(unichar unit) {
  return unit <= 0x20 || unit == 0x5c ||
         (unit >= 0x7f && unit <= 0x9f) || unit == 0xa0 || unit == 0xad ||
         unit == 0x61c || unit == 0x1680 || unit == 0x180e ||
         (unit >= 0x2000 && unit <= 0x200f) ||
         (unit >= 0x2028 && unit <= 0x202f) ||
         (unit >= 0x205f && unit <= 0x206f) || unit == 0x3000 ||
         unit == 0xfeff;
}

bool IsUnsafeDecodedUrlCodeUnit(unichar unit) {
  return (unit < 0x20) || (unit > 0x20 && IsUnsafeUrlCodeUnit(unit));
}

int HexValue(unichar unit) {
  if (unit >= '0' && unit <= '9') {
    return unit - '0';
  }
  if (unit >= 'A' && unit <= 'F') {
    return unit - 'A' + 10;
  }
  if (unit >= 'a' && unit <= 'f') {
    return unit - 'a' + 10;
  }
  return -1;
}

bool ContainsUnsafeUrlText(NSString* value) {
  const NSUInteger length = value.length;
  for (NSUInteger index = 0; index < length; ++index) {
    const unichar unit = [value characterAtIndex:index];
    if (IsUnsafeUrlCodeUnit(unit)) {
      return true;
    }
    if (unit != '%') {
      continue;
    }
    if (index + 2 >= length) {
      return true;
    }
    const int high = HexValue([value characterAtIndex:index + 1]);
    const int low = HexValue([value characterAtIndex:index + 2]);
    if (high < 0 || low < 0) {
      return true;
    }
    const int byte = (high << 4) | low;
    if (byte <= 0x1f || byte == 0x5c || byte == 0x7f) {
      return true;
    }
    index += 2;
  }
  NSString* decoded = [value stringByRemovingPercentEncoding];
  if (decoded == nil) {
    return true;
  }
  if (![decoded isEqualToString:value]) {
    for (NSUInteger index = 0; index < decoded.length; ++index) {
      if (IsUnsafeDecodedUrlCodeUnit([decoded characterAtIndex:index])) {
        return true;
      }
    }
  }
  return false;
}

bool OpenUrlWithWorkspace(NSURL* url) {
  return [[NSWorkspace sharedWorkspace] openURL:url];
}

NSString* CopyUtf8(const char* bytes, size_t length, int32_t* out_status) {
  if (bytes == nullptr && length != 0) {
    *out_status =
        SetLastError(DA_STATUS_INVALID_ARGUMENT,
                     "UTF-8 pointer may be null only when byte length is zero");
    return nil;
  }
  if (length > static_cast<size_t>(std::numeric_limits<NSInteger>::max())) {
    *out_status = SetLastError(DA_STATUS_INVALID_ARGUMENT,
                               "UTF-8 byte length exceeds platform limits");
    return nil;
  }
  if (length == 0) {
    *out_status = DA_STATUS_OK;
    return @"";
  }

  NSString* value = [[NSString alloc] initWithBytes:bytes
                                             length:length
                                           encoding:NSUTF8StringEncoding];
  if (value == nil) {
    *out_status =
        SetLastError(DA_STATUS_INVALID_UTF8, "input is not valid UTF-8");
    return nil;
  }
  *out_status = DA_STATUS_OK;
  return value;
}

bool ContainsUnsafeDisplayText(NSString* value) {
  for (NSUInteger index = 0; index < value.length; ++index) {
    const unichar unit = [value characterAtIndex:index];
    if (unit <= 0x1f || (unit >= 0x7f && unit <= 0x9f) || unit == 0xa0 ||
        unit == 0xad || unit == 0x61c || unit == 0x1680 || unit == 0x180e ||
        (unit >= 0x2000 && unit <= 0x200f) ||
        (unit >= 0x2028 && unit <= 0x202f) ||
        (unit >= 0x205f && unit <= 0x206f) || unit == 0x3000 ||
        unit == 0xfeff) {
      return true;
    }
  }
  return false;
}

bool ValidUserNotificationIdentifier(const char* bytes, size_t length) {
  if (bytes == nullptr || length == 0 ||
      length > DA_USER_NOTIFICATION_IDENTIFIER_MAX_UTF8_BYTES) {
    return false;
  }
  for (size_t index = 0; index < length; ++index) {
    const unsigned char byte = static_cast<unsigned char>(bytes[index]);
    const bool valid = (byte >= '0' && byte <= '9') ||
                       (byte >= 'A' && byte <= 'Z') ||
                       (byte >= 'a' && byte <= 'z') || byte == '-' ||
                       byte == '.' || byte == '+' || byte == '_';
    if (!valid) {
      return false;
    }
  }
  return true;
}

NSString* CopyStringView(std::string_view value) {
  return [[NSString alloc] initWithBytes:value.data()
                                  length:value.size()
                                encoding:NSUTF8StringEncoding];
}

bool HandleUserNotificationWithSystem(
    UserNotificationOperation operation, std::string_view identifier,
    std::string_view title, std::string_view body, void* context) {
  (void)context;
  NSString* copied_identifier = CopyStringView(identifier);
  UNUserNotificationCenter* center =
      [UNUserNotificationCenter currentNotificationCenter];
  if (operation == UserNotificationOperation::kRemove) {
    [g_pending_user_notifications removeObjectForKey:copied_identifier];
    NSArray<NSString*>* identifiers = @[ copied_identifier ];
    [center removePendingNotificationRequestsWithIdentifiers:identifiers];
    [center removeDeliveredNotificationsWithIdentifiers:identifiers];
    return true;
  }

  if (g_pending_user_notifications == nil) {
    g_pending_user_notifications = [[NSMutableDictionary alloc] init];
  }
  if (g_pending_user_notifications[copied_identifier] == nil &&
      g_pending_user_notifications.count >= kMaximumPendingUserNotifications) {
    return false;
  }
  uint64_t token = g_next_user_notification_token++;
  if (token == 0) {
    token = g_next_user_notification_token++;
  }
  g_pending_user_notifications[copied_identifier] = @(token);
  NSString* copied_title = CopyStringView(title);
  NSString* copied_body = CopyStringView(body);
  [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                        completionHandler:^(BOOL granted, NSError* error) {
    (void)error;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSNumber* current =
          g_pending_user_notifications[copied_identifier];
      if (!granted || current == nil || current.unsignedLongLongValue != token) {
        if (current != nil && current.unsignedLongLongValue == token) {
          [g_pending_user_notifications removeObjectForKey:copied_identifier];
        }
        return;
      }
      UNMutableNotificationContent* content =
          [[UNMutableNotificationContent alloc] init];
      content.title = copied_title;
      content.body = copied_body;
      UNNotificationRequest* request =
          [UNNotificationRequest requestWithIdentifier:copied_identifier
                                                content:content
                                                trigger:nil];
      [center addNotificationRequest:request
               withCompletionHandler:^(NSError* scheduling_error) {
        (void)scheduling_error;
        dispatch_async(dispatch_get_main_queue(), ^{
          NSNumber* completed =
              g_pending_user_notifications[copied_identifier];
          if (completed != nil &&
              completed.unsignedLongLongValue == token) {
            [g_pending_user_notifications removeObjectForKey:copied_identifier];
          }
        });
      }];
    });
  }];
  return true;
}

int32_t ValidateRect(DaRect frame) {
  if (!std::isfinite(frame.x) || !std::isfinite(frame.y) ||
      !std::isfinite(frame.width) || !std::isfinite(frame.height) ||
      frame.width <= 0.0 || frame.height <= 0.0) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "window frame must contain finite values and positive dimensions");
  }
  return DA_STATUS_OK;
}

bool PopulateScreenSnapshot(NSScreen* screen, DaScreenSnapshot* out_snapshot) {
  if (screen == nil || out_snapshot == nullptr) {
    return false;
  }
  NSNumber* screen_number =
      screen.deviceDescription[(NSDeviceDescriptionKey)@"NSScreenNumber"];
  const unsigned long long display_id = screen_number.unsignedLongLongValue;
  const NSRect frame = screen.frame;
  const NSRect visible_frame = screen.visibleFrame;
  const double scale = screen.backingScaleFactor;
  const bool valid = screen_number != nil && display_id > 0 &&
                     display_id <= std::numeric_limits<uint32_t>::max() &&
                     std::isfinite(frame.origin.x) &&
                     std::isfinite(frame.origin.y) &&
                     std::isfinite(frame.size.width) &&
                     std::isfinite(frame.size.height) &&
                     frame.size.width > 0.0 && frame.size.height > 0.0 &&
                     std::isfinite(visible_frame.origin.x) &&
                     std::isfinite(visible_frame.origin.y) &&
                     std::isfinite(visible_frame.size.width) &&
                     std::isfinite(visible_frame.size.height) &&
                     visible_frame.size.width > 0.0 &&
                     visible_frame.size.height > 0.0 &&
                     std::isfinite(scale) && scale > 0.0;
  if (!valid) {
    return false;
  }
  *out_snapshot = {
      DA_SCREEN_SNAPSHOT_VERSION_1_SIZE,
      static_cast<uint64_t>(display_id),
      {frame.origin.x, frame.origin.y, frame.size.width, frame.size.height},
      {visible_frame.origin.x, visible_frame.origin.y,
       visible_frame.size.width, visible_frame.size.height},
      scale,
  };
  return true;
}

int32_t ValidateAnimationDuration(double duration_seconds) {
  if (!std::isfinite(duration_seconds) || duration_seconds < 0.0 ||
      duration_seconds > DA_WINDOW_PRESENTATION_ANIMATION_MAX_SECONDS) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "window presentation duration must be finite and between 0 and 5");
  }
  return DA_STATUS_OK;
}

int32_t ValidateWindowPresentationConfiguration(
    const DaWindowPresentationConfiguration* configuration) {
  if (configuration == nullptr ||
      configuration->struct_size <
          DA_WINDOW_PRESENTATION_CONFIGURATION_VERSION_1_SIZE) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "window presentation configuration is missing or too small");
  }
  constexpr uint64_t kSupportedCollectionBehavior =
      DA_WINDOW_COLLECTION_BEHAVIOR_CAN_JOIN_ALL_SPACES |
      DA_WINDOW_COLLECTION_BEHAVIOR_FULL_SCREEN_AUXILIARY |
      DA_WINDOW_COLLECTION_BEHAVIOR_STATIONARY |
      DA_WINDOW_COLLECTION_BEHAVIOR_TRANSIENT;
  if (configuration->level < DA_WINDOW_LEVEL_NORMAL ||
      configuration->level > DA_WINDOW_LEVEL_STATUS ||
      configuration->reserved != 0 ||
      (configuration->collection_behavior_mask &
       ~kSupportedCollectionBehavior) != 0) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "window presentation level, reserved field, or collection behavior "
        "is invalid");
  }
  return DA_STATUS_OK;
}

NSWindowLevel WindowLevel(int32_t level) {
  switch (level) {
    case DA_WINDOW_LEVEL_NORMAL:
      return NSNormalWindowLevel;
    case DA_WINDOW_LEVEL_FLOATING:
      return NSFloatingWindowLevel;
    case DA_WINDOW_LEVEL_STATUS:
      return NSStatusWindowLevel;
  }
  return NSNormalWindowLevel;
}

NSWindowCollectionBehavior WindowCollectionBehavior(uint64_t mask) {
  NSWindowCollectionBehavior result = NSWindowCollectionBehaviorDefault;
  if ((mask & DA_WINDOW_COLLECTION_BEHAVIOR_CAN_JOIN_ALL_SPACES) != 0) {
    result |= NSWindowCollectionBehaviorCanJoinAllSpaces;
  }
  if ((mask & DA_WINDOW_COLLECTION_BEHAVIOR_FULL_SCREEN_AUXILIARY) != 0) {
    result |= NSWindowCollectionBehaviorFullScreenAuxiliary;
  }
  if ((mask & DA_WINDOW_COLLECTION_BEHAVIOR_STATIONARY) != 0) {
    result |= NSWindowCollectionBehaviorStationary;
  }
  if ((mask & DA_WINDOW_COLLECTION_BEHAVIOR_TRANSIENT) != 0) {
    result |= NSWindowCollectionBehaviorTransient;
  }
  return result;
}

int32_t ValidateViewConfiguration(const DaViewConfiguration* configuration) {
  if (configuration == nullptr ||
      configuration->struct_size < DA_VIEW_CONFIGURATION_VERSION_1_SIZE) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "view configuration is missing or smaller than version 1");
  }
  constexpr uint64_t kAutoresizingMask =
      DA_VIEW_AUTORESIZE_WIDTH | DA_VIEW_AUTORESIZE_HEIGHT;
  if ((configuration->autoresizing_mask & ~kAutoresizingMask) != 0 ||
      (configuration->accepts_first_responder != 0 &&
       configuration->accepts_first_responder != 1) ||
      configuration->reserved != 0) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "view configuration values are invalid");
  }
  return DA_STATUS_OK;
}

void ApplyViewConfiguration(DaView* view,
                            const DaViewConfiguration& configuration) {
  NSAutoresizingMaskOptions mask = 0;
  if ((configuration.autoresizing_mask & DA_VIEW_AUTORESIZE_WIDTH) != 0) {
    mask |= NSViewWidthSizable;
  }
  if ((configuration.autoresizing_mask & DA_VIEW_AUTORESIZE_HEIGHT) != 0) {
    mask |= NSViewHeightSizable;
  }
  view.autoresizingMask = mask;
  view.daAcceptsFirstResponder = configuration.accepts_first_responder == 1;
}

bool ValidTextViewColor(const DaTextViewColorConfiguration& color) {
  if (color.reserved != 0 || color.kind < DA_TEXT_VIEW_COLOR_LABEL ||
      color.kind > DA_TEXT_VIEW_COLOR_SRGB) {
    return false;
  }
  if (color.kind != DA_TEXT_VIEW_COLOR_SRGB) {
    return color.red == 0.0 && color.green == 0.0 && color.blue == 0.0 &&
           color.alpha == 1.0;
  }
  return std::isfinite(color.red) && std::isfinite(color.green) &&
         std::isfinite(color.blue) && std::isfinite(color.alpha) &&
         color.red >= 0.0 && color.red <= 1.0 && color.green >= 0.0 &&
         color.green <= 1.0 && color.blue >= 0.0 && color.blue <= 1.0 &&
         color.alpha >= 0.0 && color.alpha <= 1.0;
}

NSColor* TextViewColor(const DaTextViewColorConfiguration& color) {
  switch (color.kind) {
    case DA_TEXT_VIEW_COLOR_LABEL:
      return NSColor.labelColor;
    case DA_TEXT_VIEW_COLOR_WINDOW_BACKGROUND:
      return NSColor.windowBackgroundColor;
    case DA_TEXT_VIEW_COLOR_SRGB:
      return [NSColor colorWithSRGBRed:color.red
                                green:color.green
                                 blue:color.blue
                                alpha:color.alpha];
  }
  return nil;
}

NSFontWeight TextViewFontWeight(int32_t weight) {
  switch (weight) {
    case DA_TEXT_VIEW_FONT_WEIGHT_ULTRA_LIGHT:
      return NSFontWeightUltraLight;
    case DA_TEXT_VIEW_FONT_WEIGHT_THIN:
      return NSFontWeightThin;
    case DA_TEXT_VIEW_FONT_WEIGHT_LIGHT:
      return NSFontWeightLight;
    case DA_TEXT_VIEW_FONT_WEIGHT_REGULAR:
      return NSFontWeightRegular;
    case DA_TEXT_VIEW_FONT_WEIGHT_MEDIUM:
      return NSFontWeightMedium;
    case DA_TEXT_VIEW_FONT_WEIGHT_SEMIBOLD:
      return NSFontWeightSemibold;
    case DA_TEXT_VIEW_FONT_WEIGHT_BOLD:
      return NSFontWeightBold;
    case DA_TEXT_VIEW_FONT_WEIGHT_HEAVY:
      return NSFontWeightHeavy;
    case DA_TEXT_VIEW_FONT_WEIGHT_BLACK:
      return NSFontWeightBlack;
  }
  return NSFontWeightRegular;
}

int32_t ResolveTextViewFont(const DaTextViewConfiguration* configuration,
                            const char* font_family,
                            size_t font_family_length,
                            NSFont** out_font) {
  if (configuration == nullptr ||
      configuration->struct_size <
          DA_TEXT_VIEW_CONFIGURATION_VERSION_1_SIZE) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "text view configuration is missing or smaller than version 1");
  }
  const int32_t view_status =
      ValidateViewConfiguration(&configuration->view);
  if (view_status != DA_STATUS_OK) {
    return view_status;
  }
  if (configuration->font_kind < DA_TEXT_VIEW_FONT_SYSTEM ||
      configuration->font_kind > DA_TEXT_VIEW_FONT_NAMED ||
      configuration->font_weight < DA_TEXT_VIEW_FONT_WEIGHT_ULTRA_LIGHT ||
      configuration->font_weight > DA_TEXT_VIEW_FONT_WEIGHT_BLACK ||
      (configuration->font_kind == DA_TEXT_VIEW_FONT_NAMED &&
       configuration->font_weight != DA_TEXT_VIEW_FONT_WEIGHT_REGULAR) ||
      !std::isfinite(configuration->font_size) ||
      configuration->font_size <= 0.0 ||
      configuration->font_size > DA_TEXT_VIEW_FONT_MAX_SIZE) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "text view font kind, weight, or size is invalid");
  }
  const double padding[] = {
      configuration->padding_top,
      configuration->padding_right,
      configuration->padding_bottom,
      configuration->padding_left,
  };
  for (const double extent : padding) {
    if (!std::isfinite(extent) || extent < 0.0 ||
        extent > DA_TEXT_VIEW_PADDING_MAX_EXTENT) {
      return SetLastError(
          DA_STATUS_INVALID_ARGUMENT,
          "text view padding must be finite and within the bound");
    }
  }
  if (!ValidTextViewColor(configuration->foreground_color) ||
      !ValidTextViewColor(configuration->background_color)) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "text view color kind, reserved field, or components are invalid");
  }
  if (font_family_length > DA_TEXT_VIEW_FONT_FAMILY_MAX_UTF8_BYTES) {
    return SetLastError(
        DA_STATUS_LIMIT_EXCEEDED,
        "text view font family exceeds the UTF-8 byte limit");
  }
  int32_t status = DA_STATUS_OK;
  NSString* copied_font_family =
      CopyUtf8(font_family, font_family_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  const bool uses_named_font =
      configuration->font_kind == DA_TEXT_VIEW_FONT_NAMED;
  if ((uses_named_font && copied_font_family.length == 0) ||
      (!uses_named_font && copied_font_family.length != 0)) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "font family must be present only for a named text view font");
  }
  const NSFontWeight weight = TextViewFontWeight(configuration->font_weight);
  NSFont* font = nil;
  if (configuration->font_kind == DA_TEXT_VIEW_FONT_SYSTEM) {
    font = [NSFont systemFontOfSize:configuration->font_size weight:weight];
  } else if (configuration->font_kind ==
             DA_TEXT_VIEW_FONT_MONOSPACED_SYSTEM) {
    font = [NSFont monospacedSystemFontOfSize:configuration->font_size
                                      weight:weight];
  } else {
    font = [NSFont fontWithName:copied_font_family
                          size:configuration->font_size];
  }
  if (font == nil) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "text view named font is not available on this system");
  }
  *out_font = font;
  return DA_STATUS_OK;
}

int32_t ResolveDefinitionFont(
    const DaDefinitionPresentationConfiguration* configuration,
    const char* font_family, size_t font_family_length, NSFont** out_font) {
  if (configuration == nullptr ||
      configuration->struct_size <
          DA_DEFINITION_PRESENTATION_CONFIGURATION_VERSION_1_SIZE ||
      configuration->reserved_0 != 0 || configuration->reserved_1 != 0 ||
      configuration->font_kind < DA_TEXT_VIEW_FONT_SYSTEM ||
      configuration->font_kind > DA_TEXT_VIEW_FONT_NAMED ||
      configuration->font_weight < DA_TEXT_VIEW_FONT_WEIGHT_ULTRA_LIGHT ||
      configuration->font_weight > DA_TEXT_VIEW_FONT_WEIGHT_BLACK ||
      (configuration->font_kind == DA_TEXT_VIEW_FONT_NAMED &&
       configuration->font_weight != DA_TEXT_VIEW_FONT_WEIGHT_REGULAR) ||
      !std::isfinite(configuration->font_size) ||
      configuration->font_size <= 0.0 ||
      configuration->font_size > DA_TEXT_VIEW_FONT_MAX_SIZE ||
      !std::isfinite(configuration->baseline_x) ||
      !std::isfinite(configuration->baseline_y)) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "definition presentation configuration is invalid");
  }
  if (font_family_length > DA_TEXT_VIEW_FONT_FAMILY_MAX_UTF8_BYTES) {
    return SetLastError(DA_STATUS_LIMIT_EXCEEDED,
                        "definition font family exceeds the UTF-8 limit");
  }
  int32_t status = DA_STATUS_OK;
  NSString* copied_family =
      CopyUtf8(font_family, font_family_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  const bool named = configuration->font_kind == DA_TEXT_VIEW_FONT_NAMED;
  if ((named && copied_family.length == 0) ||
      (!named && copied_family.length != 0)) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "definition font family must be present only for a named font");
  }
  const NSFontWeight weight = TextViewFontWeight(configuration->font_weight);
  NSFont* font = nil;
  if (configuration->font_kind == DA_TEXT_VIEW_FONT_SYSTEM) {
    font = [NSFont systemFontOfSize:configuration->font_size weight:weight];
  } else if (configuration->font_kind ==
             DA_TEXT_VIEW_FONT_MONOSPACED_SYSTEM) {
    font = [NSFont monospacedSystemFontOfSize:configuration->font_size
                                      weight:weight];
  } else {
    font = [NSFont fontWithName:copied_family size:configuration->font_size];
  }
  if (font == nil) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "definition named font is not available");
  }
  *out_font = font;
  return DA_STATUS_OK;
}

DaTextEditor* TextEditor(DaHandle handle, int32_t* out_status) {
  NSView* view = static_cast<NSView*>(ObjectRegistry::Shared().Lookup(
      handle, ObjectKind::kView, ThreadDomain::kAppKitMain, out_status));
  if (view == nil) {
    return nil;
  }
  if (![view isKindOfClass:DaTextEditor.class]) {
    *out_status = SetLastError(DA_STATUS_WRONG_HANDLE_TYPE,
                               "expected text editor handle");
    return nil;
  }
  *out_status = DA_STATUS_OK;
  return static_cast<DaTextEditor*>(view);
}

bool Utf16ScalarBoundary(NSString* text, uint64_t offset) {
  const uint64_t length = static_cast<uint64_t>(text.length);
  if (offset == 0 || offset == length) {
    return true;
  }
  if (offset > length) {
    return false;
  }
  const unichar before = [text characterAtIndex:offset - 1];
  const unichar after = [text characterAtIndex:offset];
  const bool before_is_high = before >= 0xd800 && before <= 0xdbff;
  const bool after_is_low = after >= 0xdc00 && after <= 0xdfff;
  return !(before_is_high && after_is_low);
}

int32_t ValidateTextEditorSelection(NSString* text,
                                    uint64_t location,
                                    uint64_t length) {
  const uint64_t text_length = static_cast<uint64_t>(text.length);
  if (location > text_length || length > text_length - location ||
      !Utf16ScalarBoundary(text, location) ||
      !Utf16ScalarBoundary(text, location + length)) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "text editor selection must be in bounds and aligned to UTF-16 scalar boundaries");
  }
  return DA_STATUS_OK;
}

int32_t ValidateTextEditorStyleRuns(NSString* text,
                                    const DaTextEditorStyleRun* runs,
                                    size_t count) {
  if (count > DA_TEXT_EDITOR_MAX_STYLE_RUNS) {
    return SetLastError(DA_STATUS_LIMIT_EXCEEDED,
                        "text editor style run count exceeds the limit");
  }
  if (runs == nullptr && count != 0) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "text editor style runs must not be null when non-empty");
  }
  const uint64_t text_length = static_cast<uint64_t>(text.length);
  uint64_t previous_end = 0;
  for (size_t index = 0; index < count; ++index) {
    const DaTextEditorStyleRun& run = runs[index];
    if (run.location < previous_end || run.length == 0 ||
        run.location > text_length ||
        run.length > text_length - run.location ||
        !Utf16ScalarBoundary(text, run.location) ||
        !Utf16ScalarBoundary(text, run.location + run.length) ||
        !ValidTextViewColor(run.foreground_color) ||
        !ValidTextViewColor(run.underline_color) || run.reserved != 0 ||
        (run.underline_style != DA_TEXT_EDITOR_UNDERLINE_NONE &&
         run.underline_style != DA_TEXT_EDITOR_UNDERLINE_SINGLE)) {
      return SetLastError(
          DA_STATUS_INVALID_ARGUMENT,
          "text editor style runs must be ordered, non-overlapping, valid, and aligned to UTF-16 scalar boundaries");
    }
    previous_end = run.location + run.length;
  }
  return DA_STATUS_OK;
}

void ApplyTextEditorStyleRunsToStorage(
    DaTextEditor* editor,
    NSMutableAttributedString* storage,
    const DaTextEditorStyleRun* runs,
    size_t count) {
  [storage beginEditing];
  const NSRange entire_range = NSMakeRange(0, storage.length);
  if (entire_range.length != 0) {
    [storage setAttributes:@{
      NSFontAttributeName : editor.daFont,
      NSForegroundColorAttributeName : editor.daForegroundColor,
    }
                    range:entire_range];
  }
  for (size_t index = 0; index < count; ++index) {
    const DaTextEditorStyleRun& run = runs[index];
    NSMutableDictionary<NSAttributedStringKey, id>* attributes =
        [@{NSForegroundColorAttributeName :
               TextViewColor(run.foreground_color)} mutableCopy];
    if (run.underline_style == DA_TEXT_EDITOR_UNDERLINE_SINGLE) {
      attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
      attributes[NSUnderlineColorAttributeName] =
          TextViewColor(run.underline_color);
    }
    [storage addAttributes:attributes
                     range:NSMakeRange(run.location, run.length)];
  }
  [storage endEditing];
}

void ApplyTextEditorStyleRuns(DaTextEditor* editor,
                              const DaTextEditorStyleRun* runs,
                              size_t count) {
  ApplyTextEditorStyleRunsToStorage(editor, editor.daTextView.textStorage,
                                    runs, count);
  editor.daTextView.typingAttributes = @{
    NSFontAttributeName : editor.daFont,
    NSForegroundColorAttributeName : editor.daForegroundColor,
  };
}

DaWindowOwner* WindowOwner(DaHandle handle, int32_t* out_status) {
  return static_cast<DaWindowOwner*>(ObjectRegistry::Shared().Lookup(
      handle, ObjectKind::kWindow, ThreadDomain::kAppKitMain, out_status));
}

NSView* View(DaHandle handle, int32_t* out_status) {
  return static_cast<NSView*>(ObjectRegistry::Shared().Lookup(
      handle, ObjectKind::kView, ThreadDomain::kAppKitMain, out_status));
}

DaSplitView* SplitView(DaHandle handle, int32_t* out_status) {
  NSView* view = View(handle, out_status);
  if (view == nil) {
    return nil;
  }
  if (![view isKindOfClass:DaSplitView.class]) {
    *out_status = SetLastError(DA_STATUS_WRONG_HANDLE_TYPE,
                               "expected split view handle");
    return nil;
  }
  *out_status = DA_STATUS_OK;
  return static_cast<DaSplitView*>(view);
}

DaTextView* TextView(DaHandle handle, int32_t* out_status) {
  return static_cast<DaTextView*>(ObjectRegistry::Shared().Lookup(
      handle, ObjectKind::kTextView, ThreadDomain::kAppKitMain, out_status));
}

NSMenu* Menu(DaHandle handle, int32_t* out_status) {
  return static_cast<NSMenu*>(ObjectRegistry::Shared().Lookup(
      handle, ObjectKind::kMenu, ThreadDomain::kAppKitMain, out_status));
}

DaMenuItemOwner* MenuItemOwner(DaHandle handle, int32_t* out_status) {
  return static_cast<DaMenuItemOwner*>(ObjectRegistry::Shared().Lookup(
      handle, ObjectKind::kMenuItem, ThreadDomain::kAppKitMain, out_status));
}

UInt32 CarbonHotKeyModifiers(uint64_t modifiers, int32_t* out_status) {
  constexpr uint64_t kSupported = DA_MODIFIER_SHIFT | DA_MODIFIER_CONTROL |
                                  DA_MODIFIER_OPTION | DA_MODIFIER_COMMAND;
  if (modifiers == 0 || (modifiers & ~kSupported) != 0) {
    *out_status = SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "global hot key requires Shift, Control, Option, or Command only");
    return 0;
  }
  UInt32 result = 0;
  if ((modifiers & DA_MODIFIER_SHIFT) != 0) {
    result |= shiftKey;
  }
  if ((modifiers & DA_MODIFIER_CONTROL) != 0) {
    result |= controlKey;
  }
  if ((modifiers & DA_MODIFIER_OPTION) != 0) {
    result |= optionKey;
  }
  if ((modifiers & DA_MODIFIER_COMMAND) != 0) {
    result |= cmdKey;
  }
  *out_status = DA_STATUS_OK;
  return result;
}

NSEventModifierFlags AppKitModifiers(uint64_t modifiers, int32_t* out_status) {
  if ((modifiers & ~kStableModifierMask) != 0) {
    *out_status =
        SetLastError(DA_STATUS_INVALID_ARGUMENT,
                     "menu shortcut contains unsupported modifier bits");
    return 0;
  }
  NSEventModifierFlags result = 0;
  if ((modifiers & DA_MODIFIER_CAPS_LOCK) != 0) {
    result |= NSEventModifierFlagCapsLock;
  }
  if ((modifiers & DA_MODIFIER_SHIFT) != 0) {
    result |= NSEventModifierFlagShift;
  }
  if ((modifiers & DA_MODIFIER_CONTROL) != 0) {
    result |= NSEventModifierFlagControl;
  }
  if ((modifiers & DA_MODIFIER_OPTION) != 0) {
    result |= NSEventModifierFlagOption;
  }
  if ((modifiers & DA_MODIFIER_COMMAND) != 0) {
    result |= NSEventModifierFlagCommand;
  }
  if ((modifiers & DA_MODIFIER_NUMERIC_PAD) != 0) {
    result |= NSEventModifierFlagNumericPad;
  }
  if ((modifiers & DA_MODIFIER_FUNCTION) != 0) {
    result |= NSEventModifierFlagFunction;
  }
  *out_status = DA_STATUS_OK;
  return result;
}

void PrepareWindowForRelease(DaWindowOwner* owner) {
  if (owner == nil) {
    return;
  }
  [owner daInvalidatePresentation];
  owner.daHandle = 0;
  owner.window.daHandle = 0;
  owner.window.delegate = nil;
  ClearDropSession(owner.window);
  [owner.window unregisterDraggedTypes];
  [owner.window orderOut:nil];
  [owner daCloseProgrammatically];
}

void PrepareMenuForRelease(NSMenu* menu) {
  if (menu == nil) {
    return;
  }
  for (NSView* view in g_context_menu_views.allObjects) {
    if (view.menu == menu) {
      view.menu = nil;
      [g_context_menu_views removeObject:view];
    }
  }
  if (g_context_menu_views.count == 0) {
    g_context_menu_views = nil;
  }
  if (NSApp.mainMenu == menu) {
    NSApp.mainMenu = nil;
  }
}

void PrepareViewForRelease(NSView* view) {
  if (view == nil) {
    return;
  }
  view.menu = nil;
  RemoveQuickLookOwnerForView(view);
  RemoveServicesTextRequestorForView(view);
  RemoveDropDestinationOwnerForView(view);
  [g_context_menu_views removeObject:view];
  if (g_context_menu_views.count == 0) {
    g_context_menu_views = nil;
  }
}

int32_t CompletePendingRelease(DaHandle handle) {
  ObjectRegistry& registry = ObjectRegistry::Shared();
  ObjectKind kind = ObjectKind::kView;
  int32_t status = DA_STATUS_OK;
  __strong id object = registry.LookupPendingRelease(
      handle, ThreadDomain::kAppKitMain, &kind, &status);
  if (object == nil) {
    return status;
  }
  if (kind == ObjectKind::kWindow) {
    PrepareWindowForRelease(static_cast<DaWindowOwner*>(object));
  } else if ((kind == ObjectKind::kView || kind == ObjectKind::kTextView) &&
             [object isKindOfClass:NSView.class]) {
    PrepareViewForRelease(static_cast<NSView*>(object));
  } else if (kind == ObjectKind::kMenu) {
    PrepareMenuForRelease(static_cast<NSMenu*>(object));
  } else if (kind == ObjectKind::kMenuItem) {
    [static_cast<DaMenuItemOwner*>(object) daPrepareForRelease];
  } else if (kind == ObjectKind::kGlobalHotKey) {
    [static_cast<DaGlobalHotKeyOwner*>(object) daPrepareForRelease];
  } else if (kind == ObjectKind::kSecureEventInput) {
    [static_cast<DaSecureEventInputOwner*>(object) daPrepareForRelease];
  }
  __strong id released_object =
      registry.CompleteRelease(handle, ThreadDomain::kAppKitMain, &status);
  if (released_object == nil) {
    return status;
  }
  return DA_STATUS_OK;
}

int32_t EnqueueAsyncRelease(DaHandle handle) {
  const uint64_t release_epoch =
      g_async_release_epoch.load(std::memory_order_acquire);
  if (!g_accept_async_releases.load(std::memory_order_acquire)) {
    return SetLastError(DA_STATUS_SHUTTING_DOWN,
                        "native bridge is shutting down");
  }
  ObjectRegistry& registry = ObjectRegistry::Shared();
  const int32_t status =
      registry.BeginRelease(handle, ThreadDomain::kAppKitMain);
  if (status != DA_STATUS_OK) {
    return status;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_accept_async_releases.load(std::memory_order_acquire) &&
        g_async_release_epoch.load(std::memory_order_acquire) ==
            release_epoch) {
      (void)CompletePendingRelease(handle);
    }
  });
  return DA_STATUS_OK;
}

}  // namespace

int ResolveScreenSelectionIndex(
    int32_t selection, const std::vector<ScreenSelectionCandidate>& candidates,
    double mouse_x, double mouse_y) {
  if (candidates.empty()) {
    return -1;
  }
  int main_index = 0;
  for (size_t index = 0; index < candidates.size(); ++index) {
    if (candidates[index].is_main) {
      main_index = static_cast<int>(index);
      break;
    }
  }
  if (selection == DA_SCREEN_SELECTION_MENU_BAR) {
    return 0;
  }
  if (selection == DA_SCREEN_SELECTION_MOUSE) {
    for (size_t index = 0; index < candidates.size(); ++index) {
      const DaRect frame = candidates[index].snapshot.frame;
      if (mouse_x >= frame.x && mouse_x < frame.x + frame.width &&
          mouse_y >= frame.y && mouse_y < frame.y + frame.height) {
        return static_cast<int>(index);
      }
    }
  }
  return main_index;
}

void ClearLastError() {
  g_last_error.code = DA_STATUS_OK;
  g_last_error.message.clear();
}

int32_t SetLastError(DaStatus status, std::string_view message) {
  g_last_error.code = status;
  g_last_error.message.assign(message);
  return status;
}

int32_t RequireMainThread() {
  if (pthread_main_np() == 0) {
    return SetLastError(
        DA_STATUS_WRONG_THREAD,
        "AppKit bridge call must run on the process main thread");
  }
  return DA_STATUS_OK;
}

int32_t OpenExternalUrlWithPolicy(NSString* value, NSString* expected_scheme,
                                  uint64_t policy_flags,
                                  ExternalUrlOpenFunction opener,
                                  int32_t* out_opened) {
  if (out_opened == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "out_opened must not be null");
  }
  *out_opened = 0;
  if (value == nil || expected_scheme == nil || opener == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL, policy scheme, and opener must not be null");
  }
  NSData* utf8 = [value dataUsingEncoding:NSUTF8StringEncoding];
  if (utf8 == nil) {
    return SetLastError(DA_STATUS_INVALID_UTF8,
                        "external URL could not be encoded as UTF-8");
  }
  if (utf8.length == 0) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL must not be empty");
  }
  if (utf8.length > DA_EXTERNAL_URL_MAX_UTF8_BYTES) {
    return SetLastError(DA_STATUS_LIMIT_EXCEEDED,
                        "external URL exceeds the UTF-8 byte limit");
  }
  if (ContainsUnsafeUrlText(value)) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "external URL contains unsafe or ambiguous characters");
  }

  NSData* scheme_utf8 =
      [expected_scheme dataUsingEncoding:NSUTF8StringEncoding];
  if (scheme_utf8 == nil || scheme_utf8.length == 0 ||
      scheme_utf8.length > DA_EXTERNAL_URL_SCHEME_MAX_UTF8_BYTES ||
      ![expected_scheme isEqualToString:expected_scheme.lowercaseString]) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "external URL policy scheme must be lowercase bounded ASCII");
  }
  for (NSUInteger index = 0; index < expected_scheme.length; ++index) {
    if (!IsAsciiSchemeCharacter([expected_scheme characterAtIndex:index],
                                index == 0)) {
      return SetLastError(
          DA_STATUS_INVALID_ARGUMENT,
          "external URL policy scheme must be lowercase bounded ASCII");
    }
  }
  constexpr uint64_t kPolicyMask =
      DA_EXTERNAL_URL_POLICY_REQUIRE_AUTHORITY |
      DA_EXTERNAL_URL_POLICY_FORBID_AUTHORITY |
      DA_EXTERNAL_URL_POLICY_REQUIRE_HOST |
      DA_EXTERNAL_URL_POLICY_FORBID_CREDENTIALS |
      DA_EXTERNAL_URL_POLICY_REQUIRE_PATH;
  if ((policy_flags & ~kPolicyMask) != 0 ||
      ((policy_flags & DA_EXTERNAL_URL_POLICY_REQUIRE_AUTHORITY) != 0 &&
       (policy_flags & DA_EXTERNAL_URL_POLICY_FORBID_AUTHORITY) != 0) ||
      ((policy_flags & DA_EXTERNAL_URL_POLICY_REQUIRE_HOST) != 0 &&
       (policy_flags & DA_EXTERNAL_URL_POLICY_FORBID_AUTHORITY) != 0)) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL policy flags are invalid");
  }

  const NSRange colon = [value rangeOfString:@":"];
  if (colon.location == NSNotFound || colon.location == 0) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL must contain an absolute scheme");
  }
  for (NSUInteger index = 0; index < colon.location; ++index) {
    if (!IsAsciiSchemeCharacter([value characterAtIndex:index], index == 0)) {
      return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                          "external URL scheme must be ASCII");
    }
  }

  NSURLComponents* components = [NSURLComponents componentsWithString:value];
  if (components == nil || components.scheme == nil) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL is malformed");
  }
  NSString* scheme = components.scheme.lowercaseString;
  if (![scheme isEqualToString:expected_scheme]) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL scheme does not match application policy");
  }
  const NSUInteger authority_index = colon.location + 1;
  const bool has_authority =
      authority_index + 1 < value.length &&
      [value characterAtIndex:authority_index] == '/' &&
      [value characterAtIndex:authority_index + 1] == '/';
  if (((policy_flags & DA_EXTERNAL_URL_POLICY_REQUIRE_AUTHORITY) != 0 &&
       !has_authority) ||
      ((policy_flags & DA_EXTERNAL_URL_POLICY_FORBID_AUTHORITY) != 0 &&
       has_authority) ||
      ((policy_flags & DA_EXTERNAL_URL_POLICY_REQUIRE_HOST) != 0 &&
       components.host.length == 0) ||
      ((policy_flags & DA_EXTERNAL_URL_POLICY_FORBID_CREDENTIALS) != 0 &&
       (components.user != nil || components.password != nil)) ||
      ((policy_flags & DA_EXTERNAL_URL_POLICY_REQUIRE_PATH) != 0 &&
       components.path.length == 0)) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "external URL does not satisfy application policy conditions");
  }

  NSURL* url = components.URL;
  if (url == nil || url.scheme == nil) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL cannot be represented by NSURL");
  }
  *out_opened = opener(url) ? 1 : 0;
  return DA_STATUS_OK;
}

int32_t OpenAllowedExternalUrl(NSString* value,
                               ExternalUrlOpenFunction opener,
                               int32_t* out_opened) {
  NSString* expected_scheme = nil;
  uint64_t policy_flags = 0;
  const NSRange colon = [value rangeOfString:@":"];
  if (colon.location != NSNotFound && colon.location > 0) {
    expected_scheme =
        [[value substringToIndex:colon.location] lowercaseString];
    if ([expected_scheme isEqualToString:@"http"] ||
        [expected_scheme isEqualToString:@"https"]) {
      policy_flags = DA_EXTERNAL_URL_POLICY_REQUIRE_AUTHORITY |
                     DA_EXTERNAL_URL_POLICY_REQUIRE_HOST |
                     DA_EXTERNAL_URL_POLICY_FORBID_CREDENTIALS;
    } else if ([expected_scheme isEqualToString:@"mailto"]) {
      policy_flags = DA_EXTERNAL_URL_POLICY_FORBID_AUTHORITY |
                     DA_EXTERNAL_URL_POLICY_FORBID_CREDENTIALS |
                     DA_EXTERNAL_URL_POLICY_REQUIRE_PATH;
    } else {
      expected_scheme = nil;
    }
  }
  return OpenExternalUrlWithPolicy(value, expected_scheme, policy_flags,
                                   opener, out_opened);
}

int32_t GetPasteboardChangeCount(NSPasteboard* pasteboard,
                                 int64_t* out_change_count) {
  if (out_change_count == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "out_change_count must not be null");
  }
  *out_change_count = 0;
  if (pasteboard == nil) {
    return SetLastError(DA_STATUS_INTERNAL_ERROR,
                        "pasteboard is not available");
  }
  const NSInteger change_count = pasteboard.changeCount;
  if (change_count < 0) {
    return SetLastError(DA_STATUS_INTERNAL_ERROR,
                        "pasteboard returned a negative change count");
  }
  *out_change_count = static_cast<int64_t>(change_count);
  return DA_STATUS_OK;
}

int32_t ReadPasteboardText(NSPasteboard* pasteboard,
                           DaPasteboardText* out_snapshot) {
  return ReadPasteboardTextWithLimit(
      pasteboard, DA_PASTEBOARD_TEXT_MAX_UTF8_BYTES, out_snapshot);
}

int32_t ReadPasteboardTextWithLimit(NSPasteboard* pasteboard,
                                    size_t maximum_utf8_bytes,
                                    DaPasteboardText* out_snapshot) {
  if (out_snapshot == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "out_snapshot must not be null");
  }
  *out_snapshot = {};
  int64_t change_count = 0;
  const int32_t count_status =
      GetPasteboardChangeCount(pasteboard, &change_count);
  if (count_status != DA_STATUS_OK) {
    return count_status;
  }

  NSString* value = [pasteboard stringForType:NSPasteboardTypeString];
  if (value == nil) {
    g_pasteboard_text.clear();
    out_snapshot->change_count = change_count;
    return DA_STATUS_OK;
  }
  NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    return SetLastError(DA_STATUS_INTERNAL_ERROR,
                        "pasteboard text could not be encoded as UTF-8");
  }
  if (data.length > maximum_utf8_bytes) {
    g_pasteboard_text.clear();
    return SetLastError(DA_STATUS_LIMIT_EXCEEDED,
                        "pasteboard UTF-8 text exceeds the read limit");
  }
  if (data.length == 0) {
    g_pasteboard_text.clear();
  } else {
    g_pasteboard_text.assign(static_cast<const char*>(data.bytes), data.length);
  }
  out_snapshot->text =
      g_pasteboard_text.empty() ? nullptr : g_pasteboard_text.data();
  out_snapshot->text_length = g_pasteboard_text.size();
  out_snapshot->has_text = 1;
  out_snapshot->change_count = change_count;
  return DA_STATUS_OK;
}

int32_t WritePasteboardText(NSPasteboard* pasteboard, const char* text,
                            size_t text_length, int64_t* out_change_count) {
  if (out_change_count == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "out_change_count must not be null");
  }
  *out_change_count = 0;
  if (pasteboard == nil) {
    return SetLastError(DA_STATUS_INTERNAL_ERROR,
                        "pasteboard is not available");
  }
  int32_t status = DA_STATUS_OK;
  NSString* value = CopyUtf8(text, text_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  [pasteboard clearContents];
  if (![pasteboard setString:value forType:NSPasteboardTypeString]) {
    return SetLastError(DA_STATUS_INTERNAL_ERROR,
                        "pasteboard rejected the plain-text value");
  }
  return GetPasteboardChangeCount(pasteboard, out_change_count);
}

int32_t ClearPasteboard(NSPasteboard* pasteboard, int64_t* out_change_count) {
  if (out_change_count == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "out_change_count must not be null");
  }
  *out_change_count = 0;
  if (pasteboard == nil) {
    return SetLastError(DA_STATUS_INTERNAL_ERROR,
                        "pasteboard is not available");
  }
  [pasteboard clearContents];
  return GetPasteboardChangeCount(pasteboard, out_change_count);
}

void PostApplicationActiveChanged(bool is_active) {
  NativeEvent event;
  event.type = DA_EVENT_APPLICATION_ACTIVE_CHANGED;
  event.monotonic_nanos = MonotonicNanos();
  event.state = is_active;
  (void)PostEvent(event);
}

void PostApplicationReopenRequested(bool has_visible_windows) {
  NativeEvent event;
  event.type = DA_EVENT_APPLICATION_REOPEN_REQUESTED;
  event.monotonic_nanos = MonotonicNanos();
  event.state = has_visible_windows;
  (void)PostEvent(event);
}

void PostApplicationAppearanceChanged(bool is_dark) {
  NativeEvent event;
  event.type = DA_EVENT_APPLICATION_APPEARANCE_CHANGED;
  event.monotonic_nanos = MonotonicNanos();
  event.state = is_dark;
  (void)PostEvent(event);
}

bool ApplicationUsesDarkAppearance() {
  return DaApplicationUsesDarkAppearance(NSApp);
}

void StartApplicationAppearanceObservation() {
  StopApplicationAppearanceObservation();
  if (NSApp != nil) {
    g_application_appearance_observer =
        [[DaApplicationAppearanceObserver alloc] initWithApplication:NSApp];
  }
}

void StopApplicationAppearanceObservation() {
  [g_application_appearance_observer stop];
  g_application_appearance_observer = nil;
}

ApplicationTerminationDecision HandleApplicationShouldTerminate() {
  if (g_programmatic_application_termination) {
    g_programmatic_application_termination = false;
    g_pending_application_termination_operation_id = 0;
    return ApplicationTerminationDecision::kTerminateNow;
  }
  if (!g_defers_application_termination_requests) {
    return ApplicationTerminationDecision::kTerminateNow;
  }
  if (g_pending_application_termination_operation_id > 0) {
    return ApplicationTerminationDecision::kTerminateLater;
  }

  NativeEvent event;
  event.type = DA_EVENT_APPLICATION_TERMINATE_REQUESTED;
  event.monotonic_nanos = MonotonicNanos();
  event.operation_id = NextOperationId();
  g_pending_application_termination_operation_id = event.operation_id;
  if (!PostEvent(event)) {
    g_pending_application_termination_operation_id = 0;
    return ApplicationTerminationDecision::kTerminateNow;
  }
  return ApplicationTerminationDecision::kTerminateLater;
}

void InstallUserNotificationHandlerForTesting(UserNotificationHandler handler,
                                               void* context) {
  g_user_notification_handler =
      handler == nullptr ? HandleUserNotificationWithSystem : handler;
  g_user_notification_context = handler == nullptr ? nullptr : context;
}

void InstallSecureEventInputHandlersForTesting(
    SecureEventInputStatusHandler enable_handler,
    SecureEventInputStatusHandler disable_handler,
    SecureEventInputEnabledHandler enabled_handler,
    ApplicationActiveQuery active_query) {
  g_secure_event_input_enable_handler =
      enable_handler == nullptr ? EnableSecureEventInputWithSystem
                                : enable_handler;
  g_secure_event_input_disable_handler =
      disable_handler == nullptr ? DisableSecureEventInputWithSystem
                                 : disable_handler;
  g_secure_event_input_enabled_handler =
      enabled_handler == nullptr ? IsSecureEventInputEnabledWithSystem
                                 : enabled_handler;
  g_application_active_query =
      active_query == nullptr ? IsApplicationActiveWithSystem : active_query;
}

void InstallDefinitionPresentationHandlerForTesting(
    DefinitionPresentationHandler handler, void* context) {
  g_definition_presentation_handler = handler;
  g_definition_presentation_context = handler == nullptr ? nullptr : context;
}

bool HandleQuickLookPressureForTesting(DaHandle handle, double x, double y,
                                       int64_t stage) {
  return DispatchQuickLookPressure(QuickLookOwnerForHandle(handle),
                                   NSMakePoint(x, y), stage);
}

void ShutdownBridge() {
  if (pthread_main_np() == 0) {
    return;
  }
  g_accept_async_releases.store(false, std::memory_order_release);
  g_async_release_epoch.fetch_add(1, std::memory_order_acq_rel);
  StopApplicationAppearanceObservation();
  DisableEventPoster();
  g_defers_application_termination_requests = false;
  g_pending_application_termination_operation_id = 0;
  g_programmatic_application_termination = false;
  [g_pending_user_notifications removeAllObjects];
  g_pending_user_notifications = nil;
  if (NSApp != nil) {
    NSApp.dockTile.badgeLabel = nil;
    [NSApp.dockTile display];
  }

  ObjectRegistry& registry = ObjectRegistry::Shared();
  const std::vector<DaHandle> handles = registry.LiveHandles();
  for (const DaHandle handle : handles) {
    const int32_t claim_status =
        registry.BeginRelease(handle, ThreadDomain::kAppKitMain);
    if (claim_status == DA_STATUS_OK ||
        claim_status == DA_STATUS_INVALID_HANDLE) {
      (void)CompletePendingRelease(handle);
    }
  }
  registry.Clear();
  [g_drop_sessions removeAllObjects];
  g_drop_sessions = nil;
  [g_drop_destination_owners removeAllObjects];
  g_drop_destination_owners = nil;
  StopGlobalHotKeyInfrastructure();
}

void ResetBridgeForTesting() {
  ShutdownBridge();
  ClearCustomViewClassesForTesting();
  InstallUserNotificationHandlerForTesting(nullptr, nullptr);
  InstallSecureEventInputHandlersForTesting(nullptr, nullptr, nullptr,
                                            nullptr);
  InstallDefinitionPresentationHandlerForTesting(nullptr, nullptr);
  g_accept_async_releases.store(true, std::memory_order_release);
  ClearLastError();
}

}  // namespace dart_appkit

uint32_t da_abi_version(void) { return DA_ABI_VERSION; }

const char* da_status_name(int32_t status) {
  switch (status) {
    case DA_STATUS_OK:
      return "ok";
    case DA_STATUS_INVALID_ARGUMENT:
      return "invalid_argument";
    case DA_STATUS_INVALID_UTF8:
      return "invalid_utf8";
    case DA_STATUS_INVALID_HANDLE:
      return "invalid_handle";
    case DA_STATUS_WRONG_HANDLE_TYPE:
      return "wrong_handle_type";
    case DA_STATUS_WRONG_THREAD:
      return "wrong_thread";
    case DA_STATUS_EVENT_PORT_UNAVAILABLE:
      return "event_port_unavailable";
    case DA_STATUS_INTERNAL_ERROR:
      return "internal_error";
    case DA_STATUS_UNSUPPORTED_VERSION:
      return "unsupported_version";
    case DA_STATUS_SHUTTING_DOWN:
      return "shutting_down";
    case DA_STATUS_LIMIT_EXCEEDED:
      return "limit_exceeded";
    case DA_STATUS_GLOBAL_HOT_KEY_CONFLICT:
      return "global_hot_key_conflict";
    case DA_STATUS_GLOBAL_HOT_KEY_REGISTRATION_FAILED:
      return "global_hot_key_registration_failed";
    case DA_STATUS_SECURE_EVENT_INPUT_FAILED:
      return "secure_event_input_failed";
    default:
      return "unknown_status";
  }
}

void da_get_last_error(DaError* out_error) {
  if (out_error == nullptr) {
    return;
  }
  out_error->code = dart_appkit::g_last_error.code;
  out_error->message = dart_appkit::g_last_error.message.data();
  out_error->message_length = dart_appkit::g_last_error.message.size();
}

int32_t da_application_set_event_port(int64_t dart_port) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  dart_appkit::StopApplicationAppearanceObservation();
  return dart_appkit::SetEventPort(dart_port);
}

int32_t da_application_set_event_port_versioned(
    int64_t dart_port, uint32_t min_version, uint32_t max_version,
    uint32_t* out_selected_version) {
  dart_appkit::ClearLastError();
  if (out_selected_version != nullptr) {
    *out_selected_version = 0;
  }
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  dart_appkit::StopApplicationAppearanceObservation();
  const int32_t status = dart_appkit::SetEventPortVersioned(
      dart_port, min_version, max_version, out_selected_version);
  if (status == DA_STATUS_OK) {
    dart_appkit::PostApplicationActiveChanged(NSApp != nil && NSApp.isActive);
    if (*out_selected_version >= 7) {
      dart_appkit::StartApplicationAppearanceObservation();
      dart_appkit::PostApplicationAppearanceChanged(
          dart_appkit::ApplicationUsesDarkAppearance());
    }
  }
  return status;
}

int32_t da_application_terminate(void) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (NSApp == nil) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     "NSApplication is not initialized");
  }
  if (dart_appkit::g_pending_application_termination_operation_id > 0) {
    dart_appkit::g_pending_application_termination_operation_id = 0;
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp replyToApplicationShouldTerminate:YES];
    });
  } else {
    dart_appkit::g_programmatic_application_termination = true;
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
  }
  return DA_STATUS_OK;
}

int32_t da_application_set_termination_request_deferral(int32_t enabled) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (enabled != 0 && enabled != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "enabled must be 0 or 1");
  }
  if (enabled == 0 &&
      dart_appkit::g_pending_application_termination_operation_id > 0) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "reply to the pending termination request before disabling deferral");
  }
  dart_appkit::g_defers_application_termination_requests = enabled == 1;
  return DA_STATUS_OK;
}

int32_t da_application_reply_to_termination_request(int64_t operation_id,
                                                    int32_t allow) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (allow != 0 && allow != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "allow must be 0 or 1");
  }
  if (operation_id <= 0 ||
      operation_id !=
          dart_appkit::g_pending_application_termination_operation_id) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "operation_id does not match the pending termination request");
  }
  if (NSApp == nil) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     "NSApplication is not initialized");
  }
  dart_appkit::g_pending_application_termination_operation_id = 0;
  [NSApp replyToApplicationShouldTerminate:allow == 1];
  return DA_STATUS_OK;
}

int32_t da_application_open_external_url(const char* url, size_t url_length,
                                         int32_t* out_opened) {
  dart_appkit::ClearLastError();
  if (out_opened != nullptr) {
    *out_opened = 0;
  }
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (url_length > DA_EXTERNAL_URL_MAX_UTF8_BYTES) {
    return dart_appkit::SetLastError(
        DA_STATUS_LIMIT_EXCEEDED,
        "external URL exceeds the UTF-8 byte limit");
  }
  int32_t status = DA_STATUS_OK;
  NSString* value = dart_appkit::CopyUtf8(url, url_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  @try {
    return dart_appkit::OpenAllowedExternalUrl(
        value, dart_appkit::OpenUrlWithWorkspace, out_opened);
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR, exception.reason.UTF8String != nullptr
                                      ? exception.reason.UTF8String
                                      : "external URL open failed");
  }
}

int32_t da_application_open_external_url_with_policy(
    const char* url, size_t url_length, const char* expected_scheme,
    size_t expected_scheme_length, uint64_t policy_flags,
    int32_t* out_opened) {
  dart_appkit::ClearLastError();
  if (out_opened != nullptr) {
    *out_opened = 0;
  }
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (url_length > DA_EXTERNAL_URL_MAX_UTF8_BYTES ||
      expected_scheme_length > DA_EXTERNAL_URL_SCHEME_MAX_UTF8_BYTES) {
    return dart_appkit::SetLastError(
        DA_STATUS_LIMIT_EXCEEDED,
        "external URL or policy scheme exceeds its UTF-8 byte limit");
  }
  int32_t status = DA_STATUS_OK;
  NSString* value = dart_appkit::CopyUtf8(url, url_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  NSString* scheme = dart_appkit::CopyUtf8(
      expected_scheme, expected_scheme_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  @try {
    return dart_appkit::OpenExternalUrlWithPolicy(
        value, scheme, policy_flags, dart_appkit::OpenUrlWithWorkspace,
        out_opened);
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR, exception.reason.UTF8String != nullptr
                                      ? exception.reason.UTF8String
                                      : "external URL open failed");
  }
}

int32_t da_application_post_user_notification(
    const char* identifier, size_t identifier_length, const char* title,
    size_t title_length, const char* body, size_t body_length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (identifier_length > DA_USER_NOTIFICATION_IDENTIFIER_MAX_UTF8_BYTES ||
      title_length > DA_USER_NOTIFICATION_TEXT_MAX_UTF8_BYTES ||
      body_length > DA_USER_NOTIFICATION_TEXT_MAX_UTF8_BYTES) {
    return dart_appkit::SetLastError(
        DA_STATUS_LIMIT_EXCEEDED,
        "user notification input exceeds a UTF-8 byte limit");
  }
  if (!dart_appkit::ValidUserNotificationIdentifier(identifier,
                                                     identifier_length)) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "user notification identifier must be bounded nonempty ASCII");
  }
  int32_t status = DA_STATUS_OK;
  NSString* copied_title =
      dart_appkit::CopyUtf8(title, title_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  NSString* copied_body = dart_appkit::CopyUtf8(body, body_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  if ((copied_title.length == 0 && copied_body.length == 0) ||
      dart_appkit::ContainsUnsafeDisplayText(copied_title) ||
      dart_appkit::ContainsUnsafeDisplayText(copied_body)) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "user notification requires safe nonempty display text");
  }
  const std::string_view identifier_view(identifier, identifier_length);
  const std::string_view title_view(title == nullptr ? "" : title,
                                    title_length);
  const std::string_view body_view(body == nullptr ? "" : body, body_length);
  @try {
    if (!dart_appkit::g_user_notification_handler(
            dart_appkit::UserNotificationOperation::kPost, identifier_view,
            title_view, body_view,
            dart_appkit::g_user_notification_context)) {
      return dart_appkit::SetLastError(
          DA_STATUS_LIMIT_EXCEEDED,
          "user notification native pending limit is exhausted");
    }
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "user notification submission failed");
  }
}

int32_t da_application_remove_user_notification(const char* identifier,
                                                size_t identifier_length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (identifier_length > DA_USER_NOTIFICATION_IDENTIFIER_MAX_UTF8_BYTES) {
    return dart_appkit::SetLastError(
        DA_STATUS_LIMIT_EXCEEDED,
        "user notification identifier exceeds the UTF-8 byte limit");
  }
  if (!dart_appkit::ValidUserNotificationIdentifier(identifier,
                                                     identifier_length)) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "user notification identifier must be bounded nonempty ASCII");
  }
  @try {
    const std::string_view identifier_view(identifier, identifier_length);
    if (!dart_appkit::g_user_notification_handler(
            dart_appkit::UserNotificationOperation::kRemove, identifier_view,
            std::string_view(), std::string_view(),
            dart_appkit::g_user_notification_context)) {
      return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                       "user notification removal failed");
    }
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "user notification removal failed");
  }
}

int32_t da_application_set_dock_badge_label(const char* label,
                                            size_t label_length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (label_length > DA_DOCK_BADGE_LABEL_MAX_UTF8_BYTES) {
    return dart_appkit::SetLastError(
        DA_STATUS_LIMIT_EXCEEDED, "Dock badge exceeds the UTF-8 byte limit");
  }
  int32_t status = DA_STATUS_OK;
  NSString* copied_label = dart_appkit::CopyUtf8(label, label_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  if (dart_appkit::ContainsUnsafeDisplayText(copied_label)) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "Dock badge must contain safe display text");
  }
  if (NSApp == nil) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     "NSApplication is not initialized");
  }
  @try {
    NSApp.dockTile.badgeLabel = copied_label.length == 0 ? nil : copied_label;
    [NSApp.dockTile display];
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "Dock badge update failed");
  }
}

int32_t da_global_hot_key_register(uint16_t key_code, uint64_t modifiers,
                                   DaHandle* out_handle) {
  dart_appkit::ClearLastError();
  if (out_handle == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_handle must not be null");
  }
  *out_handle = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (key_code > 127) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "global hot key virtual key code must be between 0 and 127");
  }
  int32_t status = DA_STATUS_OK;
  const UInt32 carbon_modifiers =
      dart_appkit::CarbonHotKeyModifiers(modifiers, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  if (NSApp == nil) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     "NSApplication is not initialized");
  }
  @try {
    OSStatus registration_status = noErr;
    DaGlobalHotKeyOwner* owner =
        [[DaGlobalHotKeyOwner alloc] initWithKeyCode:key_code
                                          modifiers:carbon_modifiers
                                          exclusive:YES
                                              status:&registration_status];
    if (owner == nil || registration_status != noErr) {
      const DaStatus mapped_status = registration_status == eventHotKeyExistsErr
                                         ? DA_STATUS_GLOBAL_HOT_KEY_CONFLICT
                                         : DA_STATUS_GLOBAL_HOT_KEY_REGISTRATION_FAILED;
      const std::string message =
          std::string(registration_status == eventHotKeyExistsErr
                          ? "exclusive global hot key is already registered"
                          : "global hot key registration failed") +
          " (OSStatus " + std::to_string(registration_status) + ")";
      return dart_appkit::SetLastError(mapped_status, message);
    }
    const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
        owner, dart_appkit::ObjectKind::kGlobalHotKey,
        dart_appkit::ThreadDomain::kAppKitMain);
    if (handle == 0) {
      [owner daPrepareForRelease];
      return DA_STATUS_INTERNAL_ERROR;
    }
    owner.daHandle = handle;
    *out_handle = handle;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_GLOBAL_HOT_KEY_REGISTRATION_FAILED,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "global hot key registration raised an exception");
  }
}

int32_t da_secure_event_input_create(DaHandle* out_handle) {
  dart_appkit::ClearLastError();
  if (out_handle == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_handle must not be null");
  }
  *out_handle = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (g_secure_event_input_handle != 0) {
    return dart_appkit::SetLastError(
        DA_STATUS_LIMIT_EXCEEDED,
        "the bridge-wide secure event input owner already exists");
  }
  @try {
    DaSecureEventInputOwner* owner = [[DaSecureEventInputOwner alloc] init];
    const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
        owner, dart_appkit::ObjectKind::kSecureEventInput,
        dart_appkit::ThreadDomain::kAppKitMain);
    if (owner == nil || handle == 0) {
      [owner daPrepareForRelease];
      return dart_appkit::SetLastError(
          DA_STATUS_INTERNAL_ERROR,
          "secure event input owner allocation failed");
    }
    owner.daHandle = handle;
    g_secure_event_input_handle = handle;
    *out_handle = handle;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "secure event input owner creation raised an exception");
  }
}

int32_t da_secure_event_input_set_desired(DaHandle handle, int32_t desired) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (desired != 0 && desired != 1) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT, "desired must be zero or one");
  }
  int32_t status = DA_STATUS_OK;
  DaSecureEventInputOwner* owner =
      static_cast<DaSecureEventInputOwner*>(
          dart_appkit::ObjectRegistry::Shared().Lookup(
              handle, dart_appkit::ObjectKind::kSecureEventInput,
              dart_appkit::ThreadDomain::kAppKitMain, &status));
  if (owner == nil) {
    return status;
  }
  const int32_t os_status = [owner daSetDesired:desired != 0];
  if (os_status != noErr) {
    return dart_appkit::SetLastError(
        DA_STATUS_SECURE_EVENT_INPUT_FAILED,
        std::string(desired != 0 ? "enabling" : "disabling") +
            " Secure Event Input failed (OSStatus " +
            std::to_string(os_status) + ")");
  }
  return DA_STATUS_OK;
}

int32_t da_secure_event_input_get_snapshot(
    DaHandle handle, DaSecureEventInputSnapshot* out_snapshot) {
  dart_appkit::ClearLastError();
  if (out_snapshot == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_snapshot must not be null");
  }
  const uint64_t struct_size = out_snapshot->struct_size;
  *out_snapshot = {};
  if (struct_size < DA_SECURE_EVENT_INPUT_SNAPSHOT_VERSION_1_SIZE) {
    return dart_appkit::SetLastError(
        DA_STATUS_UNSUPPORTED_VERSION,
        "secure event input snapshot is smaller than version 1");
  }
  out_snapshot->struct_size =
      DA_SECURE_EVENT_INPUT_SNAPSHOT_VERSION_1_SIZE;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaSecureEventInputOwner* owner =
      static_cast<DaSecureEventInputOwner*>(
          dart_appkit::ObjectRegistry::Shared().Lookup(
              handle, dart_appkit::ObjectKind::kSecureEventInput,
              dart_appkit::ThreadDomain::kAppKitMain, &status));
  if (owner == nil) {
    return status;
  }
  out_snapshot->desired = owner.daDesired ? 1 : 0;
  out_snapshot->owned_enabled = owner.daOwnedEnabled ? 1 : 0;
  out_snapshot->system_enabled =
      g_secure_event_input_enabled_handler != nullptr &&
              g_secure_event_input_enabled_handler()
          ? 1
          : 0;
  out_snapshot->last_os_status = owner.daLastOSStatus;
  return DA_STATUS_OK;
}

int32_t da_pasteboard_read_text(DaPasteboardText* out_snapshot) {
  dart_appkit::ClearLastError();
  if (out_snapshot != nullptr) {
    *out_snapshot = {};
  }
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  @try {
    return dart_appkit::ReadPasteboardText(NSPasteboard.generalPasteboard,
                                           out_snapshot);
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "pasteboard read failed");
  }
}

int32_t da_pasteboard_write_text(const char* text, size_t text_length,
                                 int64_t* out_change_count) {
  dart_appkit::ClearLastError();
  if (out_change_count != nullptr) {
    *out_change_count = 0;
  }
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  @try {
    return dart_appkit::WritePasteboardText(
        NSPasteboard.generalPasteboard, text, text_length, out_change_count);
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "pasteboard write failed");
  }
}

int32_t da_pasteboard_clear(int64_t* out_change_count) {
  dart_appkit::ClearLastError();
  if (out_change_count != nullptr) {
    *out_change_count = 0;
  }
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  @try {
    return dart_appkit::ClearPasteboard(NSPasteboard.generalPasteboard,
                                        out_change_count);
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "pasteboard clear failed");
  }
}

int32_t da_pasteboard_get_change_count(int64_t* out_change_count) {
  dart_appkit::ClearLastError();
  if (out_change_count != nullptr) {
    *out_change_count = 0;
  }
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  @try {
    return dart_appkit::GetPasteboardChangeCount(NSPasteboard.generalPasteboard,
                                                 out_change_count);
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR, exception.reason.UTF8String != nullptr
                                      ? exception.reason.UTF8String
                                      : "pasteboard change-count read failed");
  }
}

int32_t da_menu_create_configured(
    const char* title, size_t title_length,
    const DaMenuConfiguration* configuration, DaHandle* out_menu) {
  dart_appkit::ClearLastError();
  if (out_menu == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_menu must not be null");
  }
  *out_menu = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (configuration == nullptr ||
      configuration->struct_size < DA_MENU_CONFIGURATION_VERSION_1_SIZE ||
      (configuration->auto_enables_items != 0 &&
       configuration->auto_enables_items != 1) ||
      configuration->reserved != 0) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "menu configuration is missing, undersized, or invalid");
  }
  int32_t status = DA_STATUS_OK;
  NSString* copied_title = dart_appkit::CopyUtf8(title, title_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  @try {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:copied_title];
    menu.autoenablesItems = configuration->auto_enables_items == 1;
    const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
        menu, dart_appkit::ObjectKind::kMenu,
        dart_appkit::ThreadDomain::kAppKitMain);
    if (handle == 0) {
      return DA_STATUS_INTERNAL_ERROR;
    }
    *out_menu = handle;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "AppKit menu creation failed");
  }
}

int32_t da_menu_create(const char* title, size_t title_length,
                       DaHandle* out_menu) {
  const DaMenuConfiguration configuration = {
      DA_MENU_CONFIGURATION_VERSION_1_SIZE,
      0,
      0,
  };
  return da_menu_create_configured(title, title_length, &configuration,
                                   out_menu);
}

int32_t da_menu_item_create(const char* title, size_t title_length,
                            const char* key_equivalent,
                            size_t key_equivalent_length, uint64_t modifiers,
                            DaHandle* out_item) {
  dart_appkit::ClearLastError();
  if (out_item == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_item must not be null");
  }
  *out_item = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  const NSEventModifierFlags appkit_modifiers =
      dart_appkit::AppKitModifiers(modifiers, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  NSString* copied_title = dart_appkit::CopyUtf8(title, title_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  NSString* copied_key =
      dart_appkit::CopyUtf8(key_equivalent, key_equivalent_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  @try {
    DaMenuItemOwner* owner =
        [[DaMenuItemOwner alloc] initWithTitle:copied_title
                                 keyEquivalent:copied_key
                                     modifiers:appkit_modifiers];
    const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
        owner, dart_appkit::ObjectKind::kMenuItem,
        dart_appkit::ThreadDomain::kAppKitMain);
    if (handle == 0) {
      return DA_STATUS_INTERNAL_ERROR;
    }
    owner.daHandle = handle;
    *out_item = handle;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "AppKit menu-item creation failed");
  }
}

int32_t da_menu_item_create_separator(DaHandle* out_item) {
  dart_appkit::ClearLastError();
  if (out_item == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_item must not be null");
  }
  *out_item = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  @try {
    DaMenuItemOwner* owner = [[DaMenuItemOwner alloc] initSeparator];
    const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
        owner, dart_appkit::ObjectKind::kMenuItem,
        dart_appkit::ThreadDomain::kAppKitMain);
    if (handle == 0) {
      return DA_STATUS_INTERNAL_ERROR;
    }
    owner.daHandle = handle;
    *out_item = handle;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "AppKit separator creation failed");
  }
}

int32_t da_menu_add_item(DaHandle menu, DaHandle item) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  NSMenu* native_menu = dart_appkit::Menu(menu, &status);
  if (native_menu == nil) {
    return status;
  }
  DaMenuItemOwner* owner = dart_appkit::MenuItemOwner(item, &status);
  if (owner == nil) {
    return status;
  }
  @try {
    [native_menu addItem:owner.item];
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "menu rejected the item");
  }
}

int32_t da_menu_item_set_submenu(DaHandle item, DaHandle submenu) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaMenuItemOwner* owner = dart_appkit::MenuItemOwner(item, &status);
  if (owner == nil) {
    return status;
  }
  if (owner.isSeparator) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "a separator cannot own a submenu");
  }
  NSMenu* native_submenu = nil;
  if (submenu != 0) {
    native_submenu = dart_appkit::Menu(submenu, &status);
    if (native_submenu == nil) {
      return status;
    }
  }
  @try {
    owner.item.submenu = native_submenu;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "menu item rejected the submenu");
  }
}

int32_t da_menu_item_set_enabled(DaHandle item, int32_t enabled) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (enabled != 0 && enabled != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "enabled must be 0 or 1");
  }
  int32_t status = DA_STATUS_OK;
  DaMenuItemOwner* owner = dart_appkit::MenuItemOwner(item, &status);
  if (owner == nil) {
    return status;
  }
  if (owner.isSeparator) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "a separator has no enabled state");
  }
  owner.item.enabled = enabled == 1;
  return DA_STATUS_OK;
}

int32_t da_menu_item_set_checked(DaHandle item, int32_t checked) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (checked != 0 && checked != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "checked must be 0 or 1");
  }
  int32_t status = DA_STATUS_OK;
  DaMenuItemOwner* owner = dart_appkit::MenuItemOwner(item, &status);
  if (owner == nil) {
    return status;
  }
  if (owner.isSeparator) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "a separator has no checked state");
  }
  owner.item.state = checked == 1 ? NSControlStateValueOn
                                  : NSControlStateValueOff;
  return DA_STATUS_OK;
}

int32_t da_application_set_main_menu(DaHandle menu) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (NSApp == nil) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     "NSApplication is not initialized");
  }
  int32_t status = DA_STATUS_OK;
  NSMenu* native_menu = nil;
  if (menu != 0) {
    native_menu = dart_appkit::Menu(menu, &status);
    if (native_menu == nil) {
      return status;
    }
  }
  @try {
    NSApp.mainMenu = native_menu;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "application rejected the menu");
  }
}

int32_t da_menu_item_perform_action(DaHandle item) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaMenuItemOwner* owner = dart_appkit::MenuItemOwner(item, &status);
  if (owner == nil) {
    return status;
  }
  if (owner.isSeparator || !owner.item.isEnabled || owner.item.action == nil ||
      owner.item.target == nil) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "menu item must be enabled and actionable before it is performed");
  }
  [owner daPerformAction:owner.item];
  return DA_STATUS_OK;
}

int32_t da_window_create_configured(
    DaRect frame, const char* title, size_t title_length,
    const DaWindowConfiguration* configuration, DaHandle* out_window) {
  dart_appkit::ClearLastError();
  if (out_window == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_window must not be null");
  }
  *out_window = 0;

  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  const int32_t rect_status = dart_appkit::ValidateRect(frame);
  if (rect_status != DA_STATUS_OK) {
    return rect_status;
  }
  if (NSApp == nil) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     "NSApplication is not initialized");
  }
  if (configuration == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "configuration must not be null");
  }
  if (configuration->struct_size <
      DA_WINDOW_CONFIGURATION_VERSION_1_SIZE) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "window configuration is smaller than version 1");
  }
  constexpr uint64_t kSupportedStyleMask = DA_WINDOW_STYLE_DEFAULT;
  if ((configuration->style_mask & ~kSupportedStyleMask) != 0) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "window style mask contains unsupported bits");
  }

  int32_t string_status = DA_STATUS_OK;
  NSString* copied_title =
      dart_appkit::CopyUtf8(title, title_length, &string_status);
  if (string_status != DA_STATUS_OK) {
    return string_status;
  }

  @try {
    NSWindowStyleMask style = 0;
    if ((configuration->style_mask & DA_WINDOW_STYLE_TITLED) != 0) {
      style |= NSWindowStyleMaskTitled;
    }
    if ((configuration->style_mask & DA_WINDOW_STYLE_CLOSABLE) != 0) {
      style |= NSWindowStyleMaskClosable;
    }
    if ((configuration->style_mask & DA_WINDOW_STYLE_MINIATURIZABLE) != 0) {
      style |= NSWindowStyleMaskMiniaturizable;
    }
    if ((configuration->style_mask & DA_WINDOW_STYLE_RESIZABLE) != 0) {
      style |= NSWindowStyleMaskResizable;
    }
    DaWindow* window = [[DaWindow alloc]
        initWithContentRect:NSMakeRect(frame.x, frame.y, frame.width,
                                       frame.height)
                  styleMask:style
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setFrame:NSMakeRect(frame.x, frame.y, frame.width, frame.height)
             display:NO];
    window.title = copied_title;
    window.releasedWhenClosed = NO;
    window.acceptsMouseMovedEvents = YES;
    window.daKeyEventRouting = DA_KEY_EVENT_ROUTING_DART_AND_APPKIT;
    [window registerForDraggedTypes:@[
      NSPasteboardTypeString,
      NSPasteboardTypeFileURL,
    ]];

    DaWindowOwner* owner = [[DaWindowOwner alloc] initWithWindow:window];
    const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
        owner, dart_appkit::ObjectKind::kWindow,
        dart_appkit::ThreadDomain::kAppKitMain);
    if (handle == 0) {
      return DA_STATUS_INTERNAL_ERROR;
    }
    owner.daHandle = handle;
    window.daHandle = handle;
    window.delegate = owner;
    *out_window = handle;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(DA_STATUS_INTERNAL_ERROR,
                                     exception.reason.UTF8String != nullptr
                                         ? exception.reason.UTF8String
                                         : "AppKit window creation failed");
  }
}

int32_t da_window_create(DaRect frame, const char* title, size_t title_length,
                         DaHandle* out_window) {
  const DaWindowConfiguration configuration = {
      DA_WINDOW_CONFIGURATION_VERSION_1_SIZE,
      DA_WINDOW_STYLE_DEFAULT,
  };
  return da_window_create_configured(frame, title, title_length,
                                     &configuration, out_window);
}

int32_t da_application_resolve_screen(int32_t selection,
                                      DaScreenSnapshot* out_snapshot) {
  dart_appkit::ClearLastError();
  if (out_snapshot == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_snapshot must not be null");
  }
  const uint64_t struct_size = out_snapshot->struct_size;
  *out_snapshot = {};
  if (struct_size < DA_SCREEN_SNAPSHOT_VERSION_1_SIZE) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "screen snapshot output is smaller than version 1");
  }
  out_snapshot->struct_size = DA_SCREEN_SNAPSHOT_VERSION_1_SIZE;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (selection < DA_SCREEN_SELECTION_MAIN ||
      selection > DA_SCREEN_SELECTION_MENU_BAR) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "screen selection is invalid");
  }
  NSArray<NSScreen*>* screens = NSScreen.screens;
  NSScreen* main_screen = NSScreen.mainScreen;
  std::vector<dart_appkit::ScreenSelectionCandidate> candidates;
  candidates.reserve(screens.count);
  for (NSScreen* screen in screens) {
    DaScreenSnapshot snapshot{};
    if (!dart_appkit::PopulateScreenSnapshot(screen, &snapshot)) {
      continue;
    }
    candidates.push_back({snapshot, screen == main_screen});
  }
  const NSPoint mouse = NSEvent.mouseLocation;
  const int selected_index = dart_appkit::ResolveScreenSelectionIndex(
      selection, candidates, mouse.x, mouse.y);
  if (selected_index < 0) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        "no valid AppKit screen is available for presentation");
  }
  *out_snapshot = candidates[static_cast<size_t>(selected_index)].snapshot;
  return DA_STATUS_OK;
}

int32_t da_window_set_frame(DaHandle window, DaRect frame) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  const int32_t rect_status = dart_appkit::ValidateRect(frame);
  if (rect_status != DA_STATUS_OK) {
    return rect_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  [owner daInvalidatePresentation];
  [owner.window setFrame:NSMakeRect(frame.x, frame.y, frame.width, frame.height)
                 display:YES];
  [owner daPostFrame:owner.window.frame];
  return DA_STATUS_OK;
}

int32_t da_window_get_content_layout_rect(DaHandle window,
                                          DaRect* out_rect) {
  dart_appkit::ClearLastError();
  if (out_rect == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_rect must not be null");
  }
  *out_rect = {};
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  const NSRect rect = owner.window.contentLayoutRect;
  out_rect->x = rect.origin.x;
  out_rect->y = rect.origin.y;
  out_rect->width = rect.size.width;
  out_rect->height = rect.size.height;
  return DA_STATUS_OK;
}

int32_t da_window_set_fullscreen(DaHandle window, int32_t enabled) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (enabled != 0 && enabled != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "enabled must be 0 or 1");
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  if (![owner daSetFullscreen:enabled == 1]) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "opposite fullscreen request is pending completion");
  }
  return DA_STATUS_OK;
}

int32_t da_window_set_presentation_configuration(
    DaHandle window,
    const DaWindowPresentationConfiguration* configuration) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  const int32_t configuration_status =
      dart_appkit::ValidateWindowPresentationConfiguration(configuration);
  if (configuration_status != DA_STATUS_OK) {
    return configuration_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  owner.window.level = dart_appkit::WindowLevel(configuration->level);
  owner.window.collectionBehavior = dart_appkit::WindowCollectionBehavior(
      configuration->collection_behavior_mask);
  return DA_STATUS_OK;
}

int32_t da_window_present(DaHandle window, DaRect start_frame,
                          DaRect target_frame, double duration_seconds,
                          int32_t make_key) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (make_key != 0 && make_key != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "make_key must be 0 or 1");
  }
  int32_t status = dart_appkit::ValidateRect(start_frame);
  if (status != DA_STATUS_OK) {
    return status;
  }
  status = dart_appkit::ValidateRect(target_frame);
  if (status != DA_STATUS_OK) {
    return status;
  }
  status = dart_appkit::ValidateAnimationDuration(duration_seconds);
  if (status != DA_STATUS_OK) {
    return status;
  }
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  [owner daPresentFromFrame:NSMakeRect(start_frame.x, start_frame.y,
                                       start_frame.width, start_frame.height)
                    toFrame:NSMakeRect(target_frame.x, target_frame.y,
                                       target_frame.width,
                                       target_frame.height)
                   duration:duration_seconds
                    makeKey:make_key == 1];
  return DA_STATUS_OK;
}

int32_t da_window_hide(DaHandle window, DaRect target_frame,
                       double duration_seconds) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = dart_appkit::ValidateRect(target_frame);
  if (status != DA_STATUS_OK) {
    return status;
  }
  status = dart_appkit::ValidateAnimationDuration(duration_seconds);
  if (status != DA_STATUS_OK) {
    return status;
  }
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  [owner daHideToFrame:NSMakeRect(target_frame.x, target_frame.y,
                                  target_frame.width, target_frame.height)
               duration:duration_seconds];
  return DA_STATUS_OK;
}

int32_t da_window_show(DaHandle window) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  [owner daInvalidatePresentation];
  [owner.window makeKeyAndOrderFront:nil];
  if (owner.window.contentView != nil) {
    [owner.window makeFirstResponder:owner.window.contentView];
  }
  [owner daPostCurrentWindowState];
  return DA_STATUS_OK;
}

int32_t da_window_close(DaHandle window) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  [owner daCloseProgrammatically];
  return DA_STATUS_OK;
}

int32_t da_window_request_close(DaHandle window) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  if ([owner windowShouldClose:owner.window]) {
    [owner daCloseProgrammatically];
  }
  return DA_STATUS_OK;
}

int32_t da_window_set_close_request_deferral(DaHandle window, int32_t enabled) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (enabled != 0 && enabled != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "enabled must be 0 or 1");
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  if (![owner daSetDefersCloseRequests:enabled == 1]) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "reply to the pending close request before disabling deferral");
  }
  return DA_STATUS_OK;
}

int32_t da_window_set_key_event_routing(DaHandle window, int32_t routing) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (routing != DA_KEY_EVENT_ROUTING_DART_AND_APPKIT &&
      routing != DA_KEY_EVENT_ROUTING_DART_ONLY &&
      routing != DA_KEY_EVENT_ROUTING_APPKIT_ONLY) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "routing must be a DaKeyEventRouting value");
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  owner.window.daKeyEventRouting = static_cast<DaKeyEventRouting>(routing);
  return DA_STATUS_OK;
}

int32_t da_window_reply_to_close_request(DaHandle window, int64_t operation_id,
                                         int32_t allow) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (allow != 0 && allow != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "allow must be 0 or 1");
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  if (operation_id <= 0 || ![owner daReplyToCloseRequest:operation_id
                                                   allow:allow == 1]) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "operation_id does not match the pending close request");
  }
  return DA_STATUS_OK;
}

int32_t da_window_set_title(DaHandle window, const char* title,
                            size_t title_length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  NSString* copied_title = dart_appkit::CopyUtf8(title, title_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  owner.window.title = copied_title;
  return DA_STATUS_OK;
}

int32_t da_window_set_represented_file_path(DaHandle window, const char* path,
                                            size_t path_length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (path_length > 4096) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "represented file path is too large");
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  NSString* copied_path = dart_appkit::CopyUtf8(path, path_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  if (path_length == 0) {
    owner.window.representedURL = nil;
    return DA_STATUS_OK;
  }
  if (std::memchr(path, 0, path_length) != nullptr ||
      !copied_path.isAbsolutePath) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "represented file path must be a non-empty absolute path");
  }
  @try {
    owner.window.representedURL =
        [NSURL fileURLWithPath:copied_path isDirectory:NO];
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "represented file path update failed");
  }
}

int32_t da_window_set_tab_accessory(
    DaHandle window, int32_t has_accessory,
    const DaWindowTabAccessoryConfiguration* configuration) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (has_accessory != 0 && has_accessory != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "has_accessory must be 0 or 1");
  }
  if (has_accessory == 1) {
    if (configuration == nullptr ||
        configuration->struct_size <
            DA_WINDOW_TAB_ACCESSORY_CONFIGURATION_VERSION_1_SIZE) {
      return dart_appkit::SetLastError(
          DA_STATUS_INVALID_ARGUMENT,
          "tab accessory configuration is missing or smaller than version 1");
    }
    if (configuration->reserved != 0 ||
        (configuration->shape != DA_WINDOW_TAB_ACCESSORY_SHAPE_RECTANGLE &&
         configuration->shape != DA_WINDOW_TAB_ACCESSORY_SHAPE_ELLIPSE)) {
      return dart_appkit::SetLastError(
          DA_STATUS_INVALID_ARGUMENT,
          "tab accessory shape or reserved fields are invalid");
    }
    if (!std::isfinite(configuration->width) ||
        !std::isfinite(configuration->height) ||
        configuration->width <= 0.0 || configuration->height <= 0.0 ||
        configuration->width > DA_WINDOW_TAB_ACCESSORY_MAX_EXTENT ||
        configuration->height > DA_WINDOW_TAB_ACCESSORY_MAX_EXTENT) {
      return dart_appkit::SetLastError(
          DA_STATUS_INVALID_ARGUMENT,
          "tab accessory dimensions must be finite values within the bound");
    }
    if (!std::isfinite(configuration->red) ||
        !std::isfinite(configuration->green) ||
        !std::isfinite(configuration->blue) ||
        !std::isfinite(configuration->alpha) || configuration->red < 0.0 ||
        configuration->red > 1.0 || configuration->green < 0.0 ||
        configuration->green > 1.0 || configuration->blue < 0.0 ||
        configuration->blue > 1.0 || configuration->alpha < 0.0 ||
        configuration->alpha > 1.0) {
      return dart_appkit::SetLastError(
          DA_STATUS_INVALID_ARGUMENT,
          "tab accessory color components must be finite values from zero to one");
    }
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  @try {
    if (has_accessory == 0) {
      owner.window.tab.accessoryView = nil;
      return DA_STATUS_OK;
    }
    NSView* marker = [[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, configuration->width,
                                 configuration->height)];
    marker.translatesAutoresizingMaskIntoConstraints = NO;
    marker.wantsLayer = YES;
    marker.layer.backgroundColor = [NSColor
        colorWithSRGBRed:configuration->red
                   green:configuration->green
                    blue:configuration->blue
                   alpha:configuration->alpha].CGColor;
    marker.layer.cornerRadius =
        configuration->shape == DA_WINDOW_TAB_ACCESSORY_SHAPE_ELLIPSE
            ? std::min(configuration->width, configuration->height) / 2.0
            : 0.0;
    [[marker.widthAnchor constraintEqualToConstant:configuration->width]
        setActive:YES];
    [[marker.heightAnchor constraintEqualToConstant:configuration->height]
        setActive:YES];
    owner.window.tab.accessoryView = marker;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native tab accessory update failed");
  }
}

int32_t da_window_set_tab_color(DaHandle window, int32_t has_color,
                                double red, double green, double blue,
                                double alpha) {
  const DaWindowTabAccessoryConfiguration configuration = {
      DA_WINDOW_TAB_ACCESSORY_CONFIGURATION_VERSION_1_SIZE,
      DA_WINDOW_TAB_ACCESSORY_SHAPE_ELLIPSE,
      0,
      8.0,
      8.0,
      red,
      green,
      blue,
      alpha,
  };
  return da_window_set_tab_accessory(window, has_color,
                                     has_color == 0 ? nullptr : &configuration);
}

int32_t da_window_add_tabbed_window(DaHandle window,
                                    DaHandle tabbed_window) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (window == tabbed_window) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "a window cannot tab with itself");
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  DaWindowOwner* tabbed_owner =
      dart_appkit::WindowOwner(tabbed_window, &status);
  if (tabbed_owner == nil) {
    return status;
  }
  @try {
    NSWindowTabGroup* group = owner.window.tabGroup;
    if (group == nil || group.windows.count < 2) {
      [owner.window addTabbedWindow:tabbed_owner.window
                            ordered:NSWindowAbove];
    } else {
      [group addWindow:tabbed_owner.window];
    }
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native tab grouping failed");
  }
}

int32_t da_window_remove_from_tab_group(DaHandle window) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  @try {
    NSWindowTabGroup* group = owner.window.tabGroup;
    if (group != nil && group.windows.count > 1) {
      [group removeWindow:owner.window];
    }
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native tab removal failed");
  }
}

int32_t da_window_select_tab(DaHandle window) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  @try {
    NSWindowTabGroup* group = owner.window.tabGroup;
    if (group != nil && [group.windows containsObject:owner.window]) {
      group.selectedWindow = owner.window;
    }
    [owner.window makeKeyAndOrderFront:nil];
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native tab selection failed");
  }
}

int32_t da_window_make_first_responder(DaHandle window, DaHandle view) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  NSView* responder = dart_appkit::View(view, &status);
  if (responder == nil) {
    return status;
  }
  NSView* content_view = owner.window.contentView;
  if (content_view == nil ||
      (responder != content_view && ![responder isDescendantOf:content_view])) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "first responder view must belong to the window content hierarchy");
  }
  if ([responder isKindOfClass:DaTextEditor.class]) {
    if (!responder.acceptsFirstResponder) {
      return dart_appkit::SetLastError(
          DA_STATUS_INVALID_ARGUMENT,
          "text editor wrapper does not accept first responder status");
    }
    DaTextEditor* editor = static_cast<DaTextEditor*>(responder);
    responder = editor.daTextView;
  }
  if (![owner.window makeFirstResponder:responder]) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "view refused first responder status");
  }
  return DA_STATUS_OK;
}

int32_t da_view_create_configured(
    const DaViewConfiguration* configuration, DaHandle* out_view) {
  dart_appkit::ClearLastError();
  if (out_view == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_view must not be null");
  }
  *out_view = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  const int32_t configuration_status =
      dart_appkit::ValidateViewConfiguration(configuration);
  if (configuration_status != DA_STATUS_OK) {
    return configuration_status;
  }
  DaView* view = [[DaView alloc] initWithFrame:NSZeroRect];
  dart_appkit::ApplyViewConfiguration(view, *configuration);
  const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
      view, dart_appkit::ObjectKind::kView,
      dart_appkit::ThreadDomain::kAppKitMain);
  if (handle == 0) {
    return DA_STATUS_INTERNAL_ERROR;
  }
  *out_view = handle;
  return DA_STATUS_OK;
}

int32_t da_view_create(DaHandle* out_view) {
  const DaViewConfiguration configuration = {
      DA_VIEW_CONFIGURATION_VERSION_1_SIZE,
      DA_VIEW_AUTORESIZE_DEFAULT,
      1,
      0,
  };
  return da_view_create_configured(&configuration, out_view);
}

int32_t da_view_set_secure_input_indicator(DaHandle view_handle,
                                           int32_t state) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (state < DA_SECURE_INPUT_INDICATOR_HIDDEN ||
      state > DA_SECURE_INPUT_INDICATOR_MANUAL) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "state must be a DaSecureInputIndicatorState value");
  }
  int32_t status = DA_STATUS_OK;
  NSView* view = dart_appkit::View(view_handle, &status);
  if (view == nil) {
    return status;
  }
  DaSecureInputIndicatorView* indicator = nil;
  for (NSView* subview in view.subviews) {
    if ([subview isKindOfClass:DaSecureInputIndicatorView.class]) {
      indicator = static_cast<DaSecureInputIndicatorView*>(subview);
      break;
    }
  }
  if (state == DA_SECURE_INPUT_INDICATOR_HIDDEN) {
    [indicator removeFromSuperview];
    return DA_STATUS_OK;
  }
  if (indicator == nil) {
    indicator = [[DaSecureInputIndicatorView alloc] initWithFrame:NSZeroRect];
    [view addSubview:indicator positioned:NSWindowAbove relativeTo:nil];
    [NSLayoutConstraint activateConstraints:@[
      [indicator.topAnchor constraintEqualToAnchor:view.topAnchor constant:8.0],
      [indicator.trailingAnchor constraintEqualToAnchor:view.trailingAnchor
                                               constant:-8.0],
    ]];
  }
  indicator.daState = static_cast<DaSecureInputIndicatorState>(state);
  return DA_STATUS_OK;
}

int32_t da_view_set_context_menu(DaHandle view_handle, DaHandle menu_handle) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  NSView* view = dart_appkit::View(view_handle, &status);
  if (view == nil) {
    return status;
  }
  NSMenu* menu = nil;
  if (menu_handle != 0) {
    menu = dart_appkit::Menu(menu_handle, &status);
    if (menu == nil) {
      return status;
    }
  }
  view.menu = menu;
  if (menu == nil) {
    [g_context_menu_views removeObject:view];
  } else {
    if (g_context_menu_views == nil) {
      g_context_menu_views = [NSHashTable weakObjectsHashTable];
    }
    [g_context_menu_views addObject:view];
  }
  if (g_context_menu_views.count == 0) {
    g_context_menu_views = nil;
  }
  return DA_STATUS_OK;
}

int32_t da_view_set_quick_look_request_enabled(DaHandle view_handle,
                                               int32_t enabled) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (enabled != 0 && enabled != 1) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "Quick Look request enabled state must be zero or one");
  }
  int32_t status = DA_STATUS_OK;
  NSView* view = dart_appkit::View(view_handle, &status);
  if (view == nil) {
    return status;
  }
  DaQuickLookRequestOwner* owner = QuickLookOwnerForView(view);
  if (enabled == 0) {
    if (owner != nil) {
      owner.daHandle = 0;
      owner.view = nil;
      [g_quick_look_request_owners removeObject:owner];
    }
    StopQuickLookMonitorIfUnused();
    return DA_STATUS_OK;
  }
  if (owner != nil) {
    return DA_STATUS_OK;
  }
  if (g_quick_look_request_owners == nil) {
    g_quick_look_request_owners = [[NSMutableArray alloc] init];
  }
  owner = [[DaQuickLookRequestOwner alloc] init];
  owner.view = view;
  owner.daHandle = view_handle;
  owner.previousPressureStage = 0;
  [g_quick_look_request_owners addObject:owner];
  EnsureQuickLookMonitor();
  return DA_STATUS_OK;
}

int32_t da_view_show_definition(
    DaHandle view_handle, const char* text, size_t text_length,
    const DaDefinitionPresentationConfiguration* configuration,
    const char* font_family, size_t font_family_length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  NSView* view = dart_appkit::View(view_handle, &status);
  if (view == nil) {
    return status;
  }
  if (text_length == 0) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "definition text must not be empty");
  }
  if (text_length > DA_DEFINITION_TEXT_MAX_UTF8_BYTES) {
    return dart_appkit::SetLastError(
        DA_STATUS_LIMIT_EXCEEDED,
        "definition text exceeds the UTF-8 byte limit");
  }
  NSString* copied_text = dart_appkit::CopyUtf8(text, text_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  if (dart_appkit::ContainsUnsafeDisplayText(copied_text)) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "definition text contains controls or invisible scalars");
  }
  NSFont* font = nil;
  status = dart_appkit::ResolveDefinitionFont(
      configuration, font_family, font_family_length, &font);
  if (status != DA_STATUS_OK) {
    return status;
  }

  dart_appkit::DefinitionPresentationSnapshot snapshot;
  snapshot.view = view_handle;
  snapshot.text.assign(text, text_length);
  if (font_family_length != 0) {
    snapshot.font_family.assign(font_family, font_family_length);
  }
  snapshot.font_kind = configuration->font_kind;
  snapshot.font_weight = configuration->font_weight;
  snapshot.font_size = configuration->font_size;
  snapshot.baseline_x = configuration->baseline_x;
  snapshot.baseline_y = configuration->baseline_y;
  if (dart_appkit::g_definition_presentation_handler != nullptr) {
    if (!dart_appkit::g_definition_presentation_handler(
            snapshot, dart_appkit::g_definition_presentation_context)) {
      return dart_appkit::SetLastError(
          DA_STATUS_INTERNAL_ERROR,
          "definition presentation handler rejected the request");
    }
    return DA_STATUS_OK;
  }

  NSAttributedString* attributed = [[NSAttributedString alloc]
      initWithString:copied_text
          attributes:@{NSFontAttributeName : font}];
  [view showDefinitionForAttributedString:attributed
                                  atPoint:NSMakePoint(
                                              configuration->baseline_x,
                                              configuration->baseline_y)];
  return DA_STATUS_OK;
}

int32_t da_view_set_services_text_requestor(
    DaHandle view_handle, const char* selection_text,
    size_t selection_text_length,
    const DaServicesTextRequestorConfiguration* configuration) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  NSView* view = dart_appkit::View(view_handle, &status);
  if (view == nil) {
    return status;
  }
  if (configuration == nullptr) {
    if (selection_text != nullptr || selection_text_length != 0) {
      return dart_appkit::SetLastError(
          DA_STATUS_INVALID_ARGUMENT,
          "disabled Services requestor must not include selection text");
    }
    RemoveServicesTextRequestorForView(view);
    return DA_STATUS_OK;
  }
  if (configuration->struct_size <
          DA_SERVICES_TEXT_REQUESTOR_CONFIGURATION_VERSION_1_SIZE ||
      (configuration->has_selection != 0 &&
       configuration->has_selection != 1) ||
      (configuration->accepts_returned_text != 0 &&
       configuration->accepts_returned_text != 1) ||
      configuration->reserved_0 != 0 || configuration->reserved_1 != 0 ||
      configuration->maximum_returned_text_utf8_bytes == 0 ||
      configuration->maximum_returned_text_utf8_bytes >
          DA_SERVICES_TEXT_MAX_UTF8_BYTES ||
      (configuration->has_selection == 0 &&
       (selection_text != nullptr || selection_text_length != 0)) ||
      (configuration->has_selection == 1 && selection_text_length != 0 &&
       selection_text == nullptr) ||
      (configuration->has_selection == 0 &&
       configuration->accepts_returned_text == 0)) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "Services requestor configuration or selection presence is invalid");
  }
  if (selection_text_length > DA_SERVICES_TEXT_MAX_UTF8_BYTES) {
    return dart_appkit::SetLastError(
        DA_STATUS_LIMIT_EXCEEDED,
        "Services selection exceeds the UTF-8 byte limit");
  }
  NSString* copied_selection = nil;
  if (configuration->has_selection != 0) {
    copied_selection = dart_appkit::CopyUtf8(selection_text,
                                             selection_text_length, &status);
    if (status != DA_STATUS_OK) {
      return status;
    }
  }

  DaServicesTextRequestor* requestor = ServicesTextRequestorForView(view);
  if (requestor == nil) {
    if (g_services_text_requestors == nil) {
      g_services_text_requestors = [[NSMutableArray alloc] init];
    }
    requestor = [[DaServicesTextRequestor alloc] init];
    requestor.view = view;
    [g_services_text_requestors addObject:requestor];
  }
  requestor.daHandle = view_handle;
  requestor.selectionText = copied_selection;
  requestor.acceptsReturnedText =
      configuration->accepts_returned_text != 0;
  requestor.maximumReturnedTextUtf8Bytes =
      configuration->maximum_returned_text_utf8_bytes;
  return DA_STATUS_OK;
}

int32_t da_view_set_drop_destination(
    DaHandle view_handle,
    const DaDropDestinationConfiguration* configuration) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  NSView* view = dart_appkit::View(view_handle, &status);
  if (view == nil) {
    return status;
  }
  if (configuration == nullptr) {
    RemoveDropDestinationOwnerForView(view);
    return DA_STATUS_OK;
  }
  if (configuration->struct_size <
          DA_DROP_DESTINATION_CONFIGURATION_VERSION_1_SIZE ||
      (configuration->accepts_plain_text != 0 &&
       configuration->accepts_plain_text != 1) ||
      (configuration->accepts_file_urls != 0 &&
       configuration->accepts_file_urls != 1) ||
      configuration->reserved_0 != 0 || configuration->reserved_1 != 0 ||
      (configuration->accepts_plain_text == 0 &&
       configuration->accepts_file_urls == 0) ||
      configuration->maximum_text_utf8_bytes == 0 ||
      configuration->maximum_text_utf8_bytes > DA_DROP_TEXT_MAX_UTF8_BYTES ||
      configuration->maximum_file_url_count == 0 ||
      configuration->maximum_file_url_count > DA_DROP_FILE_URL_MAX_COUNT ||
      configuration->maximum_file_url_utf8_bytes == 0 ||
      configuration->maximum_file_url_utf8_bytes >
          DA_DROP_FILE_URL_MAX_UTF8_BYTES ||
      configuration->maximum_total_file_url_utf8_bytes == 0 ||
      configuration->maximum_total_file_url_utf8_bytes >
          DA_DROP_FILE_URL_TOTAL_MAX_UTF8_BYTES ||
      configuration->maximum_file_url_utf8_bytes >
          configuration->maximum_total_file_url_utf8_bytes) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "drop destination configuration is invalid or exceeds hard limits");
  }
  DaDropDestinationOwner* owner = DropDestinationOwnerForView(view);
  if (owner == nil) {
    if (g_drop_destination_owners == nil) {
      g_drop_destination_owners = [[NSMutableArray alloc] init];
    }
    owner = [[DaDropDestinationOwner alloc] init];
    owner.view = view;
    [g_drop_destination_owners addObject:owner];
  } else {
    ClearDropSessionsForOwner(owner);
  }
  owner.daHandle = view_handle;
  owner.acceptsPlainText = configuration->accepts_plain_text != 0;
  owner.acceptsFileUrls = configuration->accepts_file_urls != 0;
  owner.maximumTextUtf8Bytes = configuration->maximum_text_utf8_bytes;
  owner.maximumFileUrlCount = configuration->maximum_file_url_count;
  owner.maximumFileUrlUtf8Bytes =
      configuration->maximum_file_url_utf8_bytes;
  owner.maximumTotalFileUrlUtf8Bytes =
      configuration->maximum_total_file_url_utf8_bytes;
  return DA_STATUS_OK;
}

int32_t da_split_view_create(int32_t axis, DaHandle* out_view) {
  dart_appkit::ClearLastError();
  if (out_view == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_view must not be null");
  }
  *out_view = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (axis != DA_SPLIT_AXIS_HORIZONTAL && axis != DA_SPLIT_AXIS_VERTICAL) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "axis must be a DaSplitAxis value");
  }
  DaSplitView* view = [[DaSplitView alloc]
      initWithAxis:static_cast<DaSplitAxis>(axis)];
  const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
      view, dart_appkit::ObjectKind::kView,
      dart_appkit::ThreadDomain::kAppKitMain);
  if (handle == 0) {
    return DA_STATUS_INTERNAL_ERROR;
  }
  *out_view = handle;
  return DA_STATUS_OK;
}

int32_t da_split_view_set_children(DaHandle split_view, DaHandle first_view,
                                   DaHandle second_view) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (split_view == first_view || split_view == second_view ||
      first_view == second_view) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "split and child handles must be three distinct views");
  }
  int32_t status = DA_STATUS_OK;
  DaSplitView* split = dart_appkit::SplitView(split_view, &status);
  if (split == nil) {
    return status;
  }
  NSView* first = dart_appkit::View(first_view, &status);
  if (first == nil) {
    return status;
  }
  NSView* second = dart_appkit::View(second_view, &status);
  if (second == nil) {
    return status;
  }
  if (![split daSetFirstView:first secondView:second]) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "split children would create an invalid view hierarchy");
  }
  return DA_STATUS_OK;
}

int32_t da_split_view_set_position(DaHandle split_view, double fraction,
                                   double first_minimum_extent,
                                   double second_minimum_extent) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (!std::isfinite(fraction) || fraction <= 0.0 || fraction >= 1.0 ||
      !std::isfinite(first_minimum_extent) || first_minimum_extent < 0.0 ||
      !std::isfinite(second_minimum_extent) || second_minimum_extent < 0.0) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "split fraction and minimum extents are invalid");
  }
  int32_t status = DA_STATUS_OK;
  DaSplitView* split = dart_appkit::SplitView(split_view, &status);
  if (split == nil) {
    return status;
  }
  [split daSetFraction:fraction
      firstMinimumExtent:first_minimum_extent
     secondMinimumExtent:second_minimum_extent];
  return DA_STATUS_OK;
}

int32_t da_split_view_get_fraction(DaHandle split_view,
                                   double* out_fraction) {
  dart_appkit::ClearLastError();
  if (out_fraction == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_fraction must not be null");
  }
  *out_fraction = 0.0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaSplitView* split = dart_appkit::SplitView(split_view, &status);
  if (split == nil) {
    return status;
  }
  const double fraction = split.daFraction;
  if (!std::isfinite(fraction) || fraction < 0.0 || fraction > 1.0) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        "native split fraction is not finite or outside [0, 1]");
  }
  *out_fraction = fraction;
  return DA_STATUS_OK;
}

int32_t da_split_view_equalize(DaHandle split_view) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaSplitView* split = dart_appkit::SplitView(split_view, &status);
  if (split == nil) {
    return status;
  }
  [split daEqualize];
  return DA_STATUS_OK;
}

int32_t da_split_view_set_zoomed_child(DaHandle split_view, int32_t child) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (child != DA_SPLIT_ZOOM_NONE && child != DA_SPLIT_ZOOM_FIRST &&
      child != DA_SPLIT_ZOOM_SECOND) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "child must be a DaSplitZoomedChild value");
  }
  int32_t status = DA_STATUS_OK;
  DaSplitView* split = dart_appkit::SplitView(split_view, &status);
  if (split == nil) {
    return status;
  }
  [split daSetZoomedChild:static_cast<DaSplitZoomedChild>(child)];
  return DA_STATUS_OK;
}

int32_t da_view_create_custom(const char* provider_identifier,
                              size_t provider_identifier_length,
                              DaHandle* out_view) {
  dart_appkit::ClearLastError();
  if (out_view == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_view must not be null");
  }
  *out_view = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  NSString* identifier = dart_appkit::CopyUtf8(
      provider_identifier, provider_identifier_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  @try {
    NSView* view = dart_appkit::CreateRegisteredCustomView(identifier, &status);
    if (view == nil) {
      return status;
    }
    const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
        view, dart_appkit::ObjectKind::kView,
        dart_appkit::ThreadDomain::kAppKitMain);
    if (handle == 0) {
      return DA_STATUS_INTERNAL_ERROR;
    }
    *out_view = handle;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR, exception.reason.UTF8String != nullptr
                                      ? exception.reason.UTF8String
                                      : "custom view provider creation failed");
  }
}

int32_t da_view_perform_custom_operation(DaHandle view_handle,
                                         const uint8_t* payload,
                                         size_t payload_length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  __unsafe_unretained NSView* view =
      dart_appkit::View(view_handle, &status);
  if (view == nil) {
    return status;
  }
  @try {
    return dart_appkit::PerformRegisteredCustomViewOperation(
        view, payload, payload_length);
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "custom view operation failed");
  }
}

int32_t da_text_view_create_configured(
    const DaTextViewConfiguration* configuration, const char* font_family,
    size_t font_family_length, DaHandle* out_view) {
  dart_appkit::ClearLastError();
  if (out_view == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_view must not be null");
  }
  *out_view = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  NSFont* font = nil;
  const int32_t configuration_status = dart_appkit::ResolveTextViewFont(
      configuration, font_family, font_family_length, &font);
  if (configuration_status != DA_STATUS_OK) {
    return configuration_status;
  }
  DaTextView* view = [[DaTextView alloc] initWithFrame:NSZeroRect];
  dart_appkit::ApplyViewConfiguration(view, configuration->view);
  view.daFont = font;
  view.daPadding = NSEdgeInsetsMake(
      configuration->padding_top, configuration->padding_left,
      configuration->padding_bottom, configuration->padding_right);
  view.daForegroundColor =
      dart_appkit::TextViewColor(configuration->foreground_color);
  view.daBackgroundColor =
      dart_appkit::TextViewColor(configuration->background_color);
  const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
      view, dart_appkit::ObjectKind::kTextView,
      dart_appkit::ThreadDomain::kAppKitMain);
  if (handle == 0) {
    return DA_STATUS_INTERNAL_ERROR;
  }
  *out_view = handle;
  return DA_STATUS_OK;
}

int32_t da_text_view_create(DaHandle* out_view) {
  DaTextViewConfiguration configuration{};
  configuration.struct_size = DA_TEXT_VIEW_CONFIGURATION_VERSION_1_SIZE;
  configuration.view = {
      DA_VIEW_CONFIGURATION_VERSION_1_SIZE,
      DA_VIEW_AUTORESIZE_DEFAULT,
      1,
      0,
  };
  configuration.font_kind = DA_TEXT_VIEW_FONT_MONOSPACED_SYSTEM;
  configuration.font_weight = DA_TEXT_VIEW_FONT_WEIGHT_REGULAR;
  configuration.font_size = 18.0;
  configuration.padding_top = 20.0;
  configuration.padding_right = 20.0;
  configuration.padding_bottom = 20.0;
  configuration.padding_left = 20.0;
  configuration.foreground_color = {
      DA_TEXT_VIEW_COLOR_LABEL, 0, 0.0, 0.0, 0.0, 1.0};
  configuration.background_color = {
      DA_TEXT_VIEW_COLOR_WINDOW_BACKGROUND, 0, 0.0, 0.0, 0.0, 1.0};
  return da_text_view_create_configured(&configuration, nullptr, 0, out_view);
}

int32_t da_text_view_set_text(DaHandle view, const char* text,
                              size_t text_length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaTextView* text_view = dart_appkit::TextView(view, &status);
  if (text_view == nil) {
    return status;
  }
  NSString* copied_text = dart_appkit::CopyUtf8(text, text_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  text_view.displayText = copied_text;
  return DA_STATUS_OK;
}

int32_t da_text_editor_create_configured(
    const DaTextEditorConfiguration* configuration, const char* font_family,
    size_t font_family_length, DaHandle* out_editor) {
  dart_appkit::ClearLastError();
  if (out_editor == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_editor must not be null");
  }
  *out_editor = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (configuration == nullptr ||
      configuration->struct_size <
          DA_TEXT_EDITOR_CONFIGURATION_VERSION_1_SIZE ||
      (configuration->initially_editable != 0 &&
       configuration->initially_editable != 1) ||
      configuration->reserved != 0) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "text editor configuration is missing, undersized, or invalid");
  }
  NSFont* font = nil;
  const int32_t configuration_status = dart_appkit::ResolveTextViewFont(
      &configuration->presentation, font_family, font_family_length, &font);
  if (configuration_status != DA_STATUS_OK) {
    return configuration_status;
  }
  @try {
    DaTextEditor* editor = [[DaTextEditor alloc] initWithFrame:NSZeroRect];
    dart_appkit::ApplyViewConfiguration(editor,
                                        configuration->presentation.view);
    editor.daFont = font;
    editor.daPadding = NSEdgeInsetsMake(
        configuration->presentation.padding_top,
        configuration->presentation.padding_left,
        configuration->presentation.padding_bottom,
        configuration->presentation.padding_right);
    editor.daForegroundColor = dart_appkit::TextViewColor(
        configuration->presentation.foreground_color);
    editor.daBackgroundColor = dart_appkit::TextViewColor(
        configuration->presentation.background_color);
    [editor daApplyPresentation];
    editor.daTextView.editable = configuration->initially_editable == 1;
    const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
        editor, dart_appkit::ObjectKind::kView,
        dart_appkit::ThreadDomain::kAppKitMain);
    if (handle == 0) {
      return DA_STATUS_INTERNAL_ERROR;
    }
    *out_editor = handle;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native text editor creation failed");
  }
}

int32_t da_text_editor_set_document(
    DaHandle editor, const char* text, size_t text_length,
    const DaTextEditorStyleRun* style_runs, size_t style_run_count,
    uint64_t selection_location, uint64_t selection_length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaTextEditor* text_editor = dart_appkit::TextEditor(editor, &status);
  if (text_editor == nil) {
    return status;
  }
  if (text_length > DA_TEXT_EDITOR_MAX_TEXT_UTF8_BYTES) {
    return dart_appkit::SetLastError(
        DA_STATUS_LIMIT_EXCEEDED,
        "text editor document exceeds the UTF-8 byte limit");
  }
  NSString* copied_text = dart_appkit::CopyUtf8(text, text_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  status = dart_appkit::ValidateTextEditorSelection(
      copied_text, selection_location, selection_length);
  if (status != DA_STATUS_OK) {
    return status;
  }
  status = dart_appkit::ValidateTextEditorStyleRuns(
      copied_text, style_runs, style_run_count);
  if (status != DA_STATUS_OK) {
    return status;
  }
  @try {
    NSMutableAttributedString* replacement = [[NSMutableAttributedString alloc]
        initWithString:copied_text
            attributes:@{
              NSFontAttributeName : text_editor.daFont,
              NSForegroundColorAttributeName :
                  text_editor.daForegroundColor,
            }];
    dart_appkit::ApplyTextEditorStyleRunsToStorage(
        text_editor, replacement, style_runs, style_run_count);
    [text_editor.daTextView.textStorage setAttributedString:replacement];
    [text_editor daClearLineHighlight];
    text_editor.daTextView.typingAttributes = @{
      NSFontAttributeName : text_editor.daFont,
      NSForegroundColorAttributeName : text_editor.daForegroundColor,
    };
    text_editor.daTextView.selectedRange =
        NSMakeRange(selection_location, selection_length);
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native text editor document update failed");
  }
}

int32_t da_text_editor_set_style_runs(
    DaHandle editor, const DaTextEditorStyleRun* style_runs,
    size_t style_run_count) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaTextEditor* text_editor = dart_appkit::TextEditor(editor, &status);
  if (text_editor == nil) {
    return status;
  }
  NSString* current_text = text_editor.daTextView.string;
  status = dart_appkit::ValidateTextEditorStyleRuns(
      current_text, style_runs, style_run_count);
  if (status != DA_STATUS_OK) {
    return status;
  }
  @try {
    const NSRange selection = text_editor.daTextView.selectedRange;
    dart_appkit::ApplyTextEditorStyleRuns(text_editor, style_runs,
                                          style_run_count);
    text_editor.daTextView.selectedRange = selection;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native text editor style update failed");
  }
}

int32_t da_text_editor_set_line_highlight(
    DaHandle editor, uint64_t location,
    const DaTextViewColorConfiguration* color) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaTextEditor* text_editor = dart_appkit::TextEditor(editor, &status);
  if (text_editor == nil) {
    return status;
  }
  if (color == nullptr) {
    [text_editor daClearLineHighlight];
    return DA_STATUS_OK;
  }
  status = dart_appkit::ValidateTextEditorSelection(
      text_editor.daTextView.string, location, 0);
  if (status != DA_STATUS_OK) {
    return status;
  }
  if (!dart_appkit::ValidTextViewColor(*color)) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "text editor line highlight color is invalid");
  }
  @try {
    [text_editor daSetLineHighlightAtLocation:location
                                        color:dart_appkit::TextViewColor(
                                                  *color)];
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native text editor line highlight update failed");
  }
}

int32_t da_text_editor_set_editable(DaHandle editor, int32_t editable) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (editable != 0 && editable != 1) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "text editor editable value must be zero or one");
  }
  int32_t status = DA_STATUS_OK;
  DaTextEditor* text_editor = dart_appkit::TextEditor(editor, &status);
  if (text_editor == nil) {
    return status;
  }
  text_editor.daTextView.editable = editable == 1;
  return DA_STATUS_OK;
}

int32_t da_text_editor_set_selection(DaHandle editor, uint64_t location,
                                     uint64_t length) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaTextEditor* text_editor = dart_appkit::TextEditor(editor, &status);
  if (text_editor == nil) {
    return status;
  }
  status = dart_appkit::ValidateTextEditorSelection(
      text_editor.daTextView.string, location, length);
  if (status != DA_STATUS_OK) {
    return status;
  }
  text_editor.daTextView.selectedRange = NSMakeRange(location, length);
  return DA_STATUS_OK;
}

int32_t da_text_editor_scroll_selection_to_visible(DaHandle editor) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaTextEditor* text_editor = dart_appkit::TextEditor(editor, &status);
  if (text_editor == nil) {
    return status;
  }
  @try {
    [text_editor.daTextView
        scrollRangeToVisible:text_editor.daTextView.selectedRange];
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native text editor selection reveal failed");
  }
}

int32_t da_text_editor_get_snapshot(DaHandle editor,
                                    DaTextEditorSnapshot* out_snapshot) {
  dart_appkit::ClearLastError();
  if (out_snapshot == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_snapshot must not be null");
  }
  *out_snapshot = {};
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaTextEditor* text_editor = dart_appkit::TextEditor(editor, &status);
  if (text_editor == nil) {
    return status;
  }
  NSData* utf8 = [text_editor.daTextView.string
      dataUsingEncoding:NSUTF8StringEncoding
   allowLossyConversion:NO];
  if (utf8 == nil) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        "native text editor contents could not be encoded as UTF-8");
  }
  if (utf8.length == 0) {
    dart_appkit::g_text_editor_snapshot.clear();
  } else {
    dart_appkit::g_text_editor_snapshot.assign(
        static_cast<const char*>(utf8.bytes), utf8.length);
  }
  const NSRange selection = text_editor.daTextView.selectedRange;
  out_snapshot->text = dart_appkit::g_text_editor_snapshot.empty()
                           ? nullptr
                           : dart_appkit::g_text_editor_snapshot.data();
  out_snapshot->text_length = dart_appkit::g_text_editor_snapshot.size();
  out_snapshot->selection_location = selection.location;
  out_snapshot->selection_length = selection.length;
  out_snapshot->is_editable = text_editor.daTextView.isEditable ? 1 : 0;
  out_snapshot->has_marked_text = text_editor.daTextView.hasMarkedText ? 1 : 0;
  return DA_STATUS_OK;
}

int32_t da_window_set_content_view(DaHandle window, DaHandle view) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  NSView* content_view = dart_appkit::View(view, &status);
  if (content_view == nil) {
    return status;
  }
  content_view.frame = owner.window.contentLayoutRect;
  owner.window.contentView = content_view;
  [owner.window makeFirstResponder:content_view];
  return DA_STATUS_OK;
}

int32_t da_release(DaHandle handle) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  const int32_t claim_status =
      dart_appkit::ObjectRegistry::Shared().BeginRelease(
          handle, dart_appkit::ThreadDomain::kAppKitMain);
  if (claim_status != DA_STATUS_OK) {
    return claim_status;
  }
  return dart_appkit::CompletePendingRelease(handle);
}

int32_t da_release_async(DaHandle handle) {
  dart_appkit::ClearLastError();
  return dart_appkit::EnqueueAsyncRelease(handle);
}

void da_release_finalizer(void* token) {
  const DaHandle handle =
      static_cast<DaHandle>(reinterpret_cast<uintptr_t>(token));
  if (handle == 0) {
    return;
  }
  (void)da_release_async(handle);
}

int32_t da_debug_is_main_thread(int32_t* out_is_main_thread) {
  dart_appkit::ClearLastError();
  if (out_is_main_thread == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_is_main_thread must not be null");
  }
  *out_is_main_thread = pthread_main_np() != 0 ? 1 : 0;
  return DA_STATUS_OK;
}

int32_t da_debug_live_object_count(uint64_t* out_count) {
  dart_appkit::ClearLastError();
  if (out_count == nullptr) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "out_count must not be null");
  }
  *out_count = 0;
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  *out_count =
      static_cast<uint64_t>(dart_appkit::ObjectRegistry::Shared().live_count());
  return DA_STATUS_OK;
}

int32_t da_debug_request_application_termination(void) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (dart_appkit::HandleApplicationShouldTerminate() !=
      dart_appkit::ApplicationTerminationDecision::kTerminateLater) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "debug application termination requires active deferral and event port");
  }
  return DA_STATUS_OK;
}
