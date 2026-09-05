#import <MetalKit/MetalKit.h>
#import <CoreText/CoreText.h>

#include "TerminalRendererPlugin.h"

#include <stdatomic.h>
#include <math.h>
#include <string.h>

static const char kProviderIdentifier[] = "dart_terminal.TerminalMetalView";
static _Atomic int32_t g_live_view_count = 0;
static _Atomic uint64_t g_next_font_catalog_handle = 1;
static const da_native_extension_services_v1* g_initialized_services = NULL;

@interface DtrFontCatalog : NSObject

@property(nonatomic, readonly) uint64_t generation;
@property(nonatomic, readonly) double pointSize;
@property(nonatomic, readonly) NSArray* fonts;
@property(nonatomic, readonly) uint32_t availableStyleBits;
@property(nonatomic, readonly) uint32_t syntheticStyleBits;

- (instancetype)initWithFamily:(NSString*)family
                      pointSize:(double)pointSize
                    generation:(uint64_t)generation
                   policyFlags:(uint32_t)policyFlags;
- (NSFont*)fontForStyle:(uint32_t)style synthetic:(BOOL*)synthetic;
- (uint32_t)faceIdForFont:(NSFont*)font;
- (uint32_t)faceIdForStyle:(uint32_t)style;
- (BOOL)fillSummary:(DtrFontCatalogSummaryV1*)output handle:(uint64_t)handle;

@end

static NSLock* FontCatalogRegistryLock(void) {
  static NSLock* lock;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    lock = [[NSLock alloc] init];
  });
  return lock;
}

static NSMutableDictionary<NSNumber*, DtrFontCatalog*>*
FontCatalogRegistry(void) {
  static NSMutableDictionary<NSNumber*, DtrFontCatalog*>* registry;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    registry = [[NSMutableDictionary alloc] init];
  });
  return registry;
}

static NSFont* CreateRequestedFont(NSString* family, double point_size) {
  if (family.length == 0) {
    return [NSFont monospacedSystemFontOfSize:point_size
                                      weight:NSFontWeightRegular];
  }
  NSFont* font = [NSFont fontWithName:family size:point_size];
  if (font != nil) {
    return font;
  }
  return [[NSFontManager sharedFontManager]
      fontWithFamily:family
              traits:0
              weight:5
                size:point_size];
}

static NSFont* CreateTraitFont(NSFont* regular, CTFontSymbolicTraits traits) {
  CTFontRef result = CTFontCreateCopyWithSymbolicTraits(
      (__bridge CTFontRef)regular, regular.pointSize, NULL, traits, traits);
  return result == NULL ? nil : CFBridgingRelease(result);
}

static NSString* PostScriptName(NSFont* font) {
  CFStringRef name = CTFontCopyPostScriptName((__bridge CTFontRef)font);
  return name == NULL ? @"" : CFBridgingRelease(name);
}

@implementation DtrFontCatalog {
  NSLock* _faceLock;
  NSMutableDictionary<NSString*, NSNumber*>* _faceIds;
  uint32_t _nextFaceId;
}

- (instancetype)initWithFamily:(NSString*)family
                      pointSize:(double)pointSize
                    generation:(uint64_t)generation
                   policyFlags:(uint32_t)policyFlags {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  NSFont* regular = CreateRequestedFont(family, pointSize);
  if (regular == nil) {
    return nil;
  }
  NSMutableArray* fonts = [[NSMutableArray alloc] initWithCapacity:4];
  [fonts addObject:regular];
  uint32_t available = DTR_FONT_STYLE_BIT_REGULAR;
  uint32_t synthetic = 0;
  const CTFontSymbolicTraits requested_traits[3] = {
      kCTFontBoldTrait,
      kCTFontItalicTrait,
      kCTFontBoldTrait | kCTFontItalicTrait,
  };
  for (uint32_t index = 0; index < 3; index++) {
    NSFont* font = CreateTraitFont(regular, requested_traits[index]);
    const uint32_t style = index + 1;
    if (font != nil) {
      available |= 1u << style;
      [fonts addObject:font];
    } else if ((policyFlags & DTR_FONT_POLICY_ALLOW_SYNTHETIC) != 0) {
      synthetic |= 1u << style;
      [fonts addObject:regular];
    } else {
      [fonts addObject:[NSNull null]];
    }
  }
  _generation = generation;
  _pointSize = pointSize;
  _fonts = [fonts copy];
  _availableStyleBits = available;
  _syntheticStyleBits = synthetic;
  _faceLock = [[NSLock alloc] init];
  _faceIds = [[NSMutableDictionary alloc] init];
  _nextFaceId = 1;
  for (id candidate in _fonts) {
    if (candidate != [NSNull null]) {
      [self faceIdForFont:(NSFont*)candidate];
    }
  }
  return self;
}

- (NSFont*)fontForStyle:(uint32_t)style synthetic:(BOOL*)synthetic {
  if (style > DTR_FONT_STYLE_BOLD_ITALIC) {
    return nil;
  }
  id candidate = self.fonts[style];
  if (candidate == [NSNull null]) {
    return nil;
  }
  if (synthetic != NULL) {
    *synthetic = (self.syntheticStyleBits & (1u << style)) != 0;
  }
  return (NSFont*)candidate;
}

- (uint32_t)faceIdForFont:(NSFont*)font {
  NSString* name = PostScriptName(font);
  [_faceLock lock];
  NSNumber* existing = _faceIds[name];
  if (existing != nil) {
    [_faceLock unlock];
    return existing.unsignedIntValue;
  }
  const uint32_t identifier = _nextFaceId++;
  _faceIds[name] = @(identifier);
  [_faceLock unlock];
  return identifier;
}

- (uint32_t)faceIdForStyle:(uint32_t)style {
  NSFont* font = [self fontForStyle:style synthetic:NULL];
  return font == nil ? 0 : [self faceIdForFont:font];
}

- (BOOL)fillSummary:(DtrFontCatalogSummaryV1*)output handle:(uint64_t)handle {
  NSFont* regular = [self fontForStyle:DTR_FONT_STYLE_REGULAR synthetic:NULL];
  CTFontRef font = (__bridge CTFontRef)regular;
  UniChar character = 'M';
  CGGlyph glyph = 0;
  CGSize advance = CGSizeZero;
  if (!CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) ||
      glyph == 0 || CTFontGetAdvancesForGlyphs(
                        font, kCTFontOrientationHorizontal, &glyph, &advance,
                        1) <= 0) {
    return NO;
  }
  const double ascent = CTFontGetAscent(font);
  const double descent = CTFontGetDescent(font);
  const double leading = CTFontGetLeading(font);
  const double cell_width = ceil(advance.width * 64.0) / 64.0;
  const double cell_height = ceil((ascent + descent + leading) * 64.0) / 64.0;
  const double underline_position = CTFontGetUnderlinePosition(font);
  const double underline_thickness = CTFontGetUnderlineThickness(font);
  const double strike_thickness =
      underline_thickness > 1.0 / 64.0 ? underline_thickness : 1.0 / 64.0;
  const double values[] = {
      self.pointSize,
      cell_width,
      cell_height,
      ascent,
      descent,
      leading,
      ascent,
      underline_position,
      underline_thickness,
      ascent * 0.35,
      strike_thickness,
  };
  for (size_t index = 0; index < sizeof(values) / sizeof(values[0]); index++) {
    if (!isfinite(values[index])) {
      return NO;
    }
  }
  if (values[0] <= 0.0 || values[1] <= 0.0 || values[2] <= 0.0 ||
      values[3] <= 0.0 || values[4] <= 0.0 || values[5] < 0.0 ||
      values[6] <= 0.0 || values[8] <= 0.0 || values[9] <= 0.0 ||
      values[10] <= 0.0) {
    return NO;
  }
  output->handle = handle;
  output->generation = self.generation;
  output->point_size = values[0];
  output->cell_width = values[1];
  output->cell_height = values[2];
  output->ascent = values[3];
  output->descent = values[4];
  output->leading = values[5];
  output->baseline = values[6];
  output->underline_position = values[7];
  output->underline_thickness = values[8];
  output->strike_position = values[9];
  output->strike_thickness = values[10];
  output->available_style_bits = self.availableStyleBits;
  output->synthetic_style_bits = self.syntheticStyleBits;
  output->regular_face_id = [self faceIdForStyle:DTR_FONT_STYLE_REGULAR];
  output->bold_face_id = [self faceIdForStyle:DTR_FONT_STYLE_BOLD];
  output->italic_face_id = [self faceIdForStyle:DTR_FONT_STYLE_ITALIC];
  output->bold_italic_face_id =
      [self faceIdForStyle:DTR_FONT_STYLE_BOLD_ITALIC];
  return YES;
}

@end

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

static int32_t PrepareFontCatalogSummary(DtrFontCatalogSummaryV1* output) {
  if (output == NULL) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  if (output->struct_size < sizeof(DtrFontCatalogSummaryV1) ||
      output->version != DTR_FONT_CATALOG_SUMMARY_VERSION) {
    return DTR_STATUS_UNSUPPORTED_VERSION;
  }
  memset(output, 0, sizeof(DtrFontCatalogSummaryV1));
  output->struct_size = sizeof(DtrFontCatalogSummaryV1);
  output->version = DTR_FONT_CATALOG_SUMMARY_VERSION;
  return DTR_STATUS_OK;
}

static int32_t PrepareResolvedFont(DtrResolvedFontV1* output) {
  if (output == NULL) {
    return DTR_STATUS_INVALID_ARGUMENT;
  }
  if (output->struct_size < sizeof(DtrResolvedFontV1) ||
      output->version != DTR_RESOLVED_FONT_VERSION) {
    return DTR_STATUS_UNSUPPORTED_VERSION;
  }
  memset(output, 0, sizeof(DtrResolvedFontV1));
  output->struct_size = sizeof(DtrResolvedFontV1);
  output->version = DTR_RESOLVED_FONT_VERSION;
  return DTR_STATUS_OK;
}

static NSString* DecodeUtf8(const uint8_t* bytes, uint32_t length,
                            BOOL allow_empty) {
  if (length == 0) {
    return allow_empty ? @"" : nil;
  }
  if (bytes == NULL || memchr(bytes, 0, length) != NULL) {
    return nil;
  }
  return [[NSString alloc] initWithBytes:bytes
                                  length:length
                                encoding:NSUTF8StringEncoding];
}

static DtrFontCatalog* FontCatalogForHandle(uint64_t handle) {
  if (handle == 0) {
    return nil;
  }
  NSLock* lock = FontCatalogRegistryLock();
  [lock lock];
  DtrFontCatalog* catalog = FontCatalogRegistry()[@(handle)];
  [lock unlock];
  return catalog;
}

static uint32_t UnicodeScalarCount(NSString* text) {
  const NSUInteger length = text.length;
  uint32_t count = 0;
  for (NSUInteger index = 0; index < length; index++) {
    const unichar current = [text characterAtIndex:index];
    if (CFStringIsSurrogateHighCharacter(current) && index + 1 < length &&
        CFStringIsSurrogateLowCharacter([text characterAtIndex:index + 1])) {
      index++;
    }
    count++;
  }
  return count;
}

int32_t dtr_font_catalog_create(const uint8_t* family_utf8,
                                uint32_t family_length, double point_size,
                                uint32_t policy_flags,
                                DtrFontCatalogSummaryV1* output) {
  @autoreleasepool {
    const int32_t output_status = PrepareFontCatalogSummary(output);
    if (output_status != DTR_STATUS_OK) {
      return output_status;
    }
    if (family_length > DTR_MAX_FONT_FAMILY_BYTES ||
        (policy_flags & ~DTR_FONT_POLICY_KNOWN_MASK) != 0 ||
        !isfinite(point_size) || point_size < 4.0 || point_size > 128.0) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    NSString* family = DecodeUtf8(family_utf8, family_length, YES);
    if (family == nil) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    const uint64_t handle = atomic_fetch_add_explicit(
        &g_next_font_catalog_handle, 1, memory_order_relaxed);
    if (handle == 0 || handle == UINT64_MAX) {
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    DtrFontCatalog* catalog =
        [[DtrFontCatalog alloc] initWithFamily:family
                                    pointSize:point_size
                                  generation:handle
                                 policyFlags:policy_flags];
    if (catalog == nil) {
      return DTR_STATUS_NOT_FOUND;
    }
    if (![catalog fillSummary:output handle:handle]) {
      return DTR_STATUS_INTERNAL;
    }
    NSLock* lock = FontCatalogRegistryLock();
    [lock lock];
    FontCatalogRegistry()[@(handle)] = catalog;
    [lock unlock];
    return DTR_STATUS_OK;
  }
}

int32_t dtr_font_catalog_release(uint64_t handle) {
  @autoreleasepool {
    if (handle == 0) {
      return DTR_STATUS_INVALID_HANDLE;
    }
    NSLock* lock = FontCatalogRegistryLock();
    [lock lock];
    NSNumber* key = @(handle);
    DtrFontCatalog* catalog = FontCatalogRegistry()[key];
    if (catalog != nil) {
      [FontCatalogRegistry() removeObjectForKey:key];
    }
    [lock unlock];
    return catalog == nil ? DTR_STATUS_INVALID_HANDLE : DTR_STATUS_OK;
  }
}

void dtr_font_catalog_release_finalizer(void* handle) {
  (void)dtr_font_catalog_release((uint64_t)(uintptr_t)handle);
}

int32_t dtr_font_catalog_resolve(uint64_t handle, uint32_t style,
                                 const uint8_t* text_utf8,
                                 uint32_t text_length,
                                 DtrResolvedFontV1* output) {
  @autoreleasepool {
    const int32_t output_status = PrepareResolvedFont(output);
    if (output_status != DTR_STATUS_OK) {
      return output_status;
    }
    if (style > DTR_FONT_STYLE_BOLD_ITALIC || text_length == 0 ||
        text_length > DTR_MAX_RESOLVE_TEXT_BYTES) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    NSString* text = DecodeUtf8(text_utf8, text_length, NO);
    if (text == nil) {
      return DTR_STATUS_INVALID_ARGUMENT;
    }
    DtrFontCatalog* catalog = FontCatalogForHandle(handle);
    if (catalog == nil) {
      return DTR_STATUS_INVALID_HANDLE;
    }
    BOOL synthetic = NO;
    NSFont* requested_font = [catalog fontForStyle:style synthetic:&synthetic];
    if (requested_font == nil) {
      return DTR_STATUS_NOT_FOUND;
    }
    NSDictionary* attributes = @{
      (__bridge NSString*)kCTFontAttributeName : requested_font,
      (__bridge NSString*)kCTLigatureAttributeName : @1,
    };
    NSAttributedString* attributed =
        [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString(
        (__bridge CFAttributedStringRef)attributed);
    if (line == NULL) {
      return DTR_STATUS_INTERNAL;
    }
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    const CFIndex run_count = runs == NULL ? 0 : CFArrayGetCount(runs);
    if (run_count <= 0) {
      CFRelease(line);
      return DTR_STATUS_INTERNAL;
    }
    CTRunRef first_run = (CTRunRef)CFArrayGetValueAtIndex(runs, 0);
    CFDictionaryRef run_attributes = CTRunGetAttributes(first_run);
    CTFontRef resolved_font = (CTFontRef)CFDictionaryGetValue(
        run_attributes, kCTFontAttributeName);
    if (resolved_font == NULL) {
      CFRelease(line);
      return DTR_STATUS_INTERNAL;
    }
    NSFont* resolved = (__bridge NSFont*)resolved_font;
    uint64_t total_glyphs = 0;
    BOOL missing = NO;
    for (CFIndex run_index = 0; run_index < run_count; run_index++) {
      CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, run_index);
      const CFIndex glyph_count = CTRunGetGlyphCount(run);
      if (glyph_count < 0 || total_glyphs + (uint64_t)glyph_count > UINT32_MAX) {
        CFRelease(line);
        return DTR_STATUS_RESOURCE_EXHAUSTED;
      }
      total_glyphs += (uint64_t)glyph_count;
      CGGlyph glyphs[256];
      for (CFIndex start = 0; start < glyph_count; start += 256) {
        const CFIndex remaining = glyph_count - start;
        const CFIndex count = remaining < 256 ? remaining : 256;
        CTRunGetGlyphs(run, CFRangeMake(start, count), glyphs);
        for (CFIndex index = 0; index < count; index++) {
          if (glyphs[index] == 0) {
            missing = YES;
          }
        }
      }
    }
    NSString* resolved_name = PostScriptName(resolved);
    NSData* resolved_name_utf8 =
        [resolved_name dataUsingEncoding:NSUTF8StringEncoding];
    if (resolved_name_utf8 == nil ||
        resolved_name_utf8.length > DTR_MAX_POSTSCRIPT_NAME_BYTES) {
      CFRelease(line);
      return DTR_STATUS_RESOURCE_EXHAUSTED;
    }
    uint32_t flags = 0;
    if (![resolved_name isEqualToString:PostScriptName(requested_font)]) {
      flags |= DTR_RESOLVED_FONT_FALLBACK;
    }
    const CTFontSymbolicTraits traits = CTFontGetSymbolicTraits(resolved_font);
    if ((traits & kCTFontColorGlyphsTrait) != 0) {
      flags |= DTR_RESOLVED_FONT_COLOR_GLYPHS;
    }
    if ((traits & kCTFontMonoSpaceTrait) != 0) {
      flags |= DTR_RESOLVED_FONT_MONOSPACED;
    }
    if (synthetic) {
      flags |= DTR_RESOLVED_FONT_SYNTHETIC;
    }
    if (missing) {
      flags |= DTR_RESOLVED_FONT_MISSING_GLYPH;
    }
    output->catalog_generation = catalog.generation;
    output->face_id = [catalog faceIdForFont:resolved];
    output->flags = flags;
    output->requested_style = style;
    output->utf16_length = (uint32_t)text.length;
    output->unicode_scalar_count = UnicodeScalarCount(text);
    output->glyph_count = (uint32_t)total_glyphs;
    output->postscript_name_length = (uint32_t)resolved_name_utf8.length;
    memcpy(output->postscript_name, resolved_name_utf8.bytes,
           resolved_name_utf8.length);
    output->postscript_name[resolved_name_utf8.length] = 0;
    CFRelease(line);
    return DTR_STATUS_OK;
  }
}

int32_t dtr_debug_live_font_catalog_count(void) {
  @autoreleasepool {
    NSLock* lock = FontCatalogRegistryLock();
    [lock lock];
    const NSUInteger count = FontCatalogRegistry().count;
    [lock unlock];
    return count > INT32_MAX ? INT32_MAX : (int32_t)count;
  }
}
