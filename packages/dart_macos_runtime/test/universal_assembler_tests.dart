import 'dart:convert';
import 'dart:io';

import 'package:dart_macos_runtime/src/tool/builder.dart';
import 'package:dart_macos_runtime/src/tool/universal_assembler.dart';

var _failures = 0;

Future<void> _test(String name, Future<void> Function() body) async {
  try {
    await body();
    stdout.writeln('PASS $name');
  } on Object catch (error, stackTrace) {
    ++_failures;
    stderr.writeln('FAIL $name: $error\n$stackTrace');
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<T> _expectThrows<T extends Object>(Future<void> Function() body) async {
  try {
    await body();
  } on T catch (error) {
    return error;
  }
  throw StateError('expected $T');
}

final class _Command {
  const _Command(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

final class _FakeExecutor implements BuilderProcessExecutor {
  final List<_Command> commands = <_Command>[];
  bool failMerge = false;
  bool failSigning = false;
  bool failThinVerification = false;
  bool wrongMergedArchitectures = false;
  String? wrongThinPathFragment;
  bool absoluteDependency = false;

  @override
  Future<BuilderCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool inheritStdio = false,
  }) async {
    commands.add(_Command(executable, List<String>.from(arguments)));
    if (executable == '/usr/bin/lipo') {
      if (arguments.first == '-create') {
        if (failMerge) return const BuilderCommandResult(exitCode: 9);
        final String output = arguments[arguments.indexOf('-output') + 1];
        final List<int> bytes = <int>[
          ...await File(arguments[1]).readAsBytes(),
          ...await File(arguments[2]).readAsBytes(),
        ];
        await File(output).writeAsBytes(bytes, flush: true);
        return const BuilderCommandResult(exitCode: 0);
      }
      final String path = arguments.last;
      if (wrongThinPathFragment != null &&
          path.contains(wrongThinPathFragment!)) {
        return const BuilderCommandResult(exitCode: 0, stdoutText: 'arm64\n');
      }
      if (path.contains('/arm64.app/')) {
        return const BuilderCommandResult(exitCode: 0, stdoutText: 'arm64\n');
      }
      if (path.contains('/x86_64.app/')) {
        return const BuilderCommandResult(exitCode: 0, stdoutText: 'x86_64\n');
      }
      return BuilderCommandResult(
        exitCode: 0,
        stdoutText: wrongMergedArchitectures ? 'arm64\n' : 'x86_64 arm64\n',
      );
    }
    if (executable == '/usr/bin/file') {
      final String contents = await File(arguments.last).readAsString();
      return BuilderCommandResult(
        exitCode: 0,
        stdoutText: contents.contains('UNDECLARED_MACHO')
            ? 'Mach-O 64-bit dynamically linked shared library\n'
            : 'ASCII text\n',
      );
    }
    if (executable == '/usr/bin/shasum') {
      final List<int> bytes = await File(arguments.last).readAsBytes();
      var value = 0;
      for (final int byte in bytes) {
        value = ((value * 33) ^ byte) & 0xffffffff;
      }
      final String seed = value.toRadixString(16).padLeft(8, '0');
      return BuilderCommandResult(
        exitCode: 0,
        stdoutText: '${seed * 8}  ${arguments.last}\n',
      );
    }
    if (executable == '/usr/bin/otool') {
      final String dependency = absoluteDependency
          ? '/private/build/libbad.dylib'
          : '@rpath/libshared.dylib';
      return BuilderCommandResult(
        exitCode: 0,
        stdoutText:
            '${arguments.last} (architecture x86_64):\n'
            '\t$dependency (compatibility version 1.0.0, current version 1.0.0)\n'
            '${arguments.last} (architecture arm64):\n'
            '\t$dependency (compatibility version 1.0.0, current version 1.0.0)\n',
      );
    }
    if (executable == '/usr/bin/codesign') {
      if (failThinVerification &&
          arguments.contains('--verify') &&
          arguments.last.contains('/arm64.app')) {
        return const BuilderCommandResult(exitCode: 12);
      }
      if (failSigning && arguments.contains('--sign')) {
        return const BuilderCommandResult(exitCode: 11);
      }
    }
    return const BuilderCommandResult(exitCode: 0, stdoutText: 'OK\n');
  }
}

final class _Fixture {
  _Fixture(this.root, this.arm64, this.x86_64);

  static Future<_Fixture> create() async {
    final Directory root = await Directory.systemTemp.createTemp(
      'universal-assembler-test-',
    );
    final Directory arm64 = Directory('${root.path}/arm64.app');
    final Directory x86_64 = Directory('${root.path}/x86_64.app');
    await _writeThin(arm64, 'arm64');
    await _writeThin(x86_64, 'x86_64');
    return _Fixture(root, arm64, x86_64);
  }

  final Directory root;
  final Directory arm64;
  final Directory x86_64;

  String get outputPath => '${root.path}/Combined.app';

  UniversalApplicationAssembler assembler(_FakeExecutor executor) =>
      UniversalApplicationAssembler(
        currentDirectory: root.path,
        processExecutor: executor,
        output: (_) {},
        errorOutput: (_) {},
      );

  UniversalAssemblerOptions options({bool reverse = false}) =>
      UniversalAssemblerOptions.parse(<String>[
        '--input-app=${reverse ? x86_64.path : arm64.path}',
        '--input-app=${reverse ? arm64.path : x86_64.path}',
        '--output-app=$outputPath',
      ]);

  Future<void> dispose() => root.delete(recursive: true);
}

const List<String> _codePaths = <String>[
  'Contents/MacOS/example',
  'Contents/Resources/application.aot',
  'Contents/Frameworks/libengine.dylib',
  'Contents/Helpers/example_worker',
  'Contents/Resources/DartHelpers/example_worker.aot',
  'Contents/Frameworks/libasset.dylib',
  'Contents/Frameworks/libcapability.dylib',
  'Contents/Frameworks/libintents.dylib',
];

Future<void> _writeThin(Directory root, String architecture) async {
  for (final String path in _codePaths) {
    await _write(
      '${root.path}/$path',
      'CODE architecture=$architecture path=$path\n',
    );
  }
  await _write('${root.path}/Contents/Info.plist', '<plist/>\n');
  await _write(
    '${root.path}/Contents/Resources/DART_SDK_LICENSE.txt',
    'license\n',
  );
  await _write(
    '${root.path}/Contents/Resources/en.lproj/Localizable.strings',
    '"key" = "value";\n',
  );
  await _write('${root.path}/Contents/Resources/Test.icns', 'icon\n');
  await _write(
    '${root.path}/Contents/Resources/Metadata.appintents/version.json',
    '{"version":"1"}\n',
  );
  await _write(
    '${root.path}/Contents/Resources/Metadata.appintents/extract.actionsdata',
    'metadata\n',
  );
  await _write(
    '${root.path}/Contents/_CodeSignature/CodeResources',
    'signature-$architecture\n',
  );
  final Map<String, Object?> manifest = <String, Object?>{
    'schemaVersion': 1,
    'runtimeMode': 'release-aot',
    'architecture': architecture,
    'bundleIdentifier': 'dev.example.application',
    'executable': 'example',
    'payload': 'application.aot',
    'engine': 'libengine.dylib',
    'dartSdkVersion': '3.13.2',
    'dartSdkRevision': 'revision',
    'runner': <String, Object?>{'activationPolicy': 'regular'},
    'icon': <String, Object?>{
      'source': 'resources/Test.icns',
      'bundleName': 'Test.icns',
      'bytes': 5,
    },
    'appIntents': <String, Object?>{
      'package': 'example_intents',
      'source': 'native/Intents.swift',
      'moduleName': 'ExampleIntents',
      'library': 'libintents.dylib',
      'sourceBytes': 10,
      'libraryBytes': architecture == 'arm64' ? 101 : 202,
      'targetTriple': '$architecture-apple-macos14.0',
      'xcodeBuildVersion': '17A1',
      'metadataBundle': 'Metadata.appintents',
      'metadataFiles': <Object?>[],
    },
    'dartHelpers': <Object?>[
      <String, Object?>{
        'name': 'example_worker',
        'entrypoint': 'bin/worker.dart',
        'payload': 'DartHelpers/example_worker.aot',
      },
    ],
    'resources': <Object?>['en.lproj/Localizable.strings'],
    'nativeAssets': <Object?>[
      <String, Object?>{
        'id': 'asset',
        'package': 'example_asset',
        'library': 'libasset.dylib',
        'abiVersion': 1,
        'abiVersionSymbol': 'example_asset_abi_version',
      },
    ],
    'nativeCapabilities': <Object?>[
      <String, Object?>{
        'id': 'capability',
        'package': 'example_capability',
        'library': 'libcapability.dylib',
        'abiVersion': 1,
        'abiVersionSymbol': 'example_capability_abi_version',
        'initializerSymbol': 'example_capability_initialize',
      },
    ],
  };
  await _write(
    '${root.path}/Contents/Resources/runtime-build-manifest.json',
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}

Future<void> _write(String path, String contents) async {
  final File file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(contents, flush: true);
}

Future<void> _writeExistingOutput(_Fixture fixture) async {
  await _write('${fixture.outputPath}/sentinel.txt', 'last-good\n');
}

Future<void> _expectOutputPreserved(_Fixture fixture) async {
  _expect(
    await File('${fixture.outputPath}/sentinel.txt').readAsString() ==
        'last-good\n',
    'failed assembly must preserve the existing output',
  );
}

Future<void> main() async {
  await _test('option parsing and usage boundaries', () async {
    final UniversalAssemblerOptions options = UniversalAssemblerOptions.parse(
      const <String>['--help'],
    );
    _expect(options.showHelp, 'help is selected');
    await _expectThrows<RuntimeBuilderException>(
      () async => UniversalAssemblerOptions.parse(const <String>[]),
    );
    await _expectThrows<RuntimeBuilderException>(
      () async => UniversalAssemblerOptions.parse(const <String>[
        '--input-app=a.app',
        '--input-app=b.app',
        '--output-app=first.app',
        '--output-app=second.app',
      ]),
    );
  });

  await _test(
    'both thin orders publish deterministic Universal evidence',
    () async {
      final _Fixture first = await _Fixture.create();
      final _Fixture second = await _Fixture.create();
      try {
        final _FakeExecutor firstExecutor = _FakeExecutor();
        final _FakeExecutor secondExecutor = _FakeExecutor();
        _expect(
          await first.assembler(firstExecutor).run(first.options()) == 0,
          'forward assembly succeeds',
        );
        _expect(
          await second
                  .assembler(secondExecutor)
                  .run(second.options(reverse: true)) ==
              0,
          'reverse assembly succeeds',
        );
        final String firstEvidence = await File(
          '${first.outputPath}/Contents/Resources/runtime-build-manifest.json',
        ).readAsString();
        final String secondEvidence = await File(
          '${second.outputPath}/Contents/Resources/runtime-build-manifest.json',
        ).readAsString();
        _expect(
          firstEvidence == secondEvidence,
          'evidence bytes are deterministic',
        );
        final Map<String, Object?> decoded =
            jsonDecode(firstEvidence) as Map<String, Object?>;
        _expect(
          decoded['schemaVersion'] == 2 &&
              jsonEncode(decoded['architectures']) ==
                  jsonEncode(<String>['arm64', 'x86_64']) &&
              (decoded['icon']! as Map<String, Object?>)['bundleName'] ==
                  'Test.icns' &&
              (decoded['nativeCapabilities']! as List<Object?>).length == 1 &&
              (decoded['dartHelpers']! as List<Object?>).length == 1 &&
              (decoded['codePaths']! as List<Object?>).length ==
                  _codePaths.length,
          'evidence records the exact architecture, runtime, and code contract',
        );
        final List<Object?> resourceFiles =
            decoded['resourceFiles']! as List<Object?>;
        _expect(
          await File('${first.outputPath}/Contents/Resources/Test.icns')
                      .readAsString() ==
                  'icon\n' &&
              resourceFiles.cast<Map<String, Object?>>().any(
                (Map<String, Object?> value) =>
                    value['path'] == 'Contents/Resources/Test.icns' &&
                    value['bytes'] == 5,
              ),
          'application icon remains an evidenced neutral resource',
        );
        _expect(
          firstExecutor.commands
                  .where(
                    (_Command command) =>
                        command.executable == '/usr/bin/lipo' &&
                        command.arguments.first == '-create',
                  )
                  .length ==
              _codePaths.length,
          'every declared code entry is merged',
        );
      } finally {
        await first.dispose();
        await second.dispose();
      }
    },
  );

  await _test(
    'successful publication atomically replaces an old output',
    () async {
      final _Fixture fixture = await _Fixture.create();
      try {
        await _writeExistingOutput(fixture);
        await fixture.assembler(_FakeExecutor()).run(fixture.options());
        _expect(
          !await File('${fixture.outputPath}/sentinel.txt').exists() &&
              await File('${fixture.outputPath}/Contents/MacOS/example')
                  .exists(),
          'verified output replaces the old directory only at publication',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );

  await _test(
    'input, output, and path containment boundaries fail closed',
    () async {
      final _Fixture fixture = await _Fixture.create();
      try {
        final UniversalApplicationAssembler assembler = fixture.assembler(
          _FakeExecutor(),
        );
        await _expectThrows<RuntimeBuilderException>(
          () => assembler.run(
            UniversalAssemblerOptions.parse(<String>[
              '--input-app=${fixture.arm64.path}',
              '--input-app=${fixture.arm64.path}',
              '--output-app=${fixture.outputPath}',
            ]),
          ),
        );
        await _expectThrows<RuntimeBuilderException>(
          () => assembler.run(
            UniversalAssemblerOptions.parse(<String>[
              '--input-app=${fixture.arm64.path}',
              '--input-app=${fixture.x86_64.path}',
              '--output-app=${fixture.arm64.path}/Nested.app',
            ]),
          ),
        );
        final Directory linkedTarget = Directory('${fixture.root.path}/target')
          ..createSync();
        await Link(fixture.outputPath).create(linkedTarget.path);
        await _expectThrows<RuntimeBuilderException>(
          () => assembler.run(fixture.options()),
        );
      } finally {
        await fixture.dispose();
      }
    },
  );

  await _test('unsafe helper payload declarations fail closed', () async {
    final _Fixture fixture = await _Fixture.create();
    try {
      for (final Directory input in <Directory>[
        fixture.arm64,
        fixture.x86_64,
      ]) {
        final File manifest = File(
          '${input.path}/Contents/Resources/runtime-build-manifest.json',
        );
        final Map<String, Object?> decoded =
            jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
        final Map<String, Object?> helper =
            (decoded['dartHelpers']! as List<Object?>).single
                as Map<String, Object?>;
        helper['payload'] = '../outside.aot';
        await manifest.writeAsString(jsonEncode(decoded));
      }
      await _expectThrows<RuntimeBuilderException>(
        () => fixture.assembler(_FakeExecutor()).run(fixture.options()),
      );
    } finally {
      await fixture.dispose();
    }
  });

  await _test('resource, plist, and manifest drift fail closed', () async {
    for (final String path in <String>[
      'Contents/Resources/DART_SDK_LICENSE.txt',
      'Contents/Info.plist',
      'Contents/Resources/runtime-build-manifest.json',
    ]) {
      final _Fixture fixture = await _Fixture.create();
      try {
        await _writeExistingOutput(fixture);
        final File changed = File('${fixture.x86_64.path}/$path');
        if (path.endsWith('.json')) {
          final Map<String, Object?> manifest =
              jsonDecode(await changed.readAsString()) as Map<String, Object?>;
          manifest['bundleIdentifier'] = 'dev.example.different';
          await changed.writeAsString(jsonEncode(manifest));
        } else {
          await changed.writeAsString('different bytes\n');
        }
        await _expectThrows<RuntimeBuilderException>(
          () => fixture.assembler(_FakeExecutor()).run(fixture.options()),
        );
        await _expectOutputPreserved(fixture);
      } finally {
        await fixture.dispose();
      }
    }
  });

  await _test('missing and extra inventory entries fail closed', () async {
    final _Fixture missing = await _Fixture.create();
    final _Fixture extra = await _Fixture.create();
    try {
      await _writeExistingOutput(missing);
      await File(
        '${missing.x86_64.path}/Contents/Resources/DART_SDK_LICENSE.txt',
      ).delete();
      await _expectThrows<RuntimeBuilderException>(
        () => missing.assembler(_FakeExecutor()).run(missing.options()),
      );
      await _expectOutputPreserved(missing);

      await _writeExistingOutput(extra);
      await _write(
        '${extra.x86_64.path}/Contents/Resources/extra.txt',
        'extra\n',
      );
      await _expectThrows<RuntimeBuilderException>(
        () => extra.assembler(_FakeExecutor()).run(extra.options()),
      );
      await _expectOutputPreserved(extra);
    } finally {
      await missing.dispose();
      await extra.dispose();
    }
  });

  await _test('symlinks and undeclared Mach-O entries fail closed', () async {
    final _Fixture linked = await _Fixture.create();
    final _Fixture undeclared = await _Fixture.create();
    try {
      await _writeExistingOutput(linked);
      await Link('${linked.arm64.path}/Contents/Resources/link')
          .create('DART_SDK_LICENSE.txt');
      await _expectThrows<RuntimeBuilderException>(
        () => linked.assembler(_FakeExecutor()).run(linked.options()),
      );
      await _expectOutputPreserved(linked);

      await _writeExistingOutput(undeclared);
      for (final Directory root in <Directory>[
        undeclared.arm64,
        undeclared.x86_64,
      ]) {
        await _write(
          '${root.path}/Contents/Resources/undeclared.bin',
          'UNDECLARED_MACHO\n',
        );
      }
      await _expectThrows<RuntimeBuilderException>(
        () => undeclared.assembler(_FakeExecutor()).run(undeclared.options()),
      );
      await _expectOutputPreserved(undeclared);
    } finally {
      await linked.dispose();
      await undeclared.dispose();
    }
  });

  await _test('wrong thin or merged architectures fail closed', () async {
    final _Fixture thin = await _Fixture.create();
    final _Fixture merged = await _Fixture.create();
    try {
      await _writeExistingOutput(thin);
      final _FakeExecutor thinExecutor = _FakeExecutor()
        ..wrongThinPathFragment = '/x86_64.app/';
      await _expectThrows<RuntimeBuilderException>(
        () => thin.assembler(thinExecutor).run(thin.options()),
      );
      await _expectOutputPreserved(thin);

      await _writeExistingOutput(merged);
      final _FakeExecutor mergedExecutor = _FakeExecutor()
        ..wrongMergedArchitectures = true;
      await _expectThrows<RuntimeBuilderException>(
        () => merged.assembler(mergedExecutor).run(merged.options()),
      );
      await _expectOutputPreserved(merged);
    } finally {
      await thin.dispose();
      await merged.dispose();
    }
  });

  await _test(
    'merge, dependency, and signing faults preserve last good output',
    () async {
      for (final _FakeExecutor executor in <_FakeExecutor>[
        _FakeExecutor()..failThinVerification = true,
        _FakeExecutor()..failMerge = true,
        _FakeExecutor()..absoluteDependency = true,
        _FakeExecutor()..failSigning = true,
      ]) {
        final _Fixture fixture = await _Fixture.create();
        try {
          await _writeExistingOutput(fixture);
          await _expectThrows<RuntimeBuilderException>(
            () => fixture.assembler(executor).run(fixture.options()),
          );
          await _expectOutputPreserved(fixture);
        } finally {
          await fixture.dispose();
        }
      }
    },
  );

  if (_failures != 0) {
    stderr.writeln('$_failures Universal assembler test(s) failed');
    exitCode = 1;
  }
}
