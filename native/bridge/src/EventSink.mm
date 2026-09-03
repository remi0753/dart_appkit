#include "BridgeInternal.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <atomic>
#include <ctime>
#include <mutex>

namespace dart_appkit {
namespace {

std::mutex g_event_sink_mutex;
EventPoster g_event_poster = nullptr;
void* g_event_poster_context = nullptr;
int64_t g_event_port = 0;
uint32_t g_event_protocol_version = 0;

}  // namespace

void InstallEventPoster(EventPoster poster, void* context) {
  const std::lock_guard<std::mutex> lock(g_event_sink_mutex);
  g_event_poster = poster;
  g_event_poster_context = context;
}

void DisableEventPoster() {
  const std::lock_guard<std::mutex> lock(g_event_sink_mutex);
  g_event_port = 0;
  g_event_protocol_version = 0;
  g_event_poster = nullptr;
  g_event_poster_context = nullptr;
}

bool HasEventPoster() {
  const std::lock_guard<std::mutex> lock(g_event_sink_mutex);
  return g_event_poster != nullptr;
}

int32_t SetEventPort(int64_t dart_port) {
  uint32_t selected_version = 0;
  return SetEventPortVersioned(dart_port, 1, 1, &selected_version);
}

int32_t SetEventPortVersioned(int64_t dart_port, uint32_t min_version,
                              uint32_t max_version,
                              uint32_t* out_selected_version) {
  const std::lock_guard<std::mutex> lock(g_event_sink_mutex);
  g_event_port = 0;
  g_event_protocol_version = 0;
  if (out_selected_version == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "out_selected_version must not be null");
  }
  *out_selected_version = 0;
  if (dart_port <= 0) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "Dart event port must be positive");
  }
  if (g_event_poster == nullptr) {
    return SetLastError(DA_STATUS_EVENT_PORT_UNAVAILABLE,
                        "Runner event poster is not installed");
  }
  if (min_version == 0 || max_version == 0 || min_version > max_version) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "event protocol range must be positive and ordered");
  }
  const uint32_t compatible_min =
      std::max(min_version, DA_EVENT_PROTOCOL_VERSION_MIN);
  const uint32_t compatible_max =
      std::min(max_version, DA_EVENT_PROTOCOL_VERSION_CURRENT);
  if (compatible_min > compatible_max) {
    return SetLastError(DA_STATUS_UNSUPPORTED_VERSION,
                        "event protocol ranges do not overlap");
  }
  g_event_port = dart_port;
  g_event_protocol_version = compatible_max;
  *out_selected_version = compatible_max;
  return DA_STATUS_OK;
}

bool PostEvent(const NativeEvent& event) {
  EventPoster poster = nullptr;
  void* context = nullptr;
  int64_t port = 0;
  uint32_t protocol_version = 0;
  {
    const std::lock_guard<std::mutex> lock(g_event_sink_mutex);
    poster = g_event_poster;
    context = g_event_poster_context;
    port = g_event_port;
    protocol_version = g_event_protocol_version;
  }

  if (poster == nullptr || port <= 0 || protocol_version == 0) {
    return false;
  }
  if (!EventTypeSupportedByProtocol(event.type, protocol_version)) {
    return false;
  }
  return poster(port, protocol_version, event, context);
}

int64_t MonotonicNanos() {
  timespec now{};
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
    return 0;
  }
  return static_cast<int64_t>(now.tv_sec) * 1000000000LL +
         static_cast<int64_t>(now.tv_nsec);
}

uint64_t StableModifiers(uint64_t appkit_modifiers) {
  uint64_t result = 0;
  const NSEventModifierFlags flags =
      static_cast<NSEventModifierFlags>(appkit_modifiers);
  if ((flags & NSEventModifierFlagCapsLock) != 0) {
    result |= DA_MODIFIER_CAPS_LOCK;
  }
  if ((flags & NSEventModifierFlagShift) != 0) {
    result |= DA_MODIFIER_SHIFT;
  }
  if ((flags & NSEventModifierFlagControl) != 0) {
    result |= DA_MODIFIER_CONTROL;
  }
  if ((flags & NSEventModifierFlagOption) != 0) {
    result |= DA_MODIFIER_OPTION;
  }
  if ((flags & NSEventModifierFlagCommand) != 0) {
    result |= DA_MODIFIER_COMMAND;
  }
  if ((flags & NSEventModifierFlagNumericPad) != 0) {
    result |= DA_MODIFIER_NUMERIC_PAD;
  }
  if ((flags & NSEventModifierFlagFunction) != 0) {
    result |= DA_MODIFIER_FUNCTION;
  }
  return result;
}

}  // namespace dart_appkit
