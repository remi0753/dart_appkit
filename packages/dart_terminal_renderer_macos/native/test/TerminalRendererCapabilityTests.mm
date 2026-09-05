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
    using FontShape = int32_t (*)(uint64_t, uint32_t, uint32_t,
                                  const uint8_t*, uint32_t, uint8_t*,
                                  uint32_t, uint32_t*);
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
    const FontShape font_shape =
        Lookup<FontShape>(image, "dtr_font_catalog_shape");
    const LiveCount live_font_count =
        Lookup<LiveCount>(image, "dtr_debug_live_font_catalog_count");
    Expect(version != nullptr && version() == DTR_ABI_VERSION,
           "renderer ABI version");
    Expect(DTR_ABI_VERSION == 3, "run shaping requires renderer ABI v3");

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

    auto shape = [&](uint64_t catalog_handle, uint32_t shape_style,
                     uint32_t features, const uint8_t* bytes,
                     uint32_t length) {
      uint32_t required = 0;
      Expect(font_shape != nullptr &&
                 font_shape(catalog_handle, shape_style, features, bytes,
                            length, nullptr, 0, &required) ==
                     DTR_STATUS_BUFFER_TOO_SMALL,
             "shape size query reports a required buffer");
      Expect(required >= sizeof(DtrShapeHeaderV1) &&
                 required <= DTR_MAX_SHAPE_OUTPUT_BYTES,
             "shape required size is bounded");
      std::vector<uint8_t> result(required, 0xa5);
      uint32_t filled_required = 0;
      Expect(font_shape(catalog_handle, shape_style, features, bytes, length,
                        result.data(), static_cast<uint32_t>(result.size()),
                        &filled_required) == DTR_STATUS_OK &&
                 filled_required == required,
             "shape fills exactly the queried buffer");
      return result;
    };

    const uint8_t kMixed[] = {
        0x41,
        0xe6, 0x97, 0xa5, 0xe6, 0x9c, 0xac, 0xe8, 0xaa, 0x9e,
        0xf0, 0x9f, 0x91, 0xa9, 0xf0, 0x9f, 0x8f, 0xbd, 0xe2, 0x80, 0x8d,
        0xf0, 0x9f, 0x92, 0xbb,
        0x65, 0xcc, 0x81,
    };
    const std::vector<uint8_t> mixed_buffer = shape(
        font_summary.handle, DTR_FONT_STYLE_REGULAR,
        DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed));
    const auto* mixed_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(mixed_buffer.data());
    Expect(mixed_header->magic == DTR_SHAPE_BUFFER_MAGIC &&
               mixed_header->version == DTR_SHAPE_BUFFER_VERSION &&
               mixed_header->header_size == sizeof(DtrShapeHeaderV1) &&
               mixed_header->total_size == mixed_buffer.size() &&
               mixed_header->catalog_generation == font_summary.generation &&
               mixed_header->requested_style == DTR_FONT_STYLE_REGULAR &&
               mixed_header->feature_flags == DTR_SHAPE_FEATURE_LIGATURES &&
               mixed_header->utf8_length == sizeof(kMixed) &&
               mixed_header->utf16_length == 13 &&
               mixed_header->unicode_scalar_count == 10 &&
               mixed_header->run_count >= 3 && mixed_header->face_count >= 3 &&
               mixed_header->glyph_count > 0,
           "mixed shaping header preserves counts and fallback structure");
    Expect(mixed_header->runs_offset == sizeof(DtrShapeHeaderV1) &&
               mixed_header->faces_offset ==
                   mixed_header->runs_offset +
                       mixed_header->run_count * sizeof(DtrShapeRunV1) &&
               mixed_header->glyphs_offset ==
                   mixed_header->faces_offset +
                       mixed_header->face_count * sizeof(DtrShapeFaceV1) &&
               mixed_header->total_size ==
                   mixed_header->glyphs_offset +
                       mixed_header->glyph_count * sizeof(DtrShapeGlyphV1),
           "packed shaping sections are contiguous and exact");
    const auto* mixed_runs = reinterpret_cast<const DtrShapeRunV1*>(
        mixed_buffer.data() + mixed_header->runs_offset);
    const auto* mixed_faces = reinterpret_cast<const DtrShapeFaceV1*>(
        mixed_buffer.data() + mixed_header->faces_offset);
    const auto* mixed_glyphs = reinterpret_cast<const DtrShapeGlyphV1*>(
        mixed_buffer.data() + mixed_header->glyphs_offset);
    bool saw_color_face = false;
    bool saw_cjk_fallback = false;
    bool saw_emoji_cluster = false;
    bool saw_combining_cluster = false;
    uint32_t covered_glyphs = 0;
    for (uint32_t face = 0; face < mixed_header->face_count; face++) {
      saw_color_face |=
          (mixed_faces[face].flags & DTR_SHAPED_RUN_COLOR_GLYPHS) != 0;
      Expect(mixed_faces[face].face_id != 0 &&
                 mixed_faces[face].postscript_name_length > 0 &&
                 mixed_faces[face].postscript_name_length <=
                     DTR_MAX_POSTSCRIPT_NAME_BYTES &&
                 mixed_faces[face].postscript_name
                         [mixed_faces[face].postscript_name_length] == 0,
             "packed face has stable identity and bounded copied name");
    }
    for (uint32_t run = 0; run < mixed_header->run_count; run++) {
      Expect(mixed_runs[run].first_glyph == covered_glyphs &&
                 mixed_runs[run].glyph_count > 0 &&
                 mixed_runs[run].utf16_length > 0 &&
                 mixed_runs[run].utf16_start + mixed_runs[run].utf16_length <=
                     mixed_header->utf16_length &&
                 std::isfinite(mixed_runs[run].typographic_width),
             "packed run covers a finite bounded range");
      saw_cjk_fallback |=
          (mixed_runs[run].flags & DTR_SHAPED_RUN_FALLBACK) != 0 &&
          (mixed_runs[run].flags & DTR_SHAPED_RUN_COLOR_GLYPHS) == 0;
      covered_glyphs += mixed_runs[run].glyph_count;
    }
    for (uint32_t glyph = 0; glyph < mixed_header->glyph_count; glyph++) {
      const DtrShapeGlyphV1& item = mixed_glyphs[glyph];
      Expect(item.run_index < mixed_header->run_count && item.face_id != 0 &&
                 item.utf16_length > 0 &&
                 item.utf16_start + item.utf16_length <=
                     mixed_header->utf16_length &&
                 std::isfinite(item.position_x) &&
                 std::isfinite(item.position_y) &&
                 std::isfinite(item.advance),
             "packed glyph has a finite position and logical cluster");
      saw_emoji_cluster |= item.utf16_start == 4 && item.utf16_length == 7;
      saw_combining_cluster |= item.utf16_start == 11 && item.utf16_length == 2;
    }
    Expect(covered_glyphs == mixed_header->glyph_count && saw_color_face &&
               saw_cjk_fallback && saw_emoji_cluster &&
               saw_combining_cluster,
           "mixed shaping preserves CJK, color emoji, and combining clusters");

    const uint8_t kEmojiFlag[] = {
        0xf0, 0x9f, 0x91, 0xa9, 0xf0, 0x9f, 0x8f, 0xbd, 0xe2, 0x80, 0x8d,
        0xf0, 0x9f, 0x92, 0xbb, 0xf0, 0x9f, 0x87, 0xaf, 0xf0, 0x9f, 0x87,
        0xb5,
    };
    const std::vector<uint8_t> emoji_flag_buffer = shape(
        font_summary.handle, DTR_FONT_STYLE_REGULAR,
        DTR_SHAPE_FEATURE_LIGATURES, kEmojiFlag, sizeof(kEmojiFlag));
    const auto* emoji_flag_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(emoji_flag_buffer.data());
    const auto* emoji_flag_glyphs = reinterpret_cast<const DtrShapeGlyphV1*>(
        emoji_flag_buffer.data() + emoji_flag_header->glyphs_offset);
    bool saw_zwj_modifier = false;
    bool saw_flag = false;
    for (uint32_t glyph = 0; glyph < emoji_flag_header->glyph_count; glyph++) {
      saw_zwj_modifier |= emoji_flag_glyphs[glyph].utf16_start == 0 &&
                          emoji_flag_glyphs[glyph].utf16_length == 7;
      saw_flag |= emoji_flag_glyphs[glyph].utf16_start == 7 &&
                  emoji_flag_glyphs[glyph].utf16_length == 4;
    }
    Expect(emoji_flag_header->utf16_length == 11 &&
               emoji_flag_header->unicode_scalar_count == 6 &&
               saw_zwj_modifier && saw_flag,
           "emoji ZWJ/modifier and regional-indicator flag clusters survive");

    uint32_t small_required = 0;
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                      DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed),
                      nullptr, 1, &small_required) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "null shaping output cannot claim nonzero capacity");
    std::vector<uint8_t> undersized(mixed_buffer.size() - 1, 0xa5);
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                      DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed),
                      undersized.data(),
                      static_cast<uint32_t>(undersized.size()),
                      &small_required) == DTR_STATUS_BUFFER_TOO_SMALL &&
               small_required == mixed_buffer.size(),
           "undersized shaping output reports the exact retry size");
    bool undersized_untouched = true;
    for (uint8_t byte : undersized) {
      undersized_untouched &= byte == 0xa5;
    }
    Expect(undersized_untouched,
           "undersized shaping call never writes a partial record");
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR, 0x80000000,
                      kMixed, sizeof(kMixed), nullptr, 0, &small_required) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "unknown shaping feature is rejected");
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR, 0,
                      kInvalidUtf8, sizeof(kInvalidUtf8), nullptr, 0,
                      &small_required) == DTR_STATUS_INVALID_ARGUMENT,
           "shaping rejects malformed UTF-8 before allocation");
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR, 0,
                      reinterpret_cast<const uint8_t*>(kLatin),
                      DTR_MAX_RESOLVE_TEXT_BYTES + 1, nullptr, 0,
                      &small_required) == DTR_STATUS_INVALID_ARGUMENT,
           "shaping rejects an over-limit input before reading it");
    Expect(font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR, 0,
                      reinterpret_cast<const uint8_t*>(kLatin),
                      sizeof(kLatin) - 1, nullptr, 0, nullptr) ==
               DTR_STATUS_INVALID_ARGUMENT,
           "shaping requires an output-size pointer");

    constexpr char kTimes[] = "Times-Roman";
    DtrFontCatalogSummaryV1 times_summary = {};
    times_summary.struct_size = sizeof(times_summary);
    times_summary.version = DTR_FONT_CATALOG_SUMMARY_VERSION;
    Expect(font_create(reinterpret_cast<const uint8_t*>(kTimes),
                       sizeof(kTimes) - 1, 16.0,
                       DTR_FONT_POLICY_ALLOW_SYNTHETIC, &times_summary) ==
               DTR_STATUS_OK,
           "ligature test face is created");
    constexpr char kLigatures[] = "office ffi affluent";
    const std::vector<uint8_t> ligatures_on = shape(
        times_summary.handle, DTR_FONT_STYLE_REGULAR,
        DTR_SHAPE_FEATURE_LIGATURES,
        reinterpret_cast<const uint8_t*>(kLigatures),
        sizeof(kLigatures) - 1);
    const std::vector<uint8_t> ligatures_off = shape(
        times_summary.handle, DTR_FONT_STYLE_REGULAR, 0,
        reinterpret_cast<const uint8_t*>(kLigatures),
        sizeof(kLigatures) - 1);
    const auto* ligatures_on_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(ligatures_on.data());
    const auto* ligatures_off_header =
        reinterpret_cast<const DtrShapeHeaderV1*>(ligatures_off.data());
    const auto* ligature_glyphs = reinterpret_cast<const DtrShapeGlyphV1*>(
        ligatures_on.data() + ligatures_on_header->glyphs_offset);
    bool saw_ligature_span = false;
    for (uint32_t glyph = 0; glyph < ligatures_on_header->glyph_count; glyph++) {
      saw_ligature_span |= ligature_glyphs[glyph].utf16_length > 1;
    }
    Expect(ligatures_on_header->glyph_count <
                   ligatures_off_header->glyph_count &&
               saw_ligature_span,
           "ligature feature changes glyph count and cluster span");
    Expect(font_release(times_summary.handle) == DTR_STATUS_OK,
           "ligature test catalog releases");

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
    std::atomic<int> concurrent_shape_failures{0};
    std::vector<std::thread> shapers;
    for (int worker = 0; worker < 4; worker++) {
      shapers.emplace_back([&] {
        for (int iteration = 0; iteration < 50; iteration++) {
          uint32_t required = 0;
          if (font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                         DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed),
                         nullptr, 0, &required) !=
                  DTR_STATUS_BUFFER_TOO_SMALL ||
              required < sizeof(DtrShapeHeaderV1) ||
              required > DTR_MAX_SHAPE_OUTPUT_BYTES) {
            concurrent_shape_failures.fetch_add(1);
            continue;
          }
          std::vector<uint8_t> bytes(required);
          uint32_t filled = 0;
          if (font_shape(font_summary.handle, DTR_FONT_STYLE_REGULAR,
                         DTR_SHAPE_FEATURE_LIGATURES, kMixed, sizeof(kMixed),
                         bytes.data(), static_cast<uint32_t>(bytes.size()),
                         &filled) != DTR_STATUS_OK ||
              filled != required ||
              reinterpret_cast<const DtrShapeHeaderV1*>(bytes.data())
                      ->catalog_generation != font_summary.generation) {
            concurrent_shape_failures.fetch_add(1);
          }
        }
      });
    }
    for (std::thread& shaper : shapers) {
      shaper.join();
    }
    Expect(concurrent_shape_failures.load() == 0,
           "concurrent whole-run shaping preserves one catalog generation");
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
    uint32_t stale_shape_required = 0;
    Expect(font_shape(released_font_handle, DTR_FONT_STYLE_REGULAR, 0,
                      reinterpret_cast<const uint8_t*>(kLatin),
                      sizeof(kLatin) - 1, nullptr, 0,
                      &stale_shape_required) == DTR_STATUS_INVALID_HANDLE &&
               stale_shape_required == 0,
           "released font catalog generation cannot shape");
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
