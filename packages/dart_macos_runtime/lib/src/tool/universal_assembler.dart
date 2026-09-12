import 'dart:convert';
import 'dart:io';

import 'builder.dart';

const String universalAssemblerUsage = '''
Usage: dart run dart_macos_runtime:universal --input-app <bundle> \\
       --input-app <bundle> --output-app <bundle>

Options:
  -h, --help                  Show this help.
      --input-app <bundle>    Thin Release AOT application (repeat twice).
      --output-app <bundle>   Atomic Universal application destination.
''';

final class UniversalAssemblerOptions {
  const UniversalAssemblerOptions({
    required this.showHelp,
    required this.inputApplications,
    required this.outputApplication,
  });

  factory UniversalAssemblerOptions.parse(List<String> arguments) {
    var showHelp = false;
    final List<String> inputs = <String>[];
    String? output;

    for (var index = 0; index < arguments.length; ++index) {
      final String argument = arguments[index];
      if (argument == '-h' || argument == '--help') {
        showHelp = true;
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
          final String value = arguments[++index];
          if (value.isEmpty) {
            throw RuntimeBuilderException(
              '$name requires a value',
              exitCode: builderUsageExitCode,
            );
          }
          return value;
        }
        throw RuntimeBuilderException(
          '$name requires a value',
          exitCode: builderUsageExitCode,
        );
      }

      if (argument == '--input-app' || argument.startsWith('--input-app=')) {
        inputs.add(optionValue('--input-app'));
      } else if (argument == '--output-app' ||
          argument.startsWith('--output-app=')) {
        if (output != null) {
          throw const RuntimeBuilderException(
            '--output-app may be specified only once',
            exitCode: builderUsageExitCode,
          );
        }
        output = optionValue('--output-app');
      } else {
        throw RuntimeBuilderException(
          'unknown option: $argument',
          exitCode: builderUsageExitCode,
        );
      }
    }
    if (!showHelp && inputs.length != 2) {
      throw const RuntimeBuilderException(
        'exactly two --input-app values are required',
        exitCode: builderUsageExitCode,
      );
    }
    if (!showHelp && output == null) {
      throw const RuntimeBuilderException(
        '--output-app is required',
        exitCode: builderUsageExitCode,
      );
    }
    return UniversalAssemblerOptions(
      showHelp: showHelp,
      inputApplications: List<String>.unmodifiable(inputs),
      outputApplication: output,
    );
  }

  final bool showHelp;
  final List<String> inputApplications;
  final String? outputApplication;
}

final class UniversalApplicationAssembler {
  UniversalApplicationAssembler({
    required this.currentDirectory,
    BuilderProcessExecutor processExecutor =
        const SystemBuilderProcessExecutor(),
    BuilderOutput? output,
    BuilderOutput? errorOutput,
  }) : processExecutor = processExecutor,
       output = output ?? stdout.write,
       errorOutput = errorOutput ?? stderr.write;

  final String currentDirectory;
  final BuilderProcessExecutor processExecutor;
  final BuilderOutput output;
  final BuilderOutput errorOutput;

  Future<int> run(UniversalAssemblerOptions options) async {
    try {
      return await _run(options);
    } on RuntimeBuilderException {
      rethrow;
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

  Future<int> _run(UniversalAssemblerOptions options) async {
    final List<Directory> unresolvedInputs = <Directory>[
      for (final String path in options.inputApplications)
        Directory(_resolvePath(path)),
    ];
    final List<Directory> inputs = <Directory>[];
    for (final Directory input in unresolvedInputs) {
      inputs.add(await _canonicalInput(input));
    }
    if (_samePath(inputs[0].path, inputs[1].path)) {
      throw const RuntimeBuilderException(
        'thin input applications must be distinct',
        exitCode: builderUsageExitCode,
      );
    }

    final Directory outputApplication = Directory(
      _resolvePath(options.outputApplication!),
    );
    if (!_basename(outputApplication.path).endsWith('.app')) {
      throw const RuntimeBuilderException(
        '--output-app must name an .app directory',
        exitCode: builderUsageExitCode,
      );
    }
    final String outputPath = await _canonicalDestination(outputApplication);
    for (final Directory input in inputs) {
      if (_pathsOverlap(input.path, outputPath)) {
        throw const RuntimeBuilderException(
          'output application must not overlap either thin input',
          exitCode: builderUsageExitCode,
        );
      }
    }

    final List<_ThinBundle> thinBundles = <_ThinBundle>[];
    for (final Directory input in inputs) {
      thinBundles.add(await _loadThinBundle(input));
    }
    final Map<String, _ThinBundle> byArchitecture = <String, _ThinBundle>{
      for (final _ThinBundle bundle in thinBundles)
        bundle.manifest.architecture: bundle,
    };
    if (byArchitecture.length != 2 ||
        !byArchitecture.containsKey('arm64') ||
        !byArchitecture.containsKey('x86_64')) {
      throw const RuntimeBuilderException(
        'thin inputs must contain exactly one arm64 and one x86_64 application',
        exitCode: builderUsageExitCode,
      );
    }
    final _ThinBundle arm64 = byArchitecture['arm64']!;
    final _ThinBundle x86_64 = byArchitecture['x86_64']!;
    _validateMatchingContracts(arm64, x86_64);

    final Set<String> codePaths = arm64.manifest.codePaths;
    final List<_ResourceEvidence> resources = await _validateInventories(
      arm64,
      x86_64,
      codePaths,
    );

    final Directory outputParent = Directory(File(outputPath).parent.path);
    final Directory staging = await outputParent.createTemp(
      '.${_basename(outputPath)}.universal-stage-',
    );
    var published = false;
    try {
      await _assembleStaging(staging, arm64, x86_64, codePaths, resources);
      await _publish(staging, Directory(outputPath));
      published = true;
    } finally {
      if (!published && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
    output('$outputPath\n');
    return 0;
  }

  Future<Directory> _canonicalInput(Directory input) async {
    if (await FileSystemEntity.type(input.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const RuntimeBuilderException(
        'thin input application must not be a symbolic link',
        exitCode: builderUsageExitCode,
      );
    }
    if (!await input.exists()) {
      throw RuntimeBuilderException(
        'thin input application does not exist: ${input.path}',
        exitCode: builderIoErrorExitCode,
      );
    }
    if (!_basename(input.path).endsWith('.app')) {
      throw const RuntimeBuilderException(
        'each --input-app must name an .app directory',
        exitCode: builderUsageExitCode,
      );
    }
    return Directory(await input.resolveSymbolicLinks());
  }

  Future<String> _canonicalDestination(Directory outputApplication) async {
    final FileSystemEntityType outputType = await FileSystemEntity.type(
      outputApplication.path,
      followLinks: false,
    );
    if (outputType == FileSystemEntityType.link) {
      throw const RuntimeBuilderException(
        'output application must not be a symbolic link',
        exitCode: builderUsageExitCode,
      );
    }
    if (outputType != FileSystemEntityType.notFound &&
        outputType != FileSystemEntityType.directory) {
      throw const RuntimeBuilderException(
        'output application must be a directory or an unused path',
        exitCode: builderUsageExitCode,
      );
    }
    final Directory parent = outputApplication.parent;
    if (!await parent.exists()) {
      throw RuntimeBuilderException(
        'output parent does not exist: ${parent.path}',
        exitCode: builderIoErrorExitCode,
      );
    }
    final String canonicalParent = await parent.resolveSymbolicLinks();
    return _join(canonicalParent, _basename(outputApplication.path));
  }

  Future<_ThinBundle> _loadThinBundle(Directory root) async {
    final Map<String, _BundleEntry> inventory = await _scanBundle(root);
    await _runChecked(
      'thin application signature validation',
      '/usr/bin/codesign',
      <String>['--verify', '--deep', '--strict', root.path],
    );
    const String manifestPath =
        'Contents/Resources/runtime-build-manifest.json';
    final _BundleEntry? manifestEntry = inventory[manifestPath];
    if (manifestEntry == null ||
        manifestEntry.type != FileSystemEntityType.file) {
      throw const RuntimeBuilderException(
        'thin application is missing its regular build manifest',
        exitCode: builderUsageExitCode,
      );
    }
    final File manifestFile = File(_join(root.path, manifestPath));
    final List<int> manifestBytes = await manifestFile.readAsBytes();
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(manifestBytes));
    } on Object catch (error) {
      throw RuntimeBuilderException(
        'thin build manifest is invalid JSON: $error',
        exitCode: builderUsageExitCode,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const RuntimeBuilderException(
        'thin build manifest must be a JSON object',
        exitCode: builderUsageExitCode,
      );
    }
    final _ThinManifest manifest = _ThinManifest.parse(decoded);
    for (final String codePath in manifest.codePaths) {
      final _BundleEntry? entry = inventory[codePath];
      if (entry == null || entry.type != FileSystemEntityType.file) {
        throw RuntimeBuilderException(
          'declared code entry is missing or not a regular file: $codePath',
          exitCode: builderUsageExitCode,
        );
      }
      final String architectures = await _runCaptured(
        'thin architecture validation ($codePath)',
        '/usr/bin/lipo',
        <String>['-archs', _join(root.path, codePath)],
      );
      if (!_sameStrings(
        architectures.split(RegExp(r'\s+')).where((String v) => v.isNotEmpty),
        <String>[manifest.architecture],
      )) {
        throw RuntimeBuilderException(
          'thin code entry does not contain exactly '
          '${manifest.architecture}: $codePath',
          exitCode: builderUsageExitCode,
        );
      }
    }
    return _ThinBundle(
      root: root,
      inventory: inventory,
      manifest: manifest,
      manifestHash: await _hashFile(manifestFile),
    );
  }

  Future<Map<String, _BundleEntry>> _scanBundle(Directory root) async {
    final Map<String, _BundleEntry> inventory = <String, _BundleEntry>{};
    final Set<String> foldedPaths = <String>{};
    await for (final FileSystemEntity entity in root.list(
      recursive: true,
      followLinks: false,
    )) {
      final String relativePath = entity.path.substring(root.path.length + 1);
      final FileSystemEntityType type = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) {
        throw RuntimeBuilderException(
          'application bundle contains a symbolic link: $relativePath',
          exitCode: builderUsageExitCode,
        );
      }
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.directory) {
        throw RuntimeBuilderException(
          'application bundle contains an unsupported entry: $relativePath',
          exitCode: builderUsageExitCode,
        );
      }
      if (!_safeRelativePath(relativePath)) {
        throw RuntimeBuilderException(
          'application bundle contains an unsafe path: $relativePath',
          exitCode: builderUsageExitCode,
        );
      }
      final String foldedPath = relativePath.toLowerCase();
      if (!foldedPaths.add(foldedPath)) {
        throw RuntimeBuilderException(
          'application bundle contains case-folded path aliases: $relativePath',
          exitCode: builderUsageExitCode,
        );
      }
      if (relativePath == 'Contents/_CodeSignature' ||
          relativePath.startsWith('Contents/_CodeSignature/')) {
        continue;
      }
      final FileStat stat = await entity.stat();
      inventory[relativePath] = _BundleEntry(
        type: type,
        permissions: stat.mode & 0x1ff,
        bytes: type == FileSystemEntityType.file ? stat.size : 0,
      );
    }
    return inventory;
  }

  void _validateMatchingContracts(_ThinBundle arm64, _ThinBundle x86_64) {
    if (arm64.manifest.canonicalContract != x86_64.manifest.canonicalContract) {
      throw const RuntimeBuilderException(
        'thin build manifests do not describe the same application contract',
        exitCode: builderUsageExitCode,
      );
    }
    if (!_sameStrings(arm64.manifest.codePaths, x86_64.manifest.codePaths)) {
      throw const RuntimeBuilderException(
        'thin build manifests do not declare the same code inventory',
        exitCode: builderUsageExitCode,
      );
    }
  }

  Future<List<_ResourceEvidence>> _validateInventories(
    _ThinBundle arm64,
    _ThinBundle x86_64,
    Set<String> codePaths,
  ) async {
    if (!_sameStrings(arm64.inventory.keys, x86_64.inventory.keys)) {
      throw const RuntimeBuilderException(
        'thin application inventories do not match exactly',
        exitCode: builderUsageExitCode,
      );
    }
    const String manifestPath =
        'Contents/Resources/runtime-build-manifest.json';
    final List<_ResourceEvidence> resources = <_ResourceEvidence>[];
    final List<String> paths = arm64.inventory.keys.toList()..sort();
    for (final String path in paths) {
      final _BundleEntry armEntry = arm64.inventory[path]!;
      final _BundleEntry x86Entry = x86_64.inventory[path]!;
      if (armEntry.type != x86Entry.type ||
          armEntry.permissions != x86Entry.permissions) {
        throw RuntimeBuilderException(
          'thin entry type or permissions differ: $path',
          exitCode: builderUsageExitCode,
        );
      }
      if (armEntry.type == FileSystemEntityType.directory ||
          path == manifestPath ||
          codePaths.contains(path)) {
        continue;
      }
      if (armEntry.permissions & 0x49 != 0) {
        throw RuntimeBuilderException(
          'unexpected executable entry outside the declared code inventory: '
          '$path',
          exitCode: builderUsageExitCode,
        );
      }
      final File armFile = File(_join(arm64.root.path, path));
      final File x86File = File(_join(x86_64.root.path, path));
      final String armDescription = await _runCaptured(
        'resource type validation ($path)',
        '/usr/bin/file',
        <String>['-b', armFile.path],
      );
      final String x86Description = await _runCaptured(
        'resource type validation ($path)',
        '/usr/bin/file',
        <String>['-b', x86File.path],
      );
      if (armDescription.contains('Mach-O') ||
          x86Description.contains('Mach-O')) {
        throw RuntimeBuilderException(
          'unexpected Mach-O entry outside the declared code inventory: $path',
          exitCode: builderUsageExitCode,
        );
      }
      if (armEntry.bytes != x86Entry.bytes) {
        throw RuntimeBuilderException(
          'architecture-neutral file sizes differ: $path',
          exitCode: builderUsageExitCode,
        );
      }
      final String armHash = await _hashFile(armFile);
      final String x86Hash = await _hashFile(x86File);
      if (armHash != x86Hash) {
        throw RuntimeBuilderException(
          'architecture-neutral file bytes differ: $path',
          exitCode: builderUsageExitCode,
        );
      }
      resources.add(
        _ResourceEvidence(path: path, bytes: armEntry.bytes, sha256: armHash),
      );
    }
    return resources;
  }

  Future<void> _assembleStaging(
    Directory staging,
    _ThinBundle arm64,
    _ThinBundle x86_64,
    Set<String> codePaths,
    List<_ResourceEvidence> resources,
  ) async {
    const String manifestPath =
        'Contents/Resources/runtime-build-manifest.json';
    final List<String> directories =
        arm64.inventory.entries
            .where(
              (MapEntry<String, _BundleEntry> entry) =>
                  entry.value.type == FileSystemEntityType.directory,
            )
            .map((MapEntry<String, _BundleEntry> entry) => entry.key)
            .toList()
          ..sort(_pathDepthOrder);
    for (final String path in directories) {
      await Directory(_join(staging.path, path)).create(recursive: true);
    }

    final List<String> files =
        arm64.inventory.entries
            .where(
              (MapEntry<String, _BundleEntry> entry) =>
                  entry.value.type == FileSystemEntityType.file,
            )
            .map((MapEntry<String, _BundleEntry> entry) => entry.key)
            .toList()
          ..sort();
    for (final String path in files) {
      if (path == manifestPath) continue;
      final File destination = File(_join(staging.path, path));
      await destination.parent.create(recursive: true);
      if (codePaths.contains(path)) {
        await _runChecked(
          'Universal code merge ($path)',
          '/usr/bin/lipo',
          <String>[
            '-create',
            _join(arm64.root.path, path),
            _join(x86_64.root.path, path),
            '-output',
            destination.path,
          ],
        );
        final String architectures = await _runCaptured(
          'Universal architecture validation ($path)',
          '/usr/bin/lipo',
          <String>['-archs', destination.path],
        );
        if (!_sameStrings(
          architectures
              .split(RegExp(r'\s+'))
              .where((String value) => value.isNotEmpty),
          const <String>['arm64', 'x86_64'],
        )) {
          throw RuntimeBuilderException(
            'merged code entry is not exactly arm64/x86_64: $path',
            exitCode: builderSoftwareExitCode,
          );
        }
        await _validateDependencies(destination, path);
      } else {
        await File(_join(arm64.root.path, path)).copy(destination.path);
      }
      await _setPermissions(destination, arm64.inventory[path]!.permissions);
    }

    final File manifestFile = File(_join(staging.path, manifestPath));
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'schemaVersion': 2,
            ...arm64.manifest.normalizedContract,
            'runtimeMode': 'release-aot',
            'architectures': const <String>['arm64', 'x86_64'],
            'bundleIdentifier': arm64.manifest.bundleIdentifier,
            'executable': arm64.manifest.executable,
            'payload': arm64.manifest.payload,
            'engine': arm64.manifest.engine,
            'dartSdkVersion': arm64.manifest.dartSdkVersion,
            'dartSdkRevision': arm64.manifest.dartSdkRevision,
            'codePaths': codePaths.toList()..sort(),
            'resourceFiles': <Map<String, Object?>>[
              for (final _ResourceEvidence resource in resources)
                <String, Object?>{
                  'path': resource.path,
                  'bytes': resource.bytes,
                  'sha256': resource.sha256,
                },
            ],
            'thinManifests': <String, String>{
              'arm64': arm64.manifestHash,
              'x86_64': x86_64.manifestHash,
            },
            'applicationContract': arm64.manifest.normalizedContract,
          }) +
          '\n',
      flush: true,
    );
    await _setPermissions(
      manifestFile,
      arm64.inventory[manifestPath]!.permissions,
    );
    await _runChecked('Info.plist validation', '/usr/bin/plutil', <String>[
      '-lint',
      _join(staging.path, 'Contents/Info.plist'),
    ]);

    final List<String> signingOrder = codePaths.toList()..sort();
    for (final String path in signingOrder) {
      await _runChecked(
        'nested code signing ($path)',
        '/usr/bin/codesign',
        <String>['--force', '--sign', '-', _join(staging.path, path)],
      );
    }
    await _runChecked(
      'outer application signing',
      '/usr/bin/codesign',
      <String>['--force', '--sign', '-', staging.path],
    );
    await _runChecked(
      'strict application signature verification',
      '/usr/bin/codesign',
      <String>['--verify', '--deep', '--strict', staging.path],
    );
  }

  Future<void> _validateDependencies(File image, String relativePath) async {
    final String output = await _runCaptured(
      'Mach-O dependency validation ($relativePath)',
      '/usr/bin/otool',
      <String>['-L', image.path],
    );
    final List<String> lines = const LineSplitter().convert(output);
    for (final String line in lines) {
      if (!line.startsWith(' ') && !line.startsWith('\t')) continue;
      final String value = line.trim().split(' (').first;
      if (value.startsWith('/') &&
          !value.startsWith('/System/') &&
          !value.startsWith('/usr/lib/')) {
        throw RuntimeBuilderException(
          'merged code entry has an absolute non-system dependency: '
          '$relativePath',
          exitCode: builderSoftwareExitCode,
        );
      }
    }
  }

  Future<void> _setPermissions(File file, int permissions) async {
    await _runChecked('permission update', '/bin/chmod', <String>[
      permissions.toRadixString(8).padLeft(3, '0'),
      file.path,
    ]);
  }

  Future<void> _publish(Directory staging, Directory outputApplication) async {
    if (!await outputApplication.exists()) {
      await staging.rename(outputApplication.path);
      return;
    }
    final Directory backup = await outputApplication.parent.createTemp(
      '.${_basename(outputApplication.path)}.previous-',
    );
    await backup.delete();
    await outputApplication.rename(backup.path);
    try {
      await staging.rename(outputApplication.path);
    } on Object {
      await backup.rename(outputApplication.path);
      rethrow;
    }
    try {
      await backup.delete(recursive: true);
    } on FileSystemException {
      // Publication has completed. A stale hidden backup is safer than
      // invalidating the verified output because cleanup alone failed.
    }
  }

  Future<String> _hashFile(File file) async {
    final String output = await _runCaptured(
      'SHA-256 calculation',
      '/usr/bin/shasum',
      <String>['-a', '256', file.path],
    );
    final String hash = output.split(RegExp(r'\s+')).first.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const RuntimeBuilderException(
        'SHA-256 tool returned an invalid digest',
        exitCode: builderSoftwareExitCode,
      );
    }
    return hash;
  }

  Future<void> _runChecked(
    String label,
    String executable,
    List<String> arguments,
  ) async {
    final BuilderCommandResult result = await processExecutor.run(
      executable,
      arguments,
      workingDirectory: currentDirectory,
    );
    if (result.stdoutText.isNotEmpty) output(result.stdoutText);
    if (result.stderrText.isNotEmpty) errorOutput(result.stderrText);
    if (result.exitCode != 0) {
      throw RuntimeBuilderException(
        '$label failed with exit code ${result.exitCode}',
        exitCode: result.exitCode,
      );
    }
  }

  Future<String> _runCaptured(
    String label,
    String executable,
    List<String> arguments,
  ) async {
    final BuilderCommandResult result = await processExecutor.run(
      executable,
      arguments,
      workingDirectory: currentDirectory,
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
        exitCode: builderSoftwareExitCode,
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
}

final class _ThinManifest {
  _ThinManifest({
    required this.architecture,
    required this.bundleIdentifier,
    required this.executable,
    required this.payload,
    required this.engine,
    required this.dartSdkVersion,
    required this.dartSdkRevision,
    required this.codePaths,
    required this.normalizedContract,
    required this.canonicalContract,
  });

  factory _ThinManifest.parse(Map<String, Object?> source) {
    String requiredString(String key) {
      final Object? value = source[key];
      if (value is! String || value.isEmpty) {
        throw RuntimeBuilderException(
          'thin build manifest has no valid $key',
          exitCode: builderUsageExitCode,
        );
      }
      return value;
    }

    if (source['schemaVersion'] != 1 ||
        source['runtimeMode'] != 'release-aot') {
      throw const RuntimeBuilderException(
        'thin build manifest must be schema 1 Release AOT evidence',
        exitCode: builderUsageExitCode,
      );
    }
    final String architecture = requiredString('architecture');
    if (architecture != 'arm64' && architecture != 'x86_64') {
      throw const RuntimeBuilderException(
        'thin build manifest architecture must be arm64 or x86_64',
        exitCode: builderUsageExitCode,
      );
    }
    final String executable = _safeLeaf(requiredString('executable'));
    final String payload = _safeLeaf(requiredString('payload'));
    final String engine = _safeLeaf(requiredString('engine'));
    final Set<String> codePaths = <String>{
      'Contents/MacOS/$executable',
      'Contents/Resources/$payload',
      'Contents/Frameworks/$engine',
    };

    void addDeclaredCode(String listKey, String valueKey, String parent) {
      final Object? value = source[listKey];
      if (value is! List<Object?>) {
        throw RuntimeBuilderException(
          'thin build manifest has no valid $listKey list',
          exitCode: builderUsageExitCode,
        );
      }
      for (final Object? item in value) {
        if (item is! Map<String, Object?> || item[valueKey] is! String) {
          throw RuntimeBuilderException(
            'thin build manifest has an invalid $listKey entry',
            exitCode: builderUsageExitCode,
          );
        }
        final String leaf = _safeLeaf(item[valueKey]! as String);
        if (!codePaths.add('$parent/$leaf')) {
          throw RuntimeBuilderException(
            'thin build manifest declares duplicate code: $leaf',
            exitCode: builderUsageExitCode,
          );
        }
      }
    }

    final Object? helpers = source['dartHelpers'];
    if (helpers is! List<Object?>) {
      throw const RuntimeBuilderException(
        'thin build manifest has no valid dartHelpers list',
        exitCode: builderUsageExitCode,
      );
    }
    for (final Object? value in helpers) {
      if (value is! Map<String, Object?> || value['name'] is! String) {
        throw const RuntimeBuilderException(
          'thin build manifest has an invalid dartHelpers entry',
          exitCode: builderUsageExitCode,
        );
      }
      final String name = _safeLeaf(value['name']! as String);
      if (!codePaths.add('Contents/Helpers/$name')) {
        throw RuntimeBuilderException(
          'thin build manifest declares duplicate code: $name',
          exitCode: builderUsageExitCode,
        );
      }
      final Object? helperPayload = value['payload'];
      if (helperPayload != null) {
        if (helperPayload is! String || !_safeRelativePath(helperPayload)) {
          throw const RuntimeBuilderException(
            'thin build manifest has an invalid Dart helper payload',
            exitCode: builderUsageExitCode,
          );
        }
        final String path = 'Contents/Resources/$helperPayload';
        if (!codePaths.add(path)) {
          throw RuntimeBuilderException(
            'thin build manifest declares duplicate code: $helperPayload',
            exitCode: builderUsageExitCode,
          );
        }
      }
    }
    addDeclaredCode('nativeAssets', 'library', 'Contents/Frameworks');
    addDeclaredCode('nativeCapabilities', 'library', 'Contents/Frameworks');

    final Map<String, Object?> normalized = _deepCopyMap(source);
    normalized.remove('schemaVersion');
    normalized.remove('architecture');
    final Object? appIntents = normalized['appIntents'];
    if (appIntents != null) {
      if (appIntents is! Map<String, Object?> ||
          appIntents['library'] is! String ||
          appIntents['targetTriple'] is! String ||
          appIntents['libraryBytes'] is! int) {
        throw const RuntimeBuilderException(
          'thin build manifest has invalid App Intents evidence',
          exitCode: builderUsageExitCode,
        );
      }
      final String targetTriple = appIntents['targetTriple']! as String;
      final String prefix = '$architecture-apple-macos';
      if (!targetTriple.startsWith(prefix) ||
          targetTriple.length == prefix.length) {
        throw const RuntimeBuilderException(
          'App Intents target does not match the thin architecture',
          exitCode: builderUsageExitCode,
        );
      }
      final String library = _safeLeaf(appIntents['library']! as String);
      if (!codePaths.add('Contents/Frameworks/$library')) {
        throw RuntimeBuilderException(
          'thin build manifest declares duplicate code: $library',
          exitCode: builderUsageExitCode,
        );
      }
      appIntents['targetTriple'] =
          r'$ARCH-apple-macos' + targetTriple.substring(prefix.length);
      appIntents.remove('libraryBytes');
    }
    final Object? canonicalObject = _canonicalizeJson(normalized);
    return _ThinManifest(
      architecture: architecture,
      bundleIdentifier: requiredString('bundleIdentifier'),
      executable: executable,
      payload: payload,
      engine: engine,
      dartSdkVersion: requiredString('dartSdkVersion'),
      dartSdkRevision: requiredString('dartSdkRevision'),
      codePaths: Set<String>.unmodifiable(codePaths),
      normalizedContract: canonicalObject! as Map<String, Object?>,
      canonicalContract: jsonEncode(canonicalObject),
    );
  }

  final String architecture;
  final String bundleIdentifier;
  final String executable;
  final String payload;
  final String engine;
  final String dartSdkVersion;
  final String dartSdkRevision;
  final Set<String> codePaths;
  final Map<String, Object?> normalizedContract;
  final String canonicalContract;
}

final class _ThinBundle {
  const _ThinBundle({
    required this.root,
    required this.inventory,
    required this.manifest,
    required this.manifestHash,
  });

  final Directory root;
  final Map<String, _BundleEntry> inventory;
  final _ThinManifest manifest;
  final String manifestHash;
}

final class _BundleEntry {
  const _BundleEntry({
    required this.type,
    required this.permissions,
    required this.bytes,
  });

  final FileSystemEntityType type;
  final int permissions;
  final int bytes;
}

final class _ResourceEvidence {
  const _ResourceEvidence({
    required this.path,
    required this.bytes,
    required this.sha256,
  });

  final String path;
  final int bytes;
  final String sha256;
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> source) =>
    jsonDecode(jsonEncode(source))! as Map<String, Object?>;

Object? _canonicalizeJson(Object? value) {
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonicalizeJson(value[key]),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final Object? item in value) _canonicalizeJson(item)];
  }
  return value;
}

String _safeLeaf(String value) {
  if (value.isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains('\\') ||
      value.contains('\u0000')) {
    throw RuntimeBuilderException(
      'build manifest code name is unsafe: $value',
      exitCode: builderUsageExitCode,
    );
  }
  return value;
}

bool _safeRelativePath(String value) {
  if (value.isEmpty || value.startsWith('/') || value.contains('\\')) {
    return false;
  }
  final List<String> parts = value.split('/');
  return parts.every(
    (String part) =>
        part.isNotEmpty &&
        part != '.' &&
        part != '..' &&
        !part.contains('\u0000'),
  );
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final List<String> sortedLeft = left.toList()..sort();
  final List<String> sortedRight = right.toList()..sort();
  if (sortedLeft.length != sortedRight.length) return false;
  for (var index = 0; index < sortedLeft.length; ++index) {
    if (sortedLeft[index] != sortedRight[index]) return false;
  }
  return true;
}

bool _samePath(String left, String right) =>
    left.toLowerCase() == right.toLowerCase();

bool _pathsOverlap(String left, String right) {
  final String normalizedLeft = left.toLowerCase();
  final String normalizedRight = right.toLowerCase();
  return normalizedLeft == normalizedRight ||
      normalizedLeft.startsWith('$normalizedRight${Platform.pathSeparator}') ||
      normalizedRight.startsWith('$normalizedLeft${Platform.pathSeparator}');
}

int _pathDepthOrder(String left, String right) {
  final int depth = left.split('/').length.compareTo(right.split('/').length);
  return depth == 0 ? left.compareTo(right) : depth;
}

String _join(String parent, String child) =>
    Directory(parent).uri.resolve(child).toFilePath();

String _basename(String path) => File(path).uri.pathSegments.last;

Future<int> runUniversalAssemblerCommand(
  List<String> arguments, {
  UniversalApplicationAssembler? assembler,
  BuilderOutput? output,
  BuilderOutput? errorOutput,
}) async {
  final BuilderOutput writeOutput = output ?? stdout.write;
  final BuilderOutput writeError = errorOutput ?? stderr.write;
  try {
    final UniversalAssemblerOptions options = UniversalAssemblerOptions.parse(
      arguments,
    );
    if (options.showHelp) {
      writeOutput(universalAssemblerUsage);
      return 0;
    }
    final UniversalApplicationAssembler active =
        assembler ??
        UniversalApplicationAssembler(
          currentDirectory: Directory.current.path,
          output: writeOutput,
          errorOutput: writeError,
        );
    return await active.run(options);
  } on RuntimeBuilderException catch (error) {
    writeError('dart_macos_runtime:universal: ${error.message}\n');
    if (error.exitCode == builderUsageExitCode) {
      writeError(universalAssemblerUsage);
    }
    return error.exitCode;
  } on Object catch (error, stackTrace) {
    writeError(
      'dart_macos_runtime:universal: unexpected failure: '
      '$error\n$stackTrace\n',
    );
    return builderSoftwareExitCode;
  }
}
