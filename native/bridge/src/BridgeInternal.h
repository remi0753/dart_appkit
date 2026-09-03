#ifndef DART_APPKIT_BRIDGE_SRC_BRIDGE_INTERNAL_H_
#define DART_APPKIT_BRIDGE_SRC_BRIDGE_INTERNAL_H_

#include <cstdint>
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

  int64_t button = -1;
  int64_t modifiers = 0;
  int64_t click_count = 0;
  int64_t key_code = 0;
  bool is_repeat = false;

  std::string characters;
  std::string characters_ignoring_modifiers;
};

using EventPoster = bool (*)(int64_t dart_port, uint32_t event_protocol_version,
                             const NativeEvent& event, void* context);

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

int64_t MonotonicNanos();
uint64_t StableModifiers(uint64_t appkit_modifiers);

void ShutdownBridge();
void ResetBridgeForTesting();

}  // namespace dart_appkit

#endif  // DART_APPKIT_BRIDGE_SRC_BRIDGE_INTERNAL_H_
