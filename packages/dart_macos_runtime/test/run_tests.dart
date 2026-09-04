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
  "diagnostics": {
    "enabled": true,
    "applicationSupportName": "Dart AppKit Hello"
  }
}
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

  @override
  Future<BuilderCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool inheritStdio = false,
  }) async {
    commands.add(_RecordedCommand(executable, arguments, inheritStdio));
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
    } else if (executable != '/bin/chmod' &&
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
    _write('${project.path}/assets/message.txt', 'hello\n');
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
    final MacosApplicationManifest manifest = MacosApplicationManifest.parse(
      _validManifest,
    );
    _expect(manifest.executableName == 'hello_window', 'executable name');
    _expect(manifest.resources.single == 'assets/message.txt', 'resource');
    _expect(manifest.diagnostics.enabled, 'diagnostics');

    _expectThrows<MacosApplicationManifestException>(() {
      MacosApplicationManifest.parse(
        _validManifest.replaceFirst(
          '"schemaVersion": 1,',
          '"schemaVersion": 1, "unknown": true,',
        ),
      );
    });
    _expectThrows<MacosApplicationManifestException>(() {
      MacosApplicationManifest.parse(
        _validManifest.replaceFirst('"bin/main.dart"', '"../bin/main.dart"'),
      );
    });
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
    final String resource = MacosRuntime.bundleResourcePath(
      'data/config.json',
      resolvedExecutable: executable,
    );
    _expect(resource.endsWith('/Contents/Resources/data/config.json'), 'path');
    _expectThrows<MacosRuntimeException>(() {
      MacosRuntime.bundleResourcePath(
        '../Info.plist',
        resolvedExecutable: executable,
      );
    });
    await root.delete(recursive: true);
  });

  await _test('Developer JIT manifest-driven assembly', () async {
    final _Fixture fixture = await _Fixture.create();
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
    final _RecordedCommand launched = executor.commands.last;
    _expect(launched.inheritStdio, 'launch inherits stdio');
    _expect(launched.arguments.contains('--smoke'), 'arguments forwarded');
    await fixture.root.delete(recursive: true);
  });

  await _test('Release AOT manifest-driven assembly', () async {
    final _Fixture fixture = await _Fixture.create();
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
      executor.commands.any(
        (_RecordedCommand command) =>
            command.executable.endsWith('/gen_snapshot'),
      ),
      'AOT snapshotter runs',
    );
    await fixture.root.delete(recursive: true);
  });

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
