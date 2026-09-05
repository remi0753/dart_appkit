#ifndef DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_
#define DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_

#include <stdint.h>

#include "dart_appkit_native_extension.h"

#define DTR_ABI_VERSION 2u
#define DTR_FONT_CATALOG_SUMMARY_VERSION 1u
#define DTR_RESOLVED_FONT_VERSION 1u
#define DTR_MAX_FONT_FAMILY_BYTES 1024u
#define DTR_MAX_RESOLVE_TEXT_BYTES (1024u * 1024u)
#define DTR_MAX_POSTSCRIPT_NAME_BYTES 127u

typedef enum DtrStatus {
  DTR_STATUS_OK = 0,
  DTR_STATUS_INVALID_ARGUMENT = 1,
  DTR_STATUS_UNSUPPORTED_VERSION = 2,
  DTR_STATUS_NOT_FOUND = 3,
  DTR_STATUS_RESOURCE_EXHAUSTED = 4,
  DTR_STATUS_INVALID_HANDLE = 5,
  DTR_STATUS_INTERNAL = 6,
} DtrStatus;

typedef enum DtrFontStyle {
  DTR_FONT_STYLE_REGULAR = 0,
  DTR_FONT_STYLE_BOLD = 1,
  DTR_FONT_STYLE_ITALIC = 2,
  DTR_FONT_STYLE_BOLD_ITALIC = 3,
} DtrFontStyle;

enum {
  DTR_FONT_POLICY_ALLOW_SYNTHETIC = 1u << 0,
  DTR_FONT_POLICY_KNOWN_MASK = DTR_FONT_POLICY_ALLOW_SYNTHETIC,
};

enum {
  DTR_FONT_STYLE_BIT_REGULAR = 1u << DTR_FONT_STYLE_REGULAR,
  DTR_FONT_STYLE_BIT_BOLD = 1u << DTR_FONT_STYLE_BOLD,
  DTR_FONT_STYLE_BIT_ITALIC = 1u << DTR_FONT_STYLE_ITALIC,
  DTR_FONT_STYLE_BIT_BOLD_ITALIC = 1u << DTR_FONT_STYLE_BOLD_ITALIC,
};

enum {
  DTR_RESOLVED_FONT_FALLBACK = 1u << 0,
  DTR_RESOLVED_FONT_COLOR_GLYPHS = 1u << 1,
  DTR_RESOLVED_FONT_SYNTHETIC = 1u << 2,
  DTR_RESOLVED_FONT_MISSING_GLYPH = 1u << 3,
  DTR_RESOLVED_FONT_MONOSPACED = 1u << 4,
  DTR_RESOLVED_FONT_KNOWN_MASK =
      DTR_RESOLVED_FONT_FALLBACK | DTR_RESOLVED_FONT_COLOR_GLYPHS |
      DTR_RESOLVED_FONT_SYNTHETIC | DTR_RESOLVED_FONT_MISSING_GLYPH |
      DTR_RESOLVED_FONT_MONOSPACED,
};

typedef struct DtrFontCatalogSummaryV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t handle;
  uint64_t generation;
  double point_size;
  double cell_width;
  double cell_height;
  double ascent;
  double descent;
  double leading;
  double baseline;
  double underline_position;
  double underline_thickness;
  double strike_position;
  double strike_thickness;
  uint32_t available_style_bits;
  uint32_t synthetic_style_bits;
  uint32_t regular_face_id;
  uint32_t bold_face_id;
  uint32_t italic_face_id;
  uint32_t bold_italic_face_id;
  uint32_t reserved[4];
} DtrFontCatalogSummaryV1;

typedef struct DtrResolvedFontV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t catalog_generation;
  uint32_t face_id;
  uint32_t flags;
  uint32_t requested_style;
  uint32_t utf16_length;
  uint32_t unicode_scalar_count;
  uint32_t glyph_count;
  uint32_t postscript_name_length;
  uint32_t reserved[4];
  uint8_t postscript_name[DTR_MAX_POSTSCRIPT_NAME_BYTES + 1u];
} DtrResolvedFontV1;

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t dtr_abi_version(void);

__attribute__((visibility("default"))) int32_t
dtr_initialize(const da_native_extension_services_v1* services);

__attribute__((visibility("default"))) int32_t dtr_debug_live_view_count(void);

// Creates an immutable native CoreText catalog. family_utf8 may be null only
// when family_length is zero, which selects the system monospaced font.
// The caller initializes output struct_size/version. On success it owns exactly
// one handle and must call dtr_font_catalog_release once.
__attribute__((visibility("default"))) int32_t dtr_font_catalog_create(
    const uint8_t* family_utf8, uint32_t family_length, double point_size,
    uint32_t policy_flags, DtrFontCatalogSummaryV1* output);

__attribute__((visibility("default"))) int32_t
dtr_font_catalog_release(uint64_t handle);

// NativeFinalizer-compatible fallback. The pointer value is the opaque handle;
// it is never dereferenced. Explicit release remains the deterministic path.
__attribute__((visibility("default"))) void
dtr_font_catalog_release_finalizer(void* handle);

// Resolves the effective first CoreText run for one complete UTF-8 text unit.
// No input pointer is retained. The caller initializes output
// struct_size/version and receives a fixed-size copied result.
__attribute__((visibility("default"))) int32_t dtr_font_catalog_resolve(
    uint64_t handle, uint32_t style, const uint8_t* text_utf8,
    uint32_t text_length, DtrResolvedFontV1* output);

__attribute__((visibility("default"))) int32_t
dtr_debug_live_font_catalog_count(void);

#if defined(__cplusplus)
}
#endif

#endif  // DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_
