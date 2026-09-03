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

@interface DaReleaseThreadProbe : NSObject {
 @private
  std::atomic<int32_t>* _deallocation_thread;
}

- (instancetype)initWithDeallocationThread:
    (std::atomic<int32_t>*)deallocationThread;

@end

@implementation DaReleaseThreadProbe

- (instancetype)initWithDeallocationThread:
    (std::atomic<int32_t>*)deallocationThread {
  self = [super init];
  if (self != nil) {
    _deallocation_thread = deallocationThread;
  }
  return self;
}

- (void)dealloc {
  _deallocation_thread->store(pthread_main_np() != 0 ? 1 : 0);
}

@end

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
  std::vector<uint32_t> protocol_versions;
  int64_t last_port = 0;
};

bool CapturePoster(int64_t port, uint32_t protocol_version,
                   const dart_appkit::NativeEvent& event, void* context) {
  auto* capture = static_cast<Capture*>(context);
  capture->last_port = port;
  capture->protocol_versions.push_back(protocol_version);
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

DaHandle CreateView() {
  DaHandle handle = 0;
  EXPECT_EQ(da_view_create(&handle), DA_STATUS_OK);
  EXPECT_TRUE(handle != 0);
  return handle;
}

DaWindowOwner* OwnerFor(DaHandle handle) {
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kWindow,
      dart_appkit::ThreadDomain::kAppKitMain, &status);
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
  EXPECT_EQ(std::string(da_status_name(DA_STATUS_UNSUPPORTED_VERSION)),
            std::string("unsupported_version"));
  EXPECT_EQ(std::string(da_status_name(DA_STATUS_SHUTTING_DOWN)),
            std::string("shutting_down"));

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
  EXPECT_EQ(da_release_async(0), DA_STATUS_INVALID_HANDLE);
}

void TestEventProtocolNegotiation() {
  Capture capture;
  dart_appkit::ResetBridgeForTesting();
  dart_appkit::InstallEventPoster(CapturePoster, &capture);

  uint32_t selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 1, 2, &selected_version),
      DA_STATUS_OK);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(2));

  dart_appkit::NativeEvent event;
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  event.monotonic_nanos = 123456789;
  EXPECT_TRUE(dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(2));

  selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 1, 1, &selected_version),
      DA_STATUS_OK);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(1));
  EXPECT_TRUE(dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(1));

  selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 3, 3, &selected_version),
      DA_STATUS_UNSUPPORTED_VERSION);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(0));
  EXPECT_TRUE(!dart_appkit::PostEvent(event));

  selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 2, 1, &selected_version),
      DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(0));
  EXPECT_EQ(da_application_set_event_port_versioned(4242, 1, 2, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  EXPECT_EQ(da_application_set_event_port(4242), DA_STATUS_OK);
  EXPECT_TRUE(dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(1));
}

void TestRegistryLifecycleAndTypes() {
  Capture capture;
  ResetWithCapture(&capture);

  const DaHandle window = CreateWindow();
  const DaHandle generic_view = CreateView();
  const DaHandle view = CreateTextView();
  EXPECT_TRUE(window <= static_cast<DaHandle>(INT64_MAX));
  EXPECT_TRUE(generic_view <= static_cast<DaHandle>(INT64_MAX));
  EXPECT_TRUE(view <= static_cast<DaHandle>(INT64_MAX));
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(3));

  const std::string unicode_text = "Hello, AppKit — 日本語";
  EXPECT_EQ(
      da_text_view_set_text(view, unicode_text.data(), unicode_text.size()),
      DA_STATUS_OK);
  EXPECT_EQ(da_window_set_content_view(window, generic_view), DA_STATUS_OK);
  EXPECT_EQ(da_text_view_set_text(generic_view, "bad", 3),
            DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_TRUE(LastErrorMessage().find("expected text view") !=
              std::string::npos);
  EXPECT_EQ(da_window_set_content_view(window, view), DA_STATUS_OK);
  EXPECT_EQ(da_window_set_content_view(window, window),
            DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_TRUE(LastErrorMessage().find("expected view") != std::string::npos);
  EXPECT_EQ(da_text_view_set_text(window, "bad", 3),
            DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_TRUE(LastErrorMessage().find("expected text view") !=
              std::string::npos);

  EXPECT_EQ(da_release(generic_view), DA_STATUS_OK);
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

void TestRegistryDomainsAndAsyncRelease() {
  Capture capture;
  ResetWithCapture(&capture);

  const DaHandle domain_handle = CreateTextView();
  std::atomic<int32_t> worker_lookup_status{DA_STATUS_OK};
  std::thread wrong_domain_worker([domain_handle, &worker_lookup_status]() {
    int32_t status = DA_STATUS_OK;
    id object = dart_appkit::ObjectRegistry::Shared().Lookup(
        domain_handle, dart_appkit::ObjectKind::kTextView,
        dart_appkit::ThreadDomain::kAppKitMain, &status);
    EXPECT_TRUE(object == nil);
    worker_lookup_status.store(status);
  });
  wrong_domain_worker.join();
  EXPECT_EQ(worker_lookup_status.load(), DA_STATUS_WRONG_THREAD);

  EXPECT_EQ(dart_appkit::ObjectRegistry::Shared().BeginRelease(
                domain_handle, static_cast<dart_appkit::ThreadDomain>(99)),
            DA_STATUS_WRONG_THREAD);
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      domain_handle, dart_appkit::ObjectKind::kTextView,
      static_cast<dart_appkit::ThreadDomain>(99), &status);
  EXPECT_TRUE(object == nil);
  EXPECT_EQ(status, DA_STATUS_WRONG_THREAD);
  EXPECT_EQ(da_release(domain_handle), DA_STATUS_OK);

  std::atomic<int32_t> deallocation_thread{-1};
  __strong DaReleaseThreadProbe* probe = [[DaReleaseThreadProbe alloc]
      initWithDeallocationThread:&deallocation_thread];
  const DaHandle async_handle = dart_appkit::ObjectRegistry::Shared().Insert(
      probe, dart_appkit::ObjectKind::kTextView,
      dart_appkit::ThreadDomain::kAppKitMain);
  EXPECT_TRUE(async_handle != 0);
  probe = nil;

  std::atomic<int32_t> async_status{DA_STATUS_INTERNAL_ERROR};
  std::thread async_worker([async_handle, &async_status]() {
    async_status.store(da_release_async(async_handle));
  });
  async_worker.join();
  EXPECT_EQ(async_status.load(), DA_STATUS_OK);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(1));
  EXPECT_EQ(da_text_view_set_text(async_handle, "pending", 7),
            DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(da_release(async_handle), DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(da_release_async(async_handle), DA_STATUS_INVALID_HANDLE);

  const NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
  while (LiveCount() != 0 && deadline.timeIntervalSinceNow > 0.0) {
    [[NSRunLoop mainRunLoop]
           runMode:NSDefaultRunLoopMode
        beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
  EXPECT_EQ(deallocation_thread.load(), 1);
}

void TestConcurrentAsyncRelease() {
  Capture capture;
  ResetWithCapture(&capture);
  const DaHandle handle = CreateTextView();

  constexpr size_t kThreadCount = 16;
  std::vector<int32_t> statuses(kThreadCount, DA_STATUS_INTERNAL_ERROR);
  std::vector<std::thread> workers;
  workers.reserve(kThreadCount);
  for (size_t index = 0; index < kThreadCount; ++index) {
    workers.emplace_back([handle, index, &statuses]() {
      statuses[index] = da_release_async(handle);
    });
  }
  for (std::thread& worker : workers) {
    worker.join();
  }

  size_t success_count = 0;
  size_t invalid_count = 0;
  for (const int32_t result : statuses) {
    if (result == DA_STATUS_OK) {
      ++success_count;
    } else if (result == DA_STATUS_INVALID_HANDLE) {
      ++invalid_count;
    }
  }
  EXPECT_EQ(success_count, static_cast<size_t>(1));
  EXPECT_EQ(invalid_count, kThreadCount - 1);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(1));

  const NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
  while (LiveCount() != 0 && deadline.timeIntervalSinceNow > 0.0) {
    [[NSRunLoop mainRunLoop]
           runMode:NSDefaultRunLoopMode
        beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
}

void TestShutdownOwnsPendingRelease() {
  Capture capture;
  ResetWithCapture(&capture);
  const DaHandle window_handle = CreateWindow();
  __strong DaWindowOwner* owner = OwnerFor(window_handle);

  std::atomic<int32_t> async_status{DA_STATUS_INTERNAL_ERROR};
  std::thread async_worker([window_handle, &async_status]() {
    async_status.store(da_release_async(window_handle));
  });
  async_worker.join();
  EXPECT_EQ(async_status.load(), DA_STATUS_OK);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(1));

  dart_appkit::ShutdownBridge();
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
  EXPECT_EQ(owner.daHandle, static_cast<DaHandle>(0));
  EXPECT_EQ(owner.window.daHandle, static_cast<DaHandle>(0));
  EXPECT_TRUE(owner.window.delegate == nil);
  EXPECT_EQ(da_release_async(window_handle), DA_STATUS_SHUTTING_DOWN);

  dart_appkit::ResetBridgeForTesting();
  const DaHandle replacement_handle = CreateTextView();
  EXPECT_EQ(replacement_handle, window_handle);
  [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                        beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(1));
  EXPECT_EQ(da_text_view_set_text(replacement_handle, "still live", 10),
            DA_STATUS_OK);
  EXPECT_EQ(da_release(replacement_handle), DA_STATUS_OK);
}

void TestRegistryChurn() {
  Capture capture;
  ResetWithCapture(&capture);

  const DaHandle stale_handle = CreateTextView();
  EXPECT_EQ(da_release(stale_handle), DA_STATUS_OK);
  for (size_t iteration = 0; iteration < 1000; ++iteration) {
    const DaHandle handle = CreateTextView();
    EXPECT_TRUE(handle != stale_handle);
    EXPECT_EQ(da_text_view_set_text(stale_handle, "stale", 5),
              DA_STATUS_INVALID_HANDLE);
    EXPECT_EQ(da_release(handle), DA_STATUS_OK);
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
  EXPECT_EQ(capture.protocol_versions.size(), static_cast<size_t>(2));
  EXPECT_EQ(capture.protocol_versions[0], static_cast<uint32_t>(1));
  EXPECT_EQ(capture.events[0].type, DA_EVENT_WINDOW_RESIZED);
  EXPECT_EQ(capture.events[0].window, window_handle);
  EXPECT_TRUE(std::abs(capture.events[0].width - 777.0) < 0.001);
  EXPECT_TRUE(std::abs(capture.events[0].height - 333.0) < 0.001);
  EXPECT_EQ(capture.events[1].type, DA_EVENT_WINDOW_CLOSED);
  EXPECT_TRUE(capture.events[1].monotonic_nanos > 0);

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
  EXPECT_EQ(capture.protocol_versions.size(), static_cast<size_t>(2));
  EXPECT_EQ(capture.protocol_versions[0], static_cast<uint32_t>(1));
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
    TestEventProtocolNegotiation();
    TestRegistryLifecycleAndTypes();
    TestThreadGuardAndFinalizer();
    TestRegistryDomainsAndAsyncRelease();
    TestConcurrentAsyncRelease();
    TestShutdownOwnsPendingRelease();
    TestRegistryChurn();
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
