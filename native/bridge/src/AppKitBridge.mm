#include "dart_appkit.h"

#import <AppKit/AppKit.h>

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <string_view>

#include "AppKitObjects.h"
#include "BridgeInternal.h"
#include "CustomViewRegistry.h"
#include "ObjectRegistry.h"

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
std::atomic<bool> g_accept_async_releases{true};
std::atomic<uint64_t> g_async_release_epoch{1};
bool g_defers_application_termination_requests = false;
int64_t g_pending_application_termination_operation_id = 0;
bool g_programmatic_application_termination = false;
constexpr uint64_t kStableModifierMask =
    DA_MODIFIER_CAPS_LOCK | DA_MODIFIER_SHIFT | DA_MODIFIER_CONTROL |
    DA_MODIFIER_OPTION | DA_MODIFIER_COMMAND | DA_MODIFIER_NUMERIC_PAD |
    DA_MODIFIER_FUNCTION;

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
  owner.daHandle = 0;
  owner.window.daHandle = 0;
  owner.window.delegate = nil;
  [owner.window orderOut:nil];
  [owner daCloseProgrammatically];
}

void PrepareMenuForRelease(NSMenu* menu) {
  if (menu != nil && NSApp.mainMenu == menu) {
    NSApp.mainMenu = nil;
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
  } else if (kind == ObjectKind::kMenu) {
    PrepareMenuForRelease(static_cast<NSMenu*>(object));
  } else if (kind == ObjectKind::kMenuItem) {
    [static_cast<DaMenuItemOwner*>(object) daPrepareForRelease];
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

int32_t OpenAllowedExternalUrl(NSString* value,
                               ExternalUrlOpenFunction opener,
                               int32_t* out_opened) {
  if (out_opened == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "out_opened must not be null");
  }
  *out_opened = 0;
  if (value == nil || opener == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL and opener must not be null");
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
  const bool is_web = [scheme isEqualToString:@"http"] ||
                      [scheme isEqualToString:@"https"];
  const bool is_mail = [scheme isEqualToString:@"mailto"];
  if (!is_web && !is_mail) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL scheme is not allowed");
  }
  if (is_web) {
    if (components.host.length == 0) {
      return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                          "web URL must contain a host");
    }
    if (components.user != nil || components.password != nil) {
      return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                          "web URL credentials are not allowed");
    }
  } else if (components.host != nil || components.user != nil ||
             components.password != nil || components.path.length == 0) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "mailto URL must contain a non-authority recipient");
  }

  NSURL* url = components.URL;
  if (url == nil || url.scheme == nil) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "external URL cannot be represented by NSURL");
  }
  *out_opened = opener(url) ? 1 : 0;
  return DA_STATUS_OK;
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

void ShutdownBridge() {
  if (pthread_main_np() == 0) {
    return;
  }
  g_accept_async_releases.store(false, std::memory_order_release);
  g_async_release_epoch.fetch_add(1, std::memory_order_acq_rel);
  DisableEventPoster();
  g_defers_application_termination_requests = false;
  g_pending_application_termination_operation_id = 0;
  g_programmatic_application_termination = false;

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
}

void ResetBridgeForTesting() {
  ShutdownBridge();
  ClearCustomViewClassesForTesting();
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
  const int32_t status = dart_appkit::SetEventPortVersioned(
      dart_port, min_version, max_version, out_selected_version);
  if (status == DA_STATUS_OK) {
    dart_appkit::PostApplicationActiveChanged(NSApp != nil && NSApp.isActive);
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

int32_t da_menu_create(const char* title, size_t title_length,
                       DaHandle* out_menu) {
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
  int32_t status = DA_STATUS_OK;
  NSString* copied_title = dart_appkit::CopyUtf8(title, title_length, &status);
  if (status != DA_STATUS_OK) {
    return status;
  }
  @try {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:copied_title];
    menu.autoenablesItems = NO;
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

int32_t da_window_create(DaRect frame, const char* title, size_t title_length,
                         DaHandle* out_window) {
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

  int32_t string_status = DA_STATUS_OK;
  NSString* copied_title =
      dart_appkit::CopyUtf8(title, title_length, &string_status);
  if (string_status != DA_STATUS_OK) {
    return string_status;
  }

  @try {
    const NSWindowStyleMask style =
        NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
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
  [owner.window setFrame:NSMakeRect(frame.x, frame.y, frame.width, frame.height)
                 display:YES];
  [owner daPostFrame:owner.window.frame];
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

int32_t da_window_set_tab_color(DaHandle window, int32_t has_color,
                                double red, double green, double blue,
                                double alpha) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (has_color != 0 && has_color != 1) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "has_color must be 0 or 1");
  }
  if (has_color == 1 &&
      (!std::isfinite(red) || !std::isfinite(green) ||
       !std::isfinite(blue) || !std::isfinite(alpha) || red < 0.0 ||
       red > 1.0 || green < 0.0 || green > 1.0 || blue < 0.0 || blue > 1.0 ||
       alpha < 0.0 || alpha > 1.0)) {
    return dart_appkit::SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "tab color components must be finite values from zero to one");
  }
  int32_t status = DA_STATUS_OK;
  DaWindowOwner* owner = dart_appkit::WindowOwner(window, &status);
  if (owner == nil) {
    return status;
  }
  @try {
    if (has_color == 0) {
      owner.window.tab.accessoryView = nil;
      return DA_STATUS_OK;
    }
    NSView* marker = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 8, 8)];
    marker.translatesAutoresizingMaskIntoConstraints = NO;
    marker.wantsLayer = YES;
    marker.layer.backgroundColor =
        [NSColor colorWithSRGBRed:red green:green blue:blue alpha:alpha].CGColor;
    marker.layer.cornerRadius = 4;
    [[marker.widthAnchor constraintEqualToConstant:8] setActive:YES];
    [[marker.heightAnchor constraintEqualToConstant:8] setActive:YES];
    owner.window.tab.accessoryView = marker;
    return DA_STATUS_OK;
  } @catch (NSException* exception) {
    return dart_appkit::SetLastError(
        DA_STATUS_INTERNAL_ERROR,
        exception.reason.UTF8String != nullptr
            ? exception.reason.UTF8String
            : "native tab color update failed");
  }
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
  if (![owner.window makeFirstResponder:responder]) {
    return dart_appkit::SetLastError(DA_STATUS_INVALID_ARGUMENT,
                                     "view refused first responder status");
  }
  return DA_STATUS_OK;
}

int32_t da_view_create(DaHandle* out_view) {
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
  DaView* view = [[DaView alloc] initWithFrame:NSZeroRect];
  const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
      view, dart_appkit::ObjectKind::kView,
      dart_appkit::ThreadDomain::kAppKitMain);
  if (handle == 0) {
    return DA_STATUS_INTERNAL_ERROR;
  }
  *out_view = handle;
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

int32_t da_text_view_create(DaHandle* out_view) {
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
  DaTextView* view = [[DaTextView alloc] initWithFrame:NSZeroRect];
  const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
      view, dart_appkit::ObjectKind::kTextView,
      dart_appkit::ThreadDomain::kAppKitMain);
  if (handle == 0) {
    return DA_STATUS_INTERNAL_ERROR;
  }
  *out_view = handle;
  return DA_STATUS_OK;
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
