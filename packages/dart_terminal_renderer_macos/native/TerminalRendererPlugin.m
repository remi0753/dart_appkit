#import <MetalKit/MetalKit.h>

#include "TerminalRendererPlugin.h"

#include <stdatomic.h>
#include <string.h>

static const char kProviderIdentifier[] = "dart_terminal.TerminalMetalView";
static _Atomic int32_t g_live_view_count = 0;
static const da_native_extension_services_v1* g_initialized_services = NULL;

@interface DtrTerminalMetalView : MTKView
@end

@implementation DtrTerminalMetalView

- (instancetype)initWithFrame:(NSRect)frame {
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device == nil) {
    return nil;
  }
  self = [super initWithFrame:frame device:device];
  if (self != nil) {
    atomic_fetch_add_explicit(&g_live_view_count, 1, memory_order_relaxed);
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.autoResizeDrawable = YES;
    self.paused = YES;
    self.enableSetNeedsDisplay = YES;
    self.framebufferOnly = YES;
    self.delegate = nil;
  }
  return self;
}

- (void)dealloc {
  atomic_fetch_sub_explicit(&g_live_view_count, 1, memory_order_relaxed);
}

- (BOOL)isFlipped {
  return YES;
}

@end

static void* CreateTerminalMetalView(void* context) {
  (void)context;
  NSView* view = [[DtrTerminalMetalView alloc] initWithFrame:NSZeroRect];
  return (__bridge_retained void*)view;
}

uint32_t dtr_abi_version(void) { return DTR_ABI_VERSION; }

int32_t dtr_initialize(const da_native_extension_services_v1* services) {
  if (services == NULL ||
      services->struct_size < sizeof(da_native_extension_services_v1) ||
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
      CreateTerminalMetalView, NULL);
  if (status == DA_STATUS_OK) {
    g_initialized_services = services;
  }
  return status;
}

int32_t dtr_debug_live_view_count(void) {
  return atomic_load_explicit(&g_live_view_count, memory_order_relaxed);
}
