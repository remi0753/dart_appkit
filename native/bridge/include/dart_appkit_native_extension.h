#ifndef DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_NATIVE_EXTENSION_H_
#define DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_NATIVE_EXTENSION_H_

#include <stddef.h>
#include <stdint.h>

#include "dart_appkit.h"

#define DA_NATIVE_EXTENSION_ABI_VERSION 1u

#if defined(__cplusplus)
extern "C" {
#endif

// Returns a retained Objective-C NSView as an opaque pointer, or null on
// construction failure. The host consumes the retain on return. This callback
// is invoked only on the AppKit process main thread.
typedef void* (*da_custom_view_factory_v1)(void* context);

typedef int32_t (*da_register_custom_view_provider_v1)(
    const uint8_t* provider_identifier, size_t provider_identifier_length,
    da_custom_view_factory_v1 factory, void* context);

typedef struct da_native_extension_services_v1 {
  size_t struct_size;
  uint32_t abi_version;
  da_register_custom_view_provider_v1 register_custom_view_provider;
} da_native_extension_services_v1;

// AppKit main thread only. The returned process-owned table remains valid until
// process exit. Unsupported versions return null and set da_get_last_error().
DA_EXPORT const da_native_extension_services_v1* da_native_extension_services(
    uint32_t requested_abi_version);

#if defined(__cplusplus)
}
#endif

#endif  // DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_NATIVE_EXTENSION_H_
