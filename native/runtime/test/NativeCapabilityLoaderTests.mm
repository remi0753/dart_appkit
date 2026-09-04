#import <AppKit/AppKit.h>

#include <dlfcn.h>

#include <atomic>
#include <iostream>
#include <string>
#include <thread>

#include "BridgeInternal.h"
#include "ExampleViewPlugin.h"
#include "ObjectRegistry.h"
#include "dart_appkit.h"
#include "dart_appkit_native_extension.h"

namespace {

int failures = 0;

void Expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "NativeCapabilityLoader expectation failed: " << description
              << '\n';
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
      std::cerr << "usage: native_capability_loader_tests <plugin.dylib>\n";
      return 64;
    }
    void* image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (image == nullptr) {
      std::cerr << "Could not load capability: " << dlerror() << '\n';
      return 1;
    }
    using Version = uint32_t (*)();
    using Initialize = int32_t (*)(const da_native_extension_services_v1*);
    using LiveCount = int32_t (*)();
    const Version version = Lookup<Version>(image, "daev_abi_version");
    const Initialize initialize = Lookup<Initialize>(image, "daev_initialize");
    const LiveCount live_count =
        Lookup<LiveCount>(image, "daev_debug_live_view_count");
    Expect(version != nullptr && version() == DAEV_ABI_VERSION,
           "capability ABI version");

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
    Expect(initialize(services) == DA_STATUS_OK, "capability initializes");
    Expect(initialize(services) == DA_STATUS_OK,
           "duplicate initialization is idempotent");

    constexpr char kProvider[] = "dev.dart-appkit.example-view";
    @autoreleasepool {
      DaHandle view = 0;
      Expect(da_view_create_custom(kProvider, sizeof(kProvider) - 1, &view) ==
                 DA_STATUS_OK,
             "dependency view is created");
      Expect(view != 0 && live_count() == 1, "plugin owns one live view");
      Expect(da_release(view) == DA_STATUS_OK, "dependency view is released");
    }
    Expect(live_count() == 0, "released view deallocates in loaded image");

    void* retained = dlopen(argv[1], RTLD_NOW | RTLD_NOLOAD);
    Expect(retained != nullptr, "capability image remains loaded");
    dart_appkit::ShutdownBridge();
    dart_appkit::ResetBridgeForTesting();
    if (retained != nullptr) {
      dlclose(retained);
    }
    dlclose(image);
  }
  if (failures != 0) {
    return 1;
  }
  std::cout << "Native capability loading contract passed\n";
  return 0;
}
