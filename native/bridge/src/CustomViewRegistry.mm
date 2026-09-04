#include "CustomViewRegistry.h"

#include "BridgeInternal.h"
#include "dart_appkit_custom_view.h"

@interface DaCustomViewProvider : NSObject

@property(nonatomic, assign) Class viewClass;
@property(nonatomic, assign) da_custom_view_factory_v1 factory;
@property(nonatomic, assign) void* context;

@end

@implementation DaCustomViewProvider
@end

namespace dart_appkit {
namespace {

NSMutableDictionary<NSString*, DaCustomViewProvider*>* g_custom_view_providers =
    nil;

NSMutableDictionary<NSString*, DaCustomViewProvider*>* CustomViewProviders() {
  if (g_custom_view_providers == nil) {
    g_custom_view_providers = [[NSMutableDictionary alloc] init];
  }
  return g_custom_view_providers;
}

int32_t RegisterFactoryBytes(const uint8_t* provider_identifier,
                             size_t provider_identifier_length,
                             da_custom_view_factory_v1 factory, void* context) {
  if (provider_identifier == nullptr || provider_identifier_length == 0) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "custom view provider identifier must not be empty");
  }
  NSString* identifier =
      [[NSString alloc] initWithBytes:provider_identifier
                               length:provider_identifier_length
                             encoding:NSUTF8StringEncoding];
  if (identifier == nil) {
    return SetLastError(DA_STATUS_INVALID_UTF8,
                        "custom view provider identifier is not valid UTF-8");
  }
  return RegisterCustomViewFactory(identifier, factory, context);
}

const da_native_extension_services_v1 kNativeExtensionServices = {
    .struct_size = sizeof(da_native_extension_services_v1),
    .abi_version = DA_NATIVE_EXTENSION_ABI_VERSION,
    .register_custom_view_provider = RegisterFactoryBytes,
};

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
  DaCustomViewProvider* existing = CustomViewProviders()[copied_identifier];
  if (existing != nil &&
      (existing.viewClass != view_class || existing.factory != nullptr)) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "custom view provider identifier is already registered");
  }
  if (existing == nil) {
    DaCustomViewProvider* provider = [[DaCustomViewProvider alloc] init];
    provider.viewClass = view_class;
    CustomViewProviders()[copied_identifier] = provider;
  }
  return DA_STATUS_OK;
}

int32_t RegisterCustomViewFactory(NSString* provider_identifier,
                                  da_custom_view_factory_v1 factory,
                                  void* context) {
  ClearLastError();
  const int32_t thread_status = RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return thread_status;
  }
  if (provider_identifier == nil || provider_identifier.length == 0 ||
      factory == nullptr) {
    return SetLastError(DA_STATUS_INVALID_ARGUMENT,
                        "custom view provider factory is incomplete");
  }
  NSString* copied_identifier = [provider_identifier copy];
  DaCustomViewProvider* existing = CustomViewProviders()[copied_identifier];
  if (existing != nil &&
      (existing.factory != factory || existing.context != context ||
       existing.viewClass != Nil)) {
    return SetLastError(
        DA_STATUS_INVALID_ARGUMENT,
        "custom view provider identifier is already registered");
  }
  if (existing == nil) {
    DaCustomViewProvider* provider = [[DaCustomViewProvider alloc] init];
    provider.factory = factory;
    provider.context = context;
    CustomViewProviders()[copied_identifier] = provider;
  }
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
  DaCustomViewProvider* provider = CustomViewProviders()[provider_identifier];
  if (provider == nil) {
    *out_status = SetLastError(DA_STATUS_INVALID_ARGUMENT,
                               "custom view provider is not registered");
    return nil;
  }
  NSView* view = nil;
  if (provider.viewClass != Nil) {
    view = [[provider.viewClass alloc] initWithFrame:NSZeroRect];
  } else {
    void* retained_view = provider.factory(provider.context);
    if (retained_view != nullptr) {
      view = (__bridge_transfer NSView*)retained_view;
    }
  }
  if (view == nil) {
    *out_status = SetLastError(DA_STATUS_INTERNAL_ERROR,
                               "custom view provider returned no view");
    return nil;
  }
  return view;
}

void ClearCustomViewClassesForTesting() {
  [g_custom_view_providers removeAllObjects];
  g_custom_view_providers = nil;
}

}  // namespace dart_appkit

extern "C" const da_native_extension_services_v1* da_native_extension_services(
    uint32_t requested_abi_version) {
  dart_appkit::ClearLastError();
  const int32_t thread_status = dart_appkit::RequireMainThread();
  if (thread_status != DA_STATUS_OK) {
    return nullptr;
  }
  if (requested_abi_version != DA_NATIVE_EXTENSION_ABI_VERSION) {
    dart_appkit::SetLastError(DA_STATUS_UNSUPPORTED_VERSION,
                              "native extension ABI version is unsupported");
    return nullptr;
  }
  return &dart_appkit::kNativeExtensionServices;
}
