#ifndef DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_
#define DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_

#include <stdint.h>

#include "dart_appkit_native_extension.h"

#define DTR_ABI_VERSION 5u
#define DTR_FONT_CATALOG_SUMMARY_VERSION 1u
#define DTR_RESOLVED_FONT_VERSION 1u
#define DTR_SHAPE_BUFFER_VERSION 1u
#define DTR_SHAPE_BUFFER_MAGIC 0x48535444u
#define DTR_RASTER_BUFFER_VERSION 1u
#define DTR_RASTER_BUFFER_MAGIC 0x47525444u
#define DTR_MAX_FONT_FAMILY_BYTES 1024u
#define DTR_MAX_RESOLVE_TEXT_BYTES (1024u * 1024u)
#define DTR_MAX_POSTSCRIPT_NAME_BYTES 127u
#define DTR_MAX_SHAPE_RUNS 65536u
#define DTR_MAX_SHAPE_FACES 4096u
#define DTR_MAX_SHAPE_GLYPHS (1024u * 1024u)
#define DTR_MAX_SHAPE_OUTPUT_BYTES (64u * 1024u * 1024u)
#define DTR_MAX_RASTER_GLYPHS 4096u
#define DTR_MAX_RASTER_DIMENSION 4096u
#define DTR_MAX_RASTER_OUTPUT_BYTES (64u * 1024u * 1024u)
#define DTR_METAL_RENDERER_CONFIG_VERSION 1u
#define DTR_METAL_RENDERER_SUMMARY_VERSION 1u
#define DTR_METAL_ATLAS_UPLOAD_VERSION 1u
#define DTR_METAL_FRAME_VERSION 1u
#define DTR_METAL_FRAME_MAGIC 0x46525444u
#define DTR_MAX_METAL_DIMENSION 4096u
#define DTR_MAX_METAL_INSTANCES 131072u
#define DTR_MAX_METAL_ATLAS_PAGES 16u
#define DTR_MAX_METAL_ATLAS_BYTES (64u * 1024u * 1024u)
#define DTR_MAX_METAL_FRAME_BYTES (8u * 1024u * 1024u)

typedef enum DtrStatus {
  DTR_STATUS_OK = 0,
  DTR_STATUS_INVALID_ARGUMENT = 1,
  DTR_STATUS_UNSUPPORTED_VERSION = 2,
  DTR_STATUS_NOT_FOUND = 3,
  DTR_STATUS_RESOURCE_EXHAUSTED = 4,
  DTR_STATUS_INVALID_HANDLE = 5,
  DTR_STATUS_INTERNAL = 6,
  DTR_STATUS_BUFFER_TOO_SMALL = 7,
  DTR_STATUS_STALE_GENERATION = 8,
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

enum {
  DTR_SHAPE_FEATURE_LIGATURES = 1u << 0,
  DTR_SHAPE_FEATURE_KNOWN_MASK = DTR_SHAPE_FEATURE_LIGATURES,
};

enum {
  DTR_SHAPED_RUN_FALLBACK = DTR_RESOLVED_FONT_FALLBACK,
  DTR_SHAPED_RUN_COLOR_GLYPHS = DTR_RESOLVED_FONT_COLOR_GLYPHS,
  DTR_SHAPED_RUN_SYNTHETIC = DTR_RESOLVED_FONT_SYNTHETIC,
  DTR_SHAPED_RUN_MISSING_GLYPH = DTR_RESOLVED_FONT_MISSING_GLYPH,
  DTR_SHAPED_RUN_MONOSPACED = DTR_RESOLVED_FONT_MONOSPACED,
  DTR_SHAPED_RUN_RIGHT_TO_LEFT = 1u << 5,
  DTR_SHAPED_RUN_KNOWN_MASK =
      DTR_RESOLVED_FONT_KNOWN_MASK | DTR_SHAPED_RUN_RIGHT_TO_LEFT,
};

enum {
  DTR_SHAPED_GLYPH_MISSING = 1u << 0,
  DTR_SHAPED_GLYPH_KNOWN_MASK = DTR_SHAPED_GLYPH_MISSING,
};

// Version-one packed shaping output. All integer and IEEE-754 fields use the
// native little-endian representation of supported macOS targets. Sections are
// contiguous in header, run, face, glyph order with no caller-owned pointer.
typedef struct DtrShapeHeaderV1 {
  uint32_t magic;
  uint32_t version;
  uint32_t header_size;
  uint32_t total_size;
  uint64_t catalog_generation;
  uint32_t requested_style;
  uint32_t feature_flags;
  uint32_t utf8_length;
  uint32_t utf16_length;
  uint32_t unicode_scalar_count;
  uint32_t run_count;
  uint32_t face_count;
  uint32_t glyph_count;
  uint32_t runs_offset;
  uint32_t faces_offset;
  uint32_t glyphs_offset;
  uint32_t reserved[3];
} DtrShapeHeaderV1;

typedef struct DtrShapeRunV1 {
  uint32_t face_id;
  uint32_t flags;
  uint32_t first_glyph;
  uint32_t glyph_count;
  uint32_t utf16_start;
  uint32_t utf16_length;
  double typographic_width;
  uint32_t reserved[2];
} DtrShapeRunV1;

typedef struct DtrShapeFaceV1 {
  uint32_t face_id;
  uint32_t flags;
  uint32_t postscript_name_length;
  uint32_t reserved;
  uint8_t postscript_name[DTR_MAX_POSTSCRIPT_NAME_BYTES + 1u];
} DtrShapeFaceV1;

typedef struct DtrShapeGlyphV1 {
  uint32_t glyph_id;
  uint32_t face_id;
  uint32_t run_index;
  uint32_t flags;
  uint32_t utf16_start;
  uint32_t utf16_length;
  double position_x;
  double position_y;
  double advance;
} DtrShapeGlyphV1;

typedef struct DtrRasterRequestV1 {
  uint32_t face_id;
  uint32_t glyph_id;
} DtrRasterRequestV1;

enum {
  DTR_RASTER_FORMAT_ALPHA8 = 1,
  DTR_RASTER_FORMAT_RGBA8_STRAIGHT = 2,
};

enum {
  DTR_RASTER_GLYPH_COLOR = 1u << 0,
  DTR_RASTER_GLYPH_MISSING = 1u << 1,
  DTR_RASTER_GLYPH_KNOWN_MASK =
      DTR_RASTER_GLYPH_COLOR | DTR_RASTER_GLYPH_MISSING,
};

typedef struct DtrRasterHeaderV1 {
  uint32_t magic;
  uint32_t version;
  uint32_t header_size;
  uint32_t total_size;
  uint64_t catalog_generation;
  uint32_t scale_16_16;
  uint32_t glyph_count;
  uint32_t records_offset;
  uint32_t pixels_offset;
  uint32_t pixel_bytes;
  uint32_t reserved[5];
} DtrRasterHeaderV1;

// origin_x is the left device-pixel bearing from the glyph position.
// origin_y is the top device-pixel bearing above the CoreText baseline.
// Pixel rows are tightly packed top-to-bottom.
typedef struct DtrRasterGlyphV1 {
  uint32_t face_id;
  uint32_t glyph_id;
  uint32_t format;
  uint32_t flags;
  int32_t origin_x;
  int32_t origin_y;
  uint32_t width;
  uint32_t height;
  uint32_t row_stride;
  uint32_t pixels_offset;
  uint32_t pixel_length;
  uint32_t reserved;
} DtrRasterGlyphV1;

enum {
  DTR_METAL_ATLAS_ALPHA8 = 1,
  DTR_METAL_ATLAS_RGBA8_STRAIGHT = 2,
};

enum {
  DTR_METAL_INSTANCE_CELL_BACKGROUND = 1,
  DTR_METAL_INSTANCE_SELECTION = 2,
  DTR_METAL_INSTANCE_ALPHA_GLYPH = 3,
  DTR_METAL_INSTANCE_COLOR_GLYPH = 4,
  DTR_METAL_INSTANCE_DECORATION = 5,
  DTR_METAL_INSTANCE_CURSOR = 6,
};

typedef struct DtrMetalRendererConfigV1 {
  uint32_t struct_size;
  uint32_t version;
  uint32_t maximum_viewport_width;
  uint32_t maximum_viewport_height;
  uint32_t maximum_instances;
  uint32_t atlas_width;
  uint32_t atlas_height;
  uint32_t maximum_alpha_pages;
  uint32_t maximum_color_pages;
  uint32_t reserved[3];
} DtrMetalRendererConfigV1;

typedef struct DtrMetalRendererSummaryV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t handle;
  uint64_t generation;
  uint32_t maximum_viewport_width;
  uint32_t maximum_viewport_height;
  uint32_t maximum_instances;
  uint32_t atlas_width;
  uint32_t atlas_height;
  uint32_t maximum_alpha_pages;
  uint32_t maximum_color_pages;
  uint32_t reserved[3];
} DtrMetalRendererSummaryV1;

typedef struct DtrMetalAtlasUploadV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t renderer_generation;
  uint64_t atlas_generation;
  uint64_t page_generation;
  uint32_t format;
  uint32_t page_index;
  uint32_t x;
  uint32_t y;
  uint32_t width;
  uint32_t height;
  uint32_t row_stride;
  uint32_t byte_length;
  uint32_t reserved[4];
} DtrMetalAtlasUploadV1;

// Version-one packed frame. Coordinates and sizes are device pixels in a
// flipped top-left viewport. Instances are contiguous and ordered by terminal
// layer. Colors are straight-alpha 0xRRGGBBAA.
typedef struct DtrMetalFrameHeaderV1 {
  uint32_t magic;
  uint32_t version;
  uint32_t header_size;
  uint32_t total_size;
  uint64_t renderer_generation;
  uint64_t frame_generation;
  uint64_t atlas_generation;
  uint32_t viewport_width;
  uint32_t viewport_height;
  uint32_t scale_16_16;
  uint32_t background_rgba;
  uint32_t instance_count;
  uint32_t instance_stride;
  uint32_t instances_offset;
  uint32_t reserved[3];
} DtrMetalFrameHeaderV1;

typedef struct DtrMetalInstanceV1 {
  int32_t x;
  int32_t y;
  uint32_t width;
  uint32_t height;
  uint32_t atlas_x;
  uint32_t atlas_y;
  uint32_t atlas_width;
  uint32_t atlas_height;
  uint32_t color_rgba;
  uint32_t kind;
  uint32_t page_index;
  uint32_t page_generation;
} DtrMetalInstanceV1;

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

// Shapes one complete UTF-8 run. A null output with zero capacity is a size
// query and returns DTR_STATUS_BUFFER_TOO_SMALL with output_required set. If a
// supplied buffer is too small, no partial output is written. No pointer is
// retained after return.
__attribute__((visibility("default"))) int32_t dtr_font_catalog_shape(
    uint64_t handle, uint32_t style, uint32_t feature_flags,
    const uint8_t* text_utf8, uint32_t text_length, uint8_t* output,
    uint32_t output_capacity, uint32_t* output_required);

// Rasterizes a unique glyph set in request order at an exact unsigned 16.16
// pixels-per-point scale. Null output with zero capacity is a size query. The
// call retains no request/output pointer and publishes no partial output.
__attribute__((visibility("default"))) int32_t dtr_font_catalog_rasterize(
    uint64_t handle, uint32_t scale_16_16,
    const DtrRasterRequestV1* requests, uint32_t request_count,
    uint8_t* output, uint32_t output_capacity, uint32_t* output_required);

__attribute__((visibility("default"))) int32_t
dtr_debug_live_font_catalog_count(void);

// Creates a generation-owned Metal resource set. Pipeline/library and bounded
// texture arrays are initialized before success is published. The caller owns
// exactly one returned handle and must release it once.
__attribute__((visibility("default"))) int32_t dtr_metal_renderer_create(
    const DtrMetalRendererConfigV1* config,
    DtrMetalRendererSummaryV1* output);

__attribute__((visibility("default"))) int32_t
dtr_metal_renderer_release(uint64_t handle);

// NativeFinalizer-compatible fallback. The pointer value is the opaque handle;
// it is never dereferenced. Explicit release remains the deterministic path.
__attribute__((visibility("default"))) void
dtr_metal_renderer_release_finalizer(void* handle);

// Copies one tightly packed dirty rectangle into a bounded atlas texture
// slice. No pointer is retained. Higher atlas/page generations clear stale
// texture contents before the new definition is published.
__attribute__((visibility("default"))) int32_t dtr_metal_renderer_upload_atlas(
    uint64_t handle, const DtrMetalAtlasUploadV1* upload,
    const uint8_t* pixels);

// Synchronous offscreen correctness/readback path. A null output with zero
// capacity is a size query. Production drawable submission remains a later
// ABI; this call retains no input/output pointer and never publishes partial
// output.
__attribute__((visibility("default"))) int32_t dtr_metal_renderer_render_rgba(
    uint64_t handle, const uint8_t* frame, uint32_t frame_length,
    uint8_t* output, uint32_t output_capacity, uint32_t* output_required);

__attribute__((visibility("default"))) int32_t
dtr_debug_live_metal_renderer_count(void);

#if defined(__cplusplus)
}
#endif

#endif  // DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_
