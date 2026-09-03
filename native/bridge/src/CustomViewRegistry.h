#ifndef DART_APPKIT_BRIDGE_SRC_CUSTOM_VIEW_REGISTRY_H_
#define DART_APPKIT_BRIDGE_SRC_CUSTOM_VIEW_REGISTRY_H_

#import <AppKit/AppKit.h>

#include <cstdint>

namespace dart_appkit {

NSView* CreateRegisteredCustomView(NSString* provider_identifier,
                                   int32_t* out_status);
void ClearCustomViewClassesForTesting();

}  // namespace dart_appkit

#endif  // DART_APPKIT_BRIDGE_SRC_CUSTOM_VIEW_REGISTRY_H_
