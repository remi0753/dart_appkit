import 'dart:convert';
import 'dart:io';

import 'package:dart_macos_runtime/src/tool/builder.dart';
import 'package:dart_macos_runtime/src/tool/distribution_publisher.dart';

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

const String _identity =
    'Developer ID Application: Example Company (ABCDE12345)';
const String _team = 'ABCDE12345';
const String _profile = 'example-profile';
const String _submissionId = '12345678-1234-1234-1234-123456789abc';

final class _Command {
  const _Command(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

final class _FakeExecutor implements BuilderProcessExecutor {
  final List<_Command> commands = <_Command>[];
  bool sourceAdhoc = true;
  bool identityAvailable = true;
  bool failSigning = false;
  bool wrongTeam = false;
  bool omitRuntime = false;
  bool omitTimestamp = false;
  bool omitDeveloperIdAuthority = false;
  bool wrongArchitectures = false;
  bool entitlementDrift = false;
  bool rejectNotary = false;
  bool malformedNotary = false;
  bool notaryLogIssues = false;
  bool failStapling = false;
  bool failGatekeeper = false;
  bool failFinalArchive = false;
  String entitlementsJson = '{}';
  int archiveCalls = 0;

  @override
  Future<BuilderCommandResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    bool inheritStdio = false,
  }) async {
    commands.add(_Command(executable, List<String>.from(arguments)));
    if (executable == '/usr/bin/codesign') {
      if (arguments.contains('--sign')) {
        return BuilderCommandResult(exitCode: failSigning ? 11 : 0);
      }
      if (arguments.contains('--entitlements')) {
        return const BuilderCommandResult(
          exitCode: 0,
          stdoutText:
              '<?xml version="1.0"?><plist version="1.0"><dict/></plist>\n',
        );
      }
      if (arguments.contains('--display') &&
          arguments.contains('--verbose=4')) {
        final bool source = !arguments.last.contains('distribution-stage');
        if (source) {
          return BuilderCommandResult(
            exitCode: 0,
            stderrText: sourceAdhoc
                ? 'Signature=adhoc\nTeamIdentifier=not set\n'
                : 'Authority=Developer ID Application: Other\n'
                      'TeamIdentifier=$_team\nflags=0x10000(runtime)\n'
                      'Timestamp=Sep 13, 2026\n',
          );
        }
        return BuilderCommandResult(
          exitCode: 0,
          stderrText:
              '${omitDeveloperIdAuthority ? 'Authority=Apple Development: Example' : 'Authority=Developer ID Application: Example Company ($_team)'}\n'
              'TeamIdentifier=${wrongTeam ? 'ZZZZZ99999' : _team}\n'
              'flags=${omitRuntime ? '0x0(none)' : '0x10000(runtime)'}\n'
              '${omitTimestamp ? '' : 'Timestamp=Sep 13, 2026\n'}',
        );
      }
      return const BuilderCommandResult(exitCode: 0);
    }
    if (executable == '/usr/bin/lipo') {
      return BuilderCommandResult(
        exitCode: 0,
        stdoutText: wrongArchitectures ? 'arm64\n' : 'x86_64 arm64\n',
      );
    }
    if (executable == '/usr/bin/otool') {
      return BuilderCommandResult(
        exitCode: 0,
        stdoutText:
            '${arguments.last}:\n'
            '\t@rpath/libengine.dylib (compatibility version 1.0.0, current version 1.0.0)\n',
      );
    }
    if (executable == '/usr/bin/file') {
      return const BuilderCommandResult(
        exitCode: 0,
        stdoutText: 'ASCII text\n',
      );
    }
    if (executable == '/usr/bin/plutil') {
      if (arguments.contains('-extract')) {
        return const BuilderCommandResult(
          exitCode: 0,
          stdoutText: 'dev.example.application\n',
        );
      }
      return BuilderCommandResult(
        exitCode: 0,
        stdoutText:
            entitlementDrift &&
                arguments.last.contains('.signed-entitlements.plist')
            ? '{"unexpected":true}\n'
            : '$entitlementsJson\n',
      );
    }
    if (executable == '/usr/bin/shasum') {
      return BuilderCommandResult(
        exitCode: 0,
        stdoutText:
            '${_hash(await File(arguments.last).readAsBytes())}  ${arguments.last}\n',
      );
    }
    if (executable == '/usr/bin/security') {
      return BuilderCommandResult(
        exitCode: 0,
        stdoutText: identityAvailable
            ? '1) ABC "$_identity"\n'
            : '0 valid identities found\n',
      );
    }
    if (executable == '/usr/bin/ditto') {
      ++archiveCalls;
      if (failFinalArchive && archiveCalls == 2) {
        return const BuilderCommandResult(exitCode: 12);
      }
      await File(arguments.last)
          .writeAsString('archive-$archiveCalls\n', flush: true);
      return const BuilderCommandResult(exitCode: 0);
    }
    if (executable == '/usr/bin/xcrun') {
      if (arguments.take(2).join(' ') == 'notarytool submit') {
        if (malformedNotary) {
          return const BuilderCommandResult(exitCode: 0, stdoutText: 'bad\n');
        }
        return const BuilderCommandResult(
          exitCode: 0,
          stdoutText: '{"id":"$_submissionId","status":"In Progress"}\n',
        );
      }
      if (arguments.take(2).join(' ') == 'notarytool wait') {
        return BuilderCommandResult(
          exitCode: 0,
          stdoutText: jsonEncode(<String, Object?>{
            'id': _submissionId,
            'status': rejectNotary ? 'Invalid' : 'Accepted',
          }),
        );
      }
      if (arguments.take(2).join(' ') == 'notarytool log') {
        await File(arguments[3]).writeAsString(
          jsonEncode(<String, Object?>{
            'jobId': _submissionId.toUpperCase(),
            'status': 'Accepted',
            'logFormatVersion': 1,
            'issues': notaryLogIssues
                ? <Object?>[
                    <String, Object?>{
                      'severity': 'warning',
                      'message': 'review required',
                    },
                  ]
                : const <Object?>[],
          }),
          flush: true,
        );
        return const BuilderCommandResult(exitCode: 0);
      }
      if (arguments.take(2).join(' ') == 'stapler staple' && failStapling) {
        return const BuilderCommandResult(exitCode: 13);
      }
      return const BuilderCommandResult(exitCode: 0);
    }
    if (executable == '/usr/sbin/spctl') {
      return BuilderCommandResult(exitCode: failGatekeeper ? 14 : 0);
    }
    return const BuilderCommandResult(exitCode: 0);
  }
}

final class _Fixture {
  _Fixture(this.root, this.source, this.entitlements);

  static Future<_Fixture> create() async {
    final Directory root = await Directory.systemTemp.createTemp(
      'distribution-publisher-test-',
    );
    final Directory source = Directory('${root.path}/Source.app');
    final File entitlements = File('${root.path}/entitlements.plist');
    await _writeSource(source);
    await entitlements.writeAsString(
      '<?xml version="1.0"?><plist version="1.0"><dict/></plist>\n',
      flush: true,
    );
    return _Fixture(root, source, entitlements);
  }

  final Directory root;
  final Directory source;
  final File entitlements;

  String get outputPath => '${root.path}/Published';

  DistributionPublisher publisher(_FakeExecutor executor) =>
      DistributionPublisher(
        currentDirectory: root.path,
        processExecutor: executor,
        output: (_) {},
        errorOutput: (_) {},
      );

  DistributionPublisherOptions options({bool validateOnly = false}) =>
      DistributionPublisherOptions.parse(<String>[
        '--input-app=${source.path}',
        '--output-directory=$outputPath',
        '--signing-identity=$_identity',
        '--team-id=$_team',
        '--entitlements=${entitlements.path}',
        '--keychain-profile=$_profile',
        '--wait-timeout-seconds=600',
        if (validateOnly) '--validate-only',
      ]);

  Future<void> writeLastGood() async {
    await Directory(outputPath).create();
    await File('$outputPath/sentinel.txt')
        .writeAsString('last-good\n', flush: true);
  }

  Future<void> expectLastGood() async {
    _expect(
      await File('$outputPath/sentinel.txt').readAsString() == 'last-good\n',
      'failure must preserve the last-good output',
    );
  }

  Future<void> dispose() => root.delete(recursive: true);
}

const List<String> _codePaths = <String>[
  'Contents/Frameworks/libengine.dylib',
  'Contents/MacOS/example',
  'Contents/Resources/application.aot',
];

Future<void> _writeSource(Directory root) async {
  for (final String path in _codePaths) {
    await _write('${root.path}/$path', 'CODE $path\n');
  }
  final Map<String, String> resources = <String, String>{
    'Contents/Info.plist': '<plist/>\n',
    'Contents/Resources/DART_SDK_LICENSE.txt': 'license\n',
  };
  for (final MapEntry<String, String> entry in resources.entries) {
    await _write('${root.path}/${entry.key}', entry.value);
  }
  await _write(
    '${root.path}/Contents/_CodeSignature/CodeResources',
    'ad-hoc signature\n',
  );
  final List<String> resourcePaths = resources.keys.toList()..sort();
  final Map<String, Object?> manifest = <String, Object?>{
    'schemaVersion': 2,
    'runtimeMode': 'release-aot',
    'architectures': const <String>['arm64', 'x86_64'],
    'bundleIdentifier': 'dev.example.application',
    'executable': 'example',
    'thinManifests': <String, String>{
      'arm64':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'x86_64':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    },
    'applicationContract': <String, Object?>{
      'runtimeMode': 'release-aot',
      'bundleIdentifier': 'dev.example.application',
      'executable': 'example',
    },
    'codePaths': _codePaths,
    'resourceFiles': <Map<String, Object?>>[
      for (final String path in resourcePaths)
        <String, Object?>{
          'path': path,
          'bytes': utf8.encode(resources[path]!).length,
          'sha256': _hash(utf8.encode(resources[path]!)),
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

String _hash(List<int> bytes) {
  var value = 0;
  for (final int byte in bytes) {
    value = ((value * 33) ^ byte) & 0xffffffff;
  }
  return value.toRadixString(16).padLeft(8, '0') * 8;
}

Future<void> main() async {
  await _test('option parsing and secret-safe boundaries', () async {
    _expect(
      DistributionPublisherOptions.parse(const <String>['--help']).showHelp,
      'help is selected',
    );
    for (final List<String> arguments in <List<String>>[
      const <String>[],
      const <String>['--input-app=a.app', '--input-app=b.app'],
      const <String>[
        '--input-app=a.app',
        '--output-directory=out',
        '--signing-identity=identity',
        '--team-id=lowercase1',
        '--entitlements=e.plist',
        '--keychain-profile=profile',
      ],
      const <String>[
        '--input-app=a.app',
        '--output-directory=out',
        '--signing-identity= identity',
        '--team-id=ABCDE12345',
        '--entitlements=e.plist',
        '--keychain-profile=profile',
      ],
      const <String>[
        '--input-app=a.app',
        '--output-directory=out',
        '--signing-identity=identity',
        '--team-id=ABCDE12345',
        '--entitlements=e.plist',
        '--keychain-profile=profile',
        '--wait-timeout-seconds=30',
      ],
      const <String>['--password=secret'],
      const <String>['--key=/private/key'],
    ]) {
      await _expectThrows<RuntimeBuilderException>(
        () async => DistributionPublisherOptions.parse(arguments),
      );
    }
  });

  await _test('validate-only checks inputs without authority', () async {
    final _Fixture fixture = await _Fixture.create();
    try {
      final _FakeExecutor executor = _FakeExecutor();
      _expect(
        await fixture
                .publisher(executor)
                .run(fixture.options(validateOnly: true)) ==
            0,
        'preflight succeeds',
      );
      _expect(
        executor.commands.every(
          (_Command command) =>
              !command.arguments.contains('--sign') &&
              command.executable != '/usr/bin/security' &&
              command.executable != '/usr/bin/xcrun' &&
              command.executable != '/usr/sbin/spctl',
        ),
        'preflight never signs, uploads, staples, or assesses',
      );
      _expect(
        !await Directory(fixture.outputPath).exists(),
        'preflight does not publish output',
      );
    } finally {
      await fixture.dispose();
    }
  });

  await _test(
    'accepted publication signs, staples, archives, and replaces',
    () async {
      final _Fixture fixture = await _Fixture.create();
      try {
        await fixture.writeLastGood();
        final _FakeExecutor executor = _FakeExecutor();
        _expect(
          await fixture.publisher(executor).run(fixture.options()) == 0,
          'publication succeeds',
        );
        final File evidence = File(
          '${fixture.outputPath}/distribution-manifest.json',
        );
        final Map<String, Object?> decoded =
            jsonDecode(await evidence.readAsString()) as Map<String, Object?>;
        _expect(
          decoded['schemaVersion'] == 1 &&
              decoded['bundleIdentifier'] == 'dev.example.application' &&
              decoded['teamIdentifier'] == _team &&
              decoded['hardenedRuntime'] == true &&
              decoded['secureTimestamp'] == true &&
              (decoded['notarization']! as Map<String, Object?>)['status'] ==
                  'Accepted' &&
              (decoded['notarization']! as Map<String, Object?>)['issues'] ==
                  0 &&
              (decoded['code']! as List<Object?>).length == _codePaths.length &&
              await Directory('${fixture.outputPath}/Source.app').exists() &&
              await File('${fixture.outputPath}/Source.zip').length() > 0 &&
              !await File('${fixture.outputPath}/sentinel.txt').exists(),
          'published output has exact accepted evidence and replaces last good',
        );
        final List<_Command> signingCommands = executor.commands
            .where((_Command command) => command.arguments.contains('--sign'))
            .toList();
        _expect(
          signingCommands.length == _codePaths.length + 1 &&
              signingCommands
                  .take(_codePaths.length)
                  .every(
                    (_Command command) =>
                        !command.arguments.contains('--deep') &&
                        command.arguments.contains('runtime') &&
                        command.arguments.contains('--timestamp'),
                  ) &&
              signingCommands.last.arguments.contains('--entitlements'),
          'nested signing is explicit and outer signing owns entitlements',
        );
        final List<_Command> entitlementDisplays = executor.commands
            .where(
              (_Command command) =>
                  command.executable == '/usr/bin/codesign' &&
                  command.arguments.contains('--display') &&
                  command.arguments.contains('--entitlements'),
            )
            .toList();
        _expect(
          entitlementDisplays.length == 1 &&
              entitlementDisplays.single.arguments.length == 5 &&
              entitlementDisplays.single.arguments[0] == '--display' &&
              entitlementDisplays.single.arguments[1] == '--entitlements' &&
              entitlementDisplays.single.arguments[2] == '-' &&
              entitlementDisplays.single.arguments[3] == '--xml',
          'signed entitlements are extracted as an XML property list',
        );
        _expect(
          executor.commands.every(
            (_Command command) =>
                !command.arguments.contains('--password') &&
                !command.arguments.contains('--apple-id') &&
                !command.arguments.contains('--key'),
          ),
          'commands contain no raw credential options',
        );
        final List<_Command> archives = executor.commands
            .where((_Command command) => command.executable == '/usr/bin/ditto')
            .toList();
        final int stapleIndex = executor.commands.indexWhere(
          (_Command command) =>
              command.arguments.take(2).join(' ') == 'stapler staple',
        );
        _expect(
          archives.length == 2 &&
              executor.commands.indexOf(archives.last) > stapleIndex,
          'final archive is created only after stapling',
        );
      } finally {
        await fixture.dispose();
      }
    },
  );

  await _test(
    'source shape, resource ownership, and paths fail closed',
    () async {
      final _Fixture overlap = await _Fixture.create();
      final _Fixture tampered = await _Fixture.create();
      final _Fixture extra = await _Fixture.create();
      final _Fixture linked = await _Fixture.create();
      try {
        await _expectThrows<RuntimeBuilderException>(
          () => overlap
              .publisher(_FakeExecutor())
              .run(
                DistributionPublisherOptions.parse(<String>[
                  '--input-app=${overlap.source.path}',
                  '--output-directory=${overlap.source.path}/output',
                  '--signing-identity=$_identity',
                  '--team-id=$_team',
                  '--entitlements=${overlap.entitlements.path}',
                  '--keychain-profile=$_profile',
                  '--validate-only',
                ]),
              ),
        );
        await File(
          '${tampered.source.path}/Contents/Resources/DART_SDK_LICENSE.txt',
        ).writeAsString('changed\n', flush: true);
        await _expectThrows<RuntimeBuilderException>(
          () => tampered
              .publisher(_FakeExecutor())
              .run(tampered.options(validateOnly: true)),
        );
        await _write(
          '${extra.source.path}/Contents/Resources/extra.txt',
          'extra\n',
        );
        await _expectThrows<RuntimeBuilderException>(
          () => extra
              .publisher(_FakeExecutor())
              .run(extra.options(validateOnly: true)),
        );
        final Directory link = Directory('${linked.root.path}/Linked.app');
        await Link(link.path).create(linked.source.path);
        await _expectThrows<RuntimeBuilderException>(
          () => linked
              .publisher(_FakeExecutor())
              .run(
                DistributionPublisherOptions.parse(<String>[
                  '--input-app=${link.path}',
                  '--output-directory=${linked.outputPath}',
                  '--signing-identity=$_identity',
                  '--team-id=$_team',
                  '--entitlements=${linked.entitlements.path}',
                  '--keychain-profile=$_profile',
                  '--validate-only',
                ]),
              ),
        );
      } finally {
        await overlap.dispose();
        await tampered.dispose();
        await extra.dispose();
        await linked.dispose();
      }
    },
  );

  await _test(
    'authority and external failures preserve last good output',
    () async {
      final List<_FakeExecutor> executors = <_FakeExecutor>[
        _FakeExecutor()..sourceAdhoc = false,
        _FakeExecutor()
          ..entitlementsJson = '{"com.apple.security.get-task-allow":true}',
        _FakeExecutor()..identityAvailable = false,
        _FakeExecutor()..failSigning = true,
        _FakeExecutor()..wrongTeam = true,
        _FakeExecutor()..omitRuntime = true,
        _FakeExecutor()..omitTimestamp = true,
        _FakeExecutor()..omitDeveloperIdAuthority = true,
        _FakeExecutor()..wrongArchitectures = true,
        _FakeExecutor()..entitlementDrift = true,
        _FakeExecutor()..malformedNotary = true,
        _FakeExecutor()..rejectNotary = true,
        _FakeExecutor()..notaryLogIssues = true,
        _FakeExecutor()..failStapling = true,
        _FakeExecutor()..failGatekeeper = true,
        _FakeExecutor()..failFinalArchive = true,
      ];
      for (final _FakeExecutor executor in executors) {
        final _Fixture fixture = await _Fixture.create();
        try {
          await fixture.writeLastGood();
          await _expectThrows<RuntimeBuilderException>(
            () => fixture.publisher(executor).run(fixture.options()),
          );
          await fixture.expectLastGood();
        } finally {
          await fixture.dispose();
        }
      }
    },
  );

  if (_failures != 0) {
    stderr.writeln('$_failures distribution publisher test(s) failed');
    exitCode = 1;
  }
}
