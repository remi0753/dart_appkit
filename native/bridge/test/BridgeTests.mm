#import <AppKit/AppKit.h>

#include <atomic>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include "AppKitObjects.h"
#include "BridgeInternal.h"
#include "ObjectRegistry.h"
#include "dart_appkit.h"

namespace {

int g_failures = 0;

#define EXPECT_TRUE(condition)                                      \
  do {                                                              \
    if (!(condition)) {                                             \
      std::cerr << __FILE__ << ':' << __LINE__                      \
                << " expectation failed: " #condition << std::endl; \
      ++g_failures;                                                 \
    }                                                               \
  } while (false)

#define EXPECT_EQ(actual, expected)                                     \
  do {                                                                  \
    const auto actual_value = (actual);                                 \
    const auto expected_value = (expected);                             \
    if (actual_value != expected_value) {                               \
      std::cerr << __FILE__ << ':' << __LINE__                          \
                << " expectation failed: " #actual " == " #expected     \
                << " (actual=" << actual_value                          \
                << ", expected=" << expected_value << ')' << std::endl; \
      ++g_failures;                                                     \
    }                                                                   \
  } while (false)

struct Capture {
  std::vector<dart_appkit::NativeEvent> events;
  int64_t last_port = 0;
};

bool CapturePoster(int64_t port, const dart_appkit::NativeEvent& event,
                   void* context) {
  auto* capture = static_cast<Capture*>(context);
  capture->last_port = port;
  capture->events.push_back(event);
  return true;
}

std::string LastErrorMessage() {
  DaError error{};
  da_get_last_error(&error);
  return std::string(error.message, error.message_length);
}

uint64_t LiveCount() {
  uint64_t count = 0;
  EXPECT_EQ(da_debug_live_object_count(&count), DA_STATUS_OK);
  return count;
}

DaHandle CreateWindow() {
  DaHandle handle = 0;
  const std::string title = "Native test";
  EXPECT_EQ(da_window_create({100.0, 100.0, 640.0, 480.0}, title.data(),
                             title.size(), &handle),
            DA_STATUS_OK);
  EXPECT_TRUE(handle != 0);
  return handle;
}

DaHandle CreateTextView() {
  DaHandle handle = 0;
  EXPECT_EQ(da_text_view_create(&handle), DA_STATUS_OK);
  EXPECT_TRUE(handle != 0);
  return handle;
}

DaWindowOwner* OwnerFor(DaHandle handle) {
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kWindow, &status);
  EXPECT_EQ(status, DA_STATUS_OK);
  return static_cast<DaWindowOwner*>(object);
}

void ResetWithCapture(Capture* capture) {
  dart_appkit::ResetBridgeForTesting();
  dart_appkit::InstallEventPoster(CapturePoster, capture);
  EXPECT_EQ(da_application_set_event_port(4242), DA_STATUS_OK);
}

void TestContractAndErrors() {
  dart_appkit::ResetBridgeForTesting();
  EXPECT_EQ(da_abi_version(), static_cast<uint32_t>(1));
  EXPECT_EQ(std::string(da_status_name(DA_STATUS_INVALID_UTF8)),
            std::string("invalid_utf8"));

  int32_t is_main = 0;
  EXPECT_EQ(da_debug_is_main_thread(&is_main), DA_STATUS_OK);
  EXPECT_EQ(is_main, 1);
  EXPECT_EQ(da_debug_is_main_thread(nullptr), DA_STATUS_INVALID_ARGUMENT);
  EXPECT_TRUE(LastErrorMessage().find("out_is_main_thread") !=
              std::string::npos);

  DaHandle handle = 99;
  EXPECT_EQ(da_window_create({0.0, 0.0, -1.0, 100.0}, nullptr, 0, &handle),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(handle, static_cast<DaHandle>(0));

  const char invalid_utf8[] = {static_cast<char>(0xc3), '('};
  handle = 99;
  EXPECT_EQ(da_window_create({0.0, 0.0, 100.0, 100.0}, invalid_utf8,
                             sizeof(invalid_utf8), &handle),
            DA_STATUS_INVALID_UTF8);
  EXPECT_EQ(handle, static_cast<DaHandle>(0));

  EXPECT_EQ(da_application_set_event_port(1), DA_STATUS_EVENT_PORT_UNAVAILABLE);
}

void TestRegistryLifecycleAndTypes() {
  Capture capture;
  ResetWithCapture(&capture);

  const DaHandle window = CreateWindow();
  const DaHandle view = CreateTextView();
  EXPECT_TRUE(window <= static_cast<DaHandle>(INT64_MAX));
  EXPECT_TRUE(view <= static_cast<DaHandle>(INT64_MAX));
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(2));

  const std::string unicode_text = "Hello, AppKit — 日本語";
  EXPECT_EQ(
      da_text_view_set_text(view, unicode_text.data(), unicode_text.size()),
      DA_STATUS_OK);
  EXPECT_EQ(da_window_set_content_view(window, view), DA_STATUS_OK);
  EXPECT_EQ(da_text_view_set_text(window, "bad", 3),
            DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_TRUE(LastErrorMessage().find("expected text view") !=
              std::string::npos);

  EXPECT_EQ(da_release(view), DA_STATUS_OK);
  EXPECT_EQ(da_release(view), DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(1));
  EXPECT_EQ(da_release(window), DA_STATUS_OK);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));

  const DaHandle first = CreateTextView();
  EXPECT_EQ(da_release(first), DA_STATUS_OK);
  const DaHandle second = CreateTextView();
  EXPECT_TRUE(first != second);
  EXPECT_EQ(da_text_view_set_text(first, "stale", 5), DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(da_release(second), DA_STATUS_OK);
}

void TestThreadGuardAndFinalizer() {
  Capture capture;
  ResetWithCapture(&capture);

  std::atomic<int32_t> worker_status{DA_STATUS_OK};
  std::atomic<int32_t> worker_is_main{-1};
  std::thread worker([&]() {
    DaHandle handle = 123;
    worker_status.store(da_text_view_create(&handle));
    EXPECT_EQ(handle, static_cast<DaHandle>(0));
    int32_t is_main = -1;
    EXPECT_EQ(da_debug_is_main_thread(&is_main), DA_STATUS_OK);
    worker_is_main.store(is_main);
  });
  worker.join();
  EXPECT_EQ(worker_status.load(), DA_STATUS_WRONG_THREAD);
  EXPECT_EQ(worker_is_main.load(), 0);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));

  const DaHandle finalized = CreateTextView();
  std::thread finalizer_thread([finalized]() {
    da_release_finalizer(
        reinterpret_cast<void*>(static_cast<uintptr_t>(finalized)));
  });
  finalizer_thread.join();

  const NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
  while (LiveCount() != 0 && deadline.timeIntervalSinceNow > 0.0) {
    [[NSRunLoop mainRunLoop]
           runMode:NSDefaultRunLoopMode
        beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
}

void TestWindowEvents() {
  Capture capture;
  ResetWithCapture(&capture);
  const DaHandle window_handle = CreateWindow();
  const DaHandle view_handle = CreateTextView();
  EXPECT_EQ(da_window_set_content_view(window_handle, view_handle),
            DA_STATUS_OK);

  DaWindowOwner* owner = OwnerFor(window_handle);
  owner.window.contentView.frame = NSMakeRect(0.0, 0.0, 777.0, 333.0);
  [owner windowDidResize:[NSNotification
                             notificationWithName:NSWindowDidResizeNotification
                                           object:owner.window]];
  [owner windowWillClose:[NSNotification
                             notificationWithName:NSWindowWillCloseNotification
                                           object:owner.window]];

  EXPECT_EQ(capture.last_port, static_cast<int64_t>(4242));
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(2));
  EXPECT_EQ(capture.events[0].type, DA_EVENT_WINDOW_RESIZED);
  EXPECT_EQ(capture.events[0].window, window_handle);
  EXPECT_TRUE(std::abs(capture.events[0].width - 777.0) < 0.001);
  EXPECT_TRUE(std::abs(capture.events[0].height - 333.0) < 0.001);
  EXPECT_EQ(capture.events[1].type, DA_EVENT_WINDOW_CLOSED);
  EXPECT_TRUE(capture.events[1].monotonic_micros > 0);

  EXPECT_EQ(da_release(view_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(window_handle), DA_STATUS_OK);
}

void TestInputEvents() {
  Capture capture;
  ResetWithCapture(&capture);
  const DaHandle window_handle = CreateWindow();
  DaWindowOwner* owner = OwnerFor(window_handle);

  NSEvent* mouse = [NSEvent
      mouseEventWithType:NSEventTypeLeftMouseDown
                location:NSMakePoint(12.5, 20.0)
           modifierFlags:NSEventModifierFlagShift | NSEventModifierFlagCommand
               timestamp:1.0
            windowNumber:owner.window.windowNumber
                 context:nil
             eventNumber:1
              clickCount:2
                pressure:1.0];
  [owner.window daPostInputEvent:mouse];

  NSEvent* key = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                  location:NSZeroPoint
                             modifierFlags:NSEventModifierFlagOption
                                 timestamp:2.0
                              windowNumber:owner.window.windowNumber
                                   context:nil
                                characters:@"é"
               charactersIgnoringModifiers:@"e"
                                 isARepeat:YES
                                   keyCode:14];
  [owner.window daPostInputEvent:key];

  EXPECT_EQ(capture.events.size(), static_cast<size_t>(2));
  const dart_appkit::NativeEvent& mouse_event = capture.events[0];
  EXPECT_EQ(mouse_event.type, DA_EVENT_MOUSE_DOWN);
  EXPECT_EQ(mouse_event.button, static_cast<int64_t>(0));
  EXPECT_EQ(mouse_event.click_count, static_cast<int64_t>(2));
  EXPECT_TRUE((mouse_event.modifiers & DA_MODIFIER_SHIFT) != 0);
  EXPECT_TRUE((mouse_event.modifiers & DA_MODIFIER_COMMAND) != 0);

  const dart_appkit::NativeEvent& key_event = capture.events[1];
  EXPECT_EQ(key_event.type, DA_EVENT_KEY_DOWN);
  EXPECT_EQ(key_event.key_code, static_cast<int64_t>(14));
  EXPECT_TRUE(key_event.is_repeat);
  EXPECT_EQ(key_event.characters, std::string("é"));
  EXPECT_EQ(key_event.characters_ignoring_modifiers, std::string("e"));
  EXPECT_TRUE((key_event.modifiers & DA_MODIFIER_OPTION) != 0);

  EXPECT_EQ(da_release(window_handle), DA_STATUS_OK);
}

}  // namespace

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestContractAndErrors();
    TestRegistryLifecycleAndTypes();
    TestThreadGuardAndFinalizer();
    TestWindowEvents();
    TestInputEvents();
    dart_appkit::ResetBridgeForTesting();
  }

  if (g_failures != 0) {
    std::cerr << g_failures << " native bridge test(s) failed" << std::endl;
    return 1;
  }
  std::cout << "all native bridge tests passed" << std::endl;
  return 0;
}
