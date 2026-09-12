#ifndef DART_APPKIT_BRIDGE_SRC_BRIDGE_INTERNAL_H_
#define DART_APPKIT_BRIDGE_SRC_BRIDGE_INTERNAL_H_

#include <cstdint>
#include <vector>
#include <string>
#include <string_view>

#include "dart_appkit.h"

namespace dart_appkit {

struct NativeEvent {
  DaEventType type = DA_EVENT_WINDOW_CLOSED;
  DaHandle window = 0;
  int64_t monotonic_nanos = 0;
  int64_t operation_id = 0;

  double width = 0.0;
  double height = 0.0;
  double x = 0.0;
  double y = 0.0;
  double scrolling_delta_x = 0.0;
  double scrolling_delta_y = 0.0;
  double backing_scale_factor = 0.0;

  double screen_x = 0.0;
  double screen_y = 0.0;
  double screen_width = 0.0;
  double screen_height = 0.0;
  double visible_screen_x = 0.0;
  double visible_screen_y = 0.0;
  double visible_screen_width = 0.0;
  double visible_screen_height = 0.0;

  int64_t button = -1;
  int64_t modifiers = 0;
  int64_t click_count = 0;
  int64_t key_code = 0;
  bool is_repeat = false;
  bool has_precise_scrolling_deltas = false;
  bool direction_inverted_from_device = false;
  bool state = false;
  bool has_screen = false;
  int64_t screen_id = 0;
  int64_t scroll_phase = DA_SCROLL_PHASE_NONE;
  int64_t momentum_phase = DA_SCROLL_PHASE_NONE;

  std::string characters;
  std::string characters_ignoring_modifiers;
};

using EventPoster = bool (*)(int64_t dart_port, uint32_t event_protocol_version,
                             const NativeEvent& event, void* context);

enum class UserNotificationOperation { kPost, kRemove };

using UserNotificationHandler = bool (*)(
    UserNotificationOperation operation, std::string_view identifier,
    std::string_view title, std::string_view body, void* context);

struct ScreenSelectionCandidate {
  DaScreenSnapshot snapshot{};
  bool is_main = false;
};

/** Returns the selected candidate index, or -1 when no candidate exists. */
int ResolveScreenSelectionIndex(
    int32_t selection, const std::vector<ScreenSelectionCandidate>& candidates,
    double mouse_x, double mouse_y);

void ClearLastError();
int32_t SetLastError(DaStatus status, std::string_view message);
int32_t RequireMainThread();

void InstallEventPoster(EventPoster poster, void* context);
void DisableEventPoster();
bool HasEventPoster();
int32_t SetEventPort(int64_t dart_port);
int32_t SetEventPortVersioned(int64_t dart_port, uint32_t min_version,
                              uint32_t max_version,
                              uint32_t* out_selected_version);
bool PostEvent(const NativeEvent& event);
int64_t NextOperationId();

enum class ApplicationTerminationDecision {
  kTerminateNow,
  kTerminateLater,
};

void PostApplicationActiveChanged(bool is_active);
void PostApplicationReopenRequested(bool has_visible_windows);
void PostApplicationAppearanceChanged(bool is_dark);
bool ApplicationUsesDarkAppearance();
void StartApplicationAppearanceObservation();
void StopApplicationAppearanceObservation();
ApplicationTerminationDecision HandleApplicationShouldTerminate();
void InstallUserNotificationHandlerForTesting(UserNotificationHandler handler,
                                              void* context);

inline bool EventTypeSupportedByProtocol(DaEventType type,
                                         uint32_t protocol_version) {
  if (protocol_version < DA_EVENT_PROTOCOL_VERSION_MIN ||
      protocol_version > DA_EVENT_PROTOCOL_VERSION_CURRENT) {
    return false;
  }
  switch (type) {
    case DA_EVENT_WINDOW_CLOSED:
    case DA_EVENT_WINDOW_RESIZED:
    case DA_EVENT_MOUSE_DOWN:
    case DA_EVENT_MOUSE_UP:
    case DA_EVENT_MOUSE_MOVED:
    case DA_EVENT_MOUSE_DRAGGED:
    case DA_EVENT_KEY_DOWN:
    case DA_EVENT_KEY_UP:
      return true;
    case DA_EVENT_SCROLL_WHEEL:
      return protocol_version >= 5;
    case DA_EVENT_WINDOW_FRAME_CHANGED:
    case DA_EVENT_WINDOW_FULLSCREEN_CHANGED:
      return protocol_version >= 6;
    case DA_EVENT_APPLICATION_APPEARANCE_CHANGED:
      return protocol_version >= 7;
    case DA_EVENT_GLOBAL_HOT_KEY_PRESSED:
      return protocol_version >= 8;
    case DA_EVENT_WINDOW_FOCUS_CHANGED:
    case DA_EVENT_WINDOW_VISIBILITY_CHANGED:
    case DA_EVENT_WINDOW_OCCLUSION_CHANGED:
    case DA_EVENT_WINDOW_BACKING_SCALE_CHANGED:
    case DA_EVENT_WINDOW_SCREEN_CHANGED:
      return protocol_version >= 3;
    case DA_EVENT_WINDOW_CLOSE_REQUESTED:
    case DA_EVENT_APPLICATION_ACTIVE_CHANGED:
    case DA_EVENT_APPLICATION_REOPEN_REQUESTED:
    case DA_EVENT_APPLICATION_TERMINATE_REQUESTED:
    case DA_EVENT_MENU_ITEM_INVOKED:
      return protocol_version >= 4;
  }
  return false;
}

int64_t MonotonicNanos();
uint64_t StableModifiers(uint64_t appkit_modifiers);

void ShutdownBridge();
void ResetBridgeForTesting();

}  // namespace dart_appkit

#endif  // DART_APPKIT_BRIDGE_SRC_BRIDGE_INTERNAL_H_
