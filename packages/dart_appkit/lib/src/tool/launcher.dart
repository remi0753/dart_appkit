import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

const int launcherUsageExitCode = 64;
const int launcherUnavailableExitCode = 69;
const int launcherSoftwareExitCode = 70;
const int launcherOsErrorExitCode = 71;
const int launcherIoErrorExitCode = 74;
const String pinnedDartSdkVersion = '3.13.2';
const String pinnedDartSdkRevision = '60a57cd42d64dc03e9f07aa60a2e250755c1ef28';

const String launcherUsage = '''
Usage: dart run dart_appkit:run [options] <entrypoint.dart> [-- arguments...]

Options:
  -h, --help                    Show this help.
      --build-dir <directory>   Generated files directory.
                                Default: <package>/.dart_tool/dart_appkit
      --engine-root <directory> Matching Dart SDK source checkout.
      --engine-library <file>   Built libdart_engine_jit_shared.dylib.

The Engine options default to DART_ENGINE_ROOT and DART_ENGINE_LIBRARY, then
to the checkout created by scripts/bootstrap_dart_engine.sh.
See docs/BUILDING_DART_ENGINE.md in the dart_appkit checkout.
''';

typedef LauncherOutput = void Function(String value);

final class LauncherException implements Exception {
  const LauncherException(this.message, {required this.exitCode});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

final class LauncherOptions {
  const LauncherOptions({
    required this.showHelp,
    required this.entrypoint,
    required this.buildDirectory,
    required this.engineRoot,
    required this.engineLibrary,
    required this.applicationArguments,
  });

  factory LauncherOptions.parse(List<String> arguments) {
    var showHelp = false;
    String? entrypoint;
    String? buildDirectory;
    String? engineRoot;
    String? engineLibrary;
    final List<String> applicationArguments = <String>[];
    var forwardingArguments = false;

    for (var index = 0; index < arguments.length; ++index) {
      final String argument = arguments[index];
      if (forwardingArguments) {
        applicationArguments.add(argument);
        continue;
      }
      if (argument == '--') {
        forwardingArguments = true;
        continue;
      }
      if (argument == '-h' || argument == '--help') {
        showHelp = true;
        continue;
      }

      String readOptionValue(String option) {
        final String prefix = '$option=';
        if (argument.startsWith(prefix)) {
          final String value = argument.substring(prefix.length);
          if (value.isEmpty) {
            throw LauncherException(
              '$option requires a value',
              exitCode: launcherUsageExitCode,
            );
          }
          return value;
        }
        if (argument == option) {
          if (index + 1 >= arguments.length) {
            throw LauncherException(
              '$option requires a value',
              exitCode: launcherUsageExitCode,
            );
          }
          return arguments[++index];
        }
        throw StateError('readOptionValue called for another option');
      }

      if (argument == '--build-dir' || argument.startsWith('--build-dir=')) {
        buildDirectory = readOptionValue('--build-dir');
      } else if (argument == '--engine-root' ||
          argument.startsWith('--engine-root=')) {
        engineRoot = readOptionValue('--engine-root');
      } else if (argument == '--engine-library' ||
          argument.startsWith('--engine-library=')) {
        engineLibrary = readOptionValue('--engine-library');
      } else if (argument.startsWith('-')) {
        throw LauncherException(
          'unknown option: $argument',
          exitCode: launcherUsageExitCode,
        );
      } else if (entrypoint == null) {
        entrypoint = argument;
      } else {
        throw const LauncherException(
          'only one entrypoint is allowed; put application arguments after --',
          exitCode: launcherUsageExitCode,
        );
      }
    }

    if (!showHelp && entrypoint == null) {
      throw const LauncherException(
        'an entrypoint Dart file is required',
        exitCode: launcherUsageExitCode,
      );
    }
    return LauncherOptions(
      showHelp: showHelp,
      entrypoint: entrypoint,
      buildDirectory: buildDirectory,
      engineRoot: engineRoot,
      engineLibrary: engineLibrary,
      applicationArguments: List<String>.unmodifiable(applicationArguments),
    );
  }

  final bool showHelp;
  final String? entrypoint;
  final String? buildDirectory;
  final String? engineRoot;
  final String? engineLibrary;
  final List<String> applicationArguments;
}

final class LauncherCommandResult {
  const LauncherCommandResult({
    required this.exitCode,
    this.stdoutText = '',
    this.stderrText = '',
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;
}

abstract interface class LauncherProcessExecutor {
  Future<LauncherCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool inheritStdio = false,
  });
}

final class SystemLauncherProcessExecutor implements LauncherProcessExecutor {
  const SystemLauncherProcessExecutor();

  @override
  Future<LauncherCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool inheritStdio = false,
  }) async {
    if (inheritStdio) {
      final Process process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.inheritStdio,
      );
      return LauncherCommandResult(exitCode: await process.exitCode);
    }

    final ProcessResult result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return LauncherCommandResult(
      exitCode: result.exitCode,
      stdoutText: result.stdout as String,
      stderrText: result.stderr as String,
    );
  }
}

final class DartAppKitLauncher {
  DartAppKitLauncher({
    required this.repositoryRoot,
    required this.currentDirectory,
    required this.resolvedDartExecutable,
    required this.operatingSystem,
    required Map<String, String> environment,
    LauncherProcessExecutor processExecutor =
        const SystemLauncherProcessExecutor(),
    LauncherOutput? output,
    LauncherOutput? errorOutput,
  }) : environment = Map<String, String>.unmodifiable(environment),
       processExecutor = processExecutor,
       output = output ?? stdout.write,
       errorOutput = errorOutput ?? stderr.write;

  static Future<DartAppKitLauncher> create({
    LauncherOutput? output,
    LauncherOutput? errorOutput,
  }) async {
    final Uri? libraryUri = await Isolate.resolvePackageUri(
      Uri.parse('package:dart_appkit/dart_appkit.dart'),
    );
    if (libraryUri == null || libraryUri.scheme != 'file') {
      throw const LauncherException(
        'could not resolve the installed dart_appkit package',
        exitCode: launcherSoftwareExitCode,
      );
    }
    final Directory packageRoot = File.fromUri(libraryUri).parent.parent;
    final Directory repositoryRoot = packageRoot.parent.parent;
    return DartAppKitLauncher(
      repositoryRoot: repositoryRoot.path,
      currentDirectory: Directory.current.path,
      resolvedDartExecutable: Platform.resolvedExecutable,
      operatingSystem: Platform.operatingSystem,
      environment: Platform.environment,
      output: output,
      errorOutput: errorOutput,
    );
  }

  final String repositoryRoot;
  final String currentDirectory;
  final String resolvedDartExecutable;
  final String operatingSystem;
  final Map<String, String> environment;
  final LauncherProcessExecutor processExecutor;
  final LauncherOutput output;
  final LauncherOutput errorOutput;

  Future<int> run(LauncherOptions options) async {
    try {
      return await _run(options);
    } on LauncherException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LauncherException(
        'file operation failed: ${error.message}'
        '${error.path == null ? '' : ' (${error.path})'}',
        exitCode: launcherIoErrorExitCode,
      );
    } on ProcessException catch (error) {
      throw LauncherException(
        'could not start ${error.executable}: ${error.message}',
        exitCode: launcherOsErrorExitCode,
      );
    }
  }

  Future<int> _run(LauncherOptions options) async {
    if (operatingSystem != 'macos') {
      throw LauncherException(
        'AppKit Runner requires macOS; current platform is $operatingSystem',
        exitCode: launcherUnavailableExitCode,
      );
    }

    final File entrypoint = await _existingFile(
      _resolvePath(options.entrypoint!),
      description: 'entrypoint',
    );
    if (!entrypoint.path.endsWith('.dart')) {
      throw LauncherException(
        'entrypoint must be a .dart file: ${entrypoint.path}',
        exitCode: launcherUsageExitCode,
      );
    }
    final File packageConfig = await _findPackageConfig(entrypoint.parent);
    final Directory projectRoot = packageConfig.parent.parent;

    final File dartExecutable = await _existingFile(
      resolvedDartExecutable,
      description: 'Dart executable',
    );
    final Directory sdkRoot = dartExecutable.parent.parent;
    final String sdkVersion = await _readMetadata(sdkRoot, 'version');
    final String sdkRevision = await _readMetadata(sdkRoot, 'revision');
    if (sdkVersion != pinnedDartSdkVersion) {
      throw LauncherException(
        'this prototype requires Dart $pinnedDartSdkVersion; the active SDK '
        'is $sdkVersion at ${sdkRoot.path}',
        exitCode: launcherUnavailableExitCode,
      );
    }
    if (sdkRevision != pinnedDartSdkRevision) {
      throw LauncherException(
        'this prototype requires Dart SDK revision $pinnedDartSdkRevision; '
        'the active SDK is $sdkRevision at ${sdkRoot.path}',
        exitCode: launcherUnavailableExitCode,
      );
    }

    String? configuredEngineRoot = options.engineRoot;
    if (configuredEngineRoot == null || configuredEngineRoot.isEmpty) {
      configuredEngineRoot = environment['DART_ENGINE_ROOT'];
    }
    if (configuredEngineRoot == null || configuredEngineRoot.isEmpty) {
      final String defaultEngineRoot = _join(
        repositoryRoot,
        '.dart_tool/dart-engine/sdk',
      );
      if (!await Directory(defaultEngineRoot).exists()) {
        throw _engineConfigurationError(
          'DART_ENGINE_ROOT is not set and the default checkout does not '
          'exist: $defaultEngineRoot. Run '
          './scripts/bootstrap_dart_engine.sh',
        );
      }
      configuredEngineRoot = defaultEngineRoot;
    }

    final Directory engineRoot = await _existingDirectory(
      _resolvePath(configuredEngineRoot),
      description: 'Dart Engine source root',
      engineConfiguration: true,
    );
    await _existingFile(
      _join(engineRoot.path, 'runtime/include/dart_api.h'),
      description: 'Dart Engine public API header',
      engineConfiguration: true,
    );
    await _existingFile(
      _join(engineRoot.path, 'runtime/engine/include/dart_engine.h'),
      description: 'Dart Engine API header',
      engineConfiguration: true,
    );
    final File dartSdkLicense = await _existingFile(
      _join(engineRoot.path, 'LICENSE'),
      description: 'Dart SDK license',
      engineConfiguration: true,
    );

    String? configuredEngineLibrary = options.engineLibrary;
    if (configuredEngineLibrary == null || configuredEngineLibrary.isEmpty) {
      configuredEngineLibrary = environment['DART_ENGINE_LIBRARY'];
    }
    if (configuredEngineLibrary == null || configuredEngineLibrary.isEmpty) {
      configuredEngineLibrary = _defaultEngineLibrary(engineRoot.path);
      if (!await File(configuredEngineLibrary).exists()) {
        throw _engineConfigurationError(
          'DART_ENGINE_LIBRARY is not set and the default library does not '
          'exist: $configuredEngineLibrary. Run '
          './scripts/bootstrap_dart_engine.sh',
        );
      }
    }
    final File engineLibrary = await _existingFile(
      _resolvePath(configuredEngineLibrary),
      description: 'Dart Engine library',
      engineConfiguration: true,
    );
    final File kernelCompiler = await _existingFile(
      _join(engineLibrary.parent.path, 'bootstrap_gen_kernel.exe'),
      description: 'Dart Engine Kernel compiler',
      engineConfiguration: true,
    );
    final File platformKernel = await _existingFile(
      _join(
        engineLibrary.parent.path,
        '${_engineSharedToolchainDirectory()}/vm_platform.dill',
      ),
      description: 'Dart Engine platform Kernel',
      engineConfiguration: true,
    );
    await _existingFile(
      _join(repositoryRoot, 'Makefile'),
      description: 'dart_appkit repository Makefile',
    );

    final Directory buildRoot = Directory(
      options.buildDirectory == null
          ? _join(projectRoot.path, '.dart_tool/dart_appkit')
          : _resolvePath(options.buildDirectory!),
    );
    await buildRoot.create(recursive: true);

    final String engineCacheKey = _fnv1a32(engineLibrary.path);
    final Directory nativeBuildRoot = Directory(
      _join(buildRoot.path, 'native-$sdkRevision-$engineCacheKey'),
    );
    await _runChecked(
      label: 'native Runner build',
      executable: 'make',
      arguments: <String>[
        '-C',
        repositoryRoot,
        'BUILD_DIR=${nativeBuildRoot.path}',
        'DART_SDK=${sdkRoot.path}',
        'DART_ENGINE_ROOT=${engineRoot.path}',
        'DART_ENGINE_LIBRARY=${engineLibrary.path}',
        'runner',
      ],
      workingDirectory: projectRoot.path,
    );
    final File runner = await _existingFile(
      _join(nativeBuildRoot.path, 'native/dart_appkit_runner'),
      description: 'built native Runner',
    );

    final Directory kernelDirectory = Directory(
      _join(buildRoot.path, 'kernel'),
    );
    await kernelDirectory.create(recursive: true);
    final File kernel = File(_join(kernelDirectory.path, 'application.dill'));
    final File depfile = File('${kernel.path}.d');
    await _runChecked(
      label: 'Kernel compilation',
      executable: kernelCompiler.path,
      arguments: <String>[
        '--platform=${platformKernel.path}',
        '--packages=${packageConfig.path}',
        '--no-aot',
        '--link-platform',
        '--no-embed-sources',
        '--output=${kernel.path}',
        '--depfile=${depfile.path}',
        '-Dsdk_hash=${sdkRevision.substring(0, 10)}',
        '-Ddart.vm.product=false',
        '-Ddart.vm.asan=false',
        '-Ddart.vm.msan=false',
        '-Ddart.vm.tsan=false',
        entrypoint.path,
      ],
      workingDirectory: projectRoot.path,
    );
    await _existingFile(kernel.path, description: 'compiled Kernel');

    final _Bundle bundle = await _assembleBundle(
      buildRoot: buildRoot,
      runner: runner,
      engineLibrary: engineLibrary,
      kernel: kernel,
      dartSdkLicense: dartSdkLicense,
      workingDirectory: projectRoot.path,
    );
    final LauncherCommandResult result = await processExecutor.run(
      bundle.executable.path,
      <String>[
        '--kernel',
        bundle.kernel.path,
        '--sdk-version',
        sdkVersion,
        '--sdk-revision',
        sdkRevision,
        '--',
        ...options.applicationArguments,
      ],
      workingDirectory: projectRoot.path,
      inheritStdio: true,
    );
    return result.exitCode;
  }

  Future<_Bundle> _assembleBundle({
    required Directory buildRoot,
    required File runner,
    required File engineLibrary,
    required File kernel,
    required File dartSdkLicense,
    required String workingDirectory,
  }) async {
    final Directory bundle = Directory(
      _join(buildRoot.path, 'DartAppKitRunner.app'),
    );
    if (await bundle.exists()) {
      await bundle.delete(recursive: true);
    }
    final Directory contents = Directory(_join(bundle.path, 'Contents'));
    final Directory macos = Directory(_join(contents.path, 'MacOS'));
    final Directory frameworks = Directory(_join(contents.path, 'Frameworks'));
    final Directory resources = Directory(_join(contents.path, 'Resources'));
    await Future.wait(<Future<Directory>>[
      macos.create(recursive: true),
      frameworks.create(recursive: true),
      resources.create(recursive: true),
    ]);

    final File bundledRunner = File(_join(macos.path, 'dart_appkit_runner'));
    final File bundledEngine = File(
      _join(frameworks.path, 'libdart_engine_jit_shared.dylib'),
    );
    final File bundledKernel = File(_join(resources.path, 'application.dill'));
    final File bundledDartSdkLicense = File(
      _join(resources.path, 'DART_SDK_LICENSE.txt'),
    );
    await Future.wait(<Future<File>>[
      runner.copy(bundledRunner.path),
      engineLibrary.copy(bundledEngine.path),
      kernel.copy(bundledKernel.path),
      dartSdkLicense.copy(bundledDartSdkLicense.path),
    ]);

    final File infoPlist = File(_join(contents.path, 'Info.plist'));
    await infoPlist.writeAsString(_infoPlist, flush: true);
    await _runChecked(
      label: 'Runner executable permission update',
      executable: '/bin/chmod',
      arguments: <String>['755', bundledRunner.path],
      workingDirectory: workingDirectory,
    );
    return _Bundle(executable: bundledRunner, kernel: bundledKernel);
  }

  Future<void> _runChecked({
    required String label,
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    final LauncherCommandResult result = await processExecutor.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.stdoutText.isNotEmpty) {
      output(result.stdoutText);
    }
    if (result.stderrText.isNotEmpty) {
      errorOutput(result.stderrText);
    }
    if (result.exitCode != 0) {
      throw LauncherException(
        '$label failed with exit code ${result.exitCode}',
        exitCode: result.exitCode,
      );
    }
  }

  Future<File> _existingFile(
    String path, {
    required String description,
    bool engineConfiguration = false,
  }) async {
    final File file = File(path);
    if (!await file.exists()) {
      if (engineConfiguration) {
        throw _engineConfigurationError('$description does not exist: $path');
      }
      throw LauncherException(
        '$description does not exist: $path',
        exitCode: launcherIoErrorExitCode,
      );
    }
    return File(await file.resolveSymbolicLinks());
  }

  Future<Directory> _existingDirectory(
    String path, {
    required String description,
    bool engineConfiguration = false,
  }) async {
    final Directory directory = Directory(path);
    if (!await directory.exists()) {
      if (engineConfiguration) {
        throw _engineConfigurationError('$description does not exist: $path');
      }
      throw LauncherException(
        '$description does not exist: $path',
        exitCode: launcherIoErrorExitCode,
      );
    }
    return Directory(await directory.resolveSymbolicLinks());
  }

  Future<File> _findPackageConfig(Directory start) async {
    Directory cursor = start;
    while (true) {
      final File candidate = File(
        _join(cursor.path, '.dart_tool/package_config.json'),
      );
      if (await candidate.exists()) {
        return File(await candidate.resolveSymbolicLinks());
      }
      final Directory parent = cursor.parent;
      if (parent.path == cursor.path) {
        throw LauncherException(
          'no .dart_tool/package_config.json found above ${start.path}; '
          'run dart pub get in the application package',
          exitCode: launcherUsageExitCode,
        );
      }
      cursor = parent;
    }
  }

  Future<String> _readMetadata(Directory sdkRoot, String name) async {
    final File file = await _existingFile(
      _join(sdkRoot.path, name),
      description: 'Dart SDK $name metadata',
    );
    final String value = (await file.readAsString()).trim();
    if (value.isEmpty) {
      throw LauncherException(
        'Dart SDK $name metadata is empty: ${file.path}',
        exitCode: launcherIoErrorExitCode,
      );
    }
    return value;
  }

  LauncherException _engineConfigurationError(String detail) {
    return LauncherException(
      '$detail. Provide the revision-matched Dart Engine described in '
      'docs/BUILDING_DART_ENGINE.md',
      exitCode: launcherUnavailableExitCode,
    );
  }

  String _defaultEngineLibrary(String engineRoot) {
    final Abi abi = Abi.current();
    final String releaseDirectory;
    if (abi == Abi.macosArm64) {
      releaseDirectory = 'ReleaseARM64';
    } else if (abi == Abi.macosX64) {
      releaseDirectory = 'ReleaseX64';
    } else {
      throw _engineConfigurationError(
        'unsupported macOS Dart ABI for the Engine build: $abi',
      );
    }
    return _join(
      engineRoot,
      'xcodebuild/$releaseDirectory/libdart_engine_jit_shared.dylib',
    );
  }

  String _engineSharedToolchainDirectory() {
    final Abi abi = Abi.current();
    if (abi == Abi.macosArm64) {
      return 'clang_arm64_shared';
    }
    if (abi == Abi.macosX64) {
      return 'clang_x64_shared';
    }
    throw _engineConfigurationError(
      'unsupported macOS Dart ABI for the Engine toolchain: $abi',
    );
  }

  String _resolvePath(String value) {
    final Uri valueUri = Uri.file(value);
    if (valueUri.isAbsolute) {
      return File.fromUri(valueUri).path;
    }
    return File.fromUri(
      Directory(currentDirectory).absolute.uri.resolveUri(valueUri),
    ).path;
  }

  static String _join(String parent, String child) {
    return Directory(parent).uri.resolve(child).toFilePath();
  }

  static String _fnv1a32(String value) {
    var hash = 0x811c9dc5;
    for (final int byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

final class _Bundle {
  const _Bundle({required this.executable, required this.kernel});

  final File executable;
  final File kernel;
}

const String _infoPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>dart_appkit_runner</string>
  <key>CFBundleIdentifier</key>
  <string>dev.dart-appkit.runner</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Dart AppKit Runner</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
''';

Future<int> runLauncherCommand(
  List<String> arguments, {
  DartAppKitLauncher? launcher,
  LauncherOutput? output,
  LauncherOutput? errorOutput,
}) async {
  final LauncherOutput writeOutput = output ?? stdout.write;
  final LauncherOutput writeError = errorOutput ?? stderr.write;
  try {
    final LauncherOptions options = LauncherOptions.parse(arguments);
    if (options.showHelp) {
      writeOutput(launcherUsage);
      return 0;
    }
    final DartAppKitLauncher activeLauncher =
        launcher ??
        await DartAppKitLauncher.create(
          output: writeOutput,
          errorOutput: writeError,
        );
    return await activeLauncher.run(options);
  } on LauncherException catch (error) {
    writeError('dart_appkit:run: ${error.message}\n');
    if (error.exitCode == launcherUsageExitCode) {
      writeError(launcherUsage);
    }
    return error.exitCode;
  } on Object catch (error, stackTrace) {
    writeError('dart_appkit:run: unexpected failure: $error\n$stackTrace\n');
    return launcherSoftwareExitCode;
  }
}
