# Text editor single background compositing

- Status: complete
- Date: 2026-09-16

## Purpose, scope and acceptance

An editor's configured background alpha must be composited once across its
viewport and padding, not multiplied by nested scroll, clip and text drawing.
Preserve text, caret, selection, marked text, explicit styles, scrolling,
resource identity and the opaque default. Do not change window policies or ABI.

Real native bitmap tests must cover empty and scrollable documents, padding,
alpha zero/intermediate/one and live transitions. Native/Dart/FFI and full gates
must pass. Caller-specific settings and workflows remain outside this library.

## Record and risks

- The current scroll view draws its background and the text view receives the
  same background. Native bitmap coverage is needed beyond color metadata.
- Use one stable background owner rather than changing a view-wide alpha;
  otherwise text and selection would fade too. Retain existing editor objects.
- Initial dirty changes are only the Engine building document and bootstrap/
  build scripts. They must be preserved and excluded from this work's commit.
- Bitmap capture must start transparent and avoid selection/scroller/glyph
  pixels. Padding and viewport samples must have the same alpha.
- The initial native bitmap regression failed on the old implementation.
  Move the single background fill to the stable editor container and disable
  nested scroll, clip and text backgrounds. Non-painting text must not declare
  itself opaque. Presentation changes invalidate drawing without replacing views.
- After the fix, all alpha assertions passed; the extra RGB assertions exposed
  the display-cache bitmap's default profile. Explicitly tag its color space as
  sRGB before drawing, keeping the original strict RGB tolerances. Temporary
  fixed-color diagnostics are removed from the test.
- Retagging alone did not change the cache-display conversion. Use an explicit
  RGBA sRGB bitmap drawing context and display the actual editor hierarchy into
  it instead. RGB and alpha expectations remain unchanged; assert a genuinely
  positive scroll offset rather than merely requesting one.
- The convenience context did not resolve the RGB assertions. Investigated
  implicit profiles by creating the CGContext directly with kCGColorSpaceSRGB,
  matching the explicit contract, and bridging that context into AppKit.
- NSColor pixel decoding still introduced a calibrated-to-sRGB conversion.
  Decode the explicit CGContext's RGBA8 premultiplied pixels directly, undoing
  premultiplication for RGB comparisons. The original tolerances and numerical
  expected sRGB values are unchanged, without display-profile interpretation.
- Direct RGBA8 measurement passed the full native suite. The final result
  isolates the RGB mismatch to color-object decoding rather than changing the
  configured color. Padding and genuinely scrolled viewport have identical alpha.
- After touched-range Xcode formatting, `make test` passed all ownership,
  scaffold, native bridge/runner/runtime, Dart API/launcher/example, assembly/
  publication, FFI and legacy-smoke gates. Diff checks also passed.
- Consumer Developer JIT (11150 ms) and Release AOT (10042 ms) native acceptance
  passed with configured opacity 0.8, stable editing/navigation/process displays,
  exact input routing and complete resource cleanup.
- The editor container is the only background painter; scroll/clip/text children
  do not paint backgrounds. The container becomes opaque only at alpha one.
  Existing configured opaque colors and text/selection drawing are retained.
- No new API/ABI, caller policy, unrelated Engine changes or temporary debug
  output are included. Subjective visual/accessibility review remains manual.
