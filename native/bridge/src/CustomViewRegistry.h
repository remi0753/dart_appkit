#ifndef DART_APPKIT_BRIDGE_SRC_CUSTOM_VIEW_REGISTRY_H_
#define DART_APPKIT_BRIDGE_SRC_CUSTOM_VIEW_REGISTRY_H_

#import <AppKit/AppKit.h>

#include <cstdint>

#include "dart_appkit_native_extension.h"

namespace dart_appkit {

NSView* CreateRegisteredCustomView(NSString* provider_identifier,
                                   int32_t* out_status);
int32_t RegisterCustomViewFactory(NSString* provider_identifier,
                                  da_custom_view_factory_v1 factory,
                                  void* context);
void ClearCustomViewClassesForTesting();

}  // namespace dart_appkit

#endif  // DART_APPKIT_BRIDGE_SRC_CUSTOM_VIEW_REGISTRY_H_
