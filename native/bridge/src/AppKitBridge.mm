#include "dart_appkit.h"

#import <AppKit/AppKit.h>

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <limits>
#include <string>
#include <string_view>

#include "AppKitObjects.h"
#include "BridgeInternal.h"
#include "ObjectRegistry.h"

namespace dart_appkit {
namespace {

struct ErrorState {
  int32_t code = DA_STATUS_OK;
  std::string message;
};

thread_local ErrorState g_last_error;
std::atomic<bool> g_accept_finalizers{true};

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
  return static_cast<DaWindowOwner*>(
      ObjectRegistry::Shared().Lookup(handle, ObjectKind::kWindow, out_status));
}

DaTextView* TextView(DaHandle handle, int32_t* out_status) {
  return static_cast<DaTextView*>(ObjectRegistry::Shared().Lookup(
      handle, ObjectKind::kTextView, out_status));
}

void PrepareWindowForRelease(DaWindowOwner* owner) {
  if (owner == nil) {
    return;
  }
  owner.daHandle = 0;
  owner.window.daHandle = 0;
  owner.window.delegate = nil;
  [owner.window orderOut:nil];
  [owner.window close];
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

void ShutdownBridge() {
  if (pthread_main_np() == 0) {
    return;
  }
  g_accept_finalizers.store(false, std::memory_order_release);
  DisableEventPoster();

  ObjectRegistry& registry = ObjectRegistry::Shared();
  const std::vector<DaHandle> handles = registry.LiveHandles();
  for (const DaHandle handle : handles) {
    ObjectKind kind = ObjectKind::kTextView;
    int32_t status = DA_STATUS_OK;
    id object = registry.LookupAny(handle, &kind, &status);
    if (status == DA_STATUS_OK && kind == ObjectKind::kWindow) {
      PrepareWindowForRelease(static_cast<DaWindowOwner*>(object));
    }
    registry.Release(handle);
  }
  registry.Clear();
}

void ResetBridgeForTesting() {
  ShutdownBridge();
  g_accept_finalizers.store(true, std::memory_order_release);
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
  return dart_appkit::SetEventPortVersioned(dart_port, min_version, max_version,
                                            out_selected_version);
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
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp terminate:nil];
  });
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
    window.title = copied_title;
    window.releasedWhenClosed = NO;
    window.acceptsMouseMovedEvents = YES;

    DaWindowOwner* owner = [[DaWindowOwner alloc] initWithWindow:window];
    const DaHandle handle = dart_appkit::ObjectRegistry::Shared().Insert(
        owner, dart_appkit::ObjectKind::kWindow);
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
  [owner.window close];
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
      view, dart_appkit::ObjectKind::kTextView);
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
  DaTextView* text_view = dart_appkit::TextView(view, &status);
  if (text_view == nil) {
    return status;
  }
  text_view.frame = owner.window.contentLayoutRect;
  owner.window.contentView = text_view;
  [owner.window makeFirstResponder:text_view];
  return DA_STATUS_OK;
}

int32_t da_release(DaHandle handle) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  dart_appkit::ObjectKind kind = dart_appkit::ObjectKind::kTextView;
  int32_t status = DA_STATUS_OK;
  id object =
      dart_appkit::ObjectRegistry::Shared().LookupAny(handle, &kind, &status);
  if (object == nil) {
    return status;
  }
  if (kind == dart_appkit::ObjectKind::kWindow) {
    dart_appkit::PrepareWindowForRelease(static_cast<DaWindowOwner*>(object));
  }
  return dart_appkit::ObjectRegistry::Shared().Release(handle);
}

void da_release_finalizer(void* token) {
  const DaHandle handle =
      static_cast<DaHandle>(reinterpret_cast<uintptr_t>(token));
  if (handle == 0 ||
      !dart_appkit::g_accept_finalizers.load(std::memory_order_acquire)) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if (dart_appkit::g_accept_finalizers.load(std::memory_order_acquire)) {
      (void)da_release(handle);
    }
  });
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
