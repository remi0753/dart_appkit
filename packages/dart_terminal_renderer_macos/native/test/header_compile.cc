#include <type_traits>

#include "TerminalRendererPlugin.h"

static_assert(std::is_standard_layout_v<da_native_extension_services_v1>);
static_assert(std::is_standard_layout_v<DtrFontCatalogSummaryV1>);
static_assert(std::is_standard_layout_v<DtrResolvedFontV1>);
static_assert(sizeof(DtrFontCatalogSummaryV1) == 152);
static_assert(sizeof(DtrResolvedFontV1) == 192);

int main() {
  auto* version = &dtr_abi_version;
  auto* initialize = &dtr_initialize;
  auto* live_count = &dtr_debug_live_view_count;
  auto* catalog_create = &dtr_font_catalog_create;
  auto* catalog_release = &dtr_font_catalog_release;
  auto* catalog_finalizer = &dtr_font_catalog_release_finalizer;
  auto* catalog_resolve = &dtr_font_catalog_resolve;
  auto* catalog_count = &dtr_debug_live_font_catalog_count;
  return version == nullptr || initialize == nullptr || live_count == nullptr ||
         catalog_create == nullptr || catalog_release == nullptr ||
         catalog_finalizer == nullptr || catalog_resolve == nullptr ||
         catalog_count == nullptr;
}
