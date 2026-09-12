import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import '../application_manifest.dart';

const int builderUsageExitCode = 64;
const int builderUnavailableExitCode = 69;
const int builderSoftwareExitCode = 70;
const int builderOsErrorExitCode = 71;
const int builderIoErrorExitCode = 74;
const String pinnedDartSdkVersion = '3.13.2';
const String pinnedDartSdkRevision = '60a57cd42d64dc03e9f07aa60a2e250755c1ef28';
const List<String> appIntentsConstGatherProtocols = <String>[
  'AppIntent',
  'AppShortcutsProvider',
];

const String builderUsage = '''
Usage: dart run dart_macos_runtime:build --manifest <file> [options]
       [-- application arguments...]

Options:
  -h, --help                    Show this help.
      --mode <mode>             developer-jit or release-aot.
                                Default: developer-jit
      --build-dir <directory>   Generated files directory.
      --engine-root <directory> Matching Dart SDK source checkout.
      --run                     Launch the assembled application.
''';

typedef BuilderOutput = void Function(String value);

enum RuntimeBuildMode {
  developerJit('developer-jit'),
  releaseAot('release-aot');

  const RuntimeBuildMode(this.name);
  final String name;
}

final class RuntimeBuilderException implements Exception {
  const RuntimeBuilderException(this.message, {required this.exitCode});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

final class RuntimeBuilderOptions {
  const RuntimeBuilderOptions({
    required this.showHelp,
    required this.manifestPath,
    required this.mode,
    required this.buildDirectory,
    required this.engineRoot,
    required this.runApplication,
    required this.applicationArguments,
  });

  factory RuntimeBuilderOptions.parse(List<String> arguments) {
    var showHelp = false;
    String? manifestPath;
    var mode = RuntimeBuildMode.developerJit;
    String? buildDirectory;
    String? engineRoot;
    var runApplication = false;
    var forwarding = false;
    final List<String> applicationArguments = <String>[];

    for (var index = 0; index < arguments.length; ++index) {
      final String argument = arguments[index];
      if (forwarding) {
        applicationArguments.add(argument);
        continue;
      }
      if (argument == '--') {
        forwarding = true;
        continue;
      }
      if (argument == '-h' || argument == '--help') {
        showHelp = true;
        continue;
      }
      if (argument == '--run') {
        runApplication = true;
        continue;
      }

      String optionValue(String name) {
        if (argument.startsWith('$name=')) {
          final String value = argument.substring(name.length + 1);
          if (value.isEmpty) {
            throw RuntimeBuilderException(
              '$name requires a value',
              exitCode: builderUsageExitCode,
            );
          }
          return value;
        }
        if (argument == name && index + 1 < arguments.length) {
          return arguments[++index];
        }
        throw RuntimeBuilderException(
          '$name requires a value',
          exitCode: builderUsageExitCode,
        );
      }

      if (argument == '--manifest' || argument.startsWith('--manifest=')) {
        manifestPath = optionValue('--manifest');
      } else if (argument == '--mode' || argument.startsWith('--mode=')) {
        final String value = optionValue('--mode');
        mode = RuntimeBuildMode.values.firstWhere(
          (RuntimeBuildMode candidate) => candidate.name == value,
          orElse: () => throw RuntimeBuilderException(
            '--mode must be developer-jit or release-aot: $value',
            exitCode: builderUsageExitCode,
          ),
        );
      } else if (argument == '--build-dir' ||
          argument.startsWith('--build-dir=')) {
        buildDirectory = optionValue('--build-dir');
      } else if (argument == '--engine-root' ||
          argument.startsWith('--engine-root=')) {
        engineRoot = optionValue('--engine-root');
      } else {
        throw RuntimeBuilderException(
          'unknown option: $argument',
          exitCode: builderUsageExitCode,
        );
      }
    }
    if (!showHelp && manifestPath == null) {
      throw const RuntimeBuilderException(
        '--manifest is required',
        exitCode: builderUsageExitCode,
      );
    }
    if (!runApplication && applicationArguments.isNotEmpty) {
      throw const RuntimeBuilderException(
        'application arguments require --run',
        exitCode: builderUsageExitCode,
      );
    }
    return RuntimeBuilderOptions(
      showHelp: showHelp,
      manifestPath: manifestPath,
      mode: mode,
      buildDirectory: buildDirectory,
      engineRoot: engineRoot,
      runApplication: runApplication,
      applicationArguments: List<String>.unmodifiable(applicationArguments),
    );
  }

  final bool showHelp;
  final String? manifestPath;
  final RuntimeBuildMode mode;
  final String? buildDirectory;
  final String? engineRoot;
  final bool runApplication;
  final List<String> applicationArguments;
}

final class BuilderCommandResult {
  const BuilderCommandResult({
    required this.exitCode,
    this.stdoutText = '',
    this.stderrText = '',
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;
}

abstract interface class BuilderProcessExecutor {
  Future<BuilderCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool inheritStdio = false,
  });
}

final class SystemBuilderProcessExecutor implements BuilderProcessExecutor {
  const SystemBuilderProcessExecutor();

  @override
  Future<BuilderCommandResult> run(
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
      return BuilderCommandResult(exitCode: await process.exitCode);
    }
    final ProcessResult result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return BuilderCommandResult(
      exitCode: result.exitCode,
      stdoutText: result.stdout as String,
      stderrText: result.stderr as String,
    );
  }
}

final class RuntimeApplicationBuilder {
  RuntimeApplicationBuilder({
    required this.repositoryRoot,
    required this.currentDirectory,
    required this.resolvedDartExecutable,
    required this.operatingSystem,
    required this.architecture,
    required Map<String, String> environment,
    BuilderProcessExecutor processExecutor =
        const SystemBuilderProcessExecutor(),
    BuilderOutput? output,
    BuilderOutput? errorOutput,
  }) : environment = Map<String, String>.unmodifiable(environment),
       processExecutor = processExecutor,
       output = output ?? stdout.write,
       errorOutput = errorOutput ?? stderr.write;

  static Future<RuntimeApplicationBuilder> create({
    BuilderOutput? output,
    BuilderOutput? errorOutput,
  }) async {
    final Uri? libraryUri = await Isolate.resolvePackageUri(
      Uri.parse('package:dart_macos_runtime/dart_macos_runtime.dart'),
    );
    if (libraryUri == null || libraryUri.scheme != 'file') {
      throw const RuntimeBuilderException(
        'could not resolve the installed dart_macos_runtime package',
        exitCode: builderSoftwareExitCode,
      );
    }
    final Directory packageRoot = File.fromUri(libraryUri).parent.parent;
    return RuntimeApplicationBuilder(
      repositoryRoot: packageRoot.parent.parent.path,
      currentDirectory: Directory.current.path,
      resolvedDartExecutable: Platform.resolvedExecutable,
      operatingSystem: Platform.operatingSystem,
      architecture: _currentArchitecture(),
      environment: Platform.environment,
      output: output,
      errorOutput: errorOutput,
    );
  }

  final String repositoryRoot;
  final String currentDirectory;
  final String resolvedDartExecutable;
  final String operatingSystem;
  final String architecture;
  final Map<String, String> environment;
  final BuilderProcessExecutor processExecutor;
  final BuilderOutput output;
  final BuilderOutput errorOutput;

  Future<int> run(RuntimeBuilderOptions options) async {
    try {
      return await _run(options);
    } on RuntimeBuilderException {
      rethrow;
    } on MacosApplicationManifestException catch (error) {
      throw RuntimeBuilderException(
        error.message,
        exitCode: builderUsageExitCode,
      );
    } on FileSystemException catch (error) {
      throw RuntimeBuilderException(
        'file operation failed: ${error.message}'
        '${error.path == null ? '' : ' (${error.path})'}',
        exitCode: builderIoErrorExitCode,
      );
    } on ProcessException catch (error) {
      throw RuntimeBuilderException(
        'could not start ${error.executable}: ${error.message}',
        exitCode: builderOsErrorExitCode,
      );
    }
  }

  Future<int> _run(RuntimeBuilderOptions options) async {
    if (operatingSystem != 'macos' ||
        (architecture != 'arm64' && architecture != 'x86_64')) {
      throw RuntimeBuilderException(
        'macOS arm64 or x86_64 is required; current platform is '
        '$operatingSystem/$architecture',
        exitCode: builderUnavailableExitCode,
      );
    }
    final File manifestFile = await _existingFile(
      _resolvePath(options.manifestPath!),
      'application manifest',
    );
    final MacosApplicationManifest manifest =
        await MacosApplicationManifest.load(manifestFile);
    final Directory projectRoot = manifestFile.parent;
    final File entrypoint = await _existingFile(
      _join(projectRoot.path, manifest.entrypoint),
      'Dart entrypoint',
    );
    final File packageConfig = await _findPackageConfig(entrypoint.parent);

    final File dartExecutable = await _existingFile(
      resolvedDartExecutable,
      'Dart executable',
    );
    final Directory sdkRoot = dartExecutable.parent.parent;
    final String sdkVersion = await _readMetadata(sdkRoot, 'version');
    final String sdkRevision = await _readMetadata(sdkRoot, 'revision');
    if (sdkVersion != pinnedDartSdkVersion ||
        sdkRevision != pinnedDartSdkRevision) {
      throw RuntimeBuilderException(
        'this runtime requires Dart $pinnedDartSdkVersion at revision '
        '$pinnedDartSdkRevision; found $sdkVersion at $sdkRevision',
        exitCode: builderUnavailableExitCode,
      );
    }

    final Directory engineRoot = await _engineRoot(options.engineRoot);
    final String engineDirectoryName =
        options.mode == RuntimeBuildMode.developerJit
        ? 'Release${architecture == 'arm64' ? 'ARM64' : 'X64'}'
        : 'Product${architecture == 'arm64' ? 'ARM64' : 'X64'}';
    final Directory engineOutput = await _existingDirectory(
      _join(engineRoot.path, 'xcodebuild/$engineDirectoryName'),
      'Dart Engine output',
    );
    final String libraryName = options.mode == RuntimeBuildMode.developerJit
        ? 'libdart_engine_jit_shared.dylib'
        : 'libdart_engine_aot_shared.dylib';
    final File engineLibrary = await _existingFile(
      _join(engineOutput.path, libraryName),
      'Dart Engine library',
    );
    final List<String> declaredFrameworkNames = <String>[
      ...manifest.nativeAssets.map(
        (MacosNativeAssetManifest value) => value.library,
      ),
      ...manifest.nativeCapabilities.map(
        (MacosNativeCapabilityManifest value) => value.library,
      ),
      if (manifest.appIntents != null) manifest.appIntents!.library,
    ];
    if (declaredFrameworkNames.contains(_basename(engineLibrary.path))) {
      throw const RuntimeBuilderException(
        'a declared native library conflicts with the Dart Engine image',
        exitCode: builderUsageExitCode,
      );
    }
    final File compiler = await _existingFile(
      _join(engineOutput.path, 'bootstrap_gen_kernel.exe'),
      'Dart Engine Kernel compiler',
    );
    final String toolchain = architecture == 'arm64'
        ? 'clang_arm64_shared'
        : 'clang_x64_shared';
    final File platform = await _existingFile(
      _join(engineOutput.path, '$toolchain/vm_platform.dill'),
      'Dart Engine platform Kernel',
    );
    final File? snapshotter = options.mode == RuntimeBuildMode.releaseAot
        ? await _existingFile(
            _join(engineOutput.path, 'gen_snapshot'),
            'Dart AOT snapshotter',
          )
        : null;
    final File sdkLicense = await _existingFile(
      _join(engineRoot.path, 'LICENSE'),
      'Dart SDK license',
    );

    final Directory buildRoot = Directory(
      options.buildDirectory == null
          ? _join(
              projectRoot.path,
              '.dart_tool/dart_macos_runtime/${options.mode.name}',
            )
          : _resolvePath(options.buildDirectory!),
    );
    await buildRoot.create(recursive: true);
    final _CompiledAppIntents? compiledAppIntents = manifest.appIntents == null
        ? null
        : await _compileAppIntents(
            manifest: manifest,
            declaration: manifest.appIntents!,
            packageConfig: packageConfig,
            buildRoot: buildRoot,
          );
    final Directory nativeBuild = Directory(_join(buildRoot.path, 'host'));
    final String makeTarget = options.mode == RuntimeBuildMode.developerJit
        ? 'runtime-jit-runner'
        : 'runtime-aot-runner';
    await _runChecked('native runtime build', 'make', <String>[
      '-C',
      repositoryRoot,
      'BUILD_DIR=${nativeBuild.path}',
      'DART_SDK=${sdkRoot.path}',
      'DART_ENGINE_ROOT=${engineRoot.path}',
      if (options.mode == RuntimeBuildMode.developerJit)
        'DART_ENGINE_LIBRARY=${engineLibrary.path}'
      else
        'DART_ENGINE_AOT_LIBRARY=${engineLibrary.path}',
      if (compiledAppIntents != null)
        'RUNTIME_APP_INTENTS_LIBRARY=${compiledAppIntents.image.path}',
      makeTarget,
    ], projectRoot.path);
    final File host = await _existingFile(
      _join(
        nativeBuild.path,
        'native/${options.mode == RuntimeBuildMode.developerJit ? 'dart_macos_runtime_developer' : 'dart_macos_runtime_release'}',
      ),
      'generic native host',
    );

    final Directory payloadDirectory = Directory(
      _join(buildRoot.path, 'payload'),
    );
    await payloadDirectory.create(recursive: true);
    final File entrypointWrapper = File(
      _join(payloadDirectory.path, 'runtime_entrypoint.dart'),
    );
    await entrypointWrapper.writeAsString(
      _entrypointWrapper(entrypoint),
      flush: true,
    );
    final File kernel = File(
      _join(
        payloadDirectory.path,
        options.mode == RuntimeBuildMode.developerJit
            ? 'application.dill'
            : 'application.aot.dill',
      ),
    );
    final File depfile = File('${kernel.path}.d');
    await _runChecked('Dart Kernel compilation', compiler.path, <String>[
      '--platform=${platform.path}',
      '--packages=${packageConfig.path}',
      if (options.mode == RuntimeBuildMode.developerJit)
        '--no-aot'
      else
        '--aot',
      '--link-platform',
      '--no-embed-sources',
      if (options.mode == RuntimeBuildMode.releaseAot) '--target-os=macos',
      if (options.mode == RuntimeBuildMode.releaseAot)
        '--invocation-modes=compile',
      '--verbosity=error',
      '--output=${kernel.path}',
      '--depfile=${depfile.path}',
      '-Dsdk_hash=${sdkRevision.substring(0, 10)}',
      '-Ddart.vm.product=${options.mode == RuntimeBuildMode.releaseAot}',
      '-Ddart.vm.asan=false',
      '-Ddart.vm.msan=false',
      '-Ddart.vm.tsan=false',
      entrypointWrapper.path,
    ], projectRoot.path);
    await _existingFile(kernel.path, 'compiled Dart Kernel');
    final File payload;
    if (snapshotter == null) {
      payload = kernel;
    } else {
      payload = File(_join(payloadDirectory.path, 'application.aot'));
      await _runChecked(
        'Dart AOT snapshot generation',
        snapshotter.path,
        <String>[
          '--snapshot-kind=app-aot-macho-dylib',
          '--macho=${payload.path}',
          kernel.path,
        ],
        projectRoot.path,
      );
      await _existingFile(payload.path, 'Dart AOT snapshot');
    }

    final Map<String, File> dartHelpers = <String, File>{};
    if (manifest.dartHelpers.isNotEmpty) {
      final Directory helperOutput = Directory(
        _join(buildRoot.path, 'helpers'),
      );
      await helperOutput.create(recursive: true);
      for (final MacosDartHelperManifest helper in manifest.dartHelpers) {
        final File helperEntrypoint = await _existingFile(
          _join(projectRoot.path, helper.entrypoint),
          'Dart helper entrypoint ${helper.name}',
        );
        final Directory helperBuild = Directory(
          _join(helperOutput.path, '${helper.name}.build'),
        );
        if (await helperBuild.exists()) {
          await helperBuild.delete(recursive: true);
        }
        await _runChecked(
          'Dart helper compilation (${helper.name})',
          dartExecutable.path,
          <String>[
            'build',
            'cli',
            '--output=${helperBuild.path}',
            '--target=${helperEntrypoint.path}',
            '--packages=${packageConfig.path}',
            '--target-os=macos',
            '--target-arch=${architecture == 'arm64' ? 'arm64' : 'x64'}',
            '--verbosity=warning',
          ],
          projectRoot.path,
        );
        final String sourceName = _basename(helper.entrypoint)
            .replaceFirst(RegExp(r'\.dart$'), '');
        final File compiledHelper = await _existingFile(
          _join(helperBuild.path, 'bundle/bin/$sourceName'),
          'compiled Dart helper ${helper.name}',
        );
        dartHelpers[helper.name] = await compiledHelper.copy(
          _join(helperOutput.path, helper.name),
        );
      }
    }

    final Map<String, File> nativeImages = <String, File>{};
    if (manifest.nativeAssets.isNotEmpty ||
        manifest.nativeCapabilities.isNotEmpty) {
      final Directory hookOutput = Directory(
        _join(buildRoot.path, 'native-assets'),
      );
      if (await hookOutput.exists()) {
        await hookOutput.delete(recursive: true);
      }
      await _runChecked(
        'Dart native asset hooks',
        dartExecutable.path,
        <String>[
          'build',
          'cli',
          '--output=${hookOutput.path}',
          '--target=${entrypoint.path}',
          '--packages=${packageConfig.path}',
          '--target-os=macos',
          '--target-arch=${architecture == 'arm64' ? 'arm64' : 'x64'}',
          '--verbosity=warning',
        ],
        projectRoot.path,
      );
      for (final MacosNativeAssetManifest asset in manifest.nativeAssets) {
        final File image = await _existingFile(
          _join(hookOutput.path, 'bundle/lib/${asset.library}'),
          'native asset ${asset.id}',
        );
        nativeImages[asset.id] = image;
      }
      for (final MacosNativeCapabilityManifest capability
          in manifest.nativeCapabilities) {
        final File image = await _existingFile(
          _join(hookOutput.path, 'bundle/lib/${capability.library}'),
          'native capability ${capability.id}',
        );
        nativeImages[capability.id] = image;
      }
    }

    final _Bundle bundle = await _assembleBundle(
      manifest: manifest,
      mode: options.mode,
      projectRoot: projectRoot,
      buildRoot: buildRoot,
      host: host,
      engineLibrary: engineLibrary,
      payload: payload,
      sdkLicense: sdkLicense,
      sdkVersion: sdkVersion,
      sdkRevision: sdkRevision,
      dartHelpers: dartHelpers,
      nativeImages: nativeImages,
      appIntents: compiledAppIntents,
    );
    output('${bundle.root.path}\n');
    if (!options.runApplication) {
      return 0;
    }
    final BuilderCommandResult launched = await processExecutor.run(
      bundle.executable.path,
      options.mode == RuntimeBuildMode.developerJit
          ? <String>[
              '--kernel',
              bundle.payload.path,
              '--sdk-version',
              sdkVersion,
              '--sdk-revision',
              sdkRevision,
              '--',
              ...options.applicationArguments,
            ]
          : options.applicationArguments,
      workingDirectory: projectRoot.path,
      inheritStdio: true,
    );
    return launched.exitCode;
  }

  Future<_CompiledAppIntents> _compileAppIntents({
    required MacosApplicationManifest manifest,
    required MacosAppIntentsManifest declaration,
    required File packageConfig,
    required Directory buildRoot,
  }) async {
    final Directory packageRoot = await _packageRoot(
      packageConfig,
      declaration.package,
    );
    final File source = await _existingFile(
      _join(packageRoot.path, declaration.source),
      'App Intents Swift source',
    );
    if (!_isWithinDirectory(packageRoot, source)) {
      throw RuntimeBuilderException(
        'App Intents Swift source resolves outside package '
        '${declaration.package}',
        exitCode: builderUsageExitCode,
      );
    }
    final int sourceBytes = await source.length();
    if (sourceBytes <= 0 ||
        sourceBytes > MacosAppIntentsManifest.maximumSourceFileBytes) {
      throw RuntimeBuilderException(
        'App Intents Swift source must be non-empty and no larger than '
        '${MacosAppIntentsManifest.maximumSourceFileBytes} bytes',
        exitCode: builderUsageExitCode,
      );
    }

    final Directory outputDirectory = Directory(
      _join(buildRoot.path, 'app-intents'),
    );
    if (await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
    await outputDirectory.create(recursive: true);
    final File protocols = File(
      _join(outputDirectory.path, 'const-gather-protocols.json'),
    );
    await protocols.writeAsString(
      '${jsonEncode(appIntentsConstGatherProtocols)}\n',
      flush: true,
    );
    final Directory moduleCache = Directory(
      _join(outputDirectory.path, 'module-cache'),
    );
    await moduleCache.create();
    final File object = File(_join(outputDirectory.path, 'module.o'));
    final File constValues = File(
      _join(outputDirectory.path, 'module.swiftconstvalues'),
    );
    final File image = File(_join(outputDirectory.path, declaration.library));
    final String targetTriple =
        '${architecture == 'arm64' ? 'arm64' : 'x86_64'}-apple-macos'
        '${manifest.minimumSystemVersion}';
    final File swiftCompiler = await _xcrunFind('swiftc');
    final File metadataProcessor = await _xcrunFind(
      'appintentsmetadataprocessor',
    );
    final String sdkRoot = await _runCapturedChecked(
      'macOS SDK discovery',
      '/usr/bin/xcrun',
      const <String>['--sdk', 'macosx', '--show-sdk-path'],
      projectWorkingDirectory: packageRoot.path,
    );
    final File xcodebuild = await _xcrunFind('xcodebuild');
    final String xcodeVersion = await _runCapturedChecked(
      'Xcode version discovery',
      xcodebuild.path,
      const <String>['-version'],
      projectWorkingDirectory: packageRoot.path,
    );
    final RegExpMatch? buildVersionMatch = RegExp(
      r'(?:^|\n)Build version ([A-Za-z0-9]+)(?:\n|$)',
    ).firstMatch(xcodeVersion);
    if (buildVersionMatch == null) {
      throw const RuntimeBuilderException(
        'Xcode did not report a valid build version',
        exitCode: builderUnavailableExitCode,
      );
    }
    final String xcodeBuildVersion = buildVersionMatch.group(1)!;
    final Directory toolchain = swiftCompiler.parent.parent.parent;
    await _runChecked(
      'App Intents Swift compilation',
      swiftCompiler.path,
      <String>[
        '-c',
        '-parse-as-library',
        '-swift-version',
        '6',
        '-emit-const-values',
        '-emit-const-values-path',
        constValues.path,
        '-Xfrontend',
        '-const-gather-protocols-file',
        '-Xfrontend',
        protocols.path,
        '-module-name',
        declaration.moduleName,
        '-target',
        targetTriple,
        '-sdk',
        sdkRoot,
        '-module-cache-path',
        moduleCache.path,
        '-o',
        object.path,
        source.path,
      ],
      packageRoot.path,
    );
    await _boundedFile(
      object.path,
      'compiled App Intents object',
      64 * 1024 * 1024,
    );
    await _boundedFile(
      constValues.path,
      'App Intents compiler constant values',
      MacosAppIntentsManifest.maximumMetadataFileBytes,
    );
    await _runChecked(
      'App Intents Swift image link',
      swiftCompiler.path,
      <String>[
        '-emit-library',
        '-target',
        targetTriple,
        '-sdk',
        sdkRoot,
        '-Xlinker',
        '-install_name',
        '-Xlinker',
        '@rpath/${declaration.library}',
        '-o',
        image.path,
        object.path,
      ],
      packageRoot.path,
    );
    await _runChecked(
      'App Intents Swift image signing',
      '/usr/bin/codesign',
      <String>['--force', '--sign', '-', image.path],
      packageRoot.path,
    );
    final File checkedImage = await _boundedFile(
      image.path,
      'App Intents Swift image',
      64 * 1024 * 1024,
    );

    final File sourceList = File(_join(outputDirectory.path, 'sources.list'));
    final File constValuesList = File(
      _join(outputDirectory.path, 'const-values.list'),
    );
    await sourceList.writeAsString('${source.path}\n', flush: true);
    await constValuesList.writeAsString('${constValues.path}\n', flush: true);
    final Directory metadataOutput = Directory(
      _join(outputDirectory.path, 'metadata-output'),
    );
    await metadataOutput.create();
    await _runChecked(
      'App Intents metadata extraction',
      metadataProcessor.path,
      <String>[
        '--output',
        metadataOutput.path,
        '--toolchain-dir',
        toolchain.path,
        '--module-name',
        declaration.moduleName,
        '--sdk-root',
        sdkRoot,
        '--xcode-version',
        xcodeBuildVersion,
        '--platform-family',
        'macOS',
        '--deployment-target',
        manifest.minimumSystemVersion,
        '--target-triple',
        targetTriple,
        '--source-file-list',
        sourceList.path,
        '--swift-const-vals-list',
        constValuesList.path,
        '--no-app-shortcuts-localization',
        '--force',
      ],
      packageRoot.path,
    );
    final Directory metadataBundle = await _existingDirectory(
      _join(metadataOutput.path, 'Metadata.appintents'),
      'App Intents metadata bundle',
    );
    final List<FileSystemEntity> metadataEntries = await metadataBundle
        .list(followLinks: false)
        .toList();
    final Set<String> metadataNames = metadataEntries
        .map((FileSystemEntity entry) => _basename(entry.path))
        .toSet();
    if (metadataEntries.length != 2 ||
        !metadataNames.contains('version.json') ||
        !metadataNames.contains('extract.actionsdata')) {
      throw RuntimeBuilderException(
        'App Intents metadata bundle must contain exactly version.json and '
        'extract.actionsdata',
        exitCode: builderSoftwareExitCode,
      );
    }
    final File versionMetadata = await _boundedFile(
      _join(metadataBundle.path, 'version.json'),
      'App Intents version metadata',
      MacosAppIntentsManifest.maximumMetadataFileBytes,
    );
    final File actionsMetadata = await _boundedFile(
      _join(metadataBundle.path, 'extract.actionsdata'),
      'App Intents action metadata',
      MacosAppIntentsManifest.maximumMetadataFileBytes,
    );
    final Object? decodedVersion;
    try {
      decodedVersion = jsonDecode(await versionMetadata.readAsString());
    } on FormatException catch (error) {
      throw RuntimeBuilderException(
        'App Intents version metadata is invalid JSON: ${error.message}',
        exitCode: builderSoftwareExitCode,
      );
    }
    if (decodedVersion is! Map<String, Object?> ||
        decodedVersion['toolsVersion'] != xcodeBuildVersion ||
        decodedVersion['version'] is! String ||
        (decodedVersion['version']! as String).isEmpty) {
      throw const RuntimeBuilderException(
        'App Intents version metadata does not match the selected Xcode tools',
        exitCode: builderSoftwareExitCode,
      );
    }
    return _CompiledAppIntents(
      declaration: declaration,
      image: checkedImage,
      versionMetadata: versionMetadata,
      actionsMetadata: actionsMetadata,
      sourceBytes: sourceBytes,
      libraryBytes: await checkedImage.length(),
      versionMetadataBytes: await versionMetadata.length(),
      actionsMetadataBytes: await actionsMetadata.length(),
      targetTriple: targetTriple,
      xcodeBuildVersion: xcodeBuildVersion,
    );
  }

  Future<_Bundle> _assembleBundle({
    required MacosApplicationManifest manifest,
    required RuntimeBuildMode mode,
    required Directory projectRoot,
    required Directory buildRoot,
    required File host,
    required File engineLibrary,
    required File payload,
    required File sdkLicense,
    required String sdkVersion,
    required String sdkRevision,
    required Map<String, File> dartHelpers,
    required Map<String, File> nativeImages,
    required _CompiledAppIntents? appIntents,
  }) async {
    final Directory root = Directory(
      _join(buildRoot.path, '${manifest.name}.app'),
    );
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    final Directory contents = Directory(_join(root.path, 'Contents'));
    final Directory macos = Directory(_join(contents.path, 'MacOS'));
    final Directory helpers = Directory(_join(contents.path, 'Helpers'));
    final Directory frameworks = Directory(_join(contents.path, 'Frameworks'));
    final Directory resources = Directory(_join(contents.path, 'Resources'));
    await Future.wait(<Future<Directory>>[
      macos.create(recursive: true),
      helpers.create(recursive: true),
      frameworks.create(recursive: true),
      resources.create(recursive: true),
    ]);
    final File executable = await host.copy(
      _join(macos.path, manifest.executableName),
    );
    await engineLibrary.copy(
      _join(frameworks.path, _basename(engineLibrary.path)),
    );
    for (final MacosNativeAssetManifest asset in manifest.nativeAssets) {
      final File? image = nativeImages[asset.id];
      if (image == null) {
        throw RuntimeBuilderException(
          'native asset output is missing: ${asset.id}',
          exitCode: builderSoftwareExitCode,
        );
      }
      await image.copy(_join(frameworks.path, asset.library));
    }
    for (final MacosNativeCapabilityManifest capability
        in manifest.nativeCapabilities) {
      final File? image = nativeImages[capability.id];
      if (image == null) {
        throw RuntimeBuilderException(
          'native capability output is missing: ${capability.id}',
          exitCode: builderSoftwareExitCode,
        );
      }
      await image.copy(_join(frameworks.path, capability.library));
    }
    if (appIntents != null) {
      await appIntents.image.copy(
        _join(frameworks.path, appIntents.declaration.library),
      );
      final Directory metadataDestination = Directory(
        _join(resources.path, 'Metadata.appintents'),
      );
      await metadataDestination.create();
      await appIntents.versionMetadata.copy(
        _join(metadataDestination.path, 'version.json'),
      );
      await appIntents.actionsMetadata.copy(
        _join(metadataDestination.path, 'extract.actionsdata'),
      );
    }
    final File bundledPayload = await payload.copy(
      _join(
        resources.path,
        mode == RuntimeBuildMode.developerJit
            ? 'application.dill'
            : 'application.aot',
      ),
    );
    await sdkLicense.copy(_join(resources.path, 'DART_SDK_LICENSE.txt'));
    for (final MacosDartHelperManifest helper in manifest.dartHelpers) {
      final File? source = dartHelpers[helper.name];
      if (source == null) {
        throw RuntimeBuilderException(
          'compiled Dart helper is missing: ${helper.name}',
          exitCode: builderSoftwareExitCode,
        );
      }
      final File destination = await source.copy(
        _join(helpers.path, helper.name),
      );
      await _runChecked(
        'Dart helper permission update (${helper.name})',
        '/bin/chmod',
        <String>['755', destination.path],
        projectRoot.path,
      );
    }
    for (final String relativePath in manifest.resources) {
      if (_reservedResources.contains(relativePath)) {
        throw RuntimeBuilderException(
          'resource name is reserved by the runtime: $relativePath',
          exitCode: builderUsageExitCode,
        );
      }
      final File source = await _existingFile(
        _join(projectRoot.path, relativePath),
        'declared resource',
      );
      final File destination = File(_join(resources.path, relativePath));
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
    }
    int? scriptingDefinitionBytes;
    final MacosScriptingDefinitionManifest? scriptingDefinition =
        manifest.scriptingDefinition;
    if (scriptingDefinition != null) {
      final File source = await _existingFile(
        _join(projectRoot.path, scriptingDefinition.path),
        'scripting definition',
      );
      scriptingDefinitionBytes = await source.length();
      if (scriptingDefinitionBytes <= 0 ||
          scriptingDefinitionBytes >
              MacosScriptingDefinitionManifest.maximumFileBytes) {
        throw RuntimeBuilderException(
          'scripting definition must be non-empty and no larger than '
          '${MacosScriptingDefinitionManifest.maximumFileBytes} bytes',
          exitCode: builderUsageExitCode,
        );
      }
      await _runChecked(
        'scripting definition validation',
        '/usr/bin/xmllint',
        <String>['--noout', '--valid', source.path],
        projectRoot.path,
      );
      await source.copy(_join(resources.path, scriptingDefinition.bundleName));
    }
    final File infoPlist = File(_join(contents.path, 'Info.plist'));
    await infoPlist.writeAsString(
      _infoPlist(manifest, sdkRevision),
      flush: true,
    );
    await _runChecked('Info.plist validation', '/usr/bin/plutil', <String>[
      '-lint',
      infoPlist.path,
    ], projectRoot.path);
    await File(
      _join(resources.path, 'runtime-build-manifest.json'),
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object>{
            'schemaVersion': 1,
            'runtimeMode': mode.name,
            'architecture': architecture,
            'bundleIdentifier': manifest.bundleIdentifier,
            'executable': manifest.executableName,
            'payload': _basename(bundledPayload.path),
            'engine': _basename(engineLibrary.path),
            'dartSdkVersion': sdkVersion,
            'dartSdkRevision': sdkRevision,
            'runner': <String, Object>{
              'activationPolicy': manifest.runner.activationPolicy.name,
              'activateOnLaunch': manifest.runner.activateOnLaunch,
              'terminateAfterLastWindowClosed':
                  manifest.runner.terminateAfterLastWindowClosed,
              'reopenHandled': manifest.runner.reopenHandled,
              'messagePump': <String, Object>{
                'maxMessagesPerTurn':
                    manifest.runner.messagePump.maxMessagesPerTurn,
                'maxTimePerTurnMicros':
                    manifest.runner.messagePump.maxTimePerTurnMicros,
              },
            },
            if (manifest.services.isNotEmpty)
              'services': <Map<String, Object>>[
                for (final MacosApplicationServiceManifest service
                    in manifest.services)
                  <String, Object>{
                    'action': service.action.name,
                    'menuItem': service.menuItem,
                  },
              ],
            if (scriptingDefinition != null)
              'scriptingDefinition': <String, Object>{
                'source': scriptingDefinition.path,
                'bundleName': scriptingDefinition.bundleName,
                'bytes': scriptingDefinitionBytes!,
              },
            if (appIntents != null)
              'appIntents': <String, Object>{
                'package': appIntents.declaration.package,
                'source': appIntents.declaration.source,
                'moduleName': appIntents.declaration.moduleName,
                'library': appIntents.declaration.library,
                'sourceBytes': appIntents.sourceBytes,
                'libraryBytes': appIntents.libraryBytes,
                'targetTriple': appIntents.targetTriple,
                'xcodeBuildVersion': appIntents.xcodeBuildVersion,
                'metadataBundle': 'Metadata.appintents',
                'metadataFiles': <Map<String, Object>>[
                  <String, Object>{
                    'name': 'extract.actionsdata',
                    'bytes': appIntents.actionsMetadataBytes,
                  },
                  <String, Object>{
                    'name': 'version.json',
                    'bytes': appIntents.versionMetadataBytes,
                  },
                ],
              },
            'dartHelpers': <Map<String, Object>>[
              for (final MacosDartHelperManifest helper in manifest.dartHelpers)
                <String, Object>{
                  'name': helper.name,
                  'entrypoint': helper.entrypoint,
                },
            ],
            'resources': manifest.resources,
            'nativeAssets': <Map<String, Object>>[
              for (final MacosNativeAssetManifest asset
                  in manifest.nativeAssets)
                <String, Object>{
                  'id': asset.id,
                  'package': asset.package,
                  'library': asset.library,
                  'abiVersion': asset.abiVersion,
                  'abiVersionSymbol': asset.abiVersionSymbol,
                },
            ],
            'nativeCapabilities': <Map<String, Object>>[
              for (final MacosNativeCapabilityManifest capability
                  in manifest.nativeCapabilities)
                <String, Object>{
                  'id': capability.id,
                  'package': capability.package,
                  'library': capability.library,
                  'abiVersion': capability.abiVersion,
                  'abiVersionSymbol': capability.abiVersionSymbol,
                  'initializerSymbol': capability.initializerSymbol,
                },
            ],
          }) +
          '\n',
      flush: true,
    );
    await _runChecked(
      'runtime executable permission update',
      '/bin/chmod',
      <String>['755', executable.path],
      projectRoot.path,
    );
    await _runChecked(
      'ad-hoc application signing',
      '/usr/bin/codesign',
      <String>['--force', '--deep', '--sign', '-', root.path],
      projectRoot.path,
    );
    return _Bundle(root: root, executable: executable, payload: bundledPayload);
  }

  Future<Directory> _engineRoot(String? configured) async {
    String? value = configured;
    if (value == null || value.isEmpty) {
      value = environment['DART_ENGINE_ROOT'];
    }
    value ??= _join(repositoryRoot, '.dart_tool/dart-engine/sdk');
    final Directory root = await _existingDirectory(
      _resolvePath(value),
      'Dart Engine source root',
    );
    await _existingFile(
      _join(root.path, 'runtime/engine/include/dart_engine.h'),
      'Dart Engine public host header',
    );
    return root;
  }

  Future<void> _runChecked(
    String label,
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) async {
    final BuilderCommandResult result = await processExecutor.run(
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
      throw RuntimeBuilderException(
        '$label failed with exit code ${result.exitCode}',
        exitCode: result.exitCode,
      );
    }
  }

  Future<File> _existingFile(String path, String description) async {
    final File file = File(path);
    if (!await file.exists()) {
      throw RuntimeBuilderException(
        '$description does not exist: $path',
        exitCode: builderIoErrorExitCode,
      );
    }
    return File(await file.resolveSymbolicLinks());
  }

  Future<Directory> _existingDirectory(String path, String description) async {
    final Directory directory = Directory(path);
    if (!await directory.exists()) {
      throw RuntimeBuilderException(
        '$description does not exist: $path',
        exitCode: builderIoErrorExitCode,
      );
    }
    return Directory(await directory.resolveSymbolicLinks());
  }

  Future<File> _boundedFile(
    String path,
    String description,
    int maximumBytes,
  ) async {
    final File file = await _existingFile(path, description);
    final int bytes = await file.length();
    if (bytes <= 0 || bytes > maximumBytes) {
      throw RuntimeBuilderException(
        '$description must be non-empty and no larger than $maximumBytes bytes',
        exitCode: builderSoftwareExitCode,
      );
    }
    return file;
  }

  Future<String> _runCapturedChecked(
    String label,
    String executable,
    List<String> arguments, {
    required String projectWorkingDirectory,
  }) async {
    final BuilderCommandResult result = await processExecutor.run(
      executable,
      arguments,
      workingDirectory: projectWorkingDirectory,
    );
    if (result.exitCode != 0) {
      if (result.stderrText.isNotEmpty) errorOutput(result.stderrText);
      throw RuntimeBuilderException(
        '$label failed with exit code ${result.exitCode}',
        exitCode: result.exitCode,
      );
    }
    final String value = result.stdoutText.trim();
    if (value.isEmpty) {
      throw RuntimeBuilderException(
        '$label returned no output',
        exitCode: builderUnavailableExitCode,
      );
    }
    return value;
  }

  Future<File> _xcrunFind(String tool) async {
    final String path = await _runCapturedChecked(
      'Xcode tool discovery ($tool)',
      '/usr/bin/xcrun',
      <String>['--find', tool],
      projectWorkingDirectory: currentDirectory,
    );
    final File file = File(path);
    if (!await file.exists()) {
      throw RuntimeBuilderException(
        'Xcode tool $tool does not exist: $path',
        exitCode: builderIoErrorExitCode,
      );
    }
    // Preserve xcrun's selected invocation name. Some Xcode tools are
    // multi-call binaries whose driver mode is selected from argv[0].
    return file.absolute;
  }

  Future<Directory> _packageRoot(File packageConfig, String package) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await packageConfig.readAsString());
    } on FormatException catch (error) {
      throw RuntimeBuilderException(
        'package configuration is invalid JSON: ${error.message}',
        exitCode: builderUsageExitCode,
      );
    }
    if (decoded is! Map<String, Object?> || decoded['packages'] is! List) {
      throw const RuntimeBuilderException(
        'package configuration has no package list',
        exitCode: builderUsageExitCode,
      );
    }
    final List<Object?> matches = (decoded['packages']! as List<Object?>)
        .where(
          (Object? value) =>
              value is Map<String, Object?> && value['name'] == package,
        )
        .toList();
    if (matches.length != 1) {
      throw RuntimeBuilderException(
        'package configuration must contain exactly one $package package',
        exitCode: builderUsageExitCode,
      );
    }
    final Map<String, Object?> entry = matches.single as Map<String, Object?>;
    final Object? rootValue = entry['rootUri'];
    if (rootValue is! String || rootValue.isEmpty) {
      throw RuntimeBuilderException(
        'package $package has no valid rootUri',
        exitCode: builderUsageExitCode,
      );
    }
    final Uri rootUri;
    try {
      rootUri = packageConfig.parent.uri.resolve(rootValue);
    } on FormatException {
      throw RuntimeBuilderException(
        'package $package has an invalid rootUri',
        exitCode: builderUsageExitCode,
      );
    }
    if (rootUri.scheme != 'file') {
      throw RuntimeBuilderException(
        'package $package rootUri must resolve to a local directory',
        exitCode: builderUsageExitCode,
      );
    }
    return _existingDirectory(
      Directory.fromUri(rootUri).path,
      'App Intents package $package',
    );
  }

  static bool _isWithinDirectory(Directory root, File file) {
    final String prefix = root.path.endsWith(Platform.pathSeparator)
        ? root.path
        : '${root.path}${Platform.pathSeparator}';
    return file.path.startsWith(prefix);
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
      if (cursor.parent.path == cursor.path) {
        throw RuntimeBuilderException(
          'no .dart_tool/package_config.json found above ${start.path}',
          exitCode: builderUsageExitCode,
        );
      }
      cursor = cursor.parent;
    }
  }

  Future<String> _readMetadata(Directory sdkRoot, String name) async {
    final File file = await _existingFile(
      _join(sdkRoot.path, name),
      'Dart SDK $name metadata',
    );
    final String value = (await file.readAsString()).trim();
    if (value.isEmpty) {
      throw RuntimeBuilderException(
        'Dart SDK $name metadata is empty',
        exitCode: builderIoErrorExitCode,
      );
    }
    return value;
  }

  String _resolvePath(String value) {
    final Uri uri = Uri.file(value);
    return uri.isAbsolute
        ? File.fromUri(uri).path
        : Directory(currentDirectory).absolute.uri.resolveUri(uri).toFilePath();
  }

  static String _join(String parent, String child) =>
      Directory(parent).uri.resolve(child).toFilePath();

  static String _basename(String path) => File(path).uri.pathSegments.last;

  static String _currentArchitecture() {
    return switch (Abi.current()) {
      Abi.macosArm64 => 'arm64',
      Abi.macosX64 => 'x86_64',
      final Abi abi => abi.toString(),
    };
  }

  static const Set<String> _reservedResources = <String>{
    'application.dill',
    'application.aot',
    'DART_SDK_LICENSE.txt',
    'runtime-build-manifest.json',
  };
}

final class _CompiledAppIntents {
  const _CompiledAppIntents({
    required this.declaration,
    required this.image,
    required this.versionMetadata,
    required this.actionsMetadata,
    required this.sourceBytes,
    required this.libraryBytes,
    required this.versionMetadataBytes,
    required this.actionsMetadataBytes,
    required this.targetTriple,
    required this.xcodeBuildVersion,
  });

  final MacosAppIntentsManifest declaration;
  final File image;
  final File versionMetadata;
  final File actionsMetadata;
  final int sourceBytes;
  final int libraryBytes;
  final int versionMetadataBytes;
  final int actionsMetadataBytes;
  final String targetTriple;
  final String xcodeBuildVersion;
}

final class _Bundle {
  const _Bundle({
    required this.root,
    required this.executable,
    required this.payload,
  });

  final Directory root;
  final File executable;
  final File payload;
}

String _infoPlist(MacosApplicationManifest manifest, String sdkRevision) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${_xml(manifest.executableName)}</string>
  <key>CFBundleIdentifier</key>
  <string>${_xml(manifest.bundleIdentifier)}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${_xml(manifest.name)}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${_xml(manifest.version)}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${_xml(manifest.minimumSystemVersion)}</string>
  <key>NSHighResolutionCapable</key>
  <true/>
${_servicesInfoPlist(manifest.services)}${_scriptingDefinitionInfoPlist(manifest.scriptingDefinition)}  <key>DMRDartSDKRevision</key>
  <string>${_xml(sdkRevision)}</string>
  <key>DMRDiagnosticsEnabled</key>
  <${manifest.diagnostics.enabled ? 'true' : 'false'}/>
  <key>DMRDiagnosticsApplicationSupportName</key>
  <string>${_xml(manifest.diagnostics.applicationSupportName)}</string>
  <key>DMRRunnerConfiguration</key>
  <dict>
    <key>ActivationPolicy</key>
    <string>${manifest.runner.activationPolicy.name}</string>
    <key>ActivateOnLaunch</key>
    <${manifest.runner.activateOnLaunch ? 'true' : 'false'}/>
    <key>TerminateAfterLastWindowClosed</key>
    <${manifest.runner.terminateAfterLastWindowClosed ? 'true' : 'false'}/>
    <key>ReopenHandled</key>
    <${manifest.runner.reopenHandled ? 'true' : 'false'}/>
    <key>MessagePump</key>
    <dict>
      <key>MaxMessagesPerTurn</key>
      <integer>${manifest.runner.messagePump.maxMessagesPerTurn}</integer>
      <key>MaxTimePerTurnMicros</key>
      <integer>${manifest.runner.messagePump.maxTimePerTurnMicros}</integer>
    </dict>
  </dict>
</dict>
</plist>
''';

String _servicesInfoPlist(List<MacosApplicationServiceManifest> services) {
  if (services.isEmpty) return '';
  final StringBuffer buffer = StringBuffer()
    ..writeln('  <key>NSServices</key>')
    ..writeln('  <array>');
  for (final MacosApplicationServiceManifest service in services) {
    final String message = switch (service.action) {
      MacosApplicationServiceAction.primary => 'performPrimaryFolderService',
      MacosApplicationServiceAction.secondary =>
        'performSecondaryFolderService',
    };
    buffer
      ..writeln('    <dict>')
      ..writeln('      <key>NSMenuItem</key>')
      ..writeln('      <dict>')
      ..writeln('        <key>default</key>')
      ..writeln('        <string>${_xml(service.menuItem)}</string>')
      ..writeln('      </dict>')
      ..writeln('      <key>NSMessage</key>')
      ..writeln('      <string>$message</string>')
      ..writeln('      <key>NSRequiredContext</key>')
      ..writeln('      <dict/>')
      ..writeln('      <key>NSSendFileTypes</key>')
      ..writeln('      <array>')
      ..writeln('        <string>public.item</string>')
      ..writeln('      </array>')
      ..writeln('    </dict>');
  }
  buffer.writeln('  </array>');
  return buffer.toString();
}

String _scriptingDefinitionInfoPlist(
  MacosScriptingDefinitionManifest? scriptingDefinition,
) {
  if (scriptingDefinition == null) return '';
  return '''  <key>NSAppleScriptEnabled</key>
  <true/>
  <key>OSAScriptingDefinition</key>
  <string>${_xml(scriptingDefinition.bundleName)}</string>
''';
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _entrypointWrapper(File entrypoint) =>
    '''
import 'dart:async';

import ${jsonEncode(entrypoint.absolute.uri.toString())} as application;

@pragma('vm:entry-point')
Future<void> main(List<String> arguments) async {
  final dynamic result = Function.apply(
    application.main,
    <Object?>[arguments],
  );
  if (result is Future) {
    await result;
  }
}
''';

Future<int> runBuilderCommand(
  List<String> arguments, {
  RuntimeApplicationBuilder? builder,
  BuilderOutput? output,
  BuilderOutput? errorOutput,
}) async {
  final BuilderOutput writeOutput = output ?? stdout.write;
  final BuilderOutput writeError = errorOutput ?? stderr.write;
  try {
    final RuntimeBuilderOptions options = RuntimeBuilderOptions.parse(
      arguments,
    );
    if (options.showHelp) {
      writeOutput(builderUsage);
      return 0;
    }
    final RuntimeApplicationBuilder active =
        builder ??
        await RuntimeApplicationBuilder.create(
          output: writeOutput,
          errorOutput: writeError,
        );
    return await active.run(options);
  } on RuntimeBuilderException catch (error) {
    writeError('dart_macos_runtime:build: ${error.message}\n');
    if (error.exitCode == builderUsageExitCode) {
      writeError(builderUsage);
    }
    return error.exitCode;
  } on Object catch (error, stackTrace) {
    writeError(
      'dart_macos_runtime:build: unexpected failure: $error\n$stackTrace\n',
    );
    return builderSoftwareExitCode;
  }
}
