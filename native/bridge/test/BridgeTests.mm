#import <AppKit/AppKit.h>

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <string>
#include <thread>
#include <vector>

#include "AppKitObjects.h"
#include "BridgeInternal.h"
#include "ObjectRegistry.h"
#include "dart_appkit.h"
#include "dart_appkit_custom_view.h"
#include "dart_appkit_native_extension.h"

@interface DaTestCustomView : NSView
@end

@implementation DaTestCustomView
@end

@interface DaAlternateCustomView : NSView
@end

@implementation DaAlternateCustomView
@end

@interface DaKeyEventProbeView : NSView

@property(nonatomic, assign) NSInteger keyDownCount;
@property(nonatomic, assign) NSInteger keyUpCount;

@end

@implementation DaKeyEventProbeView

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)keyDown:(NSEvent*)event {
  (void)event;
  ++_keyDownCount;
}

- (void)keyUp:(NSEvent*)event {
  (void)event;
  ++_keyUpCount;
}

@end

@interface DaKeyEquivalentProbeMenu : NSMenu

@property(nonatomic, assign) NSInteger performCount;

@end

@implementation DaKeyEquivalentProbeMenu

- (BOOL)performKeyEquivalent:(NSEvent*)event {
  (void)event;
  ++_performCount;
  return YES;
}

@end

@interface DaScrollProbeEvent : NSEvent

@property(nonatomic, assign) NSPoint probeLocation;
@property(nonatomic, assign) NSEventModifierFlags probeModifiers;
@property(nonatomic, assign) CGFloat probeDeltaX;
@property(nonatomic, assign) CGFloat probeDeltaY;
@property(nonatomic, assign) BOOL probePrecise;
@property(nonatomic, assign) NSEventPhase probePhase;
@property(nonatomic, assign) NSEventPhase probeMomentumPhase;
@property(nonatomic, assign) BOOL probeDirectionInverted;

@end

@implementation DaScrollProbeEvent

- (NSEventType)type {
  return NSEventTypeScrollWheel;
}

- (NSPoint)locationInWindow {
  return _probeLocation;
}

- (NSEventModifierFlags)modifierFlags {
  return _probeModifiers;
}

- (CGFloat)scrollingDeltaX {
  return _probeDeltaX;
}

- (CGFloat)scrollingDeltaY {
  return _probeDeltaY;
}

- (BOOL)hasPreciseScrollingDeltas {
  return _probePrecise;
}

- (NSEventPhase)phase {
  return _probePhase;
}

- (NSEventPhase)momentumPhase {
  return _probeMomentumPhase;
}

- (BOOL)isDirectionInvertedFromDevice {
  return _probeDirectionInverted;
}

@end

void* CreateRetainedTestCustomView(void* context) {
  Class view_class = (__bridge Class)context;
  NSView* view = [[view_class alloc] initWithFrame:NSZeroRect];
  return (__bridge_retained void*)view;
}

void* FailToCreateCustomView(void* context) {
  (void)context;
  return nullptr;
}

int32_t PerformTestCustomViewOperation(void* context, void* view,
                                       const uint8_t* payload,
                                       size_t payload_length) {
  if (context == nullptr || view == nullptr || payload == nullptr ||
      payload_length != sizeof(uint32_t)) {
    return DA_STATUS_INVALID_ARGUMENT;
  }
  NSView* native_view = (__bridge NSView*)view;
  if (![native_view isKindOfClass:DaTestCustomView.class]) {
    return DA_STATUS_WRONG_HANDLE_TYPE;
  }
  memcpy(context, payload, sizeof(uint32_t));
  return DA_STATUS_OK;
}

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

@interface DaTestPasteboard : NSObject {
 @private
  NSString* _text;
  NSInteger _changeCount;
  BOOL _hasText;
}

@end

@implementation DaTestPasteboard

- (NSInteger)changeCount {
  return _changeCount;
}

- (NSString*)stringForType:(NSPasteboardType)dataType {
  if (!_hasText || ![dataType isEqualToString:NSPasteboardTypeString]) {
    return nil;
  }
  return _text;
}

- (NSInteger)clearContents {
  _text = nil;
  _hasText = NO;
  return ++_changeCount;
}

- (BOOL)setString:(NSString*)string forType:(NSPasteboardType)dataType {
  if (![dataType isEqualToString:NSPasteboardTypeString]) {
    return NO;
  }
  _text = [string copy];
  _hasText = YES;
  return YES;
}

@end

namespace {

int g_failures = 0;
std::vector<std::string> g_opened_external_urls;

bool RecordExternalUrl(NSURL* url) {
  if (url == nil || url.absoluteString.UTF8String == nullptr) {
    return false;
  }
  g_opened_external_urls.emplace_back(url.absoluteString.UTF8String);
  return true;
}

bool RefuseExternalUrl(NSURL* url) {
  if (url != nil && url.absoluteString.UTF8String != nullptr) {
    g_opened_external_urls.emplace_back(url.absoluteString.UTF8String);
  }
  return false;
}

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

DaViewConfiguration DefaultViewConfiguration() {
  return {
      DA_VIEW_CONFIGURATION_VERSION_1_SIZE,
      DA_VIEW_AUTORESIZE_DEFAULT,
      1,
      0,
  };
}

DaTextViewConfiguration DefaultTextViewConfiguration() {
  DaTextViewConfiguration configuration{};
  configuration.struct_size = DA_TEXT_VIEW_CONFIGURATION_VERSION_1_SIZE;
  configuration.view = DefaultViewConfiguration();
  configuration.font_kind = DA_TEXT_VIEW_FONT_MONOSPACED_SYSTEM;
  configuration.font_weight = DA_TEXT_VIEW_FONT_WEIGHT_REGULAR;
  configuration.font_size = 18.0;
  configuration.padding_top = 20.0;
  configuration.padding_right = 20.0;
  configuration.padding_bottom = 20.0;
  configuration.padding_left = 20.0;
  configuration.foreground_color = {
      DA_TEXT_VIEW_COLOR_LABEL, 0, 0.0, 0.0, 0.0, 1.0};
  configuration.background_color = {
      DA_TEXT_VIEW_COLOR_WINDOW_BACKGROUND, 0, 0.0, 0.0, 0.0, 1.0};
  return configuration;
}

DaTextEditorConfiguration DefaultTextEditorConfiguration() {
  DaTextEditorConfiguration configuration{};
  configuration.struct_size = DA_TEXT_EDITOR_CONFIGURATION_VERSION_1_SIZE;
  configuration.presentation = DefaultTextViewConfiguration();
  configuration.presentation.font_size = 14.0;
  configuration.presentation.padding_top = 12.0;
  configuration.presentation.padding_right = 12.0;
  configuration.presentation.padding_bottom = 12.0;
  configuration.presentation.padding_left = 12.0;
  configuration.initially_editable = 0;
  configuration.reserved = 0;
  return configuration;
}

DaView* NativeViewFor(DaHandle handle) {
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kView,
      dart_appkit::ThreadDomain::kAppKitMain, &status);
  EXPECT_EQ(status, DA_STATUS_OK);
  EXPECT_TRUE([object isKindOfClass:DaView.class]);
  return static_cast<DaView*>(object);
}

DaTextView* NativeTextViewFor(DaHandle handle) {
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kTextView,
      dart_appkit::ThreadDomain::kAppKitMain, &status);
  EXPECT_EQ(status, DA_STATUS_OK);
  EXPECT_TRUE([object isKindOfClass:DaTextView.class]);
  return static_cast<DaTextView*>(object);
}

DaTextEditor* NativeTextEditorFor(DaHandle handle) {
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kView,
      dart_appkit::ThreadDomain::kAppKitMain, &status);
  EXPECT_EQ(status, DA_STATUS_OK);
  EXPECT_TRUE([object isKindOfClass:DaTextEditor.class]);
  return static_cast<DaTextEditor*>(object);
}

DaHandle CreateSplitView(DaSplitAxis axis) {
  DaHandle handle = 0;
  EXPECT_EQ(da_split_view_create(axis, &handle), DA_STATUS_OK);
  EXPECT_TRUE(handle != 0);
  return handle;
}

DaSplitView* SplitViewFor(DaHandle handle) {
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kView,
      dart_appkit::ThreadDomain::kAppKitMain, &status);
  EXPECT_EQ(status, DA_STATUS_OK);
  EXPECT_TRUE([object isKindOfClass:DaSplitView.class]);
  return static_cast<DaSplitView*>(object);
}

DaHandle CreateMenu(const std::string& title) {
  DaHandle handle = 0;
  EXPECT_EQ(da_menu_create(title.data(), title.size(), &handle), DA_STATUS_OK);
  EXPECT_TRUE(handle != 0);
  return handle;
}

DaHandle CreateMenuItem(const std::string& title, const std::string& key,
                        uint64_t modifiers) {
  DaHandle handle = 0;
  EXPECT_EQ(da_menu_item_create(title.data(), title.size(), key.data(),
                                key.size(), modifiers, &handle),
            DA_STATUS_OK);
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

NSMenu* MenuFor(DaHandle handle) {
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kMenu,
      dart_appkit::ThreadDomain::kAppKitMain, &status);
  EXPECT_EQ(status, DA_STATUS_OK);
  return static_cast<NSMenu*>(object);
}

DaMenuItemOwner* MenuItemOwnerFor(DaHandle handle) {
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kMenuItem,
      dart_appkit::ThreadDomain::kAppKitMain, &status);
  EXPECT_EQ(status, DA_STATUS_OK);
  return static_cast<DaMenuItemOwner*>(object);
}

void ResetWithCapture(Capture* capture) {
  dart_appkit::ResetBridgeForTesting();
  dart_appkit::InstallEventPoster(CapturePoster, capture);
  EXPECT_EQ(da_application_set_event_port(4242), DA_STATUS_OK);
}

void ResetWithCurrentCapture(Capture* capture) {
  dart_appkit::ResetBridgeForTesting();
  dart_appkit::InstallEventPoster(CapturePoster, capture);
  uint32_t selected_version = 0;
  EXPECT_EQ(da_application_set_event_port_versioned(
                4242, DA_EVENT_PROTOCOL_VERSION_MIN,
                DA_EVENT_PROTOCOL_VERSION_CURRENT, &selected_version),
            DA_STATUS_OK);
  EXPECT_EQ(selected_version, DA_EVENT_PROTOCOL_VERSION_CURRENT);
  capture->events.clear();
  capture->protocol_versions.clear();
  capture->last_port = 0;
}

size_t CountEvents(const Capture& capture, DaEventType type) {
  size_t count = 0;
  for (const dart_appkit::NativeEvent& event : capture.events) {
    if (event.type == type) {
      ++count;
    }
  }
  return count;
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
  EXPECT_EQ(std::string(da_status_name(DA_STATUS_LIMIT_EXCEEDED)),
            std::string("limit_exceeded"));

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

void TestWindowConfiguration() {
  dart_appkit::ResetBridgeForTesting();
  const std::string title = "Configured window";

  DaWindowConfiguration configuration = {
      DA_WINDOW_CONFIGURATION_VERSION_1_SIZE,
      DA_WINDOW_STYLE_TITLED | DA_WINDOW_STYLE_RESIZABLE,
  };
  DaHandle handle = 0;
  EXPECT_EQ(da_window_create_configured(
                {10.0, 20.0, 320.0, 240.0}, title.data(), title.size(),
                &configuration, &handle),
            DA_STATUS_OK);
  const NSWindowStyleMask configured_style = OwnerFor(handle).window.styleMask;
  EXPECT_TRUE((configured_style & NSWindowStyleMaskTitled) != 0);
  EXPECT_TRUE((configured_style & NSWindowStyleMaskResizable) != 0);
  EXPECT_TRUE((configured_style & NSWindowStyleMaskClosable) == 0);
  EXPECT_TRUE((configured_style & NSWindowStyleMaskMiniaturizable) == 0);
  EXPECT_EQ(da_release(handle), DA_STATUS_OK);

  configuration.style_mask = 0;
  EXPECT_EQ(da_window_create_configured(
                {10.0, 20.0, 320.0, 240.0}, title.data(), title.size(),
                &configuration, &handle),
            DA_STATUS_OK);
  EXPECT_EQ(OwnerFor(handle).window.styleMask,
            static_cast<NSWindowStyleMask>(NSWindowStyleMaskBorderless));
  EXPECT_EQ(da_release(handle), DA_STATUS_OK);

  handle = 99;
  configuration.struct_size = 0;
  EXPECT_EQ(da_window_create_configured(
                {10.0, 20.0, 320.0, 240.0}, title.data(), title.size(),
                &configuration, &handle),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(handle, static_cast<DaHandle>(0));
  configuration.struct_size = DA_WINDOW_CONFIGURATION_VERSION_1_SIZE;
  configuration.style_mask = uint64_t{1} << 63;
  EXPECT_EQ(da_window_create_configured(
                {10.0, 20.0, 320.0, 240.0}, title.data(), title.size(),
                &configuration, &handle),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_create_configured(
                {10.0, 20.0, 320.0, 240.0}, title.data(), title.size(), nullptr,
                &handle),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
}

void TestEventProtocolNegotiation() {
  Capture capture;
  dart_appkit::ResetBridgeForTesting();
  dart_appkit::InstallEventPoster(CapturePoster, &capture);

  uint32_t selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 1, 4, &selected_version),
      DA_STATUS_OK);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(4));
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(1));
  EXPECT_EQ(capture.events[0].type, DA_EVENT_APPLICATION_ACTIVE_CHANGED);
  EXPECT_EQ(capture.events[0].window, static_cast<DaHandle>(0));
  EXPECT_EQ(capture.events[0].operation_id, static_cast<int64_t>(0));

  dart_appkit::NativeEvent event;
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  event.monotonic_nanos = 123456789;
  EXPECT_TRUE(dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(4));

  event.type = DA_EVENT_WINDOW_FOCUS_CHANGED;
  event.state = true;
  EXPECT_TRUE(dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(4));

  event.type = DA_EVENT_APPLICATION_ACTIVE_CHANGED;
  event.window = 0;
  event.state = true;
  EXPECT_TRUE(dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(4));

  event.type = DA_EVENT_SCROLL_WHEEL;
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  const size_t before_version_five_event = capture.events.size();
  EXPECT_TRUE(!dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.events.size(), before_version_five_event);

  selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 5, 5, &selected_version),
      DA_STATUS_OK);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(5));
  EXPECT_TRUE(dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(5));

  event.type = DA_EVENT_WINDOW_FRAME_CHANGED;
  event.x = 10.0;
  event.y = -20.0;
  event.width = 640.0;
  event.height = 480.0;
  const size_t before_version_six_frame = capture.events.size();
  EXPECT_TRUE(!dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.events.size(), before_version_six_frame);

  event.type = DA_EVENT_WINDOW_FULLSCREEN_CHANGED;
  event.state = true;
  const size_t before_version_six_fullscreen = capture.events.size();
  EXPECT_TRUE(!dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.events.size(), before_version_six_fullscreen);

  selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 1, 3, &selected_version),
      DA_STATUS_OK);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(3));
  const size_t before_version_four_event = capture.events.size();
  EXPECT_TRUE(!dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.events.size(), before_version_four_event);
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  event.type = DA_EVENT_WINDOW_FOCUS_CHANGED;

  selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 1, 2, &selected_version),
      DA_STATUS_OK);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(2));
  const size_t before_filtered_event = capture.events.size();
  EXPECT_TRUE(!dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.events.size(), before_filtered_event);
  event.type = DA_EVENT_WINDOW_CLOSED;
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
      da_application_set_event_port_versioned(4242, 7, 7, &selected_version),
      DA_STATUS_OK);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(7));
  EXPECT_TRUE(capture.events.size() >= static_cast<size_t>(2));
  EXPECT_EQ(capture.events[capture.events.size() - 2].type,
            DA_EVENT_APPLICATION_ACTIVE_CHANGED);
  EXPECT_EQ(capture.events.back().type,
            DA_EVENT_APPLICATION_APPEARANCE_CHANGED);
  EXPECT_EQ(capture.events.back().state,
            dart_appkit::ApplicationUsesDarkAppearance());

  event.type = DA_EVENT_APPLICATION_APPEARANCE_CHANGED;
  event.window = 0;
  event.state = true;
  EXPECT_TRUE(dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(7));

  selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 1, 6, &selected_version),
      DA_STATUS_OK);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(6));
  const size_t before_version_seven_event = capture.events.size();
  EXPECT_TRUE(!dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.events.size(), before_version_seven_event);

  selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 8, 8, &selected_version),
      DA_STATUS_UNSUPPORTED_VERSION);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(0));
  EXPECT_TRUE(!dart_appkit::PostEvent(event));

  selected_version = 99;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 2, 1, &selected_version),
      DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(selected_version, static_cast<uint32_t>(0));
  EXPECT_EQ(da_application_set_event_port_versioned(4242, 1, 5, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  EXPECT_EQ(da_application_set_event_port(4242), DA_STATUS_OK);
  event.type = DA_EVENT_WINDOW_CLOSED;
  event.window = (static_cast<DaHandle>(7) << 32) | 3;
  EXPECT_TRUE(dart_appkit::PostEvent(event));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(1));
}

void TestLifecycleRequests() {
  Capture capture;
  ResetWithCurrentCapture(&capture);

  dart_appkit::PostApplicationActiveChanged(true);
  dart_appkit::PostApplicationReopenRequested(false);
  dart_appkit::PostApplicationAppearanceChanged(true);
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(3));
  EXPECT_EQ(capture.events[0].type, DA_EVENT_APPLICATION_ACTIVE_CHANGED);
  EXPECT_EQ(capture.events[0].window, static_cast<DaHandle>(0));
  EXPECT_TRUE(capture.events[0].state);
  EXPECT_EQ(capture.events[0].operation_id, static_cast<int64_t>(0));
  EXPECT_EQ(capture.events[1].type, DA_EVENT_APPLICATION_REOPEN_REQUESTED);
  EXPECT_TRUE(!capture.events[1].state);
  EXPECT_EQ(capture.events[2].type,
            DA_EVENT_APPLICATION_APPEARANCE_CHANGED);
  EXPECT_TRUE(capture.events[2].state);

  EXPECT_EQ(da_application_set_termination_request_deferral(2),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_application_set_termination_request_deferral(1), DA_STATUS_OK);
  EXPECT_EQ(da_debug_request_application_termination(), DA_STATUS_OK);
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(4));
  const int64_t termination_operation = capture.events.back().operation_id;
  EXPECT_EQ(capture.events.back().type,
            DA_EVENT_APPLICATION_TERMINATE_REQUESTED);
  EXPECT_TRUE(termination_operation > 0);
  EXPECT_TRUE(dart_appkit::HandleApplicationShouldTerminate() ==
              dart_appkit::ApplicationTerminationDecision::kTerminateLater);
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(4));
  EXPECT_EQ(da_application_set_termination_request_deferral(0),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(
      da_application_reply_to_termination_request(termination_operation + 1, 0),
      DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(
      da_application_reply_to_termination_request(termination_operation, 2),
      DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(
      da_application_reply_to_termination_request(termination_operation, 0),
      DA_STATUS_OK);
  EXPECT_EQ(
      da_application_reply_to_termination_request(termination_operation, 0),
      DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_application_set_termination_request_deferral(0), DA_STATUS_OK);
  EXPECT_TRUE(dart_appkit::HandleApplicationShouldTerminate() ==
              dart_appkit::ApplicationTerminationDecision::kTerminateNow);

  const DaHandle window_handle = CreateWindow();
  DaWindowOwner* owner = OwnerFor(window_handle);
  EXPECT_TRUE([owner windowShouldClose:owner.window]);
  EXPECT_EQ(da_window_set_close_request_deferral(window_handle, 2),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_set_close_request_deferral(window_handle, 1),
            DA_STATUS_OK);
  EXPECT_EQ(da_window_request_close(window_handle), DA_STATUS_OK);
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(5));
  const int64_t close_operation = capture.events.back().operation_id;
  EXPECT_EQ(capture.events.back().type, DA_EVENT_WINDOW_CLOSE_REQUESTED);
  EXPECT_EQ(capture.events.back().window, window_handle);
  EXPECT_TRUE(close_operation > 0);
  EXPECT_EQ(da_window_request_close(window_handle), DA_STATUS_OK);
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(5));
  EXPECT_EQ(da_window_set_close_request_deferral(window_handle, 0),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(
      da_window_reply_to_close_request(window_handle, close_operation + 1, 0),
      DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_reply_to_close_request(window_handle, close_operation, 2),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_reply_to_close_request(window_handle, close_operation, 0),
            DA_STATUS_OK);
  EXPECT_EQ(da_window_reply_to_close_request(window_handle, close_operation, 0),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_set_close_request_deferral(window_handle, 0),
            DA_STATUS_OK);
  EXPECT_EQ(da_release(window_handle), DA_STATUS_OK);

  Capture legacy_capture;
  ResetWithCapture(&legacy_capture);
  EXPECT_EQ(da_application_set_termination_request_deferral(1), DA_STATUS_OK);
  EXPECT_TRUE(dart_appkit::HandleApplicationShouldTerminate() ==
              dart_appkit::ApplicationTerminationDecision::kTerminateNow);
  const DaHandle legacy_window = CreateWindow();
  DaWindowOwner* legacy_owner = OwnerFor(legacy_window);
  EXPECT_EQ(da_window_set_close_request_deferral(legacy_window, 1),
            DA_STATUS_OK);
  EXPECT_TRUE([legacy_owner windowShouldClose:legacy_owner.window]);
  EXPECT_TRUE(legacy_capture.events.empty());
  EXPECT_EQ(da_release(legacy_window), DA_STATUS_OK);
}

void TestApplicationAppearanceObservation() {
  Capture capture;
  ResetWithCurrentCapture(&capture);
  NSAppearance* original_appearance = NSApp.appearance;

  NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  capture.events.clear();
  capture.protocol_versions.clear();

  NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  EXPECT_EQ(CountEvents(capture, DA_EVENT_APPLICATION_APPEARANCE_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(capture.events.back().type,
            DA_EVENT_APPLICATION_APPEARANCE_CHANGED);
  EXPECT_TRUE(capture.events.back().state);
  EXPECT_EQ(capture.events.back().window, static_cast<DaHandle>(0));
  EXPECT_EQ(capture.events.back().operation_id, static_cast<int64_t>(0));
  EXPECT_EQ(capture.protocol_versions.back(), static_cast<uint32_t>(7));

  NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  EXPECT_EQ(CountEvents(capture, DA_EVENT_APPLICATION_APPEARANCE_CHANGED),
            static_cast<size_t>(1));

  dart_appkit::ShutdownBridge();
  const size_t after_shutdown = capture.events.size();
  NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  EXPECT_EQ(capture.events.size(), after_shutdown);
  NSApp.appearance = original_appearance;
  dart_appkit::ResetBridgeForTesting();
}

void TestPasteboardText() {
  dart_appkit::ResetBridgeForTesting();
  NSPasteboard* pasteboard = (NSPasteboard*)[[DaTestPasteboard alloc] init];
  EXPECT_TRUE(pasteboard != nil);

  int64_t cleared_count = -1;
  EXPECT_EQ(dart_appkit::ClearPasteboard(pasteboard, &cleared_count),
            DA_STATUS_OK);
  EXPECT_TRUE(cleared_count >= 0);

  DaPasteboardText snapshot{};
  EXPECT_EQ(dart_appkit::ReadPasteboardText(pasteboard, &snapshot),
            DA_STATUS_OK);
  EXPECT_EQ(snapshot.has_text, 0);
  EXPECT_TRUE(snapshot.text == nullptr);
  EXPECT_EQ(snapshot.text_length, static_cast<size_t>(0));
  EXPECT_EQ(snapshot.change_count, cleared_count);

  const std::string unicode_with_nul("A\0é", 4);
  int64_t written_count = -1;
  EXPECT_EQ(
      dart_appkit::WritePasteboardText(pasteboard, unicode_with_nul.data(),
                                       unicode_with_nul.size(), &written_count),
      DA_STATUS_OK);
  EXPECT_TRUE(written_count > cleared_count);
  EXPECT_EQ(dart_appkit::ReadPasteboardText(pasteboard, &snapshot),
            DA_STATUS_OK);
  EXPECT_EQ(snapshot.has_text, 1);
  EXPECT_EQ(snapshot.text_length, unicode_with_nul.size());
  EXPECT_EQ(std::string(snapshot.text, snapshot.text_length), unicode_with_nul);
  EXPECT_EQ(snapshot.change_count, written_count);
  EXPECT_EQ(
      dart_appkit::ReadPasteboardTextWithLimit(pasteboard, 3, &snapshot),
      DA_STATUS_LIMIT_EXCEEDED);
  EXPECT_EQ(snapshot.has_text, 0);
  EXPECT_TRUE(snapshot.text == nullptr);
  EXPECT_EQ(snapshot.text_length, static_cast<size_t>(0));
  EXPECT_EQ(dart_appkit::ReadPasteboardTextWithLimit(
                pasteboard, unicode_with_nul.size(), &snapshot),
            DA_STATUS_OK);
  EXPECT_EQ(std::string(snapshot.text, snapshot.text_length), unicode_with_nul);

  int64_t empty_count = -1;
  EXPECT_EQ(
      dart_appkit::WritePasteboardText(pasteboard, nullptr, 0, &empty_count),
      DA_STATUS_OK);
  EXPECT_TRUE(empty_count > written_count);
  EXPECT_EQ(dart_appkit::ReadPasteboardText(pasteboard, &snapshot),
            DA_STATUS_OK);
  EXPECT_EQ(snapshot.has_text, 1);
  EXPECT_TRUE(snapshot.text == nullptr);
  EXPECT_EQ(snapshot.text_length, static_cast<size_t>(0));

  int64_t observed_count = -1;
  EXPECT_EQ(dart_appkit::GetPasteboardChangeCount(pasteboard, &observed_count),
            DA_STATUS_OK);
  EXPECT_EQ(observed_count, empty_count);
  EXPECT_EQ(dart_appkit::ClearPasteboard(pasteboard, &cleared_count),
            DA_STATUS_OK);
  EXPECT_TRUE(cleared_count > empty_count);
  EXPECT_EQ(dart_appkit::ReadPasteboardText(pasteboard, &snapshot),
            DA_STATUS_OK);
  EXPECT_EQ(snapshot.has_text, 0);
  EXPECT_EQ(snapshot.change_count, cleared_count);

  const char invalid_utf8[] = {static_cast<char>(0xc3), '('};
  observed_count = 99;
  EXPECT_EQ(
      dart_appkit::WritePasteboardText(pasteboard, invalid_utf8,
                                       sizeof(invalid_utf8), &observed_count),
      DA_STATUS_INVALID_UTF8);
  EXPECT_EQ(observed_count, static_cast<int64_t>(0));
  EXPECT_EQ(dart_appkit::ReadPasteboardText(pasteboard, nullptr),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(dart_appkit::WritePasteboardText(pasteboard, nullptr, 0, nullptr),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(dart_appkit::ClearPasteboard(pasteboard, nullptr),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(dart_appkit::GetPasteboardChangeCount(pasteboard, nullptr),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(dart_appkit::ReadPasteboardText(nil, &snapshot),
            DA_STATUS_INTERNAL_ERROR);
}

void TestExternalUrlOpening() {
  dart_appkit::ResetBridgeForTesting();
  g_opened_external_urls.clear();

  int32_t opened = -1;
  EXPECT_EQ(dart_appkit::OpenAllowedExternalUrl(
                @"https://example.com/path?query=value#fragment",
                RecordExternalUrl, &opened),
            DA_STATUS_OK);
  EXPECT_EQ(opened, 1);
  EXPECT_EQ(g_opened_external_urls.size(), static_cast<size_t>(1));
  EXPECT_EQ(g_opened_external_urls.back(),
            std::string("https://example.com/path?query=value#fragment"));

  opened = -1;
  EXPECT_EQ(dart_appkit::OpenAllowedExternalUrl(
                @"mailto:user@example.com?subject=Hello%20there",
                RefuseExternalUrl, &opened),
            DA_STATUS_OK);
  EXPECT_EQ(opened, 0);
  EXPECT_EQ(g_opened_external_urls.size(), static_cast<size_t>(2));

  const uint64_t host_policy =
      DA_EXTERNAL_URL_POLICY_REQUIRE_AUTHORITY |
      DA_EXTERNAL_URL_POLICY_REQUIRE_HOST;
  opened = -1;
  EXPECT_EQ(dart_appkit::OpenExternalUrlWithPolicy(
                @"ssh://user@example.com/path", @"ssh", host_policy,
                RecordExternalUrl, &opened),
            DA_STATUS_OK);
  EXPECT_EQ(opened, 1);

  const uint64_t non_authority_policy =
      DA_EXTERNAL_URL_POLICY_FORBID_AUTHORITY |
      DA_EXTERNAL_URL_POLICY_REQUIRE_PATH;
  opened = -1;
  EXPECT_EQ(dart_appkit::OpenExternalUrlWithPolicy(
                @"custom:value", @"custom", non_authority_policy,
                RecordExternalUrl, &opened),
            DA_STATUS_OK);
  EXPECT_EQ(opened, 1);

  opened = -1;
  EXPECT_EQ(dart_appkit::OpenExternalUrlWithPolicy(
                @"file:///tmp/report", @"file",
                DA_EXTERNAL_URL_POLICY_REQUIRE_AUTHORITY |
                    DA_EXTERNAL_URL_POLICY_REQUIRE_PATH,
                RecordExternalUrl, &opened),
            DA_STATUS_OK);
  EXPECT_EQ(opened, 1);

  struct InvalidPolicyCase {
    NSString* value;
    NSString* scheme;
    uint64_t flags;
  };
  const InvalidPolicyCase invalid_policy_cases[] = {
      {@"ssh:/path", @"ssh", DA_EXTERNAL_URL_POLICY_REQUIRE_AUTHORITY},
      {@"custom://value", @"custom",
       DA_EXTERNAL_URL_POLICY_FORBID_AUTHORITY},
      {@"ssh:///path", @"ssh", DA_EXTERNAL_URL_POLICY_REQUIRE_HOST},
      {@"ssh://user@example.com/path", @"ssh",
       DA_EXTERNAL_URL_POLICY_FORBID_CREDENTIALS},
      {@"custom:", @"custom", DA_EXTERNAL_URL_POLICY_REQUIRE_PATH},
      {@"custom:value", @"different", 0},
      {@"custom:value", @"custom", uint64_t{1} << 63},
      {@"custom:value", @"custom",
       DA_EXTERNAL_URL_POLICY_REQUIRE_AUTHORITY |
           DA_EXTERNAL_URL_POLICY_FORBID_AUTHORITY},
      {@"custom:unsafe\nvalue", @"custom", 0},
  };
  for (const InvalidPolicyCase& policy_case : invalid_policy_cases) {
    const size_t before = g_opened_external_urls.size();
    opened = -1;
    EXPECT_EQ(dart_appkit::OpenExternalUrlWithPolicy(
                  policy_case.value, policy_case.scheme, policy_case.flags,
                  RecordExternalUrl, &opened),
              DA_STATUS_INVALID_ARGUMENT);
    EXPECT_EQ(opened, 0);
    EXPECT_EQ(g_opened_external_urls.size(), before);
  }
  EXPECT_EQ(dart_appkit::OpenExternalUrlWithPolicy(
                @"custom:value", @"Custom", non_authority_policy,
                RecordExternalUrl, &opened),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(dart_appkit::OpenExternalUrlWithPolicy(
                @"custom:value", @"custom", non_authority_policy, nullptr,
                &opened),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(dart_appkit::OpenExternalUrlWithPolicy(
                @"custom:value", @"custom", non_authority_policy,
                RecordExternalUrl, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  NSArray<NSString*>* invalid = @[
    @"", @"example.com/path", @"file:///tmp/report",
    @"javascript:alert(1)", @"https://user:password@example.com",
    @"https:///missing-host", @"http:example.com", @"mailto:",
    @"mailto://user@example.com", @"https://example.com/line\nbreak",
    @"https://example.com/back\\slash",
    @"https://example.com/hidden\u202evalue",
    @"https://example.com/%0dheader", @"https://example.com/%5cpath",
    @"https://example.com/%E2%80%AEvalue",
    @"https://example.com/%zz"
  ];
  for (NSString* value in invalid) {
    const size_t before = g_opened_external_urls.size();
    opened = -1;
    EXPECT_EQ(dart_appkit::OpenAllowedExternalUrl(
                  value, RecordExternalUrl, &opened),
              DA_STATUS_INVALID_ARGUMENT);
    EXPECT_EQ(opened, 0);
    EXPECT_EQ(g_opened_external_urls.size(), before);
  }

  NSString* oversized = [@"https://example.com/"
      stringByPaddingToLength:DA_EXTERNAL_URL_MAX_UTF8_BYTES + 1
                  withString:@"a"
             startingAtIndex:0];
  opened = -1;
  EXPECT_EQ(dart_appkit::OpenAllowedExternalUrl(
                oversized, RecordExternalUrl, &opened),
            DA_STATUS_LIMIT_EXCEEDED);
  EXPECT_EQ(opened, 0);
  EXPECT_EQ(dart_appkit::OpenAllowedExternalUrl(
                @"https://example.com", nullptr, &opened),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(dart_appkit::OpenAllowedExternalUrl(
                @"https://example.com", RecordExternalUrl, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  const char invalid_utf8[] = {static_cast<char>(0xc3), '('};
  opened = -1;
  EXPECT_EQ(da_application_open_external_url(
                invalid_utf8, sizeof(invalid_utf8), &opened),
            DA_STATUS_INVALID_UTF8);
  EXPECT_EQ(opened, 0);
  EXPECT_EQ(da_application_open_external_url(nullptr, 0, nullptr),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_application_open_external_url_with_policy(
                "custom:value", strlen("custom:value"), invalid_utf8,
                sizeof(invalid_utf8), non_authority_policy, &opened),
            DA_STATUS_INVALID_UTF8);
  EXPECT_EQ(opened, 0);
  EXPECT_EQ(da_application_open_external_url_with_policy(
                nullptr, 0, nullptr, 0, 0, nullptr),
            DA_STATUS_INVALID_ARGUMENT);
}

void TestMenus() {
  Capture capture;
  ResetWithCurrentCapture(&capture);

  DaHandle output = 99;
  EXPECT_EQ(da_menu_create(nullptr, 0, nullptr), DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_menu_item_create(nullptr, 0, nullptr, 0, 0, nullptr),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_menu_item_create_separator(nullptr), DA_STATUS_INVALID_ARGUMENT);
  const char invalid_utf8[] = {static_cast<char>(0xc3), '('};
  EXPECT_EQ(da_menu_create(invalid_utf8, sizeof(invalid_utf8), &output),
            DA_STATUS_INVALID_UTF8);
  EXPECT_EQ(output, static_cast<DaHandle>(0));
  DaMenuConfiguration auto_menu_configuration = {
      DA_MENU_CONFIGURATION_VERSION_1_SIZE,
      1,
      0,
  };
  DaHandle auto_menu = 0;
  EXPECT_EQ(da_menu_create_configured("Auto", 4, &auto_menu_configuration,
                                      &auto_menu),
            DA_STATUS_OK);
  EXPECT_TRUE(MenuFor(auto_menu).autoenablesItems);
  DaMenuConfiguration invalid_menu_configuration = auto_menu_configuration;
  invalid_menu_configuration.struct_size = 0;
  EXPECT_EQ(da_menu_create_configured("Bad", 3, &invalid_menu_configuration,
                                      &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_menu_configuration = auto_menu_configuration;
  invalid_menu_configuration.auto_enables_items = 2;
  EXPECT_EQ(da_menu_create_configured("Bad", 3, &invalid_menu_configuration,
                                      &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_menu_configuration = auto_menu_configuration;
  invalid_menu_configuration.reserved = 1;
  EXPECT_EQ(da_menu_create_configured("Bad", 3, &invalid_menu_configuration,
                                      &output),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_menu_create_configured("Bad", 3, nullptr, &output),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_menu_create_configured("Bad", 3, &auto_menu_configuration,
                                      nullptr),
            DA_STATUS_INVALID_ARGUMENT);
  output = 99;
  EXPECT_EQ(da_menu_item_create("Invalid", 7, "i", 1, 1ULL << 20, &output),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(output, static_cast<DaHandle>(0));

  const DaHandle main_menu = CreateMenu("Main");
  const DaHandle app_menu = CreateMenu("Application");
  const DaHandle app_item = CreateMenuItem("Application", "", 0);
  const DaHandle quit_item = CreateMenuItem(
      "Quit — 日本語", "q", DA_MODIFIER_COMMAND | DA_MODIFIER_SHIFT);
  DaHandle separator = 0;
  EXPECT_EQ(da_menu_item_create_separator(&separator), DA_STATUS_OK);
  EXPECT_TRUE(separator != 0);

  NSMenu* native_main_menu = MenuFor(main_menu);
  NSMenu* native_app_menu = MenuFor(app_menu);
  DaMenuItemOwner* native_app_item = MenuItemOwnerFor(app_item);
  DaMenuItemOwner* native_quit_item = MenuItemOwnerFor(quit_item);
  DaMenuItemOwner* native_separator = MenuItemOwnerFor(separator);
  EXPECT_EQ(std::string(native_main_menu.title.UTF8String),
            std::string("Main"));
  EXPECT_TRUE(!native_main_menu.autoenablesItems);
  EXPECT_EQ(std::string(native_quit_item.item.title.UTF8String),
            std::string("Quit — 日本語"));
  EXPECT_EQ(std::string(native_quit_item.item.keyEquivalent.UTF8String),
            std::string("q"));
  EXPECT_TRUE((native_quit_item.item.keyEquivalentModifierMask &
               NSEventModifierFlagCommand) != 0);
  EXPECT_TRUE((native_quit_item.item.keyEquivalentModifierMask &
               NSEventModifierFlagShift) != 0);
  EXPECT_TRUE(native_separator.isSeparator);

  EXPECT_EQ(da_menu_add_item(main_menu, app_item), DA_STATUS_OK);
  EXPECT_EQ(da_menu_item_set_submenu(app_item, app_menu), DA_STATUS_OK);
  EXPECT_EQ(da_menu_add_item(app_menu, separator), DA_STATUS_OK);
  EXPECT_EQ(da_menu_add_item(app_menu, quit_item), DA_STATUS_OK);
  EXPECT_EQ(native_main_menu.numberOfItems, static_cast<NSInteger>(1));
  EXPECT_TRUE(native_app_item.item.submenu == native_app_menu);
  EXPECT_EQ(native_app_menu.numberOfItems, static_cast<NSInteger>(2));

  EXPECT_EQ(da_application_set_main_menu(main_menu), DA_STATUS_OK);
  EXPECT_TRUE(NSApp.mainMenu == native_main_menu);
  EXPECT_EQ(da_menu_item_set_enabled(quit_item, 0), DA_STATUS_OK);
  EXPECT_TRUE(!native_quit_item.item.isEnabled);
  EXPECT_EQ(da_menu_item_perform_action(quit_item), DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_menu_item_set_enabled(quit_item, 1), DA_STATUS_OK);
  EXPECT_EQ(da_menu_item_perform_action(quit_item), DA_STATUS_OK);
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(1));
  EXPECT_EQ(capture.events.back().type, DA_EVENT_MENU_ITEM_INVOKED);
  EXPECT_EQ(capture.events.back().window, quit_item);
  EXPECT_EQ(capture.events.back().operation_id, static_cast<int64_t>(0));

  EXPECT_EQ(da_menu_add_item(quit_item, app_item), DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_EQ(da_menu_item_set_submenu(quit_item, app_item),
            DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_EQ(da_menu_item_set_submenu(separator, app_menu),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_menu_item_set_enabled(separator, 1), DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_menu_item_perform_action(separator), DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_menu_item_set_enabled(quit_item, 2), DA_STATUS_INVALID_ARGUMENT);

  dart_appkit::InstallEventPoster(CapturePoster, &capture);
  uint32_t selected_version = 0;
  EXPECT_EQ(
      da_application_set_event_port_versioned(4242, 3, 3, &selected_version),
      DA_STATUS_OK);
  EXPECT_EQ(da_menu_item_perform_action(quit_item), DA_STATUS_OK);
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(1));

  EXPECT_EQ(da_release(quit_item), DA_STATUS_OK);
  EXPECT_TRUE(native_quit_item.item.target == nil);
  EXPECT_TRUE(native_quit_item.item.action == nil);
  EXPECT_TRUE(!native_quit_item.item.isEnabled);
  EXPECT_EQ(da_menu_item_perform_action(quit_item), DA_STATUS_INVALID_HANDLE);
  [native_quit_item daPerformAction:native_quit_item.item];
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(1));

  EXPECT_EQ(da_release(main_menu), DA_STATUS_OK);
  EXPECT_TRUE(NSApp.mainMenu != native_main_menu);
  EXPECT_EQ(da_application_set_main_menu(main_menu), DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(da_release(separator), DA_STATUS_OK);
  EXPECT_EQ(da_release(app_item), DA_STATUS_OK);
  EXPECT_EQ(da_release(app_menu), DA_STATUS_OK);
  EXPECT_EQ(da_release(auto_menu), DA_STATUS_OK);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
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

void TestConfiguredBaseAndTextViews() {
  Capture capture;
  ResetWithCapture(&capture);

  DaViewConfiguration view_configuration = DefaultViewConfiguration();
  view_configuration.autoresizing_mask = DA_VIEW_AUTORESIZE_WIDTH;
  view_configuration.accepts_first_responder = 0;
  DaHandle configured_view_handle = 0;
  EXPECT_EQ(da_view_create_configured(&view_configuration,
                                      &configured_view_handle),
            DA_STATUS_OK);
  DaView* configured_view = NativeViewFor(configured_view_handle);
  EXPECT_EQ(configured_view.autoresizingMask,
            static_cast<NSAutoresizingMaskOptions>(NSViewWidthSizable));
  EXPECT_TRUE(!configured_view.acceptsFirstResponder);

  DaHandle default_view_handle = CreateView();
  DaView* default_view = NativeViewFor(default_view_handle);
  EXPECT_EQ(default_view.autoresizingMask,
            static_cast<NSAutoresizingMaskOptions>(NSViewWidthSizable |
                                                   NSViewHeightSizable));
  EXPECT_TRUE(default_view.acceptsFirstResponder);

  DaTextViewConfiguration text_configuration =
      DefaultTextViewConfiguration();
  text_configuration.view.autoresizing_mask = DA_VIEW_AUTORESIZE_HEIGHT;
  text_configuration.view.accepts_first_responder = 0;
  text_configuration.font_kind = DA_TEXT_VIEW_FONT_SYSTEM;
  text_configuration.font_weight = DA_TEXT_VIEW_FONT_WEIGHT_BOLD;
  text_configuration.font_size = 14.0;
  text_configuration.padding_top = 1.0;
  text_configuration.padding_right = 2.0;
  text_configuration.padding_bottom = 3.0;
  text_configuration.padding_left = 4.0;
  text_configuration.foreground_color = {
      DA_TEXT_VIEW_COLOR_SRGB, 0, 0.1, 0.2, 0.3, 0.4};
  DaHandle configured_text_handle = 0;
  EXPECT_EQ(da_text_view_create_configured(
                &text_configuration, nullptr, 0, &configured_text_handle),
            DA_STATUS_OK);
  DaTextView* configured_text = NativeTextViewFor(configured_text_handle);
  EXPECT_EQ(configured_text.autoresizingMask,
            static_cast<NSAutoresizingMaskOptions>(NSViewHeightSizable));
  EXPECT_TRUE(!configured_text.acceptsFirstResponder);
  EXPECT_TRUE(std::abs(configured_text.daFont.pointSize - 14.0) < 0.0001);
  EXPECT_TRUE(std::abs(configured_text.daPadding.top - 1.0) < 0.0001);
  EXPECT_TRUE(std::abs(configured_text.daPadding.right - 2.0) < 0.0001);
  EXPECT_TRUE(std::abs(configured_text.daPadding.bottom - 3.0) < 0.0001);
  EXPECT_TRUE(std::abs(configured_text.daPadding.left - 4.0) < 0.0001);
  NSColor* foreground = [configured_text.daForegroundColor
      colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  EXPECT_TRUE(foreground != nil);
  EXPECT_TRUE(std::abs(foreground.redComponent - 0.1) < 0.0001);
  EXPECT_TRUE(std::abs(foreground.greenComponent - 0.2) < 0.0001);
  EXPECT_TRUE(std::abs(foreground.blueComponent - 0.3) < 0.0001);
  EXPECT_TRUE(std::abs(foreground.alphaComponent - 0.4) < 0.0001);
  EXPECT_TRUE(
      [configured_text.daBackgroundColor isEqual:NSColor.windowBackgroundColor]);

  const DaHandle default_text_handle = CreateTextView();
  DaTextView* default_text = NativeTextViewFor(default_text_handle);
  EXPECT_EQ(default_text.autoresizingMask,
            static_cast<NSAutoresizingMaskOptions>(NSViewWidthSizable |
                                                   NSViewHeightSizable));
  EXPECT_TRUE(default_text.acceptsFirstResponder);
  EXPECT_TRUE(std::abs(default_text.daFont.pointSize - 18.0) < 0.0001);
  EXPECT_TRUE((default_text.daFont.fontDescriptor.symbolicTraits &
               NSFontDescriptorTraitMonoSpace) != 0);
  EXPECT_TRUE(std::abs(default_text.daPadding.top - 20.0) < 0.0001);
  EXPECT_TRUE([default_text.daForegroundColor isEqual:NSColor.labelColor]);
  EXPECT_TRUE(
      [default_text.daBackgroundColor isEqual:NSColor.windowBackgroundColor]);

  DaTextViewConfiguration named_configuration =
      DefaultTextViewConfiguration();
  named_configuration.font_kind = DA_TEXT_VIEW_FONT_NAMED;
  NSString* available_font_name = [NSFont systemFontOfSize:13.0].fontName;
  const std::string available_font = available_font_name.UTF8String;
  DaHandle named_text_handle = 0;
  EXPECT_EQ(da_text_view_create_configured(
                &named_configuration, available_font.data(),
                available_font.size(), &named_text_handle),
            DA_STATUS_OK);
  EXPECT_EQ(NativeTextViewFor(named_text_handle).daFont.fontName,
            available_font_name);

  DaHandle output = 99;
  EXPECT_EQ(da_view_create_configured(nullptr, &output),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(output, static_cast<DaHandle>(0));
  DaViewConfiguration invalid_view = DefaultViewConfiguration();
  invalid_view.struct_size = 0;
  EXPECT_EQ(da_view_create_configured(&invalid_view, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_view = DefaultViewConfiguration();
  invalid_view.autoresizing_mask = uint64_t{1} << 63;
  EXPECT_EQ(da_view_create_configured(&invalid_view, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_view = DefaultViewConfiguration();
  invalid_view.accepts_first_responder = 2;
  EXPECT_EQ(da_view_create_configured(&invalid_view, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_view = DefaultViewConfiguration();
  invalid_view.reserved = 1;
  EXPECT_EQ(da_view_create_configured(&invalid_view, &output),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_view_create_configured(&view_configuration, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  DaTextViewConfiguration invalid_text = DefaultTextViewConfiguration();
  invalid_text.struct_size = 0;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.view.struct_size = 0;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.font_kind = 99;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.font_kind = DA_TEXT_VIEW_FONT_NAMED;
  invalid_text.font_weight = DA_TEXT_VIEW_FONT_WEIGHT_BOLD;
  EXPECT_EQ(da_text_view_create_configured(
                &invalid_text, available_font.data(), available_font.size(),
                &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.font_size = std::numeric_limits<double>::infinity();
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.font_weight = 99;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.font_size = DA_TEXT_VIEW_FONT_MAX_SIZE + 1.0;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.padding_left = DA_TEXT_VIEW_PADDING_MAX_EXTENT + 1.0;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.foreground_color.kind = DA_TEXT_VIEW_COLOR_SRGB;
  invalid_text.foreground_color.red = 2.0;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.background_color.reserved = 1;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_text = DefaultTextViewConfiguration();
  invalid_text.background_color.red = 0.5;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);

  invalid_text = DefaultTextViewConfiguration();
  invalid_text.font_kind = DA_TEXT_VIEW_FONT_NAMED;
  EXPECT_EQ(da_text_view_create_configured(&invalid_text, nullptr, 0, &output),
            DA_STATUS_INVALID_ARGUMENT);
  const std::string missing_font = "DefinitelyMissingDartAppKitFont";
  EXPECT_EQ(da_text_view_create_configured(
                &invalid_text, missing_font.data(), missing_font.size(),
                &output),
            DA_STATUS_INVALID_ARGUMENT);
  const std::string oversized_font_family(
      DA_TEXT_VIEW_FONT_FAMILY_MAX_UTF8_BYTES + 1, 'a');
  EXPECT_EQ(da_text_view_create_configured(
                &invalid_text, oversized_font_family.data(),
                oversized_font_family.size(), &output),
            DA_STATUS_LIMIT_EXCEEDED);
  const char invalid_font_utf8[] = {static_cast<char>(0xc3), '('};
  EXPECT_EQ(da_text_view_create_configured(
                &invalid_text, invalid_font_utf8, sizeof(invalid_font_utf8),
                &output),
            DA_STATUS_INVALID_UTF8);
  invalid_text = DefaultTextViewConfiguration();
  EXPECT_EQ(da_text_view_create_configured(
                &invalid_text, available_font.data(), available_font.size(),
                &output),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_text_view_create_configured(
                &text_configuration, nullptr, 0, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  EXPECT_EQ(da_release(named_text_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(default_text_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(configured_text_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(default_view_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(configured_view_handle), DA_STATUS_OK);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
}

void TestAttributedTextEditor() {
  Capture capture;
  ResetWithCapture(&capture);

  DaTextEditorConfiguration configuration = DefaultTextEditorConfiguration();
  configuration.presentation.padding_top = 7.0;
  configuration.presentation.padding_right = 8.0;
  configuration.presentation.padding_bottom = 9.0;
  configuration.presentation.padding_left = 10.0;
  configuration.presentation.foreground_color = {
      DA_TEXT_VIEW_COLOR_SRGB, 0, 0.8, 0.8, 0.8, 1.0};
  configuration.presentation.background_color = {
      DA_TEXT_VIEW_COLOR_SRGB, 0, 0.1, 0.1, 0.1, 1.0};
  DaHandle editor_handle = 0;
  EXPECT_EQ(da_text_editor_create_configured(&configuration, nullptr, 0,
                                             &editor_handle),
            DA_STATUS_OK);
  DaTextEditor* editor = NativeTextEditorFor(editor_handle);
  EXPECT_TRUE(editor.daScrollView.documentView == editor.daTextView);
  EXPECT_TRUE(editor.daScrollView.hasVerticalScroller);
  EXPECT_TRUE(editor.daScrollView.hasHorizontalScroller);
  EXPECT_TRUE(editor.daTextView.isSelectable);
  EXPECT_TRUE(!editor.daTextView.isEditable);
  EXPECT_TRUE(editor.daTextView.allowsUndo);
  EXPECT_TRUE(std::abs(editor.daScrollView.contentInsets.top - 7.0) < 0.0001);
  EXPECT_TRUE(std::abs(editor.daScrollView.contentInsets.right - 8.0) <
              0.0001);
  EXPECT_TRUE(std::abs(editor.daScrollView.contentInsets.bottom - 9.0) <
              0.0001);
  EXPECT_TRUE(std::abs(editor.daScrollView.contentInsets.left - 10.0) <
              0.0001);

  const std::string text = "theme = dark\n\xf0\x9f\x91\xbb\n";
  DaTextEditorStyleRun runs[2]{};
  runs[0].location = 0;
  runs[0].length = 5;
  runs[0].foreground_color = {
      DA_TEXT_VIEW_COLOR_SRGB, 0, 0.3, 0.6, 1.0, 1.0};
  runs[0].underline_style = DA_TEXT_EDITOR_UNDERLINE_NONE;
  runs[0].underline_color = {
      DA_TEXT_VIEW_COLOR_LABEL, 0, 0.0, 0.0, 0.0, 1.0};
  runs[1].location = 8;
  runs[1].length = 4;
  runs[1].foreground_color = {
      DA_TEXT_VIEW_COLOR_SRGB, 0, 0.4, 0.9, 0.5, 1.0};
  runs[1].underline_style = DA_TEXT_EDITOR_UNDERLINE_SINGLE;
  runs[1].underline_color = {
      DA_TEXT_VIEW_COLOR_SRGB, 0, 1.0, 0.3, 0.3, 1.0};
  EXPECT_EQ(da_text_editor_set_document(editor_handle, text.data(), text.size(),
                                        runs, 2, 13, 2),
            DA_STATUS_OK);
  EXPECT_TRUE([editor.daTextView.string isEqualToString:@"theme = dark\n👻\n"]);
  EXPECT_EQ(editor.daTextView.selectedRange.location,
            static_cast<NSUInteger>(13));
  EXPECT_EQ(editor.daTextView.selectedRange.length,
            static_cast<NSUInteger>(2));

  NSColor* keyword_color = [editor.daTextView.textStorage
      attribute:NSForegroundColorAttributeName
        atIndex:0
 effectiveRange:nullptr];
  keyword_color =
      [keyword_color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  EXPECT_TRUE(keyword_color != nil);
  EXPECT_TRUE(std::abs(keyword_color.redComponent - 0.3) < 0.0001);
  EXPECT_TRUE(std::abs(keyword_color.greenComponent - 0.6) < 0.0001);
  EXPECT_TRUE(std::abs(keyword_color.blueComponent - 1.0) < 0.0001);
  NSNumber* underline = [editor.daTextView.textStorage
      attribute:NSUnderlineStyleAttributeName
        atIndex:8
 effectiveRange:nullptr];
  EXPECT_EQ(underline.integerValue,
            static_cast<NSInteger>(NSUnderlineStyleSingle));
  NSColor* underline_color = [editor.daTextView.textStorage
      attribute:NSUnderlineColorAttributeName
        atIndex:8
 effectiveRange:nullptr];
  underline_color =
      [underline_color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  EXPECT_TRUE(underline_color != nil);
  EXPECT_TRUE(std::abs(underline_color.redComponent - 1.0) < 0.0001);

  DaTextEditorSnapshot snapshot{};
  EXPECT_EQ(da_text_editor_get_snapshot(editor_handle, &snapshot),
            DA_STATUS_OK);
  EXPECT_EQ(std::string(snapshot.text, snapshot.text_length), text);
  EXPECT_EQ(snapshot.selection_location, static_cast<uint64_t>(13));
  EXPECT_EQ(snapshot.selection_length, static_cast<uint64_t>(2));
  EXPECT_EQ(snapshot.is_editable, 0);
  EXPECT_EQ(snapshot.has_marked_text, 0);

  DaTextEditorStyleRun replacement = runs[0];
  replacement.foreground_color = {
      DA_TEXT_VIEW_COLOR_SRGB, 0, 1.0, 0.7, 0.2, 1.0};
  NSTextStorage* storage = editor.daTextView.textStorage;
  EXPECT_EQ(da_text_editor_set_style_runs(editor_handle, &replacement, 1),
            DA_STATUS_OK);
  EXPECT_TRUE(editor.daTextView.textStorage == storage);
  EXPECT_TRUE([editor.daTextView.string isEqualToString:@"theme = dark\n👻\n"]);
  EXPECT_EQ(editor.daTextView.selectedRange.location,
            static_cast<NSUInteger>(13));
  EXPECT_TRUE([editor.daTextView.textStorage
                  attribute:NSUnderlineStyleAttributeName
                    atIndex:8
             effectiveRange:nullptr] == nil);

  NSAttributedString* normal_projection =
      [editor.daTextView.textStorage copy];
  EXPECT_EQ(da_text_editor_set_editable(editor_handle, 1), DA_STATUS_OK);
  EXPECT_TRUE(editor.daTextView.isEditable);
  EXPECT_TRUE([editor.daTextView.textStorage
      isEqualToAttributedString:normal_projection]);
  EXPECT_EQ(da_text_editor_set_selection(editor_handle, 0, 5), DA_STATUS_OK);
  EXPECT_EQ(da_text_editor_get_snapshot(editor_handle, &snapshot),
            DA_STATUS_OK);
  EXPECT_EQ(snapshot.is_editable, 1);
  EXPECT_EQ(snapshot.selection_location, static_cast<uint64_t>(0));
  EXPECT_EQ(snapshot.selection_length, static_cast<uint64_t>(5));

  const DaHandle window_handle = CreateWindow();
  EXPECT_EQ(da_window_set_content_view(window_handle, editor_handle),
            DA_STATUS_OK);
  EXPECT_EQ(da_window_make_first_responder(window_handle, editor_handle),
            DA_STATUS_OK);
  EXPECT_TRUE(OwnerFor(window_handle).window.firstResponder ==
              editor.daTextView);

  NSAttributedString* before_invalid_document =
      [editor.daTextView.textStorage copy];
  const NSRange before_invalid_selection = editor.daTextView.selectedRange;
  const std::string rejected_text = "replacement";
  EXPECT_EQ(da_text_editor_set_document(
                editor_handle, rejected_text.data(), rejected_text.size(),
                nullptr, 0, 99, 0),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_TRUE([editor.daTextView.textStorage
      isEqualToAttributedString:before_invalid_document]);
  EXPECT_TRUE(NSEqualRanges(editor.daTextView.selectedRange,
                           before_invalid_selection));

  EXPECT_EQ(da_text_editor_set_selection(editor_handle, 14, 0),
            DA_STATUS_INVALID_ARGUMENT);
  DaTextEditorStyleRun invalid_run = runs[1];
  invalid_run.location = 14;
  invalid_run.length = 1;
  EXPECT_EQ(da_text_editor_set_style_runs(editor_handle, &invalid_run, 1),
            DA_STATUS_INVALID_ARGUMENT);
  DaTextEditorStyleRun unsorted[2] = {runs[1], runs[0]};
  EXPECT_EQ(da_text_editor_set_style_runs(editor_handle, unsorted, 2),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_run = runs[0];
  invalid_run.underline_style = 99;
  EXPECT_EQ(da_text_editor_set_style_runs(editor_handle, &invalid_run, 1),
            DA_STATUS_INVALID_ARGUMENT);
  invalid_run = runs[0];
  invalid_run.foreground_color.red = 2.0;
  EXPECT_EQ(da_text_editor_set_style_runs(editor_handle, &invalid_run, 1),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_text_editor_set_style_runs(editor_handle, nullptr, 1),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_text_editor_set_style_runs(
                editor_handle, &replacement,
                DA_TEXT_EDITOR_MAX_STYLE_RUNS + static_cast<size_t>(1)),
            DA_STATUS_LIMIT_EXCEEDED);
  EXPECT_EQ(da_text_editor_set_document(
                editor_handle, nullptr,
                DA_TEXT_EDITOR_MAX_TEXT_UTF8_BYTES + static_cast<size_t>(1),
                nullptr, 0, 0, 0),
            DA_STATUS_LIMIT_EXCEEDED);
  const char invalid_utf8[] = {static_cast<char>(0xc3), '('};
  EXPECT_EQ(da_text_editor_set_document(
                editor_handle, invalid_utf8, sizeof(invalid_utf8), nullptr, 0,
                0, 0),
            DA_STATUS_INVALID_UTF8);
  EXPECT_EQ(da_text_editor_set_editable(editor_handle, 2),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_text_editor_get_snapshot(editor_handle, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  DaTextEditorConfiguration invalid_configuration = configuration;
  invalid_configuration.initially_editable = 2;
  DaHandle invalid_output = 99;
  EXPECT_EQ(da_text_editor_create_configured(
                &invalid_configuration, nullptr, 0, &invalid_output),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(invalid_output, static_cast<DaHandle>(0));
  invalid_configuration = configuration;
  invalid_configuration.struct_size = 0;
  EXPECT_EQ(da_text_editor_create_configured(
                &invalid_configuration, nullptr, 0, &invalid_output),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_text_editor_create_configured(&configuration, nullptr, 0,
                                             nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  const DaHandle generic_view = CreateView();
  EXPECT_EQ(da_text_editor_set_editable(generic_view, 1),
            DA_STATUS_WRONG_HANDLE_TYPE);
  std::atomic<int32_t> worker_status{DA_STATUS_OK};
  std::thread worker([&]() {
    worker_status.store(da_text_editor_set_editable(editor_handle, 0));
  });
  worker.join();
  EXPECT_EQ(worker_status.load(), DA_STATUS_WRONG_THREAD);

  EXPECT_EQ(da_release(generic_view), DA_STATUS_OK);
  EXPECT_EQ(da_release(editor_handle), DA_STATUS_OK);
  EXPECT_EQ(da_text_editor_set_editable(editor_handle, 0),
            DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(da_release(window_handle), DA_STATUS_OK);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
}

void TestRegisteredCustomViews() {
  Capture capture;
  ResetWithCapture(&capture);

  EXPECT_EQ(dart_appkit::RegisterCustomViewClass(nil, DaTestCustomView.class),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_TRUE(LastErrorMessage().find("must not be empty") !=
              std::string::npos);
  EXPECT_EQ(dart_appkit::RegisterCustomViewClass(@"test.invalid", Nil),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(
      dart_appkit::RegisterCustomViewClass(@"test.invalid", NSObject.class),
      DA_STATUS_INVALID_ARGUMENT);

  DaHandle handle = 99;
  EXPECT_EQ(da_view_create_custom("missing", 7, &handle),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(handle, static_cast<DaHandle>(0));
  EXPECT_TRUE(LastErrorMessage().find("not registered") != std::string::npos);
  EXPECT_EQ(da_view_create_custom(nullptr, 1, &handle),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(handle, static_cast<DaHandle>(0));
  EXPECT_EQ(da_view_create_custom("test.custom", 11, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  EXPECT_EQ(dart_appkit::RegisterCustomViewClass(@"test.custom",
                                                 DaTestCustomView.class),
            DA_STATUS_OK);
  EXPECT_EQ(dart_appkit::RegisterCustomViewClass(@"test.custom",
                                                 DaTestCustomView.class),
            DA_STATUS_OK);
  EXPECT_EQ(dart_appkit::RegisterCustomViewClass(@"test.custom",
                                                 DaAlternateCustomView.class),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_TRUE(LastErrorMessage().find("already registered") !=
              std::string::npos);

  EXPECT_EQ(da_view_create_custom("test.custom", 11, &handle), DA_STATUS_OK);
  EXPECT_TRUE(handle != 0);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(1));
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kView,
      dart_appkit::ThreadDomain::kAppKitMain, &status);
  EXPECT_EQ(status, DA_STATUS_OK);
  EXPECT_TRUE([object isKindOfClass:DaTestCustomView.class]);

  const DaHandle window = CreateWindow();
  DaWindowOwner* owner = OwnerFor(window);
  EXPECT_EQ(da_window_set_content_view(window, handle), DA_STATUS_OK);
  EXPECT_TRUE(owner.window.contentView == object);
  EXPECT_EQ(da_text_view_set_text(handle, "bad", 3),
            DA_STATUS_WRONG_HANDLE_TYPE);

  std::atomic<int32_t> worker_status{DA_STATUS_OK};
  std::atomic<int32_t> worker_registration_status{DA_STATUS_OK};
  std::thread worker([&worker_status, &worker_registration_status]() {
    DaHandle worker_handle = 99;
    worker_status.store(
        da_view_create_custom("test.custom", 11, &worker_handle));
    EXPECT_EQ(worker_handle, static_cast<DaHandle>(0));
    worker_registration_status.store(dart_appkit::RegisterCustomViewClass(
        @"test.worker", DaTestCustomView.class));
  });
  worker.join();
  EXPECT_EQ(worker_status.load(), DA_STATUS_WRONG_THREAD);
  EXPECT_EQ(worker_registration_status.load(), DA_STATUS_WRONG_THREAD);

  EXPECT_EQ(da_release(handle), DA_STATUS_OK);
  EXPECT_TRUE(owner.window.contentView == object);
  EXPECT_EQ(da_window_set_content_view(window, handle),
            DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(da_release(handle), DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(da_release(window), DA_STATUS_OK);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
}

void TestNativeExtensionServices() {
  Capture capture;
  ResetWithCapture(&capture);

  EXPECT_TRUE(da_native_extension_services(99) == nullptr);
  EXPECT_TRUE(LastErrorMessage().find("unsupported") != std::string::npos);
  const da_native_extension_services_v1* services =
      da_native_extension_services(DA_NATIVE_EXTENSION_ABI_VERSION);
  EXPECT_TRUE(services != nullptr);
  EXPECT_EQ(services->struct_size,
            static_cast<size_t>(sizeof(da_native_extension_services_v1)));
  EXPECT_EQ(services->abi_version, DA_NATIVE_EXTENSION_ABI_VERSION);
  EXPECT_TRUE(services->register_custom_view_provider != nullptr);
  EXPECT_TRUE(services->register_custom_view_operation != nullptr);

  uint32_t operation_value = 0;
  EXPECT_EQ(services->register_custom_view_operation(
                reinterpret_cast<const uint8_t*>("test.missing"), 12,
                PerformTestCustomViewOperation, &operation_value),
            DA_STATUS_INVALID_ARGUMENT);

  EXPECT_EQ(services->register_custom_view_provider(
                nullptr, 1, CreateRetainedTestCustomView, nullptr),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(services->register_custom_view_provider(
                reinterpret_cast<const uint8_t*>("factory.invalid"), 15,
                nullptr, nullptr),
            DA_STATUS_INVALID_ARGUMENT);
  const uint8_t invalid_utf8[] = {0xff};
  EXPECT_EQ(services->register_custom_view_provider(
                invalid_utf8, sizeof(invalid_utf8),
                CreateRetainedTestCustomView, nullptr),
            DA_STATUS_INVALID_UTF8);

  void* context = (__bridge void*)DaTestCustomView.class;
  constexpr char kProvider[] = "test.factory";
  EXPECT_EQ(services->register_custom_view_provider(
                reinterpret_cast<const uint8_t*>(kProvider),
                sizeof(kProvider) - 1, CreateRetainedTestCustomView, context),
            DA_STATUS_OK);
  EXPECT_EQ(services->register_custom_view_operation(
                reinterpret_cast<const uint8_t*>(kProvider),
                sizeof(kProvider) - 1, PerformTestCustomViewOperation,
                &operation_value),
            DA_STATUS_OK);
  EXPECT_EQ(services->register_custom_view_operation(
                reinterpret_cast<const uint8_t*>(kProvider),
                sizeof(kProvider) - 1, PerformTestCustomViewOperation,
                &operation_value),
            DA_STATUS_OK);
  EXPECT_EQ(services->register_custom_view_provider(
                reinterpret_cast<const uint8_t*>(kProvider),
                sizeof(kProvider) - 1, CreateRetainedTestCustomView, context),
            DA_STATUS_OK);
  EXPECT_EQ(services->register_custom_view_provider(
                reinterpret_cast<const uint8_t*>(kProvider),
                sizeof(kProvider) - 1, FailToCreateCustomView, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  DaHandle handle = 0;
  EXPECT_EQ(da_view_create_custom(kProvider, sizeof(kProvider) - 1, &handle),
            DA_STATUS_OK);
  int32_t status = DA_STATUS_OK;
  id object = dart_appkit::ObjectRegistry::Shared().Lookup(
      handle, dart_appkit::ObjectKind::kView,
      dart_appkit::ThreadDomain::kAppKitMain, &status);
  EXPECT_EQ(status, DA_STATUS_OK);
  EXPECT_TRUE([object isKindOfClass:DaTestCustomView.class]);
  const uint32_t operation_payload = 0x10203040;
  EXPECT_EQ(da_view_perform_custom_operation(
                handle, reinterpret_cast<const uint8_t*>(&operation_payload),
                sizeof(operation_payload)),
            DA_STATUS_OK);
  EXPECT_EQ(operation_value, operation_payload);
  EXPECT_EQ(da_view_perform_custom_operation(handle, nullptr, 1),
            DA_STATUS_INVALID_ARGUMENT);
  std::atomic<int32_t> operation_thread_status{DA_STATUS_OK};
  std::thread operation_worker([&] {
    operation_thread_status.store(da_view_perform_custom_operation(
        handle, reinterpret_cast<const uint8_t*>(&operation_payload),
        sizeof(operation_payload)));
  });
  operation_worker.join();
  EXPECT_EQ(operation_thread_status.load(), DA_STATUS_WRONG_THREAD);
  EXPECT_EQ(da_release(handle), DA_STATUS_OK);
  EXPECT_EQ(da_view_perform_custom_operation(
                handle, reinterpret_cast<const uint8_t*>(&operation_payload),
                sizeof(operation_payload)),
            DA_STATUS_INVALID_HANDLE);
  DaHandle plain_view = 0;
  EXPECT_EQ(da_view_create(&plain_view), DA_STATUS_OK);
  EXPECT_EQ(da_view_perform_custom_operation(
                plain_view,
                reinterpret_cast<const uint8_t*>(&operation_payload),
                sizeof(operation_payload)),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_release(plain_view), DA_STATUS_OK);

  constexpr char kFailingProvider[] = "test.factory.failure";
  EXPECT_EQ(services->register_custom_view_provider(
                reinterpret_cast<const uint8_t*>(kFailingProvider),
                sizeof(kFailingProvider) - 1, FailToCreateCustomView, nullptr),
            DA_STATUS_OK);
  EXPECT_EQ(da_view_create_custom(kFailingProvider,
                                  sizeof(kFailingProvider) - 1, &handle),
            DA_STATUS_INTERNAL_ERROR);
  EXPECT_EQ(handle, static_cast<DaHandle>(0));

  const da_native_extension_services_v1* worker_services = services;
  std::atomic<int32_t> worker_status{DA_STATUS_OK};
  std::thread worker([&] {
    worker_services =
        da_native_extension_services(DA_NATIVE_EXTENSION_ABI_VERSION);
    worker_status.store(services->register_custom_view_provider(
        reinterpret_cast<const uint8_t*>("test.worker"), 11,
        CreateRetainedTestCustomView, context));
  });
  worker.join();
  EXPECT_TRUE(worker_services == nullptr);
  EXPECT_EQ(worker_status.load(), DA_STATUS_WRONG_THREAD);

  dart_appkit::ShutdownBridge();
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
}

void TestThreadGuardAndFinalizer() {
  Capture capture;
  ResetWithCapture(&capture);

  std::atomic<int32_t> worker_status{DA_STATUS_OK};
  std::atomic<int32_t> worker_is_main{-1};
  std::atomic<int32_t> pasteboard_status{DA_STATUS_OK};
  std::atomic<int32_t> external_url_status{DA_STATUS_OK};
  std::thread worker([&]() {
    DaHandle handle = 123;
    worker_status.store(da_text_view_create(&handle));
    EXPECT_EQ(handle, static_cast<DaHandle>(0));
    int32_t is_main = -1;
    EXPECT_EQ(da_debug_is_main_thread(&is_main), DA_STATUS_OK);
    worker_is_main.store(is_main);
    DaPasteboardText snapshot{reinterpret_cast<const char*>(1), 99, 1, 99};
    pasteboard_status.store(da_pasteboard_read_text(&snapshot));
    EXPECT_TRUE(snapshot.text == nullptr);
    EXPECT_EQ(snapshot.text_length, static_cast<size_t>(0));
    EXPECT_EQ(snapshot.has_text, 0);
    EXPECT_EQ(snapshot.change_count, static_cast<int64_t>(0));
    int64_t change_count = 99;
    EXPECT_EQ(da_pasteboard_write_text(nullptr, 0, &change_count),
              DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(change_count, static_cast<int64_t>(0));
    int32_t opened = 99;
    external_url_status.store(da_application_open_external_url(
        "https://example.com", 19, &opened));
    EXPECT_EQ(opened, 0);
    change_count = 99;
    EXPECT_EQ(da_pasteboard_clear(&change_count), DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(change_count, static_cast<int64_t>(0));
    change_count = 99;
    EXPECT_EQ(da_pasteboard_get_change_count(&change_count),
              DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(change_count, static_cast<int64_t>(0));
    DaHandle menu_handle = 99;
    EXPECT_EQ(da_menu_create(nullptr, 0, &menu_handle), DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(menu_handle, static_cast<DaHandle>(0));
    DaHandle item_handle = 99;
    EXPECT_EQ(da_menu_item_create(nullptr, 0, nullptr, 0, 0, &item_handle),
              DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(item_handle, static_cast<DaHandle>(0));
    item_handle = 99;
    EXPECT_EQ(da_menu_item_create_separator(&item_handle),
              DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(item_handle, static_cast<DaHandle>(0));
    EXPECT_EQ(da_menu_add_item(1, 2), DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(da_menu_item_set_submenu(1, 2), DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(da_menu_item_set_enabled(1, 1), DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(da_application_set_main_menu(1), DA_STATUS_WRONG_THREAD);
    EXPECT_EQ(da_menu_item_perform_action(1), DA_STATUS_WRONG_THREAD);
  });
  worker.join();
  EXPECT_EQ(worker_status.load(), DA_STATUS_WRONG_THREAD);
  EXPECT_EQ(pasteboard_status.load(), DA_STATUS_WRONG_THREAD);
  EXPECT_EQ(external_url_status.load(), DA_STATUS_WRONG_THREAD);
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

void TestWindowStateEvents() {
  Capture capture;
  ResetWithCurrentCapture(&capture);
  const DaHandle window_handle = CreateWindow();
  DaWindowOwner* owner = OwnerFor(window_handle);
  const NSRect created_frame = owner.window.frame;
  EXPECT_TRUE(std::abs(created_frame.origin.x - 100.0) < 0.001);
  EXPECT_TRUE(std::abs(created_frame.origin.y - 100.0) < 0.001);
  EXPECT_TRUE(std::abs(created_frame.size.width - 640.0) < 0.001);
  EXPECT_TRUE(std::abs(created_frame.size.height - 480.0) < 0.001);

  [owner daPostFocusState:YES];
  [owner daPostFocusState:YES];
  [owner daPostVisibilityState:YES];
  [owner daPostVisibilityState:YES];
  [owner daPostOcclusionState:NO];
  [owner daPostOcclusionState:NO];
  [owner daPostBackingScaleFactor:2.0];
  [owner daPostBackingScaleFactor:2.0];
  [owner daPostScreen:nil];
  [owner daPostScreen:nil];
  const DaRect moved_frame = {-1200.0, 80.0, 920.0, 580.0};
  EXPECT_EQ(da_window_set_frame(window_handle, moved_frame), DA_STATUS_OK);
  EXPECT_EQ(da_window_set_frame(window_handle, moved_frame), DA_STATUS_OK);
  EXPECT_EQ(da_window_set_fullscreen(window_handle, 0), DA_STATUS_OK);
  EXPECT_EQ(da_window_set_fullscreen(window_handle, 0), DA_STATUS_OK);

  EXPECT_EQ(capture.events.size(), static_cast<size_t>(8));
  EXPECT_EQ(CountEvents(capture, DA_EVENT_WINDOW_FOCUS_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(capture, DA_EVENT_WINDOW_VISIBILITY_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(capture, DA_EVENT_WINDOW_OCCLUSION_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(capture, DA_EVENT_WINDOW_BACKING_SCALE_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(capture, DA_EVENT_WINDOW_SCREEN_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(capture, DA_EVENT_WINDOW_FRAME_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(capture, DA_EVENT_WINDOW_FULLSCREEN_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(capture, DA_EVENT_WINDOW_RESIZED),
            static_cast<size_t>(1));
  for (size_t index = 0; index < capture.events.size(); ++index) {
    EXPECT_EQ(capture.protocol_versions[index],
              static_cast<uint32_t>(DA_EVENT_PROTOCOL_VERSION_CURRENT));
    EXPECT_EQ(capture.events[index].window, window_handle);
    EXPECT_TRUE(capture.events[index].monotonic_nanos > 0);
  }
  EXPECT_TRUE(capture.events[0].state);
  EXPECT_TRUE(capture.events[1].state);
  EXPECT_TRUE(!capture.events[2].state);
  EXPECT_TRUE(std::abs(capture.events[3].backing_scale_factor - 2.0) < 0.001);
  EXPECT_TRUE(!capture.events[4].has_screen);
  EXPECT_EQ(capture.events[4].screen_id, static_cast<int64_t>(0));
  EXPECT_TRUE(std::abs(capture.events[6].x + 1200.0) < 0.001);
  EXPECT_TRUE(std::abs(capture.events[6].y - 80.0) < 0.001);
  EXPECT_TRUE(std::abs(capture.events[6].width - 920.0) < 0.001);
  EXPECT_TRUE(std::abs(capture.events[6].height - 580.0) < 0.001);
  EXPECT_TRUE(!capture.events[7].state);

  EXPECT_EQ(da_window_set_fullscreen(window_handle, 2),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_set_frame(window_handle,
                                DaRect{0.0, 0.0, 0.0, 100.0}),
            DA_STATUS_INVALID_ARGUMENT);
  const DaHandle wrong_kind = CreateView();
  EXPECT_EQ(da_window_set_frame(wrong_kind, moved_frame),
            DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_EQ(da_window_set_fullscreen(wrong_kind, 0),
            DA_STATUS_WRONG_HANDLE_TYPE);
  std::atomic<int32_t> frame_worker_status{DA_STATUS_OK};
  std::atomic<int32_t> fullscreen_worker_status{DA_STATUS_OK};
  std::thread state_worker([&]() {
    frame_worker_status.store(da_window_set_frame(window_handle, moved_frame));
    fullscreen_worker_status.store(
        da_window_set_fullscreen(window_handle, 0));
  });
  state_worker.join();
  EXPECT_EQ(frame_worker_status.load(), DA_STATUS_WRONG_THREAD);
  EXPECT_EQ(fullscreen_worker_status.load(), DA_STATUS_WRONG_THREAD);
  EXPECT_EQ(da_release(wrong_kind), DA_STATUS_OK);

  [owner daPostFocusState:NO];
  [owner daPostVisibilityState:NO];
  [owner daPostOcclusionState:YES];
  [owner daPostBackingScaleFactor:1.0];
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(12));
  [owner daPostBackingScaleFactor:0.0];
  [owner daPostBackingScaleFactor:std::numeric_limits<double>::quiet_NaN()];
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(12));

  NSScreen* screen = NSScreen.screens.firstObject;
  if (screen != nil) {
    [owner daPostScreen:screen];
    EXPECT_EQ(capture.events.size(), static_cast<size_t>(13));
    const dart_appkit::NativeEvent& screen_event = capture.events.back();
    EXPECT_EQ(screen_event.type, DA_EVENT_WINDOW_SCREEN_CHANGED);
    EXPECT_TRUE(screen_event.has_screen);
    EXPECT_TRUE(screen_event.screen_id > 0);
    EXPECT_TRUE(screen_event.screen_width > 0.0);
    EXPECT_TRUE(screen_event.screen_height > 0.0);
    EXPECT_TRUE(screen_event.visible_screen_width > 0.0);
    EXPECT_TRUE(screen_event.visible_screen_height > 0.0);
    [owner daPostScreen:screen];
    EXPECT_EQ(capture.events.size(), static_cast<size_t>(13));
  }
  EXPECT_EQ(da_release(window_handle), DA_STATUS_OK);
  EXPECT_EQ(da_window_set_frame(window_handle, moved_frame),
            DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(da_window_set_fullscreen(window_handle, 0),
            DA_STATUS_INVALID_HANDLE);

  Capture transition_capture;
  ResetWithCurrentCapture(&transition_capture);
  const DaHandle transition_window = CreateWindow();
  DaWindowOwner* transition_owner = OwnerFor(transition_window);
  [transition_owner daPostFullscreenState:NO];
  id<NSWindowDelegate> transition_delegate = transition_owner;
  NSNotification* enter_notification = [NSNotification
      notificationWithName:NSWindowDidEnterFullScreenNotification
                    object:transition_owner.window];
  NSNotification* exit_notification = [NSNotification
      notificationWithName:NSWindowDidExitFullScreenNotification
                    object:transition_owner.window];
  [transition_delegate windowWillEnterFullScreen:enter_notification];
  EXPECT_TRUE([transition_owner daSetFullscreen:YES]);
  EXPECT_TRUE(![transition_owner daSetFullscreen:NO]);
  const size_t before_transition_frame =
      CountEvents(transition_capture, DA_EVENT_WINDOW_FRAME_CHANGED);
  [transition_owner.window setFrame:NSMakeRect(-800.0, 40.0, 800.0, 500.0)
                             display:NO];
  [transition_delegate windowDidMove:enter_notification];
  EXPECT_EQ(CountEvents(transition_capture, DA_EVENT_WINDOW_FRAME_CHANGED),
            before_transition_frame);
  const size_t before_enter_completion = transition_capture.events.size();
  [transition_delegate windowDidEnterFullScreen:enter_notification];
  EXPECT_EQ(transition_capture.events[before_enter_completion].type,
            DA_EVENT_WINDOW_FULLSCREEN_CHANGED);
  EXPECT_EQ(transition_capture.events[before_enter_completion + 1].type,
            DA_EVENT_WINDOW_FRAME_CHANGED);
  [transition_delegate windowDidEnterFullScreen:enter_notification];
  [transition_delegate windowWillExitFullScreen:exit_notification];
  EXPECT_TRUE([transition_owner daSetFullscreen:NO]);
  EXPECT_TRUE(![transition_owner daSetFullscreen:YES]);
  [transition_owner.window setFrame:NSMakeRect(120.0, 90.0, 920.0, 580.0)
                             display:NO];
  const size_t before_exit_completion = transition_capture.events.size();
  [transition_delegate windowDidExitFullScreen:exit_notification];
  EXPECT_EQ(transition_capture.events[before_exit_completion].type,
            DA_EVENT_WINDOW_FULLSCREEN_CHANGED);
  EXPECT_EQ(transition_capture.events[before_exit_completion + 1].type,
            DA_EVENT_WINDOW_FRAME_CHANGED);
  [transition_delegate windowDidExitFullScreen:exit_notification];
  [transition_delegate windowDidFailToEnterFullScreen:transition_owner.window];
  [transition_delegate windowDidFailToExitFullScreen:transition_owner.window];
  EXPECT_EQ(
      CountEvents(transition_capture, DA_EVENT_WINDOW_FULLSCREEN_CHANGED),
      static_cast<size_t>(4));
  EXPECT_TRUE(transition_capture.events.back().state);
  EXPECT_EQ(da_release(transition_window), DA_STATUS_OK);

  Capture snapshot_capture;
  ResetWithCurrentCapture(&snapshot_capture);
  const DaHandle shown_window = CreateWindow();
  EXPECT_EQ(da_window_show(shown_window), DA_STATUS_OK);
  EXPECT_EQ(CountEvents(snapshot_capture, DA_EVENT_WINDOW_FOCUS_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(snapshot_capture, DA_EVENT_WINDOW_VISIBILITY_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(snapshot_capture, DA_EVENT_WINDOW_OCCLUSION_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(
      CountEvents(snapshot_capture, DA_EVENT_WINDOW_BACKING_SCALE_CHANGED),
      static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(snapshot_capture, DA_EVENT_WINDOW_SCREEN_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(CountEvents(snapshot_capture, DA_EVENT_WINDOW_FRAME_CHANGED),
            static_cast<size_t>(1));
  EXPECT_EQ(
      CountEvents(snapshot_capture, DA_EVENT_WINDOW_FULLSCREEN_CHANGED),
      static_cast<size_t>(1));
  const size_t snapshot_size = snapshot_capture.events.size();
  [OwnerFor(shown_window) daPostCurrentWindowState];
  EXPECT_EQ(snapshot_capture.events.size(), snapshot_size);
  EXPECT_EQ(da_release(shown_window), DA_STATUS_OK);
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

void TestScrollInputEvent() {
  Capture capture;
  ResetWithCurrentCapture(&capture);
  const DaHandle window_handle = CreateWindow();
  DaWindowOwner* owner = OwnerFor(window_handle);
  owner.window.contentView.frame = NSMakeRect(0.0, 0.0, 320.0, 200.0);

  DaScrollProbeEvent* scroll = [[DaScrollProbeEvent alloc] init];
  scroll.probeLocation = NSMakePoint(12.5, 20.0);
  scroll.probeModifiers = NSEventModifierFlagShift | NSEventModifierFlagOption;
  scroll.probeDeltaX = -1.5;
  scroll.probeDeltaY = 8.75;
  scroll.probePrecise = YES;
  scroll.probePhase = NSEventPhaseChanged;
  scroll.probeMomentumPhase = NSEventPhaseBegan;
  scroll.probeDirectionInverted = YES;
  [owner.window daPostInputEvent:scroll];

  EXPECT_EQ(capture.events.size(), static_cast<size_t>(1));
  EXPECT_EQ(capture.protocol_versions[0],
            static_cast<uint32_t>(DA_EVENT_PROTOCOL_VERSION_CURRENT));
  const dart_appkit::NativeEvent& event = capture.events[0];
  EXPECT_EQ(event.type, DA_EVENT_SCROLL_WHEEL);
  EXPECT_TRUE(std::abs(event.x - 12.5) < 0.001);
  EXPECT_TRUE(std::abs(event.y - 180.0) < 0.001);
  EXPECT_TRUE(std::abs(event.scrolling_delta_x + 1.5) < 0.001);
  EXPECT_TRUE(std::abs(event.scrolling_delta_y - 8.75) < 0.001);
  EXPECT_TRUE(event.has_precise_scrolling_deltas);
  EXPECT_EQ(event.scroll_phase,
            static_cast<int64_t>(DA_SCROLL_PHASE_CHANGED));
  EXPECT_EQ(event.momentum_phase,
            static_cast<int64_t>(DA_SCROLL_PHASE_BEGAN));
  EXPECT_TRUE(event.direction_inverted_from_device);
  EXPECT_TRUE((event.modifiers & DA_MODIFIER_SHIFT) != 0);
  EXPECT_TRUE((event.modifiers & DA_MODIFIER_OPTION) != 0);

  EXPECT_EQ(da_release(window_handle), DA_STATUS_OK);
}

void TestKeyEventRouting() {
  Capture capture;
  ResetWithCapture(&capture);
  const DaHandle window_handle = CreateWindow();
  DaWindowOwner* owner = OwnerFor(window_handle);
  DaKeyEventProbeView* view =
      [[DaKeyEventProbeView alloc] initWithFrame:NSZeroRect];
  owner.window.contentView = view;
  EXPECT_TRUE([owner.window makeFirstResponder:view]);
  EXPECT_EQ(owner.window.daKeyEventRouting,
            DA_KEY_EVENT_ROUTING_DART_AND_APPKIT);

  NSMenu* previous_main_menu = NSApp.mainMenu;
  NSApp.mainMenu = nil;
  NSEvent* key_down = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                       location:NSZeroPoint
                                  modifierFlags:NSEventModifierFlagControl
                                      timestamp:3.0
                                   windowNumber:owner.window.windowNumber
                                        context:nil
                                     characters:@"\x04"
                      charactersIgnoringModifiers:@"d"
                                      isARepeat:NO
                                        keyCode:2];
  NSEvent* key_up = [NSEvent keyEventWithType:NSEventTypeKeyUp
                                     location:NSZeroPoint
                                modifierFlags:NSEventModifierFlagControl
                                    timestamp:3.1
                                 windowNumber:owner.window.windowNumber
                                      context:nil
                                   characters:@"\x04"
                    charactersIgnoringModifiers:@"d"
                                    isARepeat:NO
                                      keyCode:2];
  [owner.window sendEvent:key_down];
  [owner.window sendEvent:key_up];
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(2));
  EXPECT_EQ(view.keyDownCount, static_cast<NSInteger>(1));
  EXPECT_EQ(view.keyUpCount, static_cast<NSInteger>(1));

  EXPECT_EQ(da_window_set_key_event_routing(
                window_handle, DA_KEY_EVENT_ROUTING_DART_ONLY),
            DA_STATUS_OK);
  [owner.window sendEvent:key_down];
  [owner.window sendEvent:key_up];
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(4));
  EXPECT_EQ(view.keyDownCount, static_cast<NSInteger>(1));
  EXPECT_EQ(view.keyUpCount, static_cast<NSInteger>(1));

  DaKeyEquivalentProbeMenu* menu =
      [[DaKeyEquivalentProbeMenu alloc] initWithTitle:@"Main"];
  NSApp.mainMenu = menu;
  NSEvent* menu_key = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                        location:NSZeroPoint
                                   modifierFlags:NSEventModifierFlagCommand
                                       timestamp:3.2
                                    windowNumber:owner.window.windowNumber
                                         context:nil
                                      characters:@"w"
                       charactersIgnoringModifiers:@"w"
                                       isARepeat:NO
                                         keyCode:13];
  [owner.window sendEvent:menu_key];
  EXPECT_EQ(menu.performCount, static_cast<NSInteger>(1));
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(4));
  EXPECT_EQ(view.keyDownCount, static_cast<NSInteger>(1));

  EXPECT_EQ(da_window_set_key_event_routing(
                window_handle, DA_KEY_EVENT_ROUTING_APPKIT_ONLY),
            DA_STATUS_OK);
  NSApp.mainMenu = nil;
  [owner.window sendEvent:key_down];
  [owner.window sendEvent:key_up];
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(4));
  EXPECT_EQ(view.keyDownCount, static_cast<NSInteger>(2));
  EXPECT_EQ(view.keyUpCount, static_cast<NSInteger>(2));
  NSApp.mainMenu = menu;
  [owner.window sendEvent:menu_key];
  EXPECT_EQ(menu.performCount, static_cast<NSInteger>(2));
  EXPECT_EQ(capture.events.size(), static_cast<size_t>(4));
  EXPECT_EQ(view.keyDownCount, static_cast<NSInteger>(2));
  NSApp.mainMenu = previous_main_menu;

  EXPECT_EQ(da_window_set_key_event_routing(window_handle, -1),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_set_key_event_routing(window_handle, 3),
            DA_STATUS_INVALID_ARGUMENT);
  const DaHandle view_handle = CreateView();
  EXPECT_EQ(da_window_set_key_event_routing(
                view_handle, DA_KEY_EVENT_ROUTING_DART_ONLY),
            DA_STATUS_WRONG_HANDLE_TYPE);

  std::atomic<int32_t> worker_status{DA_STATUS_OK};
  std::thread worker([&]() {
    worker_status.store(da_window_set_key_event_routing(
        window_handle, DA_KEY_EVENT_ROUTING_DART_AND_APPKIT));
  });
  worker.join();
  EXPECT_EQ(worker_status.load(), DA_STATUS_WRONG_THREAD);

  EXPECT_EQ(da_release(view_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(window_handle), DA_STATUS_OK);
  EXPECT_EQ(da_window_set_key_event_routing(
                window_handle, DA_KEY_EVENT_ROUTING_DART_AND_APPKIT),
            DA_STATUS_INVALID_HANDLE);
}

void TestNativeTabsSplitViewsAndFirstResponder() {
  Capture capture;
  ResetWithCapture(&capture);
  const DaHandle first_window_handle = CreateWindow();
  const DaHandle second_window_handle = CreateWindow();
  const DaHandle third_window_handle = CreateWindow();
  DaWindowOwner* first_window = OwnerFor(first_window_handle);
  DaWindowOwner* second_window = OwnerFor(second_window_handle);
  DaWindowOwner* third_window = OwnerFor(third_window_handle);

  EXPECT_EQ(da_window_add_tabbed_window(first_window_handle,
                                        second_window_handle),
            DA_STATUS_OK);
  EXPECT_EQ(da_window_add_tabbed_window(first_window_handle,
                                        third_window_handle),
            DA_STATUS_OK);
  NSWindowTabGroup* tab_group = first_window.window.tabGroup;
  EXPECT_TRUE(tab_group != nil);
  EXPECT_EQ(tab_group.windows.count, static_cast<NSUInteger>(3));
  EXPECT_TRUE(tab_group.windows[0] == first_window.window);
  EXPECT_TRUE(tab_group.windows[1] == second_window.window);
  EXPECT_TRUE(tab_group.windows[2] == third_window.window);
  EXPECT_EQ(da_window_select_tab(second_window_handle), DA_STATUS_OK);
  EXPECT_TRUE(tab_group.selectedWindow == second_window.window);
  EXPECT_EQ(da_window_remove_from_tab_group(second_window_handle),
            DA_STATUS_OK);
  EXPECT_EQ(tab_group.windows.count, static_cast<NSUInteger>(2));
  EXPECT_TRUE(![tab_group.windows containsObject:second_window.window]);
  EXPECT_EQ(da_window_add_tabbed_window(first_window_handle,
                                        first_window_handle),
            DA_STATUS_INVALID_ARGUMENT);

  const DaHandle first_view_handle = CreateView();
  const DaHandle second_view_handle = CreateView();
  const DaHandle third_view_handle = CreateView();
  const DaHandle root_split_handle =
      CreateSplitView(DA_SPLIT_AXIS_HORIZONTAL);
  const DaHandle nested_split_handle =
      CreateSplitView(DA_SPLIT_AXIS_VERTICAL);
  DaSplitView* root_split = SplitViewFor(root_split_handle);
  DaSplitView* nested_split = SplitViewFor(nested_split_handle);
  int32_t lookup_status = DA_STATUS_OK;
  NSView* first_view = static_cast<NSView*>(
      dart_appkit::ObjectRegistry::Shared().Lookup(
          first_view_handle, dart_appkit::ObjectKind::kView,
          dart_appkit::ThreadDomain::kAppKitMain, &lookup_status));
  EXPECT_EQ(lookup_status, DA_STATUS_OK);
  NSView* second_view = static_cast<NSView*>(
      dart_appkit::ObjectRegistry::Shared().Lookup(
          second_view_handle, dart_appkit::ObjectKind::kView,
          dart_appkit::ThreadDomain::kAppKitMain, &lookup_status));
  EXPECT_EQ(lookup_status, DA_STATUS_OK);
  NSView* third_view = static_cast<NSView*>(
      dart_appkit::ObjectRegistry::Shared().Lookup(
          third_view_handle, dart_appkit::ObjectKind::kView,
          dart_appkit::ThreadDomain::kAppKitMain, &lookup_status));
  EXPECT_EQ(lookup_status, DA_STATUS_OK);

  root_split.frame = NSMakeRect(0.0, 0.0, 400.0, 240.0);
  EXPECT_EQ(da_split_view_set_children(nested_split_handle,
                                       second_view_handle,
                                       third_view_handle),
            DA_STATUS_OK);
  EXPECT_EQ(da_split_view_set_children(root_split_handle, first_view_handle,
                                       nested_split_handle),
            DA_STATUS_OK);
  EXPECT_EQ(da_split_view_set_position(root_split_handle, 0.1, 80.0, 90.0),
            DA_STATUS_OK);
  EXPECT_EQ(da_split_view_set_position(nested_split_handle, 0.75, 30.0, 40.0),
            DA_STATUS_OK);
  EXPECT_EQ(root_split.daAxis, DA_SPLIT_AXIS_HORIZONTAL);
  EXPECT_TRUE(root_split.isVertical);
  EXPECT_EQ(nested_split.daAxis, DA_SPLIT_AXIS_VERTICAL);
  EXPECT_TRUE(!nested_split.isVertical);
  EXPECT_EQ(root_split.subviews.count, static_cast<NSUInteger>(2));
  EXPECT_TRUE(root_split.subviews[0] == first_view);
  EXPECT_TRUE(root_split.subviews[1] == nested_split);
  EXPECT_TRUE(NSWidth(first_view.frame) >= 80.0);
  EXPECT_TRUE(NSWidth(nested_split.frame) >= 90.0);
  EXPECT_TRUE(NSHeight(second_view.frame) >= 30.0);
  EXPECT_TRUE(NSHeight(third_view.frame) >= 40.0);

  EXPECT_EQ(da_split_view_equalize(root_split_handle), DA_STATUS_OK);
  EXPECT_TRUE(std::abs(root_split.daFraction - 0.5) < 0.001);
  EXPECT_EQ(da_split_view_set_zoomed_child(root_split_handle,
                                           DA_SPLIT_ZOOM_SECOND),
            DA_STATUS_OK);
  EXPECT_TRUE(first_view.hidden);
  EXPECT_TRUE(!nested_split.hidden);
  EXPECT_EQ(da_split_view_set_zoomed_child(root_split_handle,
                                           DA_SPLIT_ZOOM_NONE),
            DA_STATUS_OK);
  EXPECT_TRUE(!first_view.hidden);
  EXPECT_TRUE(!nested_split.hidden);

  EXPECT_EQ(da_window_set_content_view(first_window_handle, root_split_handle),
            DA_STATUS_OK);
  EXPECT_EQ(da_window_make_first_responder(first_window_handle,
                                           third_view_handle),
            DA_STATUS_OK);
  EXPECT_TRUE(first_window.window.firstResponder == third_view);
  EXPECT_EQ(da_window_make_first_responder(third_window_handle,
                                           third_view_handle),
            DA_STATUS_INVALID_ARGUMENT);

  EXPECT_EQ(da_split_view_create(-1, nullptr), DA_STATUS_INVALID_ARGUMENT);
  DaHandle invalid_axis_handle = 99;
  EXPECT_EQ(da_split_view_create(2, &invalid_axis_handle),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(invalid_axis_handle, static_cast<DaHandle>(0));
  EXPECT_EQ(da_split_view_set_children(root_split_handle, first_view_handle,
                                       first_view_handle),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_split_view_set_children(first_view_handle, second_view_handle,
                                       third_view_handle),
            DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_EQ(da_split_view_set_position(root_split_handle,
                                       std::numeric_limits<double>::quiet_NaN(),
                                       0.0, 0.0),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_split_view_set_zoomed_child(root_split_handle, 2),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_add_tabbed_window(first_view_handle,
                                        third_window_handle),
            DA_STATUS_WRONG_HANDLE_TYPE);

  std::atomic<int32_t> worker_status{DA_STATUS_OK};
  std::thread worker([&]() {
    worker_status.store(da_split_view_equalize(root_split_handle));
  });
  worker.join();
  EXPECT_EQ(worker_status.load(), DA_STATUS_WRONG_THREAD);

  EXPECT_EQ(da_release(second_window_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(third_window_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(first_window_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(root_split_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(nested_split_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(first_view_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(second_view_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(third_view_handle), DA_STATUS_OK);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
}

void TestWindowPresentationMetadata() {
  Capture capture;
  ResetWithCapture(&capture);
  const DaHandle window_handle = CreateWindow();
  DaWindowOwner* owner = OwnerFor(window_handle);
  const std::string path = "/private/tmp/Project \xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E";

  EXPECT_EQ(da_window_set_represented_file_path(
                window_handle, path.data(), path.size()),
            DA_STATUS_OK);
  EXPECT_TRUE(owner.window.representedURL != nil);
  EXPECT_TRUE(owner.window.representedURL.isFileURL);
  EXPECT_TRUE([owner.window.representedURL.path
      isEqualToString:@"/private/tmp/Project 日本語"]);

  EXPECT_EQ(da_window_set_tab_color(window_handle, 1, 0.25, 0.5, 0.75, 0.8),
            DA_STATUS_OK);
  NSView* marker = owner.window.tab.accessoryView;
  EXPECT_TRUE(marker != nil);
  EXPECT_TRUE(marker.wantsLayer);
  EXPECT_TRUE(std::abs(NSWidth(marker.frame) - 8.0) < 0.001);
  EXPECT_TRUE(std::abs(NSHeight(marker.frame) - 8.0) < 0.001);
  EXPECT_TRUE(std::abs(marker.layer.cornerRadius - 4.0) < 0.001);
  NSColor* color = [[NSColor colorWithCGColor:marker.layer.backgroundColor]
      colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  CGFloat red = 0;
  CGFloat green = 0;
  CGFloat blue = 0;
  CGFloat alpha = 0;
  [color getRed:&red green:&green blue:&blue alpha:&alpha];
  EXPECT_TRUE(std::abs(red - 0.25) < 0.001);
  EXPECT_TRUE(std::abs(green - 0.5) < 0.001);
  EXPECT_TRUE(std::abs(blue - 0.75) < 0.001);
  EXPECT_TRUE(std::abs(alpha - 0.8) < 0.001);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(1));

  DaWindowTabAccessoryConfiguration accessory = {
      DA_WINDOW_TAB_ACCESSORY_CONFIGURATION_VERSION_1_SIZE,
      DA_WINDOW_TAB_ACCESSORY_SHAPE_RECTANGLE,
      0,
      14.0,
      6.0,
      0.1,
      0.2,
      0.3,
      1.0,
  };
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 1, &accessory),
            DA_STATUS_OK);
  marker = owner.window.tab.accessoryView;
  EXPECT_TRUE(std::abs(NSWidth(marker.frame) - 14.0) < 0.001);
  EXPECT_TRUE(std::abs(NSHeight(marker.frame) - 6.0) < 0.001);
  EXPECT_TRUE(std::abs(marker.layer.cornerRadius) < 0.001);

  accessory.shape = DA_WINDOW_TAB_ACCESSORY_SHAPE_ELLIPSE;
  accessory.width = 12.0;
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 1, &accessory),
            DA_STATUS_OK);
  marker = owner.window.tab.accessoryView;
  EXPECT_TRUE(std::abs(NSWidth(marker.frame) - 12.0) < 0.001);
  EXPECT_TRUE(std::abs(NSHeight(marker.frame) - 6.0) < 0.001);
  EXPECT_TRUE(std::abs(marker.layer.cornerRadius - 3.0) < 0.001);
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 0, nullptr),
            DA_STATUS_OK);
  EXPECT_TRUE(owner.window.tab.accessoryView == nil);

  EXPECT_EQ(da_window_set_represented_file_path(window_handle, nullptr, 0),
            DA_STATUS_OK);
  EXPECT_TRUE(owner.window.representedURL == nil);
  EXPECT_EQ(da_window_set_tab_color(window_handle, 0, 9, 9, 9, 9),
            DA_STATUS_OK);
  EXPECT_TRUE(owner.window.tab.accessoryView == nil);

  const std::string relative = "private/tmp";
  EXPECT_EQ(da_window_set_represented_file_path(
                window_handle, relative.data(), relative.size()),
            DA_STATUS_INVALID_ARGUMENT);
  const std::string oversized(4097, 'a');
  EXPECT_EQ(da_window_set_represented_file_path(
                window_handle, oversized.data(), oversized.size()),
            DA_STATUS_INVALID_ARGUMENT);
  const std::string embedded_nul("/tmp/a\0b", 8);
  EXPECT_EQ(da_window_set_represented_file_path(
                window_handle, embedded_nul.data(), embedded_nul.size()),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_set_tab_color(window_handle, 2, 0, 0, 0, 0),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_set_tab_color(
                window_handle, 1, std::numeric_limits<double>::quiet_NaN(), 0,
                0, 1),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_set_tab_color(window_handle, 1, 0, 0, 1.01, 1),
            DA_STATUS_INVALID_ARGUMENT);
  accessory.struct_size = 0;
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 1, &accessory),
            DA_STATUS_INVALID_ARGUMENT);
  accessory.struct_size =
      DA_WINDOW_TAB_ACCESSORY_CONFIGURATION_VERSION_1_SIZE;
  accessory.shape = 99;
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 1, &accessory),
            DA_STATUS_INVALID_ARGUMENT);
  accessory.shape = DA_WINDOW_TAB_ACCESSORY_SHAPE_RECTANGLE;
  accessory.reserved = 1;
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 1, &accessory),
            DA_STATUS_INVALID_ARGUMENT);
  accessory.reserved = 0;
  accessory.width = 257.0;
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 1, &accessory),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 2, &accessory),
            DA_STATUS_INVALID_ARGUMENT);
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 1, nullptr),
            DA_STATUS_INVALID_ARGUMENT);

  const DaHandle view_handle = CreateView();
  EXPECT_EQ(da_window_set_represented_file_path(view_handle, nullptr, 0),
            DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_EQ(da_window_set_tab_color(view_handle, 0, 0, 0, 0, 0),
            DA_STATUS_WRONG_HANDLE_TYPE);
  EXPECT_EQ(da_window_set_tab_accessory(view_handle, 0, nullptr),
            DA_STATUS_WRONG_HANDLE_TYPE);
  std::atomic<int32_t> worker_status{DA_STATUS_OK};
  std::thread worker([&]() {
    worker_status.store(
        da_window_set_represented_file_path(window_handle, nullptr, 0));
  });
  worker.join();
  EXPECT_EQ(worker_status.load(), DA_STATUS_WRONG_THREAD);

  EXPECT_EQ(da_release(view_handle), DA_STATUS_OK);
  EXPECT_EQ(da_release(window_handle), DA_STATUS_OK);
  EXPECT_EQ(da_window_set_tab_color(window_handle, 0, 0, 0, 0, 0),
            DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(da_window_set_tab_accessory(window_handle, 0, nullptr),
            DA_STATUS_INVALID_HANDLE);
  EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
}

}  // namespace

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestContractAndErrors();
    TestWindowConfiguration();
    TestEventProtocolNegotiation();
    TestLifecycleRequests();
    TestApplicationAppearanceObservation();
    TestPasteboardText();
    TestExternalUrlOpening();
    TestMenus();
    TestRegistryLifecycleAndTypes();
    TestConfiguredBaseAndTextViews();
    TestAttributedTextEditor();
    TestRegisteredCustomViews();
    TestNativeExtensionServices();
    TestThreadGuardAndFinalizer();
    TestRegistryDomainsAndAsyncRelease();
    TestConcurrentAsyncRelease();
    TestShutdownOwnsPendingRelease();
    TestRegistryChurn();
    TestWindowStateEvents();
    TestWindowEvents();
    TestInputEvents();
    TestScrollInputEvent();
    TestKeyEventRouting();
    TestWindowPresentationMetadata();
    TestNativeTabsSplitViewsAndFirstResponder();
    dart_appkit::ResetBridgeForTesting();
  }

  if (g_failures != 0) {
    std::cerr << g_failures << " native bridge test(s) failed" << std::endl;
    return 1;
  }
  std::cout << "all native bridge tests passed" << std::endl;
  return 0;
}
