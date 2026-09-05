#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>

#include <dlfcn.h>

#include <atomic>
#include <cmath>
#include <cstring>
#include <iostream>
#include <thread>
#include <vector>

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
    using FontCreate = int32_t (*)(const uint8_t*, uint32_t, double, uint32_t,
                                   DtrFontCatalogSummaryV1*);
    using FontRelease = int32_t (*)(uint64_t);
    using FontResolve = int32_t (*)(uint64_t, uint32_t, const uint8_t*,
                                    uint32_t, DtrResolvedFontV1*);
    const Version version = Lookup<Version>(image, "dtr_abi_version");
    const Initialize initialize = Lookup<Initialize>(image, "dtr_initialize");
    const LiveCount live_count =
        Lookup<LiveCount>(image, "dtr_debug_live_view_count");
    const FontCreate font_create =
        Lookup<FontCreate>(image, "dtr_font_catalog_create");
    const FontRelease font_release =
        Lookup<FontRelease>(image, "dtr_font_catalog_release");
    const FontResolve font_resolve =
        Lookup<FontResolve>(image, "dtr_font_catalog_resolve");
    const LiveCount live_font_count =
        Lookup<LiveCount>(image, "dtr_debug_live_font_catalog_count");
    Expect(version != nullptr && version() == DTR_ABI_VERSION,
           "renderer ABI version");
    Expect(DTR_ABI_VERSION == 2, "font catalog requires renderer ABI v2");

    DtrFontCatalogSummaryV1 unsupported_summary = {};
    unsupported_summary.struct_size = sizeof(unsupported_summary);
    unsupported_summary.version = 99;
    Expect(font_create != nullptr &&
               font_create(nullptr, 0, 14.0,
                           DTR_FONT_POLICY_ALLOW_SYNTHETIC,
                           &unsupported_summary) ==
                   DTR_STATUS_UNSUPPORTED_VERSION,
           "font catalog summary version is mandatory");

    constexpr char kMenlo[] = "Menlo";
    DtrFontCatalogSummaryV1 font_summary = {};
    font_summary.struct_size = sizeof(font_summary);
    font_summary.version = DTR_FONT_CATALOG_SUMMARY_VERSION;
    Expect(font_create != nullptr &&
               font_create(reinterpret_cast<const uint8_t*>(kMenlo),
                           sizeof(kMenlo) - 1, 14.0,
                           DTR_FONT_POLICY_ALLOW_SYNTHETIC, &font_summary) ==
                   DTR_STATUS_OK,
           "Menlo font catalog is created");
    Expect(font_summary.struct_size == sizeof(font_summary) &&
               font_summary.version == DTR_FONT_CATALOG_SUMMARY_VERSION &&
               font_summary.handle != 0 && font_summary.generation != 0 &&
               font_summary.point_size == 14.0 &&
               std::isfinite(font_summary.cell_width) &&
               font_summary.cell_width > 0.0 &&
               std::isfinite(font_summary.cell_height) &&
               font_summary.cell_height > 0.0 &&
               font_summary.ascent > 0.0 && font_summary.descent > 0.0 &&
               font_summary.leading >= 0.0 &&
               font_summary.baseline == font_summary.ascent &&
               font_summary.underline_thickness > 0.0 &&
               font_summary.strike_position > 0.0 &&
               font_summary.strike_thickness > 0.0,
           "font catalog metrics are finite and usable");
    Expect((font_summary.available_style_bits &
            DTR_FONT_STYLE_BIT_REGULAR) != 0 &&
               font_summary.regular_face_id != 0 &&
               font_summary.bold_face_id != 0 &&
               font_summary.italic_face_id != 0 &&
               font_summary.bold_italic_face_id != 0,
           "catalog exposes explicit style face identities");
    Expect(live_font_count != nullptr && live_font_count() == 1,
           "catalog registry owns one generation");

    auto resolve = [&](uint32_t style, const uint8_t* bytes, uint32_t length,
                       DtrResolvedFontV1* output) {
      memset(output, 0, sizeof(*output));
      output->struct_size = sizeof(*output);
      output->version = DTR_RESOLVED_FONT_VERSION;
      return font_resolve(font_summary.handle, style, bytes, length, output);
    };
    constexpr char kLatin[] = "terminal";
    DtrResolvedFontV1 latin = {};
    Expect(resolve(DTR_FONT_STYLE_REGULAR,
                   reinterpret_cast<const uint8_t*>(kLatin),
                   sizeof(kLatin) - 1, &latin) == DTR_STATUS_OK,
           "Latin font resolution succeeds");
    Expect(latin.catalog_generation == font_summary.generation &&
               latin.face_id == font_summary.regular_face_id &&
               (latin.flags & DTR_RESOLVED_FONT_FALLBACK) == 0 &&
               (latin.flags & DTR_RESOLVED_FONT_MONOSPACED) != 0 &&
               (latin.flags & DTR_RESOLVED_FONT_MISSING_GLYPH) == 0 &&
               latin.utf16_length == 8 && latin.unicode_scalar_count == 8 &&
               latin.glyph_count > 0 && latin.postscript_name_length > 0 &&
               strstr(reinterpret_cast<const char*>(latin.postscript_name),
                      "Menlo") != nullptr,
           "Latin retains requested face and exact text counts");

    const uint8_t kCjk[] = {0xe6, 0x97, 0xa5, 0xe6, 0x9c,
                            0xac, 0xe8, 0xaa, 0x9e};
    DtrResolvedFontV1 cjk = {};
    Expect(resolve(DTR_FONT_STYLE_REGULAR, kCjk, sizeof(kCjk), &cjk) ==
               DTR_STATUS_OK,
           "CJK font resolution succeeds");
    Expect((cjk.flags & DTR_RESOLVED_FONT_FALLBACK) != 0 &&
               (cjk.flags & DTR_RESOLVED_FONT_MISSING_GLYPH) == 0 &&
               cjk.face_id != latin.face_id && cjk.utf16_length == 3 &&
               cjk.unicode_scalar_count == 3,
           "CJK resolves through a distinct fallback face");

    const uint8_t kEmoji[] = {0xf0, 0x9f, 0x91, 0xa9, 0xf0, 0x9f, 0x8f, 0xbd,
                              0xe2, 0x80, 0x8d, 0xf0, 0x9f, 0x92, 0xbb};
    DtrResolvedFontV1 emoji = {};
    Expect(resolve(DTR_FONT_STYLE_REGULAR, kEmoji, sizeof(kEmoji), &emoji) ==
               DTR_STATUS_OK,
           "emoji font resolution succeeds");
    Expect((emoji.flags & DTR_RESOLVED_FONT_FALLBACK) != 0 &&
               (emoji.flags & DTR_RESOLVED_FONT_COLOR_GLYPHS) != 0 &&
               (emoji.flags & DTR_RESOLVED_FONT_MISSING_GLYPH) == 0 &&
               emoji.utf16_length == 7 && emoji.unicode_scalar_count == 4 &&
               strstr(reinterpret_cast<const char*>(emoji.postscript_name),
                      "AppleColorEmoji") != nullptr,
           "emoji resolves through the color fallback face");

    const uint8_t kInvalidUtf8[] = {0xff};
    DtrResolvedFontV1 invalid_text = {};
    Expect(resolve(DTR_FONT_STYLE_REGULAR, kInvalidUtf8,
                   sizeof(kInvalidUtf8), &invalid_text) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "invalid UTF-8 is rejected");

    std::atomic<int> concurrent_failures{0};
    std::vector<std::thread> resolvers;
    for (int worker = 0; worker < 4; worker++) {
      resolvers.emplace_back([&] {
        for (int iteration = 0; iteration < 100; iteration++) {
          DtrResolvedFontV1 result = {};
          result.struct_size = sizeof(result);
          result.version = DTR_RESOLVED_FONT_VERSION;
          if (font_resolve(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                           reinterpret_cast<const uint8_t*>(kLatin),
                           sizeof(kLatin) - 1, &result) != DTR_STATUS_OK ||
              result.catalog_generation != font_summary.generation) {
            concurrent_failures.fetch_add(1);
          }
        }
      });
    }
    for (std::thread& resolver : resolvers) {
      resolver.join();
    }
    Expect(concurrent_failures.load() == 0,
           "concurrent catalog reads retain one valid generation");
    const uint64_t released_font_handle = font_summary.handle;
    Expect(font_release != nullptr &&
               font_release(released_font_handle) == DTR_STATUS_OK,
           "font catalog releases exactly once");
    Expect(font_release(released_font_handle) == DTR_STATUS_INVALID_HANDLE,
           "double font catalog release is rejected");
    DtrResolvedFontV1 stale = {};
    stale.struct_size = sizeof(stale);
    stale.version = DTR_RESOLVED_FONT_VERSION;
    Expect(font_resolve(released_font_handle, DTR_FONT_STYLE_REGULAR,
                        reinterpret_cast<const uint8_t*>(kLatin),
                        sizeof(kLatin) - 1, &stale) ==
               DTR_STATUS_INVALID_HANDLE,
           "released font catalog generation cannot resolve");
    Expect(live_font_count() == 0, "font catalog registry returns to zero");

    DtrFontCatalogSummaryV1 racing_summary = {};
    racing_summary.struct_size = sizeof(racing_summary);
    racing_summary.version = DTR_FONT_CATALOG_SUMMARY_VERSION;
    Expect(font_create(reinterpret_cast<const uint8_t*>(kMenlo),
                       sizeof(kMenlo) - 1, 14.0,
                       DTR_FONT_POLICY_ALLOW_SYNTHETIC, &racing_summary) ==
               DTR_STATUS_OK,
           "concurrent-release catalog is created");
    std::atomic<bool> begin_race{false};
    std::atomic<int> race_failures{0};
    std::vector<std::thread> racing_resolvers;
    for (int worker = 0; worker < 4; worker++) {
      racing_resolvers.emplace_back([&] {
        while (!begin_race.load()) {
          std::this_thread::yield();
        }
        for (int iteration = 0; iteration < 200; iteration++) {
          DtrResolvedFontV1 result = {};
          result.struct_size = sizeof(result);
          result.version = DTR_RESOLVED_FONT_VERSION;
          const int32_t status = font_resolve(
              racing_summary.handle, DTR_FONT_STYLE_REGULAR,
              reinterpret_cast<const uint8_t*>(kLatin), sizeof(kLatin) - 1,
              &result);
          if (status != DTR_STATUS_OK && status != DTR_STATUS_INVALID_HANDLE) {
            race_failures.fetch_add(1);
          }
          if (status == DTR_STATUS_OK &&
              result.catalog_generation != racing_summary.generation) {
            race_failures.fetch_add(1);
          }
        }
      });
    }
    begin_race.store(true);
    Expect(font_release(racing_summary.handle) == DTR_STATUS_OK,
           "catalog release races safely with retained readers");
    for (std::thread& resolver : racing_resolvers) {
      resolver.join();
    }
    Expect(race_failures.load() == 0,
           "concurrent release yields only retained success or stale handle");
    Expect(live_font_count() == 0,
           "concurrent release returns catalog registry to zero");

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
