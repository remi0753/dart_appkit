import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> arguments) async {
  await build(arguments, (BuildInput input, BuildOutputBuilder output) async {
    if (input.config.code.targetOS.name != 'macos') {
      throw UnsupportedError('dart_terminal_renderer_macos requires macOS');
    }
    final CLibrary library = CLibrary(
      name: 'dart_terminal_renderer_macos',
      assetName: 'dart_terminal_renderer_macos.dart',
      sources: const <String>['native/TerminalRendererPlugin.m'],
      includes: const <String>['../../native/bridge/include'],
      frameworks: const <String>['AppKit', 'CoreText', 'Metal', 'MetalKit'],
      flags: const <String>[
        '-fobjc-arc',
        '-fvisibility=hidden',
        '-Wall',
        '-Wextra',
        '-Wpedantic',
        '-Werror',
        '-Wno-unused-command-line-argument',
        '-mmacosx-version-min=14.0',
      ],
      language: Language.objectiveC,
    );
    await library.build(
      input: input,
      output: output,
      routing: const <AssetRouting>[ToAppBundle()],
      linkModePreference: LinkModePreference.dynamic,
    );
  });
}
