#include "DartEventEncoder.h"

#include <array>
#include <cmath>
#include <string>

#include "include/dart_native_api.h"

namespace dart_appkit {
namespace {

void SetInt64(Dart_CObject* object, int64_t value) {
  object->type = Dart_CObject_kInt64;
  object->value.as_int64 = value;
}

void SetDouble(Dart_CObject* object, double value) {
  object->type = Dart_CObject_kDouble;
  object->value.as_double = value;
}

void SetBool(Dart_CObject* object, bool value) {
  object->type = Dart_CObject_kBool;
  object->value.as_bool = value;
}

void SetString(Dart_CObject* object, const std::string& value) {
  object->type = Dart_CObject_kString;
  object->value.as_string = value.c_str();
}

bool ValidScreen(const NativeEvent& event) {
  const bool finite =
      std::isfinite(event.screen_x) && std::isfinite(event.screen_y) &&
      std::isfinite(event.screen_width) && std::isfinite(event.screen_height) &&
      std::isfinite(event.visible_screen_x) &&
      std::isfinite(event.visible_screen_y) &&
      std::isfinite(event.visible_screen_width) &&
      std::isfinite(event.visible_screen_height);
  if (!finite) {
    return false;
  }
  if (!event.has_screen) {
    return event.screen_id == 0 && event.screen_x == 0.0 &&
           event.screen_y == 0.0 && event.screen_width == 0.0 &&
           event.screen_height == 0.0 && event.visible_screen_x == 0.0 &&
           event.visible_screen_y == 0.0 && event.visible_screen_width == 0.0 &&
           event.visible_screen_height == 0.0;
  }
  return event.screen_id > 0 && event.screen_width > 0.0 &&
         event.screen_height > 0.0 && event.visible_screen_width > 0.0 &&
         event.visible_screen_height > 0.0;
}

bool ValidScrollPhase(int64_t phase) {
  switch (phase) {
    case DA_SCROLL_PHASE_NONE:
    case DA_SCROLL_PHASE_BEGAN:
    case DA_SCROLL_PHASE_STATIONARY:
    case DA_SCROLL_PHASE_CHANGED:
    case DA_SCROLL_PHASE_ENDED:
    case DA_SCROLL_PHASE_CANCELLED:
    case DA_SCROLL_PHASE_MAY_BEGIN:
      return true;
    default:
      return false;
  }
}

}  // namespace

bool PostNativeEventToDartPort(int64_t dart_port,
                               uint32_t event_protocol_version,
                               const NativeEvent& event) {
  if (dart_port <= 0 || event.monotonic_nanos < 0 || event.operation_id < 0) {
    return false;
  }

  if (!EventTypeSupportedByProtocol(event.type, event_protocol_version)) {
    return false;
  }

  const bool application_scoped =
      event.type == DA_EVENT_APPLICATION_ACTIVE_CHANGED ||
      event.type == DA_EVENT_APPLICATION_REOPEN_REQUESTED ||
      event.type == DA_EVENT_APPLICATION_TERMINATE_REQUESTED ||
      event.type == DA_EVENT_APPLICATION_APPEARANCE_CHANGED;
  const bool reply_required =
      event.type == DA_EVENT_WINDOW_CLOSE_REQUESTED ||
      event.type == DA_EVENT_APPLICATION_TERMINATE_REQUESTED;
  if ((reply_required && event.operation_id <= 0) ||
      (!reply_required && event.operation_id != 0)) {
    return false;
  }

  std::array<Dart_CObject, 16> values{};
  std::array<Dart_CObject*, 16> pointers{};
  for (size_t index = 0; index < pointers.size(); ++index) {
    pointers[index] = &values[index];
  }

  intptr_t payload_offset = 0;
  switch (event_protocol_version) {
    case DA_EVENT_PROTOCOL_VERSION_MIN:
      if (application_scoped || event.window == 0) {
        return false;
      }
      SetInt64(&values[0], DA_EVENT_PROTOCOL_VERSION_MIN);
      SetInt64(&values[1], event.type);
      SetInt64(&values[2], static_cast<int64_t>(event.window));
      SetInt64(&values[3], event.monotonic_nanos / 1000);
      payload_offset = 4;
      break;
    case 2:
    case 3:
    case 4:
    case 5:
    case 6:
    case 7:
    case DA_EVENT_PROTOCOL_VERSION_CURRENT: {
      const int64_t source_generation =
          static_cast<int64_t>(event.window >> 32);
      if ((application_scoped &&
           (event.window != 0 || source_generation != 0)) ||
          (!application_scoped &&
           (event.window == 0 || source_generation <= 0))) {
        return false;
      }
      SetInt64(&values[0], event_protocol_version);
      SetInt64(&values[1], event.type);
      SetInt64(&values[2], static_cast<int64_t>(event.window));
      SetInt64(&values[3], source_generation);
      SetInt64(&values[4], event.monotonic_nanos);
      SetInt64(&values[5], event.operation_id);
      payload_offset = 6;
      break;
    }
    default:
      return false;
  }

  intptr_t length = payload_offset;
  switch (event.type) {
    case DA_EVENT_WINDOW_CLOSED:
    case DA_EVENT_WINDOW_CLOSE_REQUESTED:
    case DA_EVENT_APPLICATION_TERMINATE_REQUESTED:
    case DA_EVENT_MENU_ITEM_INVOKED:
    case DA_EVENT_GLOBAL_HOT_KEY_PRESSED:
      break;
    case DA_EVENT_WINDOW_RESIZED:
      length += 2;
      SetDouble(&values[payload_offset], event.width);
      SetDouble(&values[payload_offset + 1], event.height);
      break;
    case DA_EVENT_WINDOW_FRAME_CHANGED:
      if (!std::isfinite(event.x) || !std::isfinite(event.y) ||
          !std::isfinite(event.width) || !std::isfinite(event.height) ||
          event.width <= 0.0 || event.height <= 0.0) {
        return false;
      }
      length += 4;
      SetDouble(&values[payload_offset], event.x);
      SetDouble(&values[payload_offset + 1], event.y);
      SetDouble(&values[payload_offset + 2], event.width);
      SetDouble(&values[payload_offset + 3], event.height);
      break;
    case DA_EVENT_WINDOW_FOCUS_CHANGED:
    case DA_EVENT_WINDOW_VISIBILITY_CHANGED:
    case DA_EVENT_WINDOW_OCCLUSION_CHANGED:
    case DA_EVENT_APPLICATION_ACTIVE_CHANGED:
    case DA_EVENT_APPLICATION_REOPEN_REQUESTED:
    case DA_EVENT_APPLICATION_APPEARANCE_CHANGED:
    case DA_EVENT_WINDOW_FULLSCREEN_CHANGED:
      length += 1;
      SetBool(&values[payload_offset], event.state);
      break;
    case DA_EVENT_WINDOW_BACKING_SCALE_CHANGED:
      if (!std::isfinite(event.backing_scale_factor) ||
          event.backing_scale_factor <= 0.0) {
        return false;
      }
      length += 1;
      SetDouble(&values[payload_offset], event.backing_scale_factor);
      break;
    case DA_EVENT_WINDOW_SCREEN_CHANGED:
      if (!ValidScreen(event)) {
        return false;
      }
      length += 10;
      SetBool(&values[payload_offset], event.has_screen);
      SetInt64(&values[payload_offset + 1], event.screen_id);
      SetDouble(&values[payload_offset + 2], event.screen_x);
      SetDouble(&values[payload_offset + 3], event.screen_y);
      SetDouble(&values[payload_offset + 4], event.screen_width);
      SetDouble(&values[payload_offset + 5], event.screen_height);
      SetDouble(&values[payload_offset + 6], event.visible_screen_x);
      SetDouble(&values[payload_offset + 7], event.visible_screen_y);
      SetDouble(&values[payload_offset + 8], event.visible_screen_width);
      SetDouble(&values[payload_offset + 9], event.visible_screen_height);
      break;
    case DA_EVENT_MOUSE_DOWN:
    case DA_EVENT_MOUSE_UP:
    case DA_EVENT_MOUSE_MOVED:
    case DA_EVENT_MOUSE_DRAGGED:
      length += 5;
      SetDouble(&values[payload_offset], event.x);
      SetDouble(&values[payload_offset + 1], event.y);
      SetInt64(&values[payload_offset + 2], event.button);
      SetInt64(&values[payload_offset + 3], event.modifiers);
      SetInt64(&values[payload_offset + 4], event.click_count);
      break;
    case DA_EVENT_SCROLL_WHEEL:
      if (!std::isfinite(event.x) || !std::isfinite(event.y) ||
          !std::isfinite(event.scrolling_delta_x) ||
          !std::isfinite(event.scrolling_delta_y) ||
          !ValidScrollPhase(event.scroll_phase) ||
          !ValidScrollPhase(event.momentum_phase)) {
        return false;
      }
      length += 9;
      SetDouble(&values[payload_offset], event.x);
      SetDouble(&values[payload_offset + 1], event.y);
      SetDouble(&values[payload_offset + 2], event.scrolling_delta_x);
      SetDouble(&values[payload_offset + 3], event.scrolling_delta_y);
      SetBool(&values[payload_offset + 4],
              event.has_precise_scrolling_deltas);
      SetInt64(&values[payload_offset + 5], event.scroll_phase);
      SetInt64(&values[payload_offset + 6], event.momentum_phase);
      SetBool(&values[payload_offset + 7],
              event.direction_inverted_from_device);
      SetInt64(&values[payload_offset + 8], event.modifiers);
      break;
    case DA_EVENT_KEY_DOWN:
    case DA_EVENT_KEY_UP:
      length += 5;
      SetInt64(&values[payload_offset], event.key_code);
      SetInt64(&values[payload_offset + 1], event.modifiers);
      SetBool(&values[payload_offset + 2], event.is_repeat);
      SetString(&values[payload_offset + 3], event.characters);
      SetString(&values[payload_offset + 4],
                event.characters_ignoring_modifiers);
      break;
    default:
      return false;
  }

  Dart_CObject message{};
  message.type = Dart_CObject_kArray;
  message.value.as_array.length = length;
  message.value.as_array.values = pointers.data();
  return Dart_PostCObject(dart_port, &message);
}

}  // namespace dart_appkit
