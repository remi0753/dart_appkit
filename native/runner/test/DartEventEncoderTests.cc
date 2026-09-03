#include <cstdint>
#include <cstring>
#include <iostream>
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

  const int accepted_posts = g_post_count;
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
  EXPECT_TRUE(!dart_appkit::PostNativeEventToDartPort(4242, 4, event));
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
