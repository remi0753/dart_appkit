# dart_terminal_renderer_macos

This package owns the native macOS view used by Dart Terminal's renderer. Its
Dart 3.13 build hook compiles the Objective-C implementation as a code asset;
`dart_macos_runtime` stages and retains that image. The public Dart facade
initializes the versioned capability and creates an ordinary `dart_appkit`
`View` without exposing Objective-C objects or native registry handles.

The capability provides a paused, on-demand, framebuffer-only, flipped
`MTKView` plus generation-owned CoreText font catalogs. Catalogs resolve actual
or explicit synthetic regular/bold/italic/bold-italic styles, ordered CJK and
color-emoji fallback, and terminal cell/decorations metrics. Calls are bounded,
synchronous, and intended for a font/render worker domain rather than an AppKit
event handler. Terminal grids, glyph rasterization/atlases, draw submission,
shaders, input, and application policy remain outside this package boundary.

Applications declare the following native capability in their runtime manifest:

```json
{
  "id": "dart_terminal_renderer_macos",
  "package": "dart_terminal_renderer_macos",
  "library": "libdart_terminal_renderer_macos.dylib",
  "abiVersion": 2,
  "abiVersionSymbol": "dtr_abi_version",
  "initializerSymbol": "dtr_initialize"
}
```

Call `TerminalRendererMacos.initialize()` after attaching the AppKit
application, then use `TerminalRendererMacos.createView()`.

Font work does not require AppKit initialization. Create a catalog with
`TerminalFontCatalog.open()`, resolve whole grapheme/text units with `resolve`,
and call `dispose` from the owning worker domain. No native call retains a Dart
pointer, and a disposed catalog generation cannot be reused.
