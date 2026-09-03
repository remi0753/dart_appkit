#include "DartEventEncoder.h"

#include <array>
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

}  // namespace

bool PostNativeEventToDartPort(int64_t dart_port,
                               uint32_t event_protocol_version,
                               const NativeEvent& event) {
  if (dart_port <= 0 || event.window == 0 || event.monotonic_nanos < 0 ||
      event.operation_id < 0) {
    return false;
  }

  std::array<Dart_CObject, 11> values{};
  std::array<Dart_CObject*, 11> pointers{};
  for (size_t index = 0; index < pointers.size(); ++index) {
    pointers[index] = &values[index];
  }

  intptr_t payload_offset = 0;
  switch (event_protocol_version) {
    case DA_EVENT_PROTOCOL_VERSION_MIN:
      if (event.operation_id != 0) {
        return false;
      }
      SetInt64(&values[0], DA_EVENT_PROTOCOL_VERSION_MIN);
      SetInt64(&values[1], event.type);
      SetInt64(&values[2], static_cast<int64_t>(event.window));
      SetInt64(&values[3], event.monotonic_nanos / 1000);
      payload_offset = 4;
      break;
    case DA_EVENT_PROTOCOL_VERSION_CURRENT: {
      const int64_t source_generation =
          static_cast<int64_t>(event.window >> 32);
      if (source_generation <= 0) {
        return false;
      }
      SetInt64(&values[0], DA_EVENT_PROTOCOL_VERSION_CURRENT);
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
      break;
    case DA_EVENT_WINDOW_RESIZED:
      length += 2;
      SetDouble(&values[payload_offset], event.width);
      SetDouble(&values[payload_offset + 1], event.height);
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
