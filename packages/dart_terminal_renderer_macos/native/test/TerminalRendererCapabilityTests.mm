#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>

#include <dlfcn.h>

#include <atomic>
#include <iostream>
#include <thread>

#include "AppKitObjects.h"
#include "BridgeInternal.h"
#include "ObjectRegistry.h"
#include "TerminalRendererPlugin.h"
#include "dart_appkit.h"
#include "dart_appkit_native_extension.h"

namespace {

int failures = 0;

void Expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "TerminalRenderer expectation failed: " << description << '\n';
    ++failures;
  }
}

template <typename Function>
Function Lookup(void* image, const char* symbol) {
  dlerror();
  Function function = reinterpret_cast<Function>(dlsym(image, symbol));
  const char* error = dlerror();
  if (function == nullptr || error != nullptr) {
    std::cerr << "Could not resolve " << symbol << ": "
              << (error == nullptr ? "unknown" : error) << '\n';
    ++failures;
  }
  return function;
}

}  // namespace

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    if (argc != 2) {
      std::cerr << "usage: terminal_renderer_tests <plugin.dylib>\n";
      return 64;
    }
    void* image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (image == nullptr) {
      std::cerr << "Could not load renderer capability: " << dlerror() << '\n';
      return 1;
    }
    using Version = uint32_t (*)();
    using Initialize = int32_t (*)(const da_native_extension_services_v1*);
    using LiveCount = int32_t (*)();
    const Version version = Lookup<Version>(image, "dtr_abi_version");
    const Initialize initialize = Lookup<Initialize>(image, "dtr_initialize");
    const LiveCount live_count =
        Lookup<LiveCount>(image, "dtr_debug_live_view_count");
    Expect(version != nullptr && version() == DTR_ABI_VERSION,
           "renderer ABI version");

    da_native_extension_services_v1 incompatible = {};
    incompatible.struct_size = sizeof(incompatible);
    incompatible.abi_version = 99;
    Expect(initialize != nullptr &&
               initialize(&incompatible) == DA_STATUS_UNSUPPORTED_VERSION,
           "incompatible host ABI is rejected");

    const da_native_extension_services_v1* services =
        da_native_extension_services(DA_NATIVE_EXTENSION_ABI_VERSION);
    Expect(services != nullptr, "host service table");
    std::atomic<int32_t> worker_status{DA_STATUS_OK};
    std::thread worker([&] { worker_status.store(initialize(services)); });
    worker.join();
    Expect(worker_status.load() == DA_STATUS_WRONG_THREAD,
           "off-main initialization is rejected");
    Expect(initialize(services) == DA_STATUS_OK, "renderer initializes");
    Expect(initialize(services) == DA_STATUS_OK,
           "duplicate initialization is idempotent");

    @autoreleasepool {
      constexpr char kProvider[] = "dart_terminal.TerminalMetalView";
      DaHandle view_handle = 0;
      Expect(da_view_create_custom(kProvider, sizeof(kProvider) - 1,
                                   &view_handle) == DA_STATUS_OK,
             "terminal view is created");
      Expect(view_handle != 0 && live_count() == 1,
             "renderer owns one live view");

      int32_t lookup_status = DA_STATUS_OK;
      __unsafe_unretained id object =
          dart_appkit::ObjectRegistry::Shared().Lookup(
              view_handle, dart_appkit::ObjectKind::kView,
              dart_appkit::ThreadDomain::kAppKitMain, &lookup_status);
      Expect(lookup_status == DA_STATUS_OK, "view handle resolves");
      Expect([object isKindOfClass:NSClassFromString(@"DtrTerminalMetalView")],
             "provider creates the renderer class");
      __unsafe_unretained MTKView* view = static_cast<MTKView*>(object);
      Expect(view.device != nil, "view owns a Metal device");
      Expect(view.isPaused, "view is paused until explicit redraw");
      Expect(view.enableSetNeedsDisplay, "view redraw is demand driven");
      Expect(view.autoResizeDrawable, "drawable follows view size");
      Expect(view.framebufferOnly, "drawable is framebuffer only");
      Expect(view.delegate == nil, "view starts without a render delegate");
      Expect(view.isFlipped, "view uses top-left coordinates");

      constexpr char kTitle[] = "Terminal renderer capability";
      DaHandle window_handle = 0;
      Expect(
          da_window_create({100.0, 100.0, 640.0, 480.0}, kTitle,
                           sizeof(kTitle) - 1, &window_handle) == DA_STATUS_OK,
          "test window is created");
      Expect(da_window_set_content_view(window_handle, view_handle) ==
                 DA_STATUS_OK,
             "renderer attaches through the public view handle");
      __unsafe_unretained DaWindowOwner* owner = static_cast<DaWindowOwner*>(
          dart_appkit::ObjectRegistry::Shared().Lookup(
              window_handle, dart_appkit::ObjectKind::kWindow,
              dart_appkit::ThreadDomain::kAppKitMain, &lookup_status));
      Expect(lookup_status == DA_STATUS_OK && owner.window.contentView == view,
             "window owns the attached renderer view");
      Expect(owner.window.firstResponder == view,
             "attached renderer becomes first responder");

      Expect(da_release(view_handle) == DA_STATUS_OK,
             "Dart view handle releases independently");
      Expect(live_count() == 1, "window retain keeps attached renderer alive");
      Expect(da_release(view_handle) == DA_STATUS_INVALID_HANDLE,
             "released renderer handle cannot be reused");
      DaHandle replacement_handle = 0;
      Expect(da_view_create(&replacement_handle) == DA_STATUS_OK,
             "replacement view is created");
      Expect(da_window_set_content_view(window_handle, replacement_handle) ==
                 DA_STATUS_OK,
             "renderer can be detached through ordinary view replacement");
      Expect(da_release(replacement_handle) == DA_STATUS_OK,
             "replacement view handle releases");
      Expect(da_release(window_handle) == DA_STATUS_OK,
             "window handle releases");
      dart_appkit::ShutdownBridge();
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    Expect(live_count() == 0, "renderer deallocates during teardown");

    void* retained = dlopen(argv[1], RTLD_NOW | RTLD_NOLOAD);
    Expect(retained != nullptr,
           "renderer image remains loaded through teardown");
    dart_appkit::ResetBridgeForTesting();
    if (retained != nullptr) {
      dlclose(retained);
    }
    dlclose(image);
  }
  if (failures != 0) {
    return 1;
  }
  std::cout << "Terminal renderer capability contract passed\n";
  return 0;
}
