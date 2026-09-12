#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <string>

#include "DartEventEncoder.h"
#include "include/dart_native_api.h"

namespace {

int g_failures = 0;
int g_post_count = 0;
int g_expected_case = 0;

#define EXPECT_TRUE(condition)                                      \
  do {                                                              \
    if (!(condition)) {                                             \
      std::cerr << __FILE__ << ':' << __LINE__                      \
                << " expectation failed: " #condition << std::endl; \
      ++g_failures;                                                 \
    }                                                               \
  } while (false)

#define EXPECT_EQ(actual, expected)                                 \
  do {                                                              \
    const auto actual_value = (actual);                             \
    const auto expected_value = (expected);                         \
    if (actual_value != expected_value) {                           \
      std::cerr << __FILE__ << ':' << __LINE__                      \
                << " expectation failed: " #actual " == " #expected \
                << std::endl;                                       \
      ++g_failures;                                                 \
    }                                                               \
  } while (false)

void ExpectInt(Dart_CObject* object, int64_t value) {
  EXPECT_EQ(object->type, Dart_CObject_kInt64);
  EXPECT_EQ(object->value.as_int64, value);
}

void ExpectDouble(Dart_CObject* object, double value) {
  EXPECT_EQ(object->type, Dart_CObject_kDouble);
  EXPECT_EQ(object->value.as_double, value);
}

void ExpectBool(Dart_CObject* object, bool value) {
  EXPECT_EQ(object->type, Dart_CObject_kBool);
  EXPECT_EQ(object->value.as_bool, value);
}

void ExpectUtf8Bytes(Dart_CObject* object, const std::string& value) {
  EXPECT_EQ(object->type, Dart_CObject_kTypedData);
  EXPECT_EQ(object->value.as_typed_data.type, Dart_TypedData_kUint8);
  EXPECT_EQ(object->value.as_typed_data.length,
            static_cast<intptr_t>(value.size()));
  EXPECT_TRUE(std::memcmp(object->value.as_typed_data.values, value.data(),
                          value.size()) == 0);
}

}  // namespace

extern "C" bool Dart_PostCObject(Dart_Port port_id, Dart_CObject* message) {
  ++g_post_count;
  EXPECT_EQ(port_id, static_cast<Dart_Port>(4242));
  EXPECT_EQ(message->type, Dart_CObject_kArray);
  Dart_CObject** values = message->value.as_array.values;
  if (g_expected_case == 1) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(6));
    ExpectInt(values[0], 1);
    ExpectInt(values[1], DA_EVENT_WINDOW_RESIZED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 1234567);
    ExpectDouble(values[4], 640.5);
    ExpectDouble(values[5], 480.25);
  } else if (g_expected_case == 2) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(11));
    ExpectInt(values[0], 2);
    ExpectInt(values[1], DA_EVENT_KEY_DOWN);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectInt(values[6], 14);
    ExpectInt(values[7], DA_MODIFIER_OPTION);
    EXPECT_EQ(values[8]->type, Dart_CObject_kBool);
    EXPECT_TRUE(values[8]->value.as_bool);
    EXPECT_EQ(values[9]->type, Dart_CObject_kString);
    EXPECT_TRUE(std::strcmp(values[9]->value.as_string, "é") == 0);
    EXPECT_EQ(values[10]->type, Dart_CObject_kString);
    EXPECT_TRUE(std::strcmp(values[10]->value.as_string, "e") == 0);
  } else if (g_expected_case == 3) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(16));
    ExpectInt(values[0], 3);
    ExpectInt(values[1], DA_EVENT_WINDOW_SCREEN_CHANGED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectBool(values[6], true);
    ExpectInt(values[7], 55);
    ExpectDouble(values[8], -1920.0);
    ExpectDouble(values[9], 0.0);
    ExpectDouble(values[10], 1920.0);
    ExpectDouble(values[11], 1080.0);
    ExpectDouble(values[12], -1920.0);
    ExpectDouble(values[13], 25.0);
    ExpectDouble(values[14], 1920.0);
    ExpectDouble(values[15], 1055.0);
  } else if (g_expected_case == 4) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(6));
    ExpectInt(values[0], 4);
    ExpectInt(values[1], DA_EVENT_WINDOW_CLOSE_REQUESTED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 42);
  } else if (g_expected_case == 5) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(7));
    ExpectInt(values[0], 4);
    ExpectInt(values[1], DA_EVENT_APPLICATION_ACTIVE_CHANGED);
    ExpectInt(values[2], 0);
    ExpectInt(values[3], 0);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectBool(values[6], true);
  } else if (g_expected_case == 6) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(6));
    ExpectInt(values[0], 4);
    ExpectInt(values[1], DA_EVENT_APPLICATION_TERMINATE_REQUESTED);
    ExpectInt(values[2], 0);
    ExpectInt(values[3], 0);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 43);
  } else if (g_expected_case == 7) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(6));
    ExpectInt(values[0], 4);
    ExpectInt(values[1], DA_EVENT_MENU_ITEM_INVOKED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
  } else if (g_expected_case == 8) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(15));
    ExpectInt(values[0], 5);
    ExpectInt(values[1], DA_EVENT_SCROLL_WHEEL);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectDouble(values[6], 12.5);
    ExpectDouble(values[7], 20.25);
    ExpectDouble(values[8], -1.5);
    ExpectDouble(values[9], 8.75);
    ExpectBool(values[10], true);
    ExpectInt(values[11], DA_SCROLL_PHASE_CHANGED);
    ExpectInt(values[12], DA_SCROLL_PHASE_BEGAN);
    ExpectBool(values[13], false);
    ExpectInt(values[14], DA_MODIFIER_SHIFT);
  } else if (g_expected_case == 9) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(10));
    ExpectInt(values[0], 6);
    ExpectInt(values[1], DA_EVENT_WINDOW_FRAME_CHANGED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectDouble(values[6], -1200.0);
    ExpectDouble(values[7], 80.0);
    ExpectDouble(values[8], 920.0);
    ExpectDouble(values[9], 580.0);
  } else if (g_expected_case == 10) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(7));
    ExpectInt(values[0], 6);
    ExpectInt(values[1], DA_EVENT_WINDOW_FULLSCREEN_CHANGED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectBool(values[6], true);
  } else if (g_expected_case == 11) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(7));
    ExpectInt(values[0], 7);
    ExpectInt(values[1], DA_EVENT_APPLICATION_APPEARANCE_CHANGED);
    ExpectInt(values[2], 0);
    ExpectInt(values[3], 0);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectBool(values[6], true);
  } else if (g_expected_case == 12) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(6));
    ExpectInt(values[0], 8);
    ExpectInt(values[1], DA_EVENT_GLOBAL_HOT_KEY_PRESSED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
  } else if (g_expected_case == 13) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(8));
    ExpectInt(values[0], 9);
    ExpectInt(values[1], DA_EVENT_VIEW_QUICK_LOOK_REQUESTED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectDouble(values[6], 12.5);
    ExpectDouble(values[7], 20.25);
  } else if (g_expected_case == 14) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(7));
    ExpectInt(values[0], 10);
    ExpectInt(values[1], DA_EVENT_VIEW_SERVICES_TEXT_RECEIVED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectUtf8Bytes(values[6], std::string("service\0—text", 15));
  } else if (g_expected_case == 15) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(10));
    ExpectInt(values[0], 11);
    ExpectInt(values[1], DA_EVENT_VIEW_DROP_PERFORMED);
    ExpectInt(values[2], (static_cast<int64_t>(7) << 32) | 3);
    ExpectInt(values[3], 7);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectInt(values[6], DA_DROP_CONTENT_FILE_URLS);
    ExpectDouble(values[7], 30.5);
    ExpectDouble(values[8], 40.25);
    ExpectUtf8Bytes(values[9], std::string("\x01\0\0\0\x03\0\0\0url", 11));
  } else if (g_expected_case == 16) {
    EXPECT_EQ(message->value.as_array.length, static_cast<intptr_t>(8));
    ExpectInt(values[0], 12);
    ExpectInt(values[1], DA_EVENT_APPLICATION_FOLDER_SERVICE_REQUESTED);
    ExpectInt(values[2], 0);
    ExpectInt(values[3], 0);
    ExpectInt(values[4], 1234567890);
    ExpectInt(values[5], 0);
    ExpectInt(values[6], DA_FOLDER_SERVICE_NEW_WINDOWS);
    ExpectUtf8Bytes(
        values[7],
        std::string("\x01\0\0\0\x0b\0\0\0file:///tmp", 19));
  } else {
    EXPECT_TRUE(false);
  }
  return true;
}

int main() {
  dart_appkit::NativeEvent event;
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  event.monotonic_nanos = 1234567890;
  event.type = DA_EVENT_WINDOW_RESIZED;
  event.width = 640.5;
  event.height = 480.25;

  g_expected_case = 1;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 1, event));

  event.type = DA_EVENT_KEY_DOWN;
  event.key_code = 14;
  event.modifiers = DA_MODIFIER_OPTION;
  event.is_repeat = true;
  event.characters = "é";
  event.characters_ignoring_modifiers = "e";
  g_expected_case = 2;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 2, event));

  event.type = DA_EVENT_WINDOW_SCREEN_CHANGED;
  event.has_screen = true;
  event.screen_id = 55;
  event.screen_x = -1920.0;
  event.screen_y = 0.0;
  event.screen_width = 1920.0;
  event.screen_height = 1080.0;
  event.visible_screen_x = -1920.0;
  event.visible_screen_y = 25.0;
  event.visible_screen_width = 1920.0;
  event.visible_screen_height = 1055.0;
  g_expected_case = 3;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 3, event));

  event.type = DA_EVENT_WINDOW_CLOSE_REQUESTED;
  event.operation_id = 42;
  g_expected_case = 4;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 4, event));

  event.type = DA_EVENT_APPLICATION_ACTIVE_CHANGED;
  event.window = 0;
  event.operation_id = 0;
  event.state = true;
  g_expected_case = 5;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 4, event));

  event.type = DA_EVENT_APPLICATION_TERMINATE_REQUESTED;
  event.operation_id = 43;
  g_expected_case = 6;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 4, event));

  event.type = DA_EVENT_MENU_ITEM_INVOKED;
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  event.operation_id = 0;
  g_expected_case = 7;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 4, event));

  event.type = DA_EVENT_SCROLL_WHEEL;
  event.x = 12.5;
  event.y = 20.25;
  event.scrolling_delta_x = -1.5;
  event.scrolling_delta_y = 8.75;
  event.has_precise_scrolling_deltas = true;
  event.scroll_phase = DA_SCROLL_PHASE_CHANGED;
  event.momentum_phase = DA_SCROLL_PHASE_BEGAN;
  event.direction_inverted_from_device = false;
  event.modifiers = DA_MODIFIER_SHIFT;
  g_expected_case = 8;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 5, event));

  event.type = DA_EVENT_WINDOW_FRAME_CHANGED;
  event.x = -1200.0;
  event.y = 80.0;
  event.width = 920.0;
  event.height = 580.0;
  g_expected_case = 9;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 6, event));

  event.type = DA_EVENT_WINDOW_FULLSCREEN_CHANGED;
  event.state = true;
  g_expected_case = 10;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 6, event));

  event.type = DA_EVENT_APPLICATION_APPEARANCE_CHANGED;
  event.window = 0;
  event.state = true;
  g_expected_case = 11;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 7, event));

  event.type = DA_EVENT_GLOBAL_HOT_KEY_PRESSED;
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  event.state = false;
  g_expected_case = 12;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 8, event));

  event.type = DA_EVENT_VIEW_QUICK_LOOK_REQUESTED;
  event.x = 12.5;
  event.y = 20.25;
  g_expected_case = 13;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 9, event));
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 8, event));

  event.type = DA_EVENT_VIEW_SERVICES_TEXT_RECEIVED;
  event.characters = std::string("service\0—text", 15);
  g_expected_case = 14;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 10, event));
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 9, event));

  event.type = DA_EVENT_VIEW_DROP_PERFORMED;
  event.drop_content_kind = DA_DROP_CONTENT_FILE_URLS;
  event.x = 30.5;
  event.y = 40.25;
  event.characters = std::string("\x01\0\0\0\x03\0\0\0url", 11);
  g_expected_case = 15;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 11, event));
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 10, event));

  event.type = DA_EVENT_APPLICATION_FOLDER_SERVICE_REQUESTED;
  event.window = 0;
  event.folder_service_disposition = DA_FOLDER_SERVICE_NEW_WINDOWS;
  event.characters =
      std::string("\x01\0\0\0\x0b\0\0\0file:///tmp", 19);
  g_expected_case = 16;
  EXPECT_TRUE(dart_appkit::PostNativeEventToDartPort(4242, 12, event));
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 11, event));

  const int accepted_posts = g_post_count;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 7, event));
  event.type = DA_EVENT_APPLICATION_APPEARANCE_CHANGED;
  event.window = 0;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 6, event));
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 5, event));
  event.type = DA_EVENT_WINDOW_FRAME_CHANGED;
  event.width = 0.0;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 6, event));
  event.width = 920.0;
  event.x = std::numeric_limits<double>::infinity();
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 6, event));
  event.x = -1200.0;
  event.type = DA_EVENT_SCROLL_WHEEL;
  event.scroll_phase = 3;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 5, event));
  event.scroll_phase = DA_SCROLL_PHASE_CHANGED;
  event.scrolling_delta_y = std::numeric_limits<double>::infinity();
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 5, event));
  event.scrolling_delta_y = 8.75;
  event.type = DA_EVENT_APPLICATION_ACTIVE_CHANGED;
  event.window = 0;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 3, event));
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 4, event));
  event.type = DA_EVENT_WINDOW_CLOSE_REQUESTED;
  event.operation_id = 0;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 4, event));
  event.type = DA_EVENT_WINDOW_CLOSED;
  event.operation_id = 1;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 4, event));
  event.operation_id = 0;
  event.type = DA_EVENT_WINDOW_SCREEN_CHANGED;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 2, event));
  event.screen_id = 0;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 3, event));
  event.screen_id = 55;
  event.visible_screen_width = 0.0;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 3, event));
  event.visible_screen_width = 1920.0;
  event.type = DA_EVENT_WINDOW_BACKING_SCALE_CHANGED;
  event.backing_scale_factor = 0.0;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 3, event));
  event.type = DA_EVENT_KEY_DOWN;
  event.operation_id = 1;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 1, event));
  event.operation_id = 0;
  event.type = DA_EVENT_VIEW_DROP_PERFORMED;
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  event.drop_content_kind = 2;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 11, event));
  event.drop_content_kind = DA_DROP_CONTENT_PLAIN_TEXT;
  event.x = std::numeric_limits<double>::infinity();
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 11, event));
  event.x = 30.5;
  event.type = DA_EVENT_APPLICATION_FOLDER_SERVICE_REQUESTED;
  event.window = 0;
  event.folder_service_disposition = 2;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 12, event));
  event.folder_service_disposition = DA_FOLDER_SERVICE_NEW_TABS;
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 12, event));
  event.type = DA_EVENT_KEY_DOWN;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 13, event));
  event.window = 0;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 2, event));
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  event.monotonic_nanos = -1;
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 2, event));
  EXPECT_EQ(g_post_count, accepted_posts);

  if (g_failures != 0) {
    std::cerr << g_failures << " Dart event encoder test(s) failed"
              << std::endl;
    return 1;
  }
  std::cout << "all Dart event encoder tests passed" << std::endl;
  return 0;
}
