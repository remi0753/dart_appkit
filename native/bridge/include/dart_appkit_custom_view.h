#ifndef DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_CUSTOM_VIEW_H_
#define DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_CUSTOM_VIEW_H_

#if !defined(__OBJC__) || !defined(__cplusplus)
#error "dart_appkit_custom_view.h requires Objective-C++"
#endif

#import <AppKit/AppKit.h>

#include "dart_appkit.h"

namespace dart_appkit {

/**
 * AppKit main thread only. Registers an NSView subclass under a copied name.
 *
 * Registering the same name/class pair again succeeds. Replacing an existing
 * name with a different class is rejected. Instances are later created with
 * initWithFrame: by da_view_create_custom.
 */
DA_EXPORT int32_t RegisterCustomViewClass(NSString* provider_identifier,
                                          Class view_class);

}  // namespace dart_appkit

#endif  // DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_CUSTOM_VIEW_H_
