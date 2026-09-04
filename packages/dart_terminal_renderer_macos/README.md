# dart_terminal_renderer_macos

This package owns the native macOS view used by Dart Terminal's renderer. Its
Dart 3.13 build hook compiles the Objective-C implementation as a code asset;
`dart_macos_runtime` stages and retains that image. The public Dart facade
initializes the versioned capability and creates an ordinary `dart_appkit`
`View` without exposing Objective-C objects or native registry handles.

The current capability is deliberately only a renderer shell: a paused,
on-demand, framebuffer-only, flipped `MTKView`. Terminal grids, glyph shaping,
atlases, draw submission, shaders, input, and application policy remain out of
scope until their corresponding roadmap phases.

Applications declare the following native capability in their runtime manifest:

```json
{
  "id": "dart_terminal_renderer_macos",
  "package": "dart_terminal_renderer_macos",
  "library": "libdart_terminal_renderer_macos.dylib",
  "abiVersion": 1,
  "abiVersionSymbol": "dtr_abi_version",
  "initializerSymbol": "dtr_initialize"
}
```

Call `TerminalRendererMacos.initialize()` after attaching the AppKit
application, then use `TerminalRendererMacos.createView()`.
