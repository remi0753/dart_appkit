import 'dart:async';
import 'dart:io';

import 'package:dart_appkit/src/tool/launcher.dart';

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

void _discard(String value) {
  if (value.isEmpty) {
    return;
  }
}

bool _containsInOrder(List<String> values, List<String> expected) {
  var expectedIndex = 0;
  for (final String value in values) {
    if (expectedIndex < expected.length && value == expected[expectedIndex]) {
      ++expectedIndex;
    }
  }
  return expectedIndex == expected.length;
}

Future<LauncherException> _expectLauncherError(
  FutureOr<void> Function() body,
) async {
  try {
    await body();
  } on LauncherException catch (error) {
    return error;
  }
  throw StateError('expected LauncherException but no exception was thrown');
}

final class _RecordedCommand {
  _RecordedCommand({
    required this.executable,
    required List<String> arguments,
    required this.workingDirectory,
    required this.inheritStdio,
  }) : arguments = List<String>.unmodifiable(arguments);

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final bool inheritStdio;
}

final class _FakeExecutor implements LauncherProcessExecutor {
  final List<_RecordedCommand> commands = <_RecordedCommand>[];
  int makeExitCode = 0;
  int compilerExitCode = 0;
  int launchedExitCode = 23;

  @override
  Future<LauncherCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool inheritStdio = false,
  }) async {
    commands.add(
      _RecordedCommand(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        inheritStdio: inheritStdio,
      ),
    );
    if (inheritStdio) {
      return LauncherCommandResult(exitCode: launchedExitCode);
    }
    if (executable == 'make') {
      if (makeExitCode != 0) {
        return LauncherCommandResult(
          exitCode: makeExitCode,
          stderrText: 'injected Make failure\n',
        );
      }
      final String buildArgument = arguments.firstWhere(
        (String value) => value.startsWith('BUILD_DIR='),
      );
      final String buildDirectory = buildArgument.substring(
        'BUILD_DIR='.length,
      );
      _writeFile(
        '$buildDirectory/native/dart_appkit_runner',
        'fake native runner',
      );
      return const LauncherCommandResult(
        exitCode: 0,
        stdoutText: 'fake native build passed\n',
      );
    }
    if (executable.endsWith('/bootstrap_gen_kernel.exe')) {
      if (compilerExitCode != 0) {
        return LauncherCommandResult(
          exitCode: compilerExitCode,
          stderrText: 'injected Kernel compiler failure\n',
        );
      }
      final String outputArgument = arguments.firstWhere(
        (String value) => value.startsWith('--output='),
      );
      final String outputPath = outputArgument.substring('--output='.length);
      _writeFile(outputPath, 'fake full Kernel');
      final String depfileArgument = arguments.firstWhere(
        (String value) => value.startsWith('--depfile='),
      );
      _writeFile(
        depfileArgument.substring('--depfile='.length),
        '$outputPath: ${arguments.last}\n',
      );
      return const LauncherCommandResult(exitCode: 0);
    }
    if (executable == '/bin/chmod') {
      return const LauncherCommandResult(exitCode: 0);
    }
    throw StateError('unexpected fake command: $executable $arguments');
  }
}

final class _Fixture {
  _Fixture._({
    required this.root,
    required this.repository,
    required this.project,
    required this.sdk,
    required this.engine,
    required this.engineLibrary,
    required this.executor,
  });

  static Future<_Fixture> create() async {
    final Directory root = await Directory.systemTemp.createTemp(
      'dart_appkit_launcher_test.',
    );
    final Directory repository = Directory('${root.path}/repository');
    final Directory project = Directory('${root.path}/application');
    final Directory sdk = Directory('${root.path}/sdk');
    final Directory engine = Directory('${root.path}/engine-sdk');
    final File engineLibrary = File(
      '${root.path}/engine-output/libdart_engine_jit_shared.dylib',
    );

    _writeFile('${repository.path}/Makefile', 'runner:\n\t@true\n');
    _writeFile('${project.path}/bin/main.dart', 'void main() {}\n');
    _writeFile(
      '${project.path}/.dart_tool/package_config.json',
      '{"configVersion":2,"packages":[]}\n',
    );
    _writeFile('${sdk.path}/bin/dart', 'fake dart');
    _writeFile('${sdk.path}/version', '3.13.2\n');
    _writeFile(
      '${sdk.path}/revision',
      '60a57cd42d64dc03e9f07aa60a2e250755c1ef28\n',
    );
    _writeFile('${engine.path}/runtime/include/dart_api.h', '// fake\n');
    _writeFile(
      '${engine.path}/runtime/engine/include/dart_engine.h',
      '// fake\n',
    );
    _writeFile('${engine.path}/LICENSE', 'fake Dart SDK license\n');
    _writeFile(engineLibrary.path, 'fake dylib');
    _writeEngineBuildTools(engineLibrary.parent.path);
    return _Fixture._(
      root: root,
      repository: repository,
      project: project,
      sdk: sdk,
      engine: engine,
      engineLibrary: engineLibrary,
      executor: _FakeExecutor(),
    );
  }

  final Directory root;
  final Directory repository;
  final Directory project;
  final Directory sdk;
  final Directory engine;
  final File engineLibrary;
  final _FakeExecutor executor;

  DartAppKitLauncher launcher({
    Map<String, String>? environment,
    StringBuffer? output,
    StringBuffer? errors,
  }) {
    return DartAppKitLauncher(
      repositoryRoot: repository.path,
      currentDirectory: project.path,
      resolvedDartExecutable: '${sdk.path}/bin/dart',
      operatingSystem: 'macos',
      environment:
          environment ??
          <String, String>{
            'DART_ENGINE_ROOT': engine.path,
            'DART_ENGINE_LIBRARY': engineLibrary.path,
          },
      processExecutor: executor,
      output: output?.write ?? _discard,
      errorOutput: errors?.write ?? _discard,
    );
  }

  void installDefaultEngine() {
    final String defaultRoot = '${repository.path}/.dart_tool/dart-engine/sdk';
    _writeFile('$defaultRoot/LICENSE', 'fake Dart SDK license\n');
    _writeFile('$defaultRoot/runtime/include/dart_api.h', '// fake\n');
    _writeFile(
      '$defaultRoot/runtime/engine/include/dart_engine.h',
      '// fake\n',
    );
    _writeFile(
      '$defaultRoot/xcodebuild/ReleaseARM64/'
          'libdart_engine_jit_shared.dylib',
      'fake arm64 dylib',
    );
    _writeEngineBuildTools('$defaultRoot/xcodebuild/ReleaseARM64');
    _writeFile(
      '$defaultRoot/xcodebuild/ReleaseX64/'
          'libdart_engine_jit_shared.dylib',
      'fake x64 dylib',
    );
    _writeEngineBuildTools('$defaultRoot/xcodebuild/ReleaseX64');
  }

  Future<void> dispose() => root.delete(recursive: true);
}

void _writeFile(String path, String content) {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void _writeEngineBuildTools(String buildDirectory) {
  _writeFile('$buildDirectory/bootstrap_gen_kernel.exe', 'fake compiler');
  _writeFile(
    '$buildDirectory/clang_arm64_shared/vm_platform.dill',
    'fake arm64 platform',
  );
  _writeFile(
    '$buildDirectory/clang_x64_shared/vm_platform.dill',
    'fake x64 platform',
  );
}

Future<void> _testOptionsAndHelp() async {
  final LauncherOptions options = LauncherOptions.parse(<String>[
    '--build-dir=out',
    '--engine-root',
    'engine',
    '--engine-library=engine.dylib',
    'bin/main.dart',
    '--',
    '--application-flag',
    'two words',
  ]);
  _expect(options.entrypoint == 'bin/main.dart', 'entrypoint parsed');
  _expect(options.buildDirectory == 'out', 'build directory parsed');
  _expect(options.engineRoot == 'engine', 'engine root parsed');
  _expect(options.engineLibrary == 'engine.dylib', 'engine library parsed');
  _expect(
    options.applicationArguments.join('|') == '--application-flag|two words',
    'application arguments preserved',
  );

  final StringBuffer help = StringBuffer();
  final int helpExit = await runLauncherCommand(<String>[
    '--help',
  ], output: help.write);
  _expect(helpExit == 0, 'help succeeds');
  _expect(help.toString().contains('Usage:'), 'help contains usage');

  final LauncherException missingValue = await _expectLauncherError(
    () => LauncherOptions.parse(<String>['--build-dir']),
  );
  _expect(missingValue.exitCode == launcherUsageExitCode, 'usage exit code');
  final LauncherException extraEntrypoint = await _expectLauncherError(
    () => LauncherOptions.parse(<String>['one.dart', 'two.dart']),
  );
  _expect(
    extraEntrypoint.message.contains('only one entrypoint'),
    'extra entrypoint guidance',
  );
}

Future<void> _testFullWorkflowAndForwarding() async {
  final _Fixture fixture = await _Fixture.create();
  try {
    final StringBuffer output = StringBuffer();
    final DartAppKitLauncher launcher = fixture.launcher(output: output);
    final LauncherOptions options = LauncherOptions.parse(<String>[
      '--build-dir',
      'generated',
      'bin/main.dart',
      '--',
      'first',
      'two words',
    ]);
    final int result = await launcher.run(options);
    _expect(
      result == fixture.executor.launchedExitCode,
      'Runner exit forwarded',
    );
    _expect(output.toString().contains('native build passed'), 'build output');
    _expect(fixture.executor.commands.length == 4, 'four commands executed');

    final _RecordedCommand make = fixture.executor.commands[0];
    final String resolvedSdk = await fixture.sdk.resolveSymbolicLinks();
    final String resolvedEngine = await fixture.engine.resolveSymbolicLinks();
    final String resolvedProject = await fixture.project.resolveSymbolicLinks();
    _expect(make.executable == 'make', 'Make runs first');
    _expect(make.arguments.last == 'runner', 'Runner target selected');
    _expect(
      make.arguments.any((String value) => value == 'DART_SDK=$resolvedSdk'),
      'SDK path forwarded to Make',
    );
    _expect(
      make.arguments.any(
        (String value) => value == 'DART_ENGINE_ROOT=$resolvedEngine',
      ),
      'Engine root forwarded to Make',
    );

    final _RecordedCommand compiler = fixture.executor.commands[1];
    final String resolvedEngineBuild = await fixture.engineLibrary.parent
        .resolveSymbolicLinks();
    _expect(
      compiler.executable == '$resolvedEngineBuild/bootstrap_gen_kernel.exe',
      'revision-matched Engine compiler used',
    );
    _expect(
      compiler.arguments.contains('--link-platform'),
      'platform Kernel linked explicitly',
    );
    _expect(
      compiler.arguments.any(
        (String value) =>
            value.startsWith('--platform=$resolvedEngineBuild/clang_'),
      ),
      'revision-matched Engine platform used',
    );
    _expect(
      compiler.arguments.contains(
        '--packages=$resolvedProject/.dart_tool/package_config.json',
      ),
      'nearest package config forwarded',
    );

    final Directory bundle = Directory(
      '${fixture.project.path}/generated/DartAppKitRunner.app/Contents',
    );
    _expect(
      File('${bundle.path}/MacOS/dart_appkit_runner').existsSync(),
      'Runner copied into bundle',
    );
    _expect(
      File('${bundle.path}/Frameworks/libdart_engine_jit_shared.dylib')
          .existsSync(),
      'Engine copied under its rpath install name',
    );
    _expect(
      File('${bundle.path}/Resources/application.dill').existsSync(),
      'Kernel copied into bundle',
    );
    _expect(
      File('${bundle.path}/Resources/DART_SDK_LICENSE.txt')
              .readAsStringSync() ==
          'fake Dart SDK license\n',
      'exact Dart SDK license copied into bundle',
    );
    _expect(
      File('${bundle.path}/Info.plist')
          .readAsStringSync()
          .contains('<string>dart_appkit_runner</string>'),
      'Info.plist names Runner',
    );

    final _RecordedCommand launch = fixture.executor.commands[3];
    _expect(launch.inheritStdio, 'Runner inherits stdio');
    _expect(
      _containsInOrder(launch.arguments, <String>[
        '--sdk-version',
        '3.13.2',
        '--sdk-revision',
        '60a57cd42d64dc03e9f07aa60a2e250755c1ef28',
        '--',
        'first',
        'two words',
      ]),
      'metadata and application arguments forwarded in order',
    );
  } finally {
    await fixture.dispose();
  }
}

Future<void> _testConfigurationAndPackageFailuresAreEarly() async {
  final _Fixture fixture = await _Fixture.create();
  try {
    final DartAppKitLauncher missingEngine = fixture.launcher(
      environment: const <String, String>{},
    );
    final LauncherOptions options = LauncherOptions.parse(<String>[
      'bin/main.dart',
    ]);
    final LauncherException engineError = await _expectLauncherError(
      () => missingEngine.run(options),
    );
    _expect(
      engineError.exitCode == launcherUnavailableExitCode,
      'missing Engine unavailable exit',
    );
    _expect(
      engineError.message.contains('DART_ENGINE_ROOT'),
      'missing Engine key named',
    );
    _expect(
      fixture.executor.commands.isEmpty,
      'no command before Engine error',
    );

    _writeFile('${fixture.sdk.path}/version', '3.14.0\n');
    final LauncherException versionError = await _expectLauncherError(
      () => fixture.launcher().run(options),
    );
    _expect(
      versionError.message.contains('requires Dart 3.13.2'),
      'pinned SDK mismatch guidance',
    );
    _expect(fixture.executor.commands.isEmpty, 'no command before SDK error');
    _writeFile('${fixture.sdk.path}/version', '3.13.2\n');

    _writeFile('${fixture.sdk.path}/revision', 'not-the-pinned-revision\n');
    final LauncherException revisionError = await _expectLauncherError(
      () => fixture.launcher().run(options),
    );
    _expect(
      revisionError.message.contains(pinnedDartSdkRevision),
      'pinned revision mismatch guidance',
    );
    _expect(
      fixture.executor.commands.isEmpty,
      'no command before revision error',
    );
    _writeFile('${fixture.sdk.path}/revision', '$pinnedDartSdkRevision\n');

    File('${fixture.project.path}/.dart_tool/package_config.json').deleteSync();
    final LauncherException packageError = await _expectLauncherError(
      () => fixture.launcher().run(options),
    );
    _expect(
      packageError.message.contains('dart pub get'),
      'missing package config remediation',
    );
    _expect(
      fixture.executor.commands.isEmpty,
      'no command before package error',
    );
  } finally {
    await fixture.dispose();
  }
}

Future<void> _testDefaultEngineDiscovery() async {
  final _Fixture fixture = await _Fixture.create();
  try {
    fixture.installDefaultEngine();
    final DartAppKitLauncher launcher = fixture.launcher(
      environment: const <String, String>{},
    );
    final int result = await launcher.run(
      LauncherOptions.parse(<String>['bin/main.dart']),
    );
    _expect(result == fixture.executor.launchedExitCode, 'Runner launched');

    final _RecordedCommand make = fixture.executor.commands.first;
    final String defaultRoot = await Directory(
      '${fixture.repository.path}/.dart_tool/dart-engine/sdk',
    ).resolveSymbolicLinks();
    _expect(
      make.arguments.contains('DART_ENGINE_ROOT=$defaultRoot'),
      'project-local Engine root discovered',
    );
    _expect(
      make.arguments.any(
        (String value) =>
            value.startsWith('DART_ENGINE_LIBRARY=$defaultRoot/xcodebuild/'),
      ),
      'standard Engine library discovered',
    );
  } finally {
    await fixture.dispose();
  }
}

Future<void> _testCommandFailuresPropagate() async {
  final _Fixture makeFixture = await _Fixture.create();
  try {
    makeFixture.executor.makeExitCode = 2;
    final StringBuffer errors = StringBuffer();
    final LauncherException error = await _expectLauncherError(
      () => makeFixture
          .launcher(errors: errors)
          .run(LauncherOptions.parse(<String>['bin/main.dart'])),
    );
    _expect(error.exitCode == 2, 'Make exit code propagated');
    _expect(errors.toString().contains('Make failure'), 'Make stderr relayed');
    _expect(
      makeFixture.executor.commands.length == 1,
      'failure stops workflow',
    );
  } finally {
    await makeFixture.dispose();
  }

  final _Fixture compilerFixture = await _Fixture.create();
  try {
    compilerFixture.executor.compilerExitCode = 65;
    final StringBuffer errors = StringBuffer();
    final LauncherException error = await _expectLauncherError(
      () => compilerFixture
          .launcher(errors: errors)
          .run(LauncherOptions.parse(<String>['bin/main.dart'])),
    );
    _expect(error.exitCode == 65, 'compiler exit code propagated');
    _expect(
      errors.toString().contains('compiler failure'),
      'compiler stderr relayed',
    );
    _expect(
      compilerFixture.executor.commands.length == 2,
      'bundle and launch skipped after compiler failure',
    );
  } finally {
    await compilerFixture.dispose();
  }
}

Future<void> main() async {
  await _test('launcher options and help', _testOptionsAndHelp);
  await _test(
    'launcher workflow, bundle, and forwarding',
    _testFullWorkflowAndForwarding,
  );
  await _test(
    'launcher rejects missing configuration before work',
    _testConfigurationAndPackageFailuresAreEarly,
  );
  await _test(
    'launcher discovers the project-local Engine',
    _testDefaultEngineDiscovery,
  );
  await _test(
    'launcher command failures propagate',
    _testCommandFailuresPropagate,
  );
  if (_failures != 0) {
    stderr.writeln('$_failures launcher test(s) failed');
    exitCode = 1;
    return;
  }
  stdout.writeln('all launcher tests passed');
}
