#ifndef DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_
#define DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_

#include <stdint.h>

#include "dart_appkit_native_extension.h"

#define DTR_ABI_VERSION 1u

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t dtr_abi_version(void);

__attribute__((visibility("default"))) int32_t
dtr_initialize(const da_native_extension_services_v1* services);

__attribute__((visibility("default"))) int32_t dtr_debug_live_view_count(void);

#if defined(__cplusplus)
}
#endif

#endif  // DART_TERMINAL_RENDERER_MACOS_NATIVE_TERMINAL_RENDERER_PLUGIN_H_
