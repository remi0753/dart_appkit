#include "TerminalRendererPlugin.h"

_Static_assert(sizeof(DtrFontCatalogSummaryV1) == 152,
               "font catalog summary ABI size");
_Static_assert(sizeof(DtrResolvedFontV1) == 192,
               "resolved font ABI size");
_Static_assert(sizeof(DtrShapeHeaderV1) == 80, "shape header ABI size");
_Static_assert(sizeof(DtrShapeRunV1) == 40, "shape run ABI size");
_Static_assert(sizeof(DtrShapeFaceV1) == 144, "shape face ABI size");
_Static_assert(sizeof(DtrShapeGlyphV1) == 48, "shape glyph ABI size");

int main(void) {
  uint32_t (*version)(void) = dtr_abi_version;
  int32_t (*initialize)(const da_native_extension_services_v1*) =
      dtr_initialize;
  int32_t (*live_count)(void) = dtr_debug_live_view_count;
  int32_t (*catalog_create)(const uint8_t*, uint32_t, double, uint32_t,
                            DtrFontCatalogSummaryV1*) =
      dtr_font_catalog_create;
  int32_t (*catalog_release)(uint64_t) = dtr_font_catalog_release;
  void (*catalog_finalizer)(void*) = dtr_font_catalog_release_finalizer;
  int32_t (*catalog_resolve)(uint64_t, uint32_t, const uint8_t*, uint32_t,
                             DtrResolvedFontV1*) = dtr_font_catalog_resolve;
  int32_t (*catalog_shape)(uint64_t, uint32_t, uint32_t, const uint8_t*,
                           uint32_t, uint8_t*, uint32_t, uint32_t*) =
      dtr_font_catalog_shape;
  int32_t (*catalog_count)(void) = dtr_debug_live_font_catalog_count;
  return version == 0 || initialize == 0 || live_count == 0 ||
         catalog_create == 0 || catalog_release == 0 ||
         catalog_finalizer == 0 || catalog_resolve == 0 ||
         catalog_shape == 0 || catalog_count == 0;
}
