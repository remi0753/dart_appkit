import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_macos_runtime/dart_macos_runtime.dart';
import 'package:dart_macos_runtime/src/tool/builder.dart';
import 'package:dart_macos_runtime/testing.dart';

typedef TestBody = FutureOr<void> Function();

int _failures = 0;

Future<void> _test(String name, TestBody body) async {
  try {
    await body();
    stdout.writeln('PASS $name');
  } on Object catch (error, stackTrace) {
    ++_failures;
    stderr.writeln('FAIL $name: $error');
    stderr.writeln(stackTrace);
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('expectation failed: $description');
  }
}

T _expectThrows<T extends Object>(void Function() body) {
  try {
    body();
  } on Object catch (error) {
    if (error is T) {
      return error;
    }
    throw StateError('expected $T but caught ${error.runtimeType}');
  }
  throw StateError('expected $T but no error was thrown');
}

Future<T> _expectThrowsAsync<T extends Object>(
  Future<void> Function() body,
) async {
  try {
    await body();
  } on Object catch (error) {
    if (error is T) return error;
    throw StateError('expected $T but caught ${error.runtimeType}');
  }
  throw StateError('expected $T but no error was thrown');
}

const String _validManifest = '''
{
  "schemaVersion": 1,
  "application": {
    "name": "HelloWindow",
    "executableName": "hello_window",
    "bundleIdentifier": "dev.dart-appkit.hello-window",
    "version": "0.1.0",
    "minimumSystemVersion": "14.0"
  },
  "dart": {"entrypoint": "bin/main.dart"},
  "resources": ["assets/message.txt"],
  "nativeCapabilities": [],
  "diagnostics": {
    "enabled": true,
    "applicationSupportName": "Dart AppKit Hello"
  }
}
''';

String _withFolderServices(String manifest) =>
    manifest.replaceFirst('"dart":', '''"services": [
    {
      "kind": "newTabAtFolder",
      "menuItem": "New <Terminal> Tab & Here"
    },
    {
      "kind": "newWindowAtFolder",
      "menuItem": "New Terminal Window Here"
    }
  ],
  "dart":''');

String _withScriptingDefinition(String manifest) => manifest.replaceFirst(
  '"dart":',
  '''"scriptingDefinition": {"path": "resources/Test.sdef"},
  "dart":''',
);

const String _validSdef = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
<dictionary title="Test Terminology">
  <suite name="Test Suite" code="DTas" description="Test suite.">
    <class name="application" code="capp" description="The application.">
      <cocoa class="NSApplication"/>
    </class>
  </suite>
</dictionary>
''';

final class _FakeBindings implements RuntimeBindings {
  int runtimeVersion = 1;
  int diagnosticsVersion = 1;
  int status = 0;
  int? exitCode;
  int? terminationCode;
  int? phase;

  @override
  int diagnosticsAbiVersion() => diagnosticsVersion;

  @override
  int recordDiagnosticPhase(int phase) {
    this.phase = phase;
    return status;
  }

  @override
  int requestTermination(int exitCode) {
    terminationCode = exitCode;
    return status;
  }

  @override
  int runtimeAbiVersion() => runtimeVersion;

  @override
  int setExitCode(int exitCode) {
    this.exitCode = exitCode;
    return status;
  }
}

final class _RecordedCommand {
  _RecordedCommand(this.executable, this.arguments, this.inheritStdio);
  final String executable;
  final List<String> arguments;
  final bool inheritStdio;
}

final class _FakeExecutor implements BuilderProcessExecutor {
  final List<_RecordedCommand> commands = <_RecordedCommand>[];
  bool failScriptingDefinitionValidation = false;

  @override
  Future<BuilderCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool inheritStdio = false,
  }) async {
    commands.add(_RecordedCommand(executable, arguments, inheritStdio));
    if (executable == '/usr/bin/xmllint' && failScriptingDefinitionValidation) {
      return const BuilderCommandResult(
        exitCode: 2,
        stderrText: 'invalid scripting definition',
      );
    }
    if (inheritStdio) {
      return const BuilderCommandResult(exitCode: 23);
    }
    if (executable == 'make') {
      final String build = arguments
          .firstWhere((String value) => value.startsWith('BUILD_DIR='))
          .substring('BUILD_DIR='.length);
      final bool jit = arguments.contains('runtime-jit-runner');
      _write(
        '$build/native/${jit ? 'dart_macos_runtime_developer' : 'dart_macos_runtime_release'}',
        'fake host',
      );
    } else if (executable.endsWith('/bootstrap_gen_kernel.exe')) {
      final String output = arguments
          .firstWhere((String value) => value.startsWith('--output='))
          .substring('--output='.length);
      _write(output, 'fake Kernel');
      final String depfile = arguments
          .firstWhere((String value) => value.startsWith('--depfile='))
          .substring('--depfile='.length);
      _write(depfile, '$output: ${arguments.last}\n');
    } else if (executable.endsWith('/gen_snapshot')) {
      final String output = arguments
          .firstWhere((String value) => value.startsWith('--macho='))
          .substring('--macho='.length);
      _write(output, 'fake AOT snapshot');
    } else if (executable.endsWith('/bin/dart') &&
        arguments.length >= 2 &&
        arguments[0] == 'build' &&
        arguments[1] == 'cli') {
      final String output = arguments
          .firstWhere((String value) => value.startsWith('--output='))
          .substring('--output='.length);
      final String target = arguments
          .firstWhere((String value) => value.startsWith('--target='))
          .substring('--target='.length);
      if (target.endsWith('/helper.dart')) {
        _write('$output/bundle/bin/helper', 'fake Dart helper');
      } else {
        _write(
          '$output/bundle/lib/libexample_view.dylib',
          'fake capability image',
        );
        _write(
          '$output/bundle/lib/libdart_pty_macos.dylib',
          'fake native asset',
        );
      }
    } else if (executable != '/bin/chmod' &&
        executable != '/usr/bin/xmllint' &&
        executable != '/usr/bin/plutil' &&
        executable != '/usr/bin/codesign') {
      throw StateError('unexpected command: $executable $arguments');
    }
    return const BuilderCommandResult(exitCode: 0);
  }
}

final class _Fixture {
  _Fixture(this.root, this.repository, this.project, this.sdk, this.engine);

  static Future<_Fixture> create() async {
    final Directory root = await Directory.systemTemp.createTemp(
      'dart_macos_runtime_test.',
    );
    final Directory repository = Directory('${root.path}/repository');
    final Directory project = Directory('${root.path}/application');
    final Directory sdk = Directory('${root.path}/sdk');
    final Directory engine = Directory('${root.path}/engine');
    _write('${repository.path}/Makefile', 'all:\n\t@true\n');
    _write('${project.path}/macos_application.json', _validManifest);
    _write('${project.path}/bin/main.dart', 'void main() {}\n');
    _write('${project.path}/bin/helper.dart', 'void main() {}\n');
    _write('${project.path}/assets/message.txt', 'hello\n');
    _write('${project.path}/resources/Test.sdef', _validSdef);
    _write(
      '${project.path}/.dart_tool/package_config.json',
      '{"configVersion":2,"packages":[]}\n',
    );
    _write('${sdk.path}/bin/dart', 'fake dart');
    _write('${sdk.path}/version', '$pinnedDartSdkVersion\n');
    _write('${sdk.path}/revision', '$pinnedDartSdkRevision\n');
    _write('${engine.path}/runtime/engine/include/dart_engine.h', '// fake\n');
    _write('${engine.path}/LICENSE', 'fake license\n');
    for (final String output in <String>['ReleaseARM64', 'ProductARM64']) {
      final String base = '${engine.path}/xcodebuild/$output';
      _write('$base/bootstrap_gen_kernel.exe', 'fake compiler');
      _write('$base/clang_arm64_shared/vm_platform.dill', 'fake platform');
    }
    _write(
      '${engine.path}/xcodebuild/ReleaseARM64/libdart_engine_jit_shared.dylib',
      'fake JIT engine',
    );
    _write(
      '${engine.path}/xcodebuild/ProductARM64/libdart_engine_aot_shared.dylib',
      'fake AOT engine',
    );
    _write('${engine.path}/xcodebuild/ProductARM64/gen_snapshot', 'fake gen');
    return _Fixture(root, repository, project, sdk, engine);
  }

  final Directory root;
  final Directory repository;
  final Directory project;
  final Directory sdk;
  final Directory engine;

  RuntimeApplicationBuilder builder(_FakeExecutor executor) =>
      RuntimeApplicationBuilder(
        repositoryRoot: repository.path,
        currentDirectory: project.path,
        resolvedDartExecutable: '${sdk.path}/bin/dart',
        operatingSystem: 'macos',
        architecture: 'arm64',
        environment: <String, String>{'DART_ENGINE_ROOT': engine.path},
        processExecutor: executor,
        output: (_) {},
        errorOutput: (_) {},
      );
}

void _write(String path, String contents) {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

Future<void> main() async {
  await _test('strict manifest parsing', () {
    final Directory sdefRoot = Directory.systemTemp.createTempSync(
      'dart_macos_runtime_sdef.',
    );
    final String sdefPath = '${sdefRoot.path}/Test.sdef';
    _write(sdefPath, _validSdef);
    final ProcessResult sdefValidation = Process.runSync(
      '/usr/bin/xmllint',
      <String>['--noout', '--valid', sdefPath],
    );
    sdefRoot.deleteSync(recursive: true);
    _expect(
      sdefValidation.exitCode == 0,
      'test scripting definition is valid: ${sdefValidation.stderr}',
    );
    final MacosApplicationManifest manifest = MacosApplicationManifest.parse(
      _validManifest,
    );
    _expect(manifest.executableName == 'hello_window', 'executable name');
    _expect(manifest.resources.single == 'assets/message.txt', 'resource');
    _expect(manifest.dartHelpers.isEmpty, 'helpers default empty');
    _expect(manifest.services.isEmpty, 'services default empty');
    _expect(manifest.scriptingDefinition == null, 'scripting default empty');
    _expect(manifest.diagnostics.enabled, 'diagnostics');
    _expect(
      manifest.runner.activationPolicy == MacosRunnerActivationPolicy.regular,
      'runner activation default',
    );
    _expect(manifest.runner.activateOnLaunch, 'runner launch default');
    _expect(
      !manifest.runner.terminateAfterLastWindowClosed,
      'runner last-window default',
    );
    _expect(manifest.runner.reopenHandled, 'runner reopen default');
    _expect(
      manifest.runner.messagePump.maxMessagesPerTurn == 64 &&
          manifest.runner.messagePump.maxTimePerTurnMicros == 4000,
      'runner message-pump defaults',
    );

    _expectThrows<MacosApplicationManifestException>(() {
      MacosApplicationManifest.parse(
        _validManifest.replaceFirst(
          '"schemaVersion": 1,',
          '"schemaVersion": 1, "unknown": true,',
        ),
      );
    });
    final MacosApplicationManifest scriptingManifest =
        MacosApplicationManifest.parse(
          _withScriptingDefinition(_validManifest),
        );
    _expect(
      scriptingManifest.scriptingDefinition?.path == 'resources/Test.sdef' &&
          scriptingManifest.scriptingDefinition?.bundleName == 'Test.sdef',
      'closed scripting definition declaration',
    );
    for (final String declaration in <String>[
      'true',
      '{}',
      '{"path":"resources/Test.sdef","extra":true}',
      '{"path":"resources/Test.xml"}',
      '{"path":"/tmp/Test.sdef"}',
      '{"path":"https://example.com/Test.sdef"}',
      '{"path":"${'x' * 1020}.sdef"}',
    ]) {
      _expectThrows<MacosApplicationManifestException>(() {
        MacosApplicationManifest.parse(
          _validManifest.replaceFirst(
            '"dart":',
            '"scriptingDefinition": $declaration, "dart":',
          ),
        );
      });
    }
    _expectThrows<MacosApplicationManifestException>(() {
      MacosApplicationManifest.parse(
        _withScriptingDefinition(
          _validManifest.replaceFirst(
            '"assets/message.txt"',
            '"assets/message.txt", "Test.sdef"',
          ),
        ),
      );
    });
    final MacosApplicationManifest serviceManifest =
        MacosApplicationManifest.parse(_withFolderServices(_validManifest));
    _expect(serviceManifest.services.length == 2, 'service count');
    _expect(
      serviceManifest.services[0].kind ==
              MacosApplicationServiceKind.newTabAtFolder &&
          serviceManifest.services[0].menuItem == 'New <Terminal> Tab & Here' &&
          serviceManifest.services[1].kind ==
              MacosApplicationServiceKind.newWindowAtFolder,
      'closed folder service declarations',
    );
    _expectThrows<UnsupportedError>(() {
      serviceManifest.services.add(serviceManifest.services.first);
    });
    for (final String services in <String>[
      '{}',
      '[true]',
      '[{"kind":"openFolder","menuItem":"Open Here"}]',
      '[{"kind":"newTabAtFolder"}]',
      '[{"kind":"newTabAtFolder","menuItem":"Open Here","extra":true}]',
      '[{"kind":"newTabAtFolder","menuItem":1}]',
      '[{"kind":"newTabAtFolder","menuItem":""}]',
      '[{"kind":"newTabAtFolder","menuItem":" Open Here"}]',
      '[{"kind":"newTabAtFolder","menuItem":"Open/Here"}]',
      '[{"kind":"newTabAtFolder","menuItem":"Open\\nHere"}]',
      '''[
        {"kind":"newTabAtFolder","menuItem":"Open Tab Here"},
        {"kind":"newTabAtFolder","menuItem":"Another Tab Here"}
      ]''',
      '''[
        {"kind":"newTabAtFolder","menuItem":"Open Here"},
        {"kind":"newWindowAtFolder","menuItem":"Open Here"}
      ]''',
    ]) {
      _expectThrows<MacosApplicationManifestException>(() {
        MacosApplicationManifest.parse(
          _validManifest.replaceFirst(
            '"dart":',
            '"services": $services, "dart":',
          ),
        );
      });
    }
    _expectThrows<MacosApplicationManifestException>(() {
      final String oversized =
          'x' * (MacosApplicationServiceManifest.maximumMenuItemUtf8Bytes + 1);
      MacosApplicationManifest.parse(
        _validManifest.replaceFirst(
          '"dart":',
          '"services": [{"kind":"newTabAtFolder",'
              '"menuItem":${jsonEncode(oversized)}}], "dart":',
        ),
      );
    });
    final String boundaryLabel = 'é' * 128;
    final MacosApplicationManifest boundaryServiceManifest =
        MacosApplicationManifest.parse(
          _validManifest.replaceFirst(
            '"dart":',
            '"services": [{"kind":"newTabAtFolder",'
                '"menuItem":${jsonEncode(boundaryLabel)}}], "dart":',
          ),
        );
    _expect(
      boundaryServiceManifest.services.single.menuItem == boundaryLabel,
      'service menu item accepts the exact UTF-8 boundary',
    );
    _expectThrows<MacosApplicationManifestException>(() {
      MacosApplicationManifest.parse(
        _validManifest.replaceFirst('"bin/main.dart"', '"../bin/main.dart"'),
      );
    });
    final MacosApplicationManifest runnerManifest =
        MacosApplicationManifest.parse(
          _validManifest.replaceFirst('"dart":', '''"runner": {
    "activationPolicy": "accessory",
    "activateOnLaunch": false,
    "terminateAfterLastWindowClosed": true,
    "reopenHandled": false,
    "messagePump": {
      "maxMessagesPerTurn": 17,
      "maxTimePerTurnMicros": 2500
    }
  },
  "dart":'''),
        );
    _expect(
      runnerManifest.runner.activationPolicy ==
          MacosRunnerActivationPolicy.accessory,
      'runner activation policy',
    );
    _expect(!runnerManifest.runner.activateOnLaunch, 'runner launch policy');
    _expect(
      runnerManifest.runner.terminateAfterLastWindowClosed,
      'runner last-window policy',
    );
    _expect(!runnerManifest.runner.reopenHandled, 'runner reopen policy');
    _expect(
      runnerManifest.runner.messagePump.maxMessagesPerTurn == 17 &&
          runnerManifest.runner.messagePump.maxTimePerTurnMicros == 2500,
      'runner message-pump policy',
    );
    _expectThrows<MacosApplicationManifestException>(() {
      MacosApplicationManifest.parse(
        _validManifest.replaceFirst(
          '"dart":',
          '"runner": {"activationPolicy": "agent"}, "dart":',
        ),
      );
    });
    for (final String messagePump in <String>[
      '{"maxMessagesPerTurn": 0}',
      '{"maxMessagesPerTurn": 1025}',
      '{"maxTimePerTurnMicros": 16001}',
      '{"maxTimePerTurnMicros": 1.5}',
      '{"unknown": 1}',
    ]) {
      _expectThrows<MacosApplicationManifestException>(() {
        MacosApplicationManifest.parse(
          _validManifest.replaceFirst(
            '"dart":',
            '"runner": {"messagePump": $messagePump}, "dart":',
          ),
        );
      });
    }
    _expectThrows<MacosApplicationManifestException>(() {
      MacosApplicationManifest.parse(
        _validManifest.replaceFirst(
          '"dart":',
          '"runner": {"activateOnLaunch": 1}, "dart":',
        ),
      );
    });
    final MacosApplicationManifest capabilityManifest =
        MacosApplicationManifest.parse(
          _validManifest.replaceFirst(
            '"nativeCapabilities": []',
            '''"nativeCapabilities": [
      {
        "id": "example_view",
        "package": "example_view",
        "library": "libexample_view.dylib",
        "abiVersion": 1,
        "abiVersionSymbol": "example_abi_version",
        "initializerSymbol": "example_initialize"
      }
    ]''',
          ),
        );
    _expect(
      capabilityManifest.nativeCapabilities.single.id == 'example_view',
      'native capability declaration',
    );
    final MacosApplicationManifest nativeAssetManifest =
        MacosApplicationManifest.parse(
          _validManifest.replaceFirst(
            '"nativeCapabilities": []',
            '''"nativeAssets": [
      {
        "id": "dart_pty_macos",
        "package": "dart_pty_macos",
        "library": "libdart_pty_macos.dylib",
        "abiVersion": 1,
        "abiVersionSymbol": "dpty_abi_version"
      }
    ],
    "nativeCapabilities": []''',
          ),
        );
    _expect(
      nativeAssetManifest.nativeAssets.single.id == 'dart_pty_macos',
      'plain native asset declaration',
    );
    final MacosApplicationManifest helperManifest =
        MacosApplicationManifest.parse(
          _validManifest.replaceFirst('"resources":', '''"dartHelpers": [
      {"name": "runtime_worker", "entrypoint": "bin/helper.dart"}
    ],
    "resources":'''),
        );
    _expect(
      helperManifest.dartHelpers.single.name == 'runtime_worker',
      'Dart helper declaration',
    );
    _expectThrows<MacosApplicationManifestException>(() {
      MacosApplicationManifest.parse(
        _validManifest.replaceFirst('"resources":', '''"dartHelpers": [
      {"name": "..", "entrypoint": "bin/helper.dart"}
    ],
    "resources":'''),
      );
    });
    _expectThrows<MacosApplicationManifestException>(() {
      MacosApplicationManifest.parse(
        _validManifest.replaceFirst('"resources":', '''"dartHelpers": [
      {"name": "worker", "entrypoint": "bin/helper.dart"},
      {"name": "worker", "entrypoint": "bin/helper.dart"}
    ],
    "resources":'''),
      );
    });
  });

  await _test('native capability declaration and image retention', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'dmr_capability.',
    );
    final String contents = '${root.path}/Example.app/Contents';
    final String executable = '$contents/MacOS/example';
    final String library = '$contents/Frameworks/libexample_view.dylib';
    _write(library, 'fake dylib');
    _write(
      '$contents/Resources/runtime-build-manifest.json',
      jsonEncode(<String, Object>{
        'nativeCapabilities': <Map<String, Object>>[
          <String, Object>{
            'id': 'example_view',
            'library': 'libexample_view.dylib',
            'abiVersion': 7,
            'abiVersionSymbol': 'example_abi_version',
            'initializerSymbol': 'example_initialize',
          },
        ],
      }),
    );
    var calls = 0;
    MacosNativeCapability.resetForTesting();
    MacosNativeCapability.setInitializerForTesting(({
      required String libraryPath,
      required int abiVersion,
      required String abiVersionSymbol,
      required String initializerSymbol,
    }) {
      ++calls;
      _expect(libraryPath == library, 'declared image path');
      _expect(abiVersion == 7, 'declared ABI');
      _expect(abiVersionSymbol == 'example_abi_version', 'version symbol');
      _expect(initializerSymbol == 'example_initialize', 'initializer symbol');
    });
    final MacosNativeCapability first = MacosNativeCapability.load(
      'example_view',
      resolvedExecutable: executable,
    );
    final MacosNativeCapability second = MacosNativeCapability.load(
      'example_view',
      resolvedExecutable: executable,
    );
    _expect(identical(first, second), 'duplicate initialization is idempotent');
    _expect(calls == 1, 'initializer runs exactly once');
    _expectThrows<MacosNativeCapabilityException>(() {
      MacosNativeCapability.load('missing', resolvedExecutable: executable);
    });
    MacosNativeCapability.resetForTesting();
    await root.delete(recursive: true);
  });

  await _test('runtime facade and resource boundary', () async {
    final _FakeBindings bindings = _FakeBindings();
    MacosRuntime.setBindingsForTesting(bindings);
    MacosRuntime.validateHost();
    MacosRuntime.setExitCode(70);
    MacosRuntime.requestTermination(exitCode: 75);
    MacosRuntime.recordDiagnosticPhase(RuntimeDiagnosticPhase.rootReady);
    _expect(bindings.exitCode == 70, 'exit code forwarded');
    _expect(bindings.terminationCode == 75, 'termination forwarded');
    _expect(bindings.phase == 2, 'phase forwarded');

    bindings.runtimeVersion = 99;
    _expectThrows<MacosRuntimeException>(MacosRuntime.validateHost);
    bindings.runtimeVersion = 1;
    bindings.status = 3;
    _expectThrows<MacosRuntimeException>(() => MacosRuntime.setExitCode(70));

    final Directory root = await Directory.systemTemp.createTemp('dmr.app.');
    final String executable = '${root.path}/Hello.app/Contents/MacOS/hello';
    _write('${root.path}/Hello.app/Contents/Resources/data/config.json', '{}');
    _write(
      '${root.path}/Hello.app/Contents/Frameworks/libexample.dylib',
      'fake',
    );
    _write('${root.path}/Hello.app/Contents/Helpers/runtime_worker', 'fake');
    final String resource = MacosRuntime.bundleResourcePath(
      'data/config.json',
      resolvedExecutable: executable,
    );
    _expect(resource.endsWith('/Contents/Resources/data/config.json'), 'path');
    final String framework = MacosRuntime.bundleFrameworkPath(
      'libexample.dylib',
      resolvedExecutable: executable,
    );
    _expect(
      framework.endsWith('/Contents/Frameworks/libexample.dylib'),
      'framework path',
    );
    final String helper = MacosRuntime.bundleHelperPath(
      'runtime_worker',
      resolvedExecutable: executable,
    );
    _expect(helper.endsWith('/Contents/Helpers/runtime_worker'), 'helper path');
    _expectThrows<MacosRuntimeException>(() {
      MacosRuntime.bundleResourcePath(
        '../Info.plist',
        resolvedExecutable: executable,
      );
    });
    _expectThrows<MacosRuntimeException>(() {
      MacosRuntime.bundleFrameworkPath(
        '../libexample.dylib',
        resolvedExecutable: executable,
      );
    });
    await root.delete(recursive: true);
  });

  await _test('declared Dart helpers are compiled and staged', () async {
    final _Fixture fixture = await _Fixture.create();
    _write(
      '${fixture.project.path}/macos_application.json',
      _validManifest.replaceFirst('"resources":', '''"dartHelpers": [
      {"name": "runtime_worker", "entrypoint": "bin/helper.dart"}
    ],
    "resources":'''),
    );
    final _FakeExecutor executor = _FakeExecutor();
    final int result = await fixture
        .builder(executor)
        .run(
          RuntimeBuilderOptions.parse(<String>[
            '--manifest=${fixture.project.path}/macos_application.json',
            '--build-dir=${fixture.root.path}/build-helper',
          ]),
        );
    _expect(result == 0, 'helper build succeeds');
    final String contents =
        '${fixture.root.path}/build-helper/HelloWindow.app/Contents';
    _expect(
      File('$contents/Helpers/runtime_worker').existsSync(),
      'helper is staged',
    );
    final Map<String, Object?> buildManifest = jsonDecode(
      File('$contents/Resources/runtime-build-manifest.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    _expect(
      (buildManifest['dartHelpers']! as List<Object?>).length == 1,
      'helper declaration is recorded',
    );
    _expect(
      !buildManifest.containsKey('services') &&
          !buildManifest.containsKey('scriptingDefinition') &&
          !File('$contents/Info.plist')
              .readAsStringSync()
              .contains('<key>NSAppleScriptEnabled</key>') &&
          !File('$contents/Info.plist')
              .readAsStringSync()
              .contains('<key>OSAScriptingDefinition</key>'),
      'legacy manifests do not gain Service or scripting metadata',
    );
    _expect(
      executor.commands.any(
        (_RecordedCommand command) =>
            command.executable.endsWith('/bin/dart') &&
            command.arguments.take(2).join(' ') == 'build cli' &&
            command.arguments.any(
              (String value) => value.endsWith('/bin/helper.dart'),
            ),
      ),
      'Dart helper compiler runs',
    );
    await fixture.root.delete(recursive: true);
  });

  await _test('scripting definition staging failures are closed', () async {
    final _Fixture fixture = await _Fixture.create();
    _write(
      '${fixture.project.path}/macos_application.json',
      _withScriptingDefinition(_validManifest),
    );
    final String source = '${fixture.project.path}/resources/Test.sdef';
    await File(source).delete();
    final _FakeExecutor missingExecutor = _FakeExecutor();
    final RuntimeBuilderException missing =
        await _expectThrowsAsync<RuntimeBuilderException>(
          () => fixture
              .builder(missingExecutor)
              .run(
                RuntimeBuilderOptions.parse(<String>[
                  '--manifest=${fixture.project.path}/macos_application.json',
                  '--build-dir=${fixture.root.path}/build-missing-sdef',
                ]),
              ),
        );
    _expect(
      missing.exitCode == builderIoErrorExitCode,
      'missing scripting definition is an I/O failure',
    );

    _write(
      source,
      'x' * (MacosScriptingDefinitionManifest.maximumFileBytes + 1),
    );
    final RuntimeBuilderException oversized =
        await _expectThrowsAsync<RuntimeBuilderException>(
          () => fixture
              .builder(_FakeExecutor())
              .run(
                RuntimeBuilderOptions.parse(<String>[
                  '--manifest=${fixture.project.path}/macos_application.json',
                  '--build-dir=${fixture.root.path}/build-oversized-sdef',
                ]),
              ),
        );
    _expect(
      oversized.exitCode == builderUsageExitCode,
      'oversized scripting definition is rejected before validation',
    );

    _write(source, '<dictionary/>\n');
    final _FakeExecutor invalidExecutor = _FakeExecutor()
      ..failScriptingDefinitionValidation = true;
    final RuntimeBuilderException invalid =
        await _expectThrowsAsync<RuntimeBuilderException>(
          () => fixture
              .builder(invalidExecutor)
              .run(
                RuntimeBuilderOptions.parse(<String>[
                  '--manifest=${fixture.project.path}/macos_application.json',
                  '--build-dir=${fixture.root.path}/build-invalid-sdef',
                ]),
              ),
        );
    _expect(
      invalid.exitCode == 2 &&
          !File(
            '${fixture.root.path}/build-invalid-sdef/HelloWindow.app/'
            'Contents/Resources/Test.sdef',
          ).existsSync(),
      'invalid scripting definition is not staged',
    );
    await fixture.root.delete(recursive: true);
  });

  await _test('Developer JIT manifest-driven assembly', () async {
    final _Fixture fixture = await _Fixture.create();
    _write(
      '${fixture.project.path}/macos_application.json',
      _withScriptingDefinition(_withFolderServices(_validManifest))
          .replaceFirst('"dart":', '''"runner": {
    "activationPolicy": "prohibited",
    "activateOnLaunch": false,
    "terminateAfterLastWindowClosed": true,
    "reopenHandled": false,
    "messagePump": {
      "maxMessagesPerTurn": 17,
      "maxTimePerTurnMicros": 2500
    }
  },
  "dart":'''),
    );
    final _FakeExecutor executor = _FakeExecutor();
    final int result = await fixture
        .builder(executor)
        .run(
          RuntimeBuilderOptions.parse(<String>[
            '--manifest',
            '${fixture.project.path}/macos_application.json',
            '--build-dir',
            '${fixture.root.path}/build-jit',
            '--run',
            '--',
            '--smoke',
          ]),
        );
    _expect(result == 23, 'application result is forwarded');
    final Directory bundle = Directory(
      '${fixture.root.path}/build-jit/HelloWindow.app',
    );
    _expect(bundle.existsSync(), 'bundle exists');
    _expect(
      File('${bundle.path}/Contents/Resources/application.dill').existsSync(),
      'JIT payload is bundled',
    );
    _expect(
      File('${bundle.path}/Contents/Resources/assets/message.txt').existsSync(),
      'declared resource is bundled',
    );
    _expect(
      File('${bundle.path}/Contents/Resources/Test.sdef').readAsStringSync() ==
          _validSdef,
      'validated scripting definition is staged at the resource root',
    );
    final String infoPlist = File('${bundle.path}/Contents/Info.plist')
        .readAsStringSync();
    _expect(
      infoPlist.contains('<string>prohibited</string>'),
      'runner activation policy is bundled',
    );
    _expect(
      infoPlist.contains(
        '<key>TerminateAfterLastWindowClosed</key>\n    <true/>',
      ),
      'runner last-window policy is bundled',
    );
    _expect(
      infoPlist.contains(
            '<key>MaxMessagesPerTurn</key>\n      <integer>17</integer>',
          ) &&
          infoPlist.contains(
            '<key>MaxTimePerTurnMicros</key>\n      <integer>2500</integer>',
          ),
      'runner message-pump policy is bundled',
    );
    const String expectedServices = '''  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>New &lt;Terminal&gt; Tab &amp; Here</string>
      </dict>
      <key>NSMessage</key>
      <string>openTab</string>
      <key>NSRequiredContext</key>
      <dict/>
      <key>NSSendFileTypes</key>
      <array>
        <string>public.item</string>
      </array>
    </dict>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>New Terminal Window Here</string>
      </dict>
      <key>NSMessage</key>
      <string>openWindow</string>
      <key>NSRequiredContext</key>
      <dict/>
      <key>NSSendFileTypes</key>
      <array>
        <string>public.item</string>
      </array>
    </dict>
  </array>
''';
    _expect(
      infoPlist.contains(expectedServices),
      'folder Services are deterministic and XML escaped',
    );
    _expect(
      infoPlist.contains('<key>NSAppleScriptEnabled</key>\n  <true/>') &&
          infoPlist.contains(
            '<key>OSAScriptingDefinition</key>\n  <string>Test.sdef</string>',
          ),
      'scripting definition plist keys are exact',
    );
    final ProcessResult plistLint = Process.runSync('/usr/bin/plutil', <String>[
      '-lint',
      '${bundle.path}/Contents/Info.plist',
    ]);
    _expect(
      plistLint.exitCode == 0,
      'real plutil accepts generated folder Services: ${plistLint.stderr}',
    );
    _expect(
      executor.commands.any(
        (_RecordedCommand command) =>
            command.executable == '/usr/bin/plutil' &&
            command.arguments.length == 2 &&
            command.arguments.first == '-lint' &&
            command.arguments.last.endsWith('/Contents/Info.plist'),
      ),
      'generated Info.plist is validated before signing',
    );
    _expect(
      executor.commands.any(
        (_RecordedCommand command) =>
            command.executable == '/usr/bin/xmllint' &&
            command.arguments.length == 3 &&
            command.arguments[0] == '--noout' &&
            command.arguments[1] == '--valid' &&
            command.arguments.last.endsWith('/resources/Test.sdef'),
      ),
      'scripting definition is DTD-validated before staging',
    );
    final Map<String, Object?> buildManifest = jsonDecode(
      File('${bundle.path}/Contents/Resources/runtime-build-manifest.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final Map<String, Object?> runner =
        buildManifest['runner']! as Map<String, Object?>;
    _expect(runner['reopenHandled'] == false, 'runner policy is recorded');
    final Map<String, Object?> messagePump =
        runner['messagePump']! as Map<String, Object?>;
    _expect(
      messagePump['maxMessagesPerTurn'] == 17 &&
          messagePump['maxTimePerTurnMicros'] == 2500,
      'runner message-pump policy is recorded',
    );
    final List<Object?> services = buildManifest['services']! as List<Object?>;
    _expect(
      services.length == 2 &&
          (services[0]! as Map<String, Object?>)['kind'] == 'newTabAtFolder' &&
          (services[1]! as Map<String, Object?>)['menuItem'] ==
              'New Terminal Window Here',
      'validated folder Services are recorded',
    );
    final Map<String, Object?> scripting =
        buildManifest['scriptingDefinition']! as Map<String, Object?>;
    _expect(
      scripting['source'] == 'resources/Test.sdef' &&
          scripting['bundleName'] == 'Test.sdef' &&
          scripting['bytes'] == utf8.encode(_validSdef).length,
      'scripting definition source, resource name, and size are recorded',
    );
    final _RecordedCommand launched = executor.commands.last;
    _expect(launched.inheritStdio, 'launch inherits stdio');
    _expect(launched.arguments.contains('--smoke'), 'arguments forwarded');
    await fixture.root.delete(recursive: true);
  });

  await _test('Release AOT manifest-driven assembly', () async {
    final _Fixture fixture = await _Fixture.create();
    _write(
      '${fixture.project.path}/macos_application.json',
      _withScriptingDefinition(_withFolderServices(_validManifest)),
    );
    final _FakeExecutor executor = _FakeExecutor();
    final int result = await fixture
        .builder(executor)
        .run(
          RuntimeBuilderOptions.parse(<String>[
            '--manifest=${fixture.project.path}/macos_application.json',
            '--mode=release-aot',
            '--build-dir=${fixture.root.path}/build-aot',
          ]),
        );
    _expect(result == 0, 'build-only succeeds');
    final Directory bundle = Directory(
      '${fixture.root.path}/build-aot/HelloWindow.app',
    );
    _expect(
      File('${bundle.path}/Contents/Resources/application.aot').existsSync(),
      'AOT payload is bundled',
    );
    final Map<String, Object?> buildManifest = jsonDecode(
      File('${bundle.path}/Contents/Resources/runtime-build-manifest.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    _expect(buildManifest['runtimeMode'] == 'release-aot', 'mode recorded');
    _expect(
      (buildManifest['services']! as List<Object?>).length == 2,
      'AOT build records folder Services',
    );
    _expect(
      (buildManifest['scriptingDefinition']!
              as Map<String, Object?>)['bundleName'] ==
          'Test.sdef',
      'AOT build records the scripting definition',
    );
    final String infoPlist = File('${bundle.path}/Contents/Info.plist')
        .readAsStringSync();
    _expect(
      infoPlist.indexOf('<string>openTab</string>') <
              infoPlist.indexOf('<string>openWindow</string>') &&
          infoPlist.contains('<string>public.item</string>') &&
          infoPlist.contains('<key>NSAppleScriptEnabled</key>'),
      'AOT Info.plist preserves Services and scripting metadata',
    );
    _expect(
      executor.commands.any(
        (_RecordedCommand command) =>
            command.executable.endsWith('/gen_snapshot'),
      ),
      'AOT snapshotter runs',
    );
    await fixture.root.delete(recursive: true);
  });

  await _test('native asset hooks are staged by declaration', () async {
    final _Fixture fixture = await _Fixture.create();
    _write(
      '${fixture.project.path}/macos_application.json',
      _validManifest.replaceFirst(
        '"nativeCapabilities": []',
        '''"nativeCapabilities": [
      {
        "id": "example_view",
        "package": "example_view",
        "library": "libexample_view.dylib",
        "abiVersion": 1,
        "abiVersionSymbol": "example_abi_version",
        "initializerSymbol": "example_initialize"
      }
    ]''',
      ),
    );
    final _FakeExecutor executor = _FakeExecutor();
    final int result = await fixture
        .builder(executor)
        .run(
          RuntimeBuilderOptions.parse(<String>[
            '--manifest=${fixture.project.path}/macos_application.json',
            '--build-dir=${fixture.root.path}/build-capability',
          ]),
        );
    _expect(result == 0, 'capability build succeeds');
    final String contents =
        '${fixture.root.path}/build-capability/HelloWindow.app/Contents';
    _expect(
      File('$contents/Frameworks/libexample_view.dylib').existsSync(),
      'declared capability image is staged',
    );
    final Map<String, Object?> buildManifest = jsonDecode(
      File('$contents/Resources/runtime-build-manifest.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final List<Object?> capabilities =
        buildManifest['nativeCapabilities']! as List<Object?>;
    _expect(capabilities.length == 1, 'capability declaration is recorded');
    _expect(
      executor.commands.any(
        (_RecordedCommand command) =>
            command.executable.endsWith('/bin/dart') &&
            command.arguments.take(2).join(' ') == 'build cli',
      ),
      'Dart build hooks run',
    );
    await fixture.root.delete(recursive: true);
  });

  await _test(
    'plain native assets are staged without AppKit initialization',
    () async {
      final _Fixture fixture = await _Fixture.create();
      _write(
        '${fixture.project.path}/macos_application.json',
        _validManifest.replaceFirst(
          '"nativeCapabilities": []',
          '''"nativeAssets": [
      {
        "id": "dart_pty_macos",
        "package": "dart_pty_macos",
        "library": "libdart_pty_macos.dylib",
        "abiVersion": 1,
        "abiVersionSymbol": "dpty_abi_version"
      }
    ],
    "nativeCapabilities": []''',
        ),
      );
      final _FakeExecutor executor = _FakeExecutor();
      final int result = await fixture
          .builder(executor)
          .run(
            RuntimeBuilderOptions.parse(<String>[
              '--manifest=${fixture.project.path}/macos_application.json',
              '--build-dir=${fixture.root.path}/build-native-asset',
            ]),
          );
      _expect(result == 0, 'plain native asset build succeeds');
      final String contents =
          '${fixture.root.path}/build-native-asset/HelloWindow.app/Contents';
      _expect(
        File('$contents/Frameworks/libdart_pty_macos.dylib').existsSync(),
        'plain native asset image is staged',
      );
      final Map<String, Object?> buildManifest = jsonDecode(
        File('$contents/Resources/runtime-build-manifest.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final List<Object?> assets =
          buildManifest['nativeAssets']! as List<Object?>;
      _expect(assets.length == 1, 'plain native asset is recorded');
      _expect(
        (assets.single! as Map<String, Object?>).containsKey(
              'initializerSymbol',
            ) ==
            false,
        'plain asset does not acquire an AppKit initializer',
      );
      await fixture.root.delete(recursive: true);
    },
  );

  await _test('builder option validation', () {
    _expectThrows<RuntimeBuilderException>(
      () => RuntimeBuilderOptions.parse(const <String>[]),
    );
    _expectThrows<RuntimeBuilderException>(
      () => RuntimeBuilderOptions.parse(const <String>[
        '--manifest=x',
        '--mode=debug',
      ]),
    );
    _expectThrows<RuntimeBuilderException>(
      () => RuntimeBuilderOptions.parse(const <String>[
        '--manifest=x',
        '--',
        'arg',
      ]),
    );
  });

  if (_failures != 0) {
    exitCode = 1;
  }
}
