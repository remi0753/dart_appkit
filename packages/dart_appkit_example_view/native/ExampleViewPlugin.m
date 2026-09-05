#import <AppKit/AppKit.h>

#include "ExampleViewPlugin.h"

#include <stdatomic.h>
#include <string.h>

static const char kProviderIdentifier[] = "dev.dart-appkit.example-view";
static _Atomic int32_t g_live_view_count = 0;
static const da_native_extension_services_v1* g_initialized_services = NULL;

@interface DaExampleCapabilityView : NSView
@end

@implementation DaExampleCapabilityView

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self != nil) {
    atomic_fetch_add_explicit(&g_live_view_count, 1, memory_order_relaxed);
    self.wantsLayer = YES;
  }
  return self;
}

- (void)dealloc {
  atomic_fetch_sub_explicit(&g_live_view_count, 1, memory_order_relaxed);
}

- (BOOL)isFlipped {
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [[NSColor colorWithRed:0.10 green:0.12 blue:0.17 alpha:1.0] setFill];
  NSRectFill(self.bounds);
  NSDictionary<NSAttributedStringKey, id>* attributes = @{
    NSFontAttributeName :
        [NSFont monospacedSystemFontOfSize:22.0 weight:NSFontWeightMedium],
    NSForegroundColorAttributeName : [NSColor colorWithRed:0.48
                                                     green:0.82
                                                      blue:1.0
                                                     alpha:1.0],
  };
  [@"Hello from a dependency-owned native capability"
         drawAtPoint:NSMakePoint(28.0, 28.0)
      withAttributes:attributes];
}

@end

static void* CreateExampleView(void* context) {
  (void)context;
  NSView* view = [[DaExampleCapabilityView alloc] initWithFrame:NSZeroRect];
  return (__bridge_retained void*)view;
}

uint32_t daev_abi_version(void) { return DAEV_ABI_VERSION; }

int32_t daev_initialize(const da_native_extension_services_v1* services) {
  if (services == NULL ||
      services->struct_size <
          offsetof(da_native_extension_services_v1,
                   register_custom_view_operation) ||
      services->abi_version != DA_NATIVE_EXTENSION_ABI_VERSION ||
      services->register_custom_view_provider == NULL) {
    return DA_STATUS_UNSUPPORTED_VERSION;
  }
  if (g_initialized_services != NULL) {
    return g_initialized_services == services ? DA_STATUS_OK
                                              : DA_STATUS_INVALID_ARGUMENT;
  }
  const int32_t status = services->register_custom_view_provider(
      (const uint8_t*)kProviderIdentifier, strlen(kProviderIdentifier),
      CreateExampleView, NULL);
  if (status == DA_STATUS_OK) {
    g_initialized_services = services;
  }
  return status;
}

int32_t daev_debug_live_view_count(void) {
  return atomic_load_explicit(&g_live_view_count, memory_order_relaxed);
}
