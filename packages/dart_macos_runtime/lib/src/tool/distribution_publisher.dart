import 'dart:convert';
import 'dart:io';

import 'builder.dart';

const String distributionPublisherUsage = '''
Usage: dart run dart_macos_runtime:distribute --input-app <bundle> \\
       --output-directory <directory> --signing-identity <identity> \\
       --team-id <identifier> --entitlements <plist> \\
       --keychain-profile <profile> [options]

Options:
  -h, --help                         Show this help.
      --validate-only                Validate inputs without signing or upload.
      --input-app <bundle>           Audited Universal Release AOT application.
      --output-directory <directory> Atomic distribution destination.
      --signing-identity <identity>  Developer ID Application identity.
      --team-id <identifier>         Expected ten-character Apple Team ID.
      --entitlements <plist>         Reviewed outer-application entitlements.
      --keychain-profile <profile>   notarytool Keychain profile name.
      --wait-timeout-seconds <n>     Notary wait timeout, 60..7200 (default 1800).
''';

final class DistributionPublisherOptions {
  const DistributionPublisherOptions({
    required this.showHelp,
    required this.validateOnly,
    required this.inputApplication,
    required this.outputDirectory,
    required this.signingIdentity,
    required this.teamIdentifier,
    required this.entitlementsPath,
    required this.keychainProfile,
    required this.waitTimeoutSeconds,
  });

  factory DistributionPublisherOptions.parse(List<String> arguments) {
    var showHelp = false;
    var validateOnly = false;
    String? inputApplication;
    String? outputDirectory;
    String? signingIdentity;
    String? teamIdentifier;
    String? entitlementsPath;
    String? keychainProfile;
    var waitTimeoutSeconds = 1800;
    final Set<String> seen = <String>{};

    for (var index = 0; index < arguments.length; ++index) {
      final String argument = arguments[index];
      if (argument == '-h' || argument == '--help') {
        showHelp = true;
        continue;
      }
      if (argument == '--validate-only') {
        if (validateOnly) {
          throw const RuntimeBuilderException(
            '--validate-only may be specified only once',
            exitCode: builderUsageExitCode,
          );
        }
        validateOnly = true;
        continue;
      }

      String optionValue(String name) {
        if (!seen.add(name)) {
          throw RuntimeBuilderException(
            '$name may be specified only once',
            exitCode: builderUsageExitCode,
          );
        }
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
        inputApplication = optionValue('--input-app');
      } else if (argument == '--output-directory' ||
          argument.startsWith('--output-directory=')) {
        outputDirectory = optionValue('--output-directory');
      } else if (argument == '--signing-identity' ||
          argument.startsWith('--signing-identity=')) {
        signingIdentity = optionValue('--signing-identity');
      } else if (argument == '--team-id' || argument.startsWith('--team-id=')) {
        teamIdentifier = optionValue('--team-id');
      } else if (argument == '--entitlements' ||
          argument.startsWith('--entitlements=')) {
        entitlementsPath = optionValue('--entitlements');
      } else if (argument == '--keychain-profile' ||
          argument.startsWith('--keychain-profile=')) {
        keychainProfile = optionValue('--keychain-profile');
      } else if (argument == '--wait-timeout-seconds' ||
          argument.startsWith('--wait-timeout-seconds=')) {
        final String value = optionValue('--wait-timeout-seconds');
        waitTimeoutSeconds = int.tryParse(value) ?? -1;
        if (waitTimeoutSeconds < 60 || waitTimeoutSeconds > 7200) {
          throw const RuntimeBuilderException(
            '--wait-timeout-seconds must be an integer from 60 through 7200',
            exitCode: builderUsageExitCode,
          );
        }
      } else {
        throw RuntimeBuilderException(
          'unknown option: $argument',
          exitCode: builderUsageExitCode,
        );
      }
    }

    if (!showHelp) {
      final List<String> missing = <String>[
        if (inputApplication == null) '--input-app',
        if (outputDirectory == null) '--output-directory',
        if (signingIdentity == null) '--signing-identity',
        if (teamIdentifier == null) '--team-id',
        if (entitlementsPath == null) '--entitlements',
        if (keychainProfile == null) '--keychain-profile',
      ];
      if (missing.isNotEmpty) {
        throw RuntimeBuilderException(
          'required option is missing: ${missing.first}',
          exitCode: builderUsageExitCode,
        );
      }
      _validateLabel(signingIdentity!, '--signing-identity', 256);
      _validateLabel(keychainProfile!, '--keychain-profile', 128);
      if (!RegExp(r'^[A-Z0-9]{10}$').hasMatch(teamIdentifier!)) {
        throw const RuntimeBuilderException(
          '--team-id must be ten uppercase letters or digits',
          exitCode: builderUsageExitCode,
        );
      }
    }

    return DistributionPublisherOptions(
      showHelp: showHelp,
      validateOnly: validateOnly,
      inputApplication: inputApplication,
      outputDirectory: outputDirectory,
      signingIdentity: signingIdentity,
      teamIdentifier: teamIdentifier,
      entitlementsPath: entitlementsPath,
      keychainProfile: keychainProfile,
      waitTimeoutSeconds: waitTimeoutSeconds,
    );
  }

  final bool showHelp;
  final bool validateOnly;
  final String? inputApplication;
  final String? outputDirectory;
  final String? signingIdentity;
  final String? teamIdentifier;
  final String? entitlementsPath;
  final String? keychainProfile;
  final int waitTimeoutSeconds;

  static void _validateLabel(String value, String option, int maxBytes) {
    if (value.trim() != value ||
        value.isEmpty ||
        utf8.encode(value).length > maxBytes ||
        value.runes.any((int rune) => rune < 0x20 || rune == 0x7f)) {
      throw RuntimeBuilderException(
        '$option must be a trimmed display-safe value',
        exitCode: builderUsageExitCode,
      );
    }
  }
}

final class DistributionPublisher {
  DistributionPublisher({
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

  Future<int> run(DistributionPublisherOptions options) async {
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

  Future<int> _run(DistributionPublisherOptions options) async {
    final Directory source = await _canonicalInput(
      Directory(_resolvePath(options.inputApplication!)),
    );
    final File entitlements = await _canonicalEntitlements(
      File(_resolvePath(options.entitlementsPath!)),
    );
    final String outputPath = await _canonicalDestination(
      Directory(_resolvePath(options.outputDirectory!)),
    );
    if (_pathsOverlap(source.path, outputPath) ||
        _pathsOverlap(entitlements.path, outputPath)) {
      throw const RuntimeBuilderException(
        'output directory must not overlap an input',
        exitCode: builderUsageExitCode,
      );
    }

    final _SourceBundle bundle = await _loadSource(source);
    final String entitlementsJson = await _canonicalPlist(entitlements);
    final Object? entitlementsValue = jsonDecode(entitlementsJson);
    if (entitlementsValue is! Map<String, Object?>) {
      throw const RuntimeBuilderException(
        'entitlements must be a property-list dictionary',
        exitCode: builderUsageExitCode,
      );
    }
    const Set<String> prohibitedTrueEntitlements = <String>{
      'com.apple.security.get-task-allow',
      'com.apple.security.cs.allow-jit',
      'com.apple.security.cs.allow-unsigned-executable-memory',
      'com.apple.security.cs.disable-executable-page-protection',
      'com.apple.security.cs.disable-library-validation',
      'com.apple.security.cs.debugger',
    };
    for (final String key in prohibitedTrueEntitlements) {
      if (entitlementsValue[key] == true) {
        throw RuntimeBuilderException(
          'Release AOT distribution forbids entitlement: $key',
          exitCode: builderUsageExitCode,
        );
      }
    }
    final String entitlementsHash = await _hashFile(entitlements);
    if (options.validateOnly) {
      output(
        'DISTRIBUTION_PREFLIGHT_PASS '
        'bundle=${bundle.bundleIdentifier} code=${bundle.codePaths.length}\n',
      );
      return 0;
    }

    await _validateIdentityAvailable(options.signingIdentity!);
    final Directory outputDirectory = Directory(outputPath);
    final Directory staging = await outputDirectory.parent.createTemp(
      '.${_basename(outputPath)}.distribution-stage-',
    );
    var published = false;
    try {
      final Directory signedApplication = Directory(
        _join(staging.path, _basename(source.path)),
      );
      await _copyBundle(source, signedApplication);
      final Directory codeSignature = Directory(
        _join(signedApplication.path, 'Contents/_CodeSignature'),
      );
      if (await codeSignature.exists()) {
        await codeSignature.delete(recursive: true);
      }
      await _signAndVerify(
        signedApplication,
        bundle,
        options,
        entitlements,
        entitlementsJson,
        staging,
      );

      final File submissionArchive = File(
        _join(staging.path, '.notary-submission.zip'),
      );
      await _archive(signedApplication, submissionArchive);
      final String submissionId = await _submit(
        submissionArchive,
        options.keychainProfile!,
      );
      await _waitForAcceptance(
        submissionId,
        options.keychainProfile!,
        options.waitTimeoutSeconds,
      );
      final _NotaryLogSummary notaryLog = await _reviewNotaryLog(
        submissionId,
        options.keychainProfile!,
        staging,
      );
      await _runChecked('ticket stapling', '/usr/bin/xcrun', <String>[
        'stapler',
        'staple',
        '-v',
        signedApplication.path,
      ]);
      await _runChecked('stapled ticket validation', '/usr/bin/xcrun', <String>[
        'stapler',
        'validate',
        '-v',
        signedApplication.path,
      ]);
      await _runChecked(
        'post-staple signature validation',
        '/usr/bin/codesign',
        <String>['--verify', '--deep', '--strict', signedApplication.path],
      );
      await _runChecked(
        'Gatekeeper execution assessment',
        '/usr/sbin/spctl',
        <String>[
          '--assess',
          '--type',
          'execute',
          '--verbose=4',
          signedApplication.path,
        ],
      );

      if (await submissionArchive.exists()) await submissionArchive.delete();
      final String archiveName =
          '${_basename(source.path).substring(0, _basename(source.path).length - 4)}.zip';
      final File finalArchive = File(_join(staging.path, archiveName));
      await _archive(signedApplication, finalArchive);
      final String archiveHash = await _hashFile(finalArchive);
      final List<Map<String, Object?>> signedCode = <Map<String, Object?>>[];
      for (final String path in bundle.codePaths.toList()..sort()) {
        signedCode.add(<String, Object?>{
          'path': path,
          'sha256': await _hashFile(File(_join(signedApplication.path, path))),
        });
      }
      final File evidence = File(
        _join(staging.path, 'distribution-manifest.json'),
      );
      await evidence.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'schemaVersion': 1,
          'bundleIdentifier': bundle.bundleIdentifier,
          'architectures': const <String>['arm64', 'x86_64'],
          'sourceManifestSha256': bundle.manifestHash,
          'entitlementsSha256': entitlementsHash,
          'signingIdentity': options.signingIdentity,
          'teamIdentifier': options.teamIdentifier,
          'hardenedRuntime': true,
          'secureTimestamp': true,
          'notarization': <String, Object?>{'id': submissionId, 'status': 'Accepted', 'logFormatVersion': notaryLog.formatVersion, 'issues': notaryLog.issueCount, 'stapled': true, 'gatekeeperAccepted': true},
          'application': _basename(source.path),
          'archive': <String, Object?>{'name': archiveName, 'sha256': archiveHash},
          'code': signedCode,
        })}\n',
        flush: true,
      );
      await _publish(staging, outputDirectory);
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
        'input application must not be a symbolic link',
        exitCode: builderUsageExitCode,
      );
    }
    if (!await input.exists()) {
      throw RuntimeBuilderException(
        'input application does not exist: ${input.path}',
        exitCode: builderIoErrorExitCode,
      );
    }
    if (!_basename(input.path).endsWith('.app')) {
      throw const RuntimeBuilderException(
        '--input-app must name an .app directory',
        exitCode: builderUsageExitCode,
      );
    }
    return Directory(await input.resolveSymbolicLinks());
  }

  Future<File> _canonicalEntitlements(File input) async {
    if (await FileSystemEntity.type(input.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const RuntimeBuilderException(
        'entitlements must not be a symbolic link',
        exitCode: builderUsageExitCode,
      );
    }
    if (!await input.exists()) {
      throw RuntimeBuilderException(
        'entitlements do not exist: ${input.path}',
        exitCode: builderIoErrorExitCode,
      );
    }
    return File(await input.resolveSymbolicLinks());
  }

  Future<String> _canonicalDestination(Directory outputDirectory) async {
    final FileSystemEntityType type = await FileSystemEntity.type(
      outputDirectory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      throw const RuntimeBuilderException(
        'output directory must not be a symbolic link',
        exitCode: builderUsageExitCode,
      );
    }
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw const RuntimeBuilderException(
        'output must be a directory or an unused path',
        exitCode: builderUsageExitCode,
      );
    }
    if (!await outputDirectory.parent.exists()) {
      throw RuntimeBuilderException(
        'output parent does not exist: ${outputDirectory.parent.path}',
        exitCode: builderIoErrorExitCode,
      );
    }
    return _join(
      await outputDirectory.parent.resolveSymbolicLinks(),
      _basename(outputDirectory.path),
    );
  }

  Future<_SourceBundle> _loadSource(Directory root) async {
    final Map<String, _BundleEntry> inventory = await _scanBundle(root);
    await _runChecked(
      'source application signature validation',
      '/usr/bin/codesign',
      <String>['--verify', '--deep', '--strict', root.path],
    );
    final String sourceSignature = await _runCombined(
      'source signature inspection',
      '/usr/bin/codesign',
      <String>['--display', '--verbose=4', root.path],
    );
    if (!sourceSignature.contains('Signature=adhoc') ||
        !sourceSignature.contains('TeamIdentifier=not set')) {
      throw const RuntimeBuilderException(
        'source application must retain its audited ad-hoc signature',
        exitCode: builderUsageExitCode,
      );
    }

    const String manifestPath =
        'Contents/Resources/runtime-build-manifest.json';
    if (inventory[manifestPath]?.type != FileSystemEntityType.file) {
      throw const RuntimeBuilderException(
        'input application is missing its regular build manifest',
        exitCode: builderUsageExitCode,
      );
    }
    final File manifestFile = File(_join(root.path, manifestPath));
    final Object? decoded;
    try {
      decoded = jsonDecode(await manifestFile.readAsString());
    } on Object catch (error) {
      throw RuntimeBuilderException(
        'input build manifest is invalid JSON: $error',
        exitCode: builderUsageExitCode,
      );
    }
    final Object? architectures = decoded is Map<String, Object?>
        ? decoded['architectures']
        : null;
    if (decoded is! Map<String, Object?> ||
        decoded['schemaVersion'] != 2 ||
        decoded['runtimeMode'] != 'release-aot' ||
        architectures is! List<Object?> ||
        architectures.length != 2 ||
        architectures.any((Object? value) => value is! String) ||
        !_sameStrings(architectures.cast<String>(), const <String>[
          'arm64',
          'x86_64',
        ])) {
      throw const RuntimeBuilderException(
        'input must be a schema-2 Universal Release AOT application',
        exitCode: builderUsageExitCode,
      );
    }
    final String bundleIdentifier = _requiredString(
      decoded,
      'bundleIdentifier',
    );
    final String executable = _requiredString(decoded, 'executable');
    final Object? applicationContract = decoded['applicationContract'];
    final Object? thinManifests = decoded['thinManifests'];
    if (applicationContract is! Map<String, Object?> ||
        applicationContract['runtimeMode'] != 'release-aot' ||
        applicationContract['bundleIdentifier'] != bundleIdentifier ||
        applicationContract['executable'] != executable ||
        thinManifests is! Map<String, Object?> ||
        thinManifests.length != 2 ||
        !_sameStrings(thinManifests.keys, const <String>['arm64', 'x86_64']) ||
        thinManifests.values.any(
          (Object? value) =>
              value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value),
        )) {
      throw const RuntimeBuilderException(
        'input build manifest has invalid Universal ownership evidence',
        exitCode: builderUsageExitCode,
      );
    }
    final Object? pathsValue = decoded['codePaths'];
    if (pathsValue is! List<Object?> || pathsValue.isEmpty) {
      throw const RuntimeBuilderException(
        'input build manifest has no code inventory',
        exitCode: builderUsageExitCode,
      );
    }
    final Set<String> codePaths = <String>{};
    String previous = '';
    for (final Object? value in pathsValue) {
      if (value is! String ||
          !_safeRelativePath(value) ||
          value.compareTo(previous) <= 0 ||
          !codePaths.add(value)) {
        throw const RuntimeBuilderException(
          'input build manifest code inventory is unsafe or unordered',
          exitCode: builderUsageExitCode,
        );
      }
      previous = value;
      if (inventory[value]?.type != FileSystemEntityType.file) {
        throw RuntimeBuilderException(
          'declared code entry is missing or not a file: $value',
          exitCode: builderUsageExitCode,
        );
      }
    }
    if (!codePaths.contains('Contents/MacOS/$executable')) {
      throw const RuntimeBuilderException(
        'input build manifest omits its main executable',
        exitCode: builderUsageExitCode,
      );
    }
    final String declaredBundleIdentifier = await _runCaptured(
      'bundle identifier validation',
      '/usr/bin/plutil',
      <String>[
        '-extract',
        'CFBundleIdentifier',
        'raw',
        '-o',
        '-',
        _join(root.path, 'Contents/Info.plist'),
      ],
    );
    if (declaredBundleIdentifier != bundleIdentifier) {
      throw const RuntimeBuilderException(
        'Info.plist bundle identifier differs from build evidence',
        exitCode: builderUsageExitCode,
      );
    }
    for (final String path in codePaths) {
      final String fullPath = _join(root.path, path);
      final String architectures = await _runCaptured(
        'source architecture validation ($path)',
        '/usr/bin/lipo',
        <String>['-archs', fullPath],
      );
      if (!_sameStrings(
        architectures.split(RegExp(r'\s+')).where((String v) => v.isNotEmpty),
        const <String>['arm64', 'x86_64'],
      )) {
        throw RuntimeBuilderException(
          'source code is not exactly arm64/x86_64: $path',
          exitCode: builderUsageExitCode,
        );
      }
      await _validateDependencies(File(fullPath), path);
    }
    final Object? resourcesValue = decoded['resourceFiles'];
    if (resourcesValue is! List<Object?>) {
      throw const RuntimeBuilderException(
        'input build manifest has no resource inventory',
        exitCode: builderUsageExitCode,
      );
    }
    final Set<String> resourcePaths = <String>{};
    previous = '';
    for (final Object? value in resourcesValue) {
      if (value is! Map<String, Object?> ||
          value.length != 3 ||
          value['path'] is! String ||
          value['bytes'] is! int ||
          value['sha256'] is! String) {
        throw const RuntimeBuilderException(
          'input resource evidence is malformed',
          exitCode: builderUsageExitCode,
        );
      }
      final String path = value['path']! as String;
      final int bytes = value['bytes']! as int;
      final String hash = value['sha256']! as String;
      if (!_safeRelativePath(path) ||
          path.compareTo(previous) <= 0 ||
          !resourcePaths.add(path) ||
          inventory[path]?.type != FileSystemEntityType.file ||
          inventory[path]!.bytes != bytes ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
          await _hashFile(File(_join(root.path, path))) != hash) {
        throw RuntimeBuilderException(
          'input resource evidence differs from bundle bytes: $path',
          exitCode: builderUsageExitCode,
        );
      }
      previous = path;
    }
    final Set<String> actualResourcePaths = inventory.entries
        .where(
          (MapEntry<String, _BundleEntry> entry) =>
              entry.value.type == FileSystemEntityType.file &&
              !codePaths.contains(entry.key) &&
              entry.key != manifestPath &&
              !entry.key.startsWith('Contents/_CodeSignature/'),
        )
        .map((MapEntry<String, _BundleEntry> entry) => entry.key)
        .toSet();
    if (!_sameStrings(resourcePaths, actualResourcePaths)) {
      throw const RuntimeBuilderException(
        'input resource evidence does not own the exact neutral inventory',
        exitCode: builderUsageExitCode,
      );
    }
    for (final MapEntry<String, _BundleEntry> entry in inventory.entries) {
      if (entry.value.type != FileSystemEntityType.file ||
          codePaths.contains(entry.key) ||
          entry.key == manifestPath ||
          entry.key.startsWith('Contents/_CodeSignature/')) {
        continue;
      }
      if (entry.value.permissions & 0x49 != 0) {
        throw RuntimeBuilderException(
          'undeclared executable entry in source: ${entry.key}',
          exitCode: builderUsageExitCode,
        );
      }
      final String description = await _runCaptured(
        'source resource type validation (${entry.key})',
        '/usr/bin/file',
        <String>['-b', _join(root.path, entry.key)],
      );
      if (description.contains('Mach-O')) {
        throw RuntimeBuilderException(
          'undeclared Mach-O entry in source: ${entry.key}',
          exitCode: builderUsageExitCode,
        );
      }
    }
    return _SourceBundle(
      bundleIdentifier: bundleIdentifier,
      executable: executable,
      codePaths: Set<String>.unmodifiable(codePaths),
      inventory: inventory,
      manifestHash: await _hashFile(manifestFile),
    );
  }

  Future<Map<String, _BundleEntry>> _scanBundle(Directory root) async {
    final Map<String, _BundleEntry> inventory = <String, _BundleEntry>{};
    final Set<String> folded = <String>{};
    await for (final FileSystemEntity entity in root.list(
      recursive: true,
      followLinks: false,
    )) {
      final String relative = entity.path.substring(root.path.length + 1);
      final FileSystemEntityType type = await FileSystemEntity.type(
        entity.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link ||
          (type != FileSystemEntityType.file &&
              type != FileSystemEntityType.directory) ||
          !_safeRelativePath(relative) ||
          !folded.add(relative.toLowerCase())) {
        throw RuntimeBuilderException(
          'application bundle contains an unsafe entry: $relative',
          exitCode: builderUsageExitCode,
        );
      }
      final FileStat stat = await entity.stat();
      inventory[relative] = _BundleEntry(
        type: type,
        permissions: stat.mode & 0x1ff,
        bytes: type == FileSystemEntityType.file ? stat.size : 0,
      );
    }
    return inventory;
  }

  Future<void> _copyBundle(Directory source, Directory destination) async {
    final Map<String, _BundleEntry> inventory = await _scanBundle(source);
    final List<String> directories =
        inventory.entries
            .where(
              (MapEntry<String, _BundleEntry> e) =>
                  e.value.type == FileSystemEntityType.directory,
            )
            .map((MapEntry<String, _BundleEntry> e) => e.key)
            .toList()
          ..sort(_pathDepthOrder);
    await destination.create();
    for (final String path in directories) {
      await Directory(_join(destination.path, path)).create(recursive: true);
    }
    final List<String> files =
        inventory.entries
            .where(
              (MapEntry<String, _BundleEntry> e) =>
                  e.value.type == FileSystemEntityType.file,
            )
            .map((MapEntry<String, _BundleEntry> e) => e.key)
            .toList()
          ..sort();
    for (final String path in files) {
      final File outputFile = File(_join(destination.path, path));
      await outputFile.parent.create(recursive: true);
      await File(_join(source.path, path)).copy(outputFile.path);
      await _runChecked('copied file permission update', '/bin/chmod', <String>[
        inventory[path]!.permissions.toRadixString(8).padLeft(3, '0'),
        outputFile.path,
      ]);
    }
  }

  Future<void> _validateIdentityAvailable(String identity) async {
    final String identities = await _runCombined(
      'Developer ID identity lookup',
      '/usr/bin/security',
      const <String>['find-identity', '-v', '-p', 'codesigning'],
    );
    if (!identities.contains(identity)) {
      throw const RuntimeBuilderException(
        'requested signing identity is not available',
        exitCode: builderUnavailableExitCode,
      );
    }
  }

  Future<void> _signAndVerify(
    Directory application,
    _SourceBundle bundle,
    DistributionPublisherOptions options,
    File entitlements,
    String expectedEntitlementsJson,
    Directory staging,
  ) async {
    final List<String> signingOrder = bundle.codePaths.toList()..sort();
    for (final String path in signingOrder) {
      await _runChecked(
        'Developer ID signing ($path)',
        '/usr/bin/codesign',
        <String>[
          '--force',
          '--sign',
          options.signingIdentity!,
          '--options',
          'runtime',
          '--timestamp',
          _join(application.path, path),
        ],
      );
    }
    await _runChecked(
      'outer Developer ID signing',
      '/usr/bin/codesign',
      <String>[
        '--force',
        '--sign',
        options.signingIdentity!,
        '--options',
        'runtime',
        '--timestamp',
        '--entitlements',
        entitlements.path,
        application.path,
      ],
    );

    final String requirement =
        'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
        'and certificate leaf[subject.OU] = "${options.teamIdentifier}"';
    await _runChecked(
      'Developer ID requirement validation',
      '/usr/bin/codesign',
      <String>[
        '--verify',
        '--deep',
        '--strict',
        '-R=$requirement',
        application.path,
      ],
    );
    for (final String path in <String>[
      for (final String codePath in signingOrder)
        _join(application.path, codePath),
      application.path,
    ]) {
      final String details = await _runCombined(
        'Developer ID signature inspection',
        '/usr/bin/codesign',
        <String>['--display', '--verbose=4', path],
      );
      if (details.contains('Signature=adhoc') ||
          !details.contains('TeamIdentifier=${options.teamIdentifier}') ||
          !details.contains('Authority=Developer ID Application:') ||
          !RegExp(r'flags=.*\bruntime\b').hasMatch(details) ||
          !RegExp(r'^Timestamp=.+$', multiLine: true).hasMatch(details)) {
        throw const RuntimeBuilderException(
          'signed code lacks the required Developer ID runtime metadata',
          exitCode: builderSoftwareExitCode,
        );
      }
    }
    final BuilderCommandResult extracted = await _execute(
      '/usr/bin/codesign',
      <String>['--display', '--entitlements', '-', '--xml', application.path],
    );
    if (extracted.exitCode != 0 || extracted.stdoutText.trim().isEmpty) {
      throw const RuntimeBuilderException(
        'could not extract signed application entitlements',
        exitCode: builderSoftwareExitCode,
      );
    }
    final File extractedFile = File(
      _join(staging.path, '.signed-entitlements.plist'),
    );
    await extractedFile.writeAsString(extracted.stdoutText, flush: true);
    final String signedEntitlementsJson = await _canonicalPlist(extractedFile);
    if (signedEntitlementsJson != expectedEntitlementsJson) {
      throw const RuntimeBuilderException(
        'signed application entitlements differ from the reviewed input',
        exitCode: builderSoftwareExitCode,
      );
    }
    await extractedFile.delete();
  }

  Future<String> _submit(File archive, String profile) async {
    final String raw = await _runCaptured(
      'notary submission',
      '/usr/bin/xcrun',
      <String>[
        'notarytool',
        'submit',
        archive.path,
        '--keychain-profile',
        profile,
        '--output-format',
        'json',
        '--no-progress',
      ],
    );
    final Map<String, Object?> response = _jsonObject(raw, 'notary submission');
    final Object? id = response['id'];
    final Object? status = response['status'];
    final bool currentUploadEvidence =
        status == null &&
        const <String>{
          'Successfully uploaded file',
          'Successfully uploaded file.',
        }.contains(response['message']) &&
        response['path'] == archive.path;
    final bool legacyStatusEvidence = const <String>{
      'Uploaded',
      'Submitted',
      'In Progress',
      'Accepted',
    }.contains(status);
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        (!currentUploadEvidence && !legacyStatusEvidence)) {
      throw const RuntimeBuilderException(
        'notary submission returned invalid evidence',
        exitCode: builderSoftwareExitCode,
      );
    }
    return id.toLowerCase();
  }

  Future<void> _waitForAcceptance(
    String id,
    String profile,
    int timeoutSeconds,
  ) async {
    final String raw = await _runCaptured(
      'notary acceptance wait',
      '/usr/bin/xcrun',
      <String>[
        'notarytool',
        'wait',
        id,
        '--keychain-profile',
        profile,
        '--output-format',
        'json',
        '--no-progress',
        '--timeout',
        '${timeoutSeconds}s',
      ],
    );
    final Map<String, Object?> response = _jsonObject(
      raw,
      'notary acceptance wait',
    );
    if (response['id']?.toString().toLowerCase() != id ||
        response['status'] != 'Accepted') {
      throw RuntimeBuilderException(
        'notary service did not accept submission $id',
        exitCode: builderSoftwareExitCode,
      );
    }
  }

  Future<_NotaryLogSummary> _reviewNotaryLog(
    String id,
    String profile,
    Directory staging,
  ) async {
    final File log = File(_join(staging.path, '.notary-log.json'));
    await _runChecked('notary log retrieval', '/usr/bin/xcrun', <String>[
      'notarytool',
      'log',
      id,
      log.path,
      '--keychain-profile',
      profile,
    ]);
    if (!await log.exists() || await log.length() == 0) {
      throw const RuntimeBuilderException(
        'notary log was not created',
        exitCode: builderSoftwareExitCode,
      );
    }
    if (await log.length() > 1024 * 1024) {
      throw const RuntimeBuilderException(
        'notary log exceeds the bounded review limit',
        exitCode: builderSoftwareExitCode,
      );
    }
    final Map<String, Object?> value = _jsonObject(
      await log.readAsString(),
      'notary log',
    );
    final Object? jobId = value['jobId'];
    final Object? status = value['status'];
    final Object? formatVersion = value['logFormatVersion'];
    final Object? issues = value['issues'];
    if (jobId is! String ||
        jobId.toLowerCase() != id ||
        status != 'Accepted' ||
        formatVersion is! int ||
        issues is! List<Object?>) {
      throw const RuntimeBuilderException(
        'notary log does not match the accepted submission',
        exitCode: builderSoftwareExitCode,
      );
    }
    if (issues.isNotEmpty) {
      throw RuntimeBuilderException(
        'notary log contains ${issues.length} issue(s)',
        exitCode: builderSoftwareExitCode,
      );
    }
    await log.delete();
    return _NotaryLogSummary(
      formatVersion: formatVersion,
      issueCount: issues.length,
    );
  }

  Map<String, Object?> _jsonObject(String value, String label) {
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is Map<String, Object?>) return decoded;
    } on Object {
      // Report the bounded classification below without echoing service data.
    }
    throw RuntimeBuilderException(
      '$label returned invalid JSON',
      exitCode: builderSoftwareExitCode,
    );
  }

  Future<void> _archive(Directory application, File archive) async {
    await _runChecked(
      'application archive creation',
      '/usr/bin/ditto',
      <String>[
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        application.path,
        archive.path,
      ],
    );
    if (!await archive.exists() || await archive.length() == 0) {
      throw const RuntimeBuilderException(
        'archive tool did not create a non-empty archive',
        exitCode: builderSoftwareExitCode,
      );
    }
  }

  Future<String> _canonicalPlist(File file) async {
    final String value = await _runCaptured(
      'property-list canonicalization',
      '/usr/bin/plutil',
      <String>['-convert', 'json', '-o', '-', file.path],
    );
    try {
      final Object? decoded = jsonDecode(value);
      return jsonEncode(_canonicalJson(decoded));
    } on Object {
      throw const RuntimeBuilderException(
        'property-list conversion returned invalid JSON',
        exitCode: builderUsageExitCode,
      );
    }
  }

  Object? _canonicalJson(Object? value) {
    if (value is Map<String, Object?>) {
      final List<String> keys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final String key in keys) key: _canonicalJson(value[key]),
      };
    }
    if (value is List<Object?>) {
      return <Object?>[for (final Object? item in value) _canonicalJson(item)];
    }
    return value;
  }

  Future<void> _validateDependencies(File image, String relativePath) async {
    final String output = await _runCaptured(
      'Mach-O dependency validation ($relativePath)',
      '/usr/bin/otool',
      <String>['-L', image.path],
    );
    for (final String line in const LineSplitter().convert(output)) {
      if (!line.startsWith(' ') && !line.startsWith('\t')) continue;
      final String dependency = line.trim().split(' (').first;
      if (dependency.startsWith('/') &&
          !dependency.startsWith('/System/') &&
          !dependency.startsWith('/usr/lib/')) {
        throw RuntimeBuilderException(
          'code entry has an absolute non-system dependency: $relativePath',
          exitCode: builderSoftwareExitCode,
        );
      }
    }
  }

  Future<void> _publish(Directory staging, Directory outputDirectory) async {
    if (!await outputDirectory.exists()) {
      await staging.rename(outputDirectory.path);
      return;
    }
    final Directory backup = await outputDirectory.parent.createTemp(
      '.${_basename(outputDirectory.path)}.previous-',
    );
    await backup.delete();
    await outputDirectory.rename(backup.path);
    try {
      await staging.rename(outputDirectory.path);
    } on Object {
      await backup.rename(outputDirectory.path);
      rethrow;
    }
    try {
      await backup.delete(recursive: true);
    } on FileSystemException {
      // A verified publication remains safer than deleting it for cleanup.
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
    final BuilderCommandResult result = await _execute(executable, arguments);
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
    final BuilderCommandResult result = await _execute(executable, arguments);
    if (result.exitCode != 0) {
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

  Future<String> _runCombined(
    String label,
    String executable,
    List<String> arguments,
  ) async {
    final BuilderCommandResult result = await _execute(executable, arguments);
    if (result.exitCode != 0) {
      throw RuntimeBuilderException(
        '$label failed with exit code ${result.exitCode}',
        exitCode: result.exitCode,
      );
    }
    final String value = '${result.stdoutText}\n${result.stderrText}'.trim();
    if (value.isEmpty) {
      throw RuntimeBuilderException(
        '$label returned no output',
        exitCode: builderSoftwareExitCode,
      );
    }
    return value;
  }

  Future<BuilderCommandResult> _execute(
    String executable,
    List<String> arguments,
  ) => processExecutor.run(
    executable,
    arguments,
    workingDirectory: currentDirectory,
  );

  String _resolvePath(String value) {
    final Uri uri = Uri.file(value);
    return uri.isAbsolute
        ? File.fromUri(uri).path
        : Directory(currentDirectory).absolute.uri.resolveUri(uri).toFilePath();
  }
}

final class _SourceBundle {
  const _SourceBundle({
    required this.bundleIdentifier,
    required this.executable,
    required this.codePaths,
    required this.inventory,
    required this.manifestHash,
  });

  final String bundleIdentifier;
  final String executable;
  final Set<String> codePaths;
  final Map<String, _BundleEntry> inventory;
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

final class _NotaryLogSummary {
  const _NotaryLogSummary({
    required this.formatVersion,
    required this.issueCount,
  });

  final int formatVersion;
  final int issueCount;
}

String _requiredString(Map<String, Object?> source, String key) {
  final Object? value = source[key];
  if (value is! String || value.isEmpty) {
    throw RuntimeBuilderException(
      'input build manifest has no valid $key',
      exitCode: builderUsageExitCode,
    );
  }
  return value;
}

bool _safeRelativePath(String value) {
  if (value.isEmpty || value.startsWith('/') || value.contains('\\')) {
    return false;
  }
  return value
      .split('/')
      .every(
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

Future<int> runDistributionPublisherCommand(
  List<String> arguments, {
  DistributionPublisher? publisher,
  BuilderOutput? output,
  BuilderOutput? errorOutput,
}) async {
  final BuilderOutput writeOutput = output ?? stdout.write;
  final BuilderOutput writeError = errorOutput ?? stderr.write;
  try {
    final DistributionPublisherOptions options =
        DistributionPublisherOptions.parse(arguments);
    if (options.showHelp) {
      writeOutput(distributionPublisherUsage);
      return 0;
    }
    final DistributionPublisher active =
        publisher ??
        DistributionPublisher(
          currentDirectory: Directory.current.path,
          output: writeOutput,
          errorOutput: writeError,
        );
    return await active.run(options);
  } on RuntimeBuilderException catch (error) {
    writeError('dart_macos_runtime:distribute: ${error.message}\n');
    if (error.exitCode == builderUsageExitCode) {
      writeError(distributionPublisherUsage);
    }
    return error.exitCode;
  } on Object catch (error, stackTrace) {
    writeError(
      'dart_macos_runtime:distribute: unexpected failure: '
      '$error\n$stackTrace\n',
    );
    return builderSoftwareExitCode;
  }
}
