#include "CustomViewRegistry.h"

#include "BridgeInternal.h"
#include "dart_appkit_custom_view.h"

namespace dart_appkit {
namespace {

NSMutableDictionary<NSString*, id>* g_custom_view_classes = nil;

NSMutableDictionary<NSString*, id>* CustomViewClasses() {
  if (g_custom_view_classes == nil) {
    g_custom_view_classes = [[NSMutableDictionary alloc] init];
  }
  return g_custom_view_classes;
}

}  // namespace

int32_t RegisterCustomViewClass(NSString* provider_identifier,
                                Class view_class) {
  ClearLastError();
  const int32_t thread_status = RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (provider_identifier == nil || provider_identifier.length == 0) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "custom view provider identifier must not be empty");
  }
  if (view_class == Nil || ![view_class isSubclassOfClass:NSView.class]) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "custom view provider class must inherit NSView");
  }

  NSString* copied_identifier = [provider_identifier copy];
  id existing = CustomViewClasses()[copied_identifier];
  if (existing != nil && existing != view_class) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "custom view provider identifier is already registered");
  }
  CustomViewClasses()[copied_identifier] = view_class;
  return DA_STATUS_OK;
}

NSView* CreateRegisteredCustomView(NSString* provider_identifier,
                                   int32_t* out_status) {
  if (out_status == nullptr) {
    SetLastError(DA_STATUS_INVALID_ARGUMENT,
                 "custom view creation requires an output status");
    return nil;
  }
  *out_status = DA_STATUS_OK;
  if (provider_identifier == nil || provider_identifier.length == 0) {
    *out_status =
        SetLastError(DA_STATUS_INVALID_ARGUMENT,
                     "custom view provider identifier must not be empty");
    return nil;
  }
  Class view_class =
      static_cast<Class>(CustomViewClasses()[provider_identifier]);
  if (view_class == Nil) {
    *out_status = SetLastError(DA_STATUS_INVALID_ARGUMENT,
                               "custom view provider is not registered");
    return nil;
  }
  NSView* view = [[view_class alloc] initWithFrame:NSZeroRect];
  if (view == nil) {
    *out_status = SetLastError(DA_STATUS_INTERNAL_ERROR,
                               "custom view provider returned no view");
    return nil;
  }
  return view;
}

void ClearCustomViewClassesForTesting() {
  [g_custom_view_classes removeAllObjects];
  g_custom_view_classes = nil;
}

}  // namespace dart_appkit
