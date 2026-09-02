import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _pinnedRevision = '60a57cd42d64dc03e9f07aa60a2e250755c1ef28';
const Duration _hostTimeout = Duration(seconds: 15);

Never _usage(String message) {
  stderr.writeln('PUBLIC_DART_API_HOST_PROBE_FAIL $message');
  stderr.writeln(
    'usage: dart tool/public_dart_api_host_probe_runner.dart '
    '--engine-root=PATH --host-source=PATH '
    '--jit-host=PATH --jit-library=PATH --jit-application=PATH '
    '--jit-platform=PATH --aot-host=PATH --aot-library=PATH '
    '--aot-application=PATH',
  );
  exit(64);
}

Future<void> main(List<String> arguments) async {
  final Map<String, String> options = <String, String>{};
  for (final String argument in arguments) {
    final int separator = argument.indexOf('=');
    if (!argument.startsWith('--') || separator <= 2) {
      _usage('invalid argument: $argument');
    }
    final String name = argument.substring(2, separator);
    if (options.containsKey(name)) {
      _usage('duplicate option: $name');
    }
    options[name] = argument.substring(separator + 1);
  }

  const Set<String> required = <String>{
    'engine-root',
    'host-source',
    'jit-host',
    'jit-library',
    'jit-application',
    'jit-platform',
    'aot-host',
    'aot-library',
    'aot-application',
  };
  if (options.keys.toSet().difference(required).isNotEmpty ||
      required.difference(options.keys.toSet()).isNotEmpty) {
    _usage('exactly the documented options are required');
  }

  final Directory engineRoot = Directory(options['engine-root']!);
  final File hostSource = File(options['host-source']!);
  final File jitHost = File(options['jit-host']!);
  final File jitLibrary = File(options['jit-library']!);
  final File jitApplication = File(options['jit-application']!);
  final File jitPlatform = File(options['jit-platform']!);
  final File aotHost = File(options['aot-host']!);
  final File aotLibrary = File(options['aot-library']!);
  final File aotApplication = File(options['aot-application']!);
  for (final FileSystemEntity entity in <FileSystemEntity>[
    engineRoot,
    hostSource,
    jitHost,
    jitLibrary,
    jitApplication,
    jitPlatform,
    aotHost,
    aotLibrary,
    aotApplication,
  ]) {
    _require(entity.existsSync(), 'missing required input: ${entity.path}');
  }

  await _requireCleanOfficialSdk(engineRoot);
  _auditHostSource(hostSource);
  final bool jitBootstrapExported = await _auditLibrary(jitLibrary);
  final bool aotBootstrapExported = await _auditLibrary(aotLibrary);
  _require(
    jitBootstrapExported == aotBootstrapExported,
    'JIT and AOT disagree on public platform bootstrap availability',
  );

  final _HostResult jit = await _runHost(
    mode: 'jit',
    executable: jitHost,
    application: jitApplication,
    platform: jitPlatform,
  );
  final _HostResult aot = await _runHost(
    mode: 'aot',
    executable: aotHost,
    application: aotApplication,
  );

  await _requireCleanOfficialSdk(engineRoot);
  final bool accepted =
      jitBootstrapExported && jit.runtimeSupported && aot.runtimeSupported;
  stdout.writeln(
    'PUBLIC_DART_API_HOST_DECISION '
    'accepted=$accepted '
    'public_platform_bootstrap=$jitBootstrapExported '
    'jit_runtime=${jit.runtimeSupported} '
    'aot_runtime=${aot.runtimeSupported}',
  );
}

Future<void> _requireCleanOfficialSdk(Directory engineRoot) async {
  final ProcessResult revision = await Process.run('git', <String>[
    '-C',
    engineRoot.path,
    'rev-parse',
    'HEAD',
  ]);
  _require(revision.exitCode == 0, 'could not read SDK revision');
  _require(
    (revision.stdout as String).trim() == _pinnedRevision,
    'SDK is not at pinned revision $_pinnedRevision',
  );
  final ProcessResult status = await Process.run('git', <String>[
    '-C',
    engineRoot.path,
    'status',
    '--porcelain',
    '--untracked-files=no',
  ]);
  _require(status.exitCode == 0, 'could not inspect SDK status');
  _require(
    (status.stdout as String).trim().isEmpty,
    'SDK contains tracked source changes',
  );
}

void _auditHostSource(File source) {
  final String text = source.readAsStringSync();
  for (final String forbidden in <String>[
    'dart_engine.h',
    'dart_embedder_api.h',
    'runtime/bin',
    'DartEngine_',
    'SetupCoreLibraries',
    'InitOnce(',
  ]) {
    _require(
      !text.contains(forbidden),
      'host source crosses the public boundary with $forbidden',
    );
  }
  for (final String required in <String>[
    'include/dart_api.h',
    'include/dart_native_api.h',
    'Dart_Initialize(',
    'Dart_CreateIsolateGroup(',
    'Dart_CreateIsolateGroupFromKernel(',
    'Dart_Cleanup(',
  ]) {
    _require(
      text.contains(required),
      'host source does not exercise $required',
    );
  }
}

Future<bool> _auditLibrary(File library) async {
  final ProcessResult result = await Process.run('nm', <String>[
    '-gU',
    library.path,
  ]);
  _require(result.exitCode == 0, 'nm failed for ${library.path}');
  final String symbols = result.stdout as String;
  for (final String required in <String>[
    '_Dart_Initialize',
    '_Dart_Cleanup',
    '_Dart_CreateIsolateGroup',
    '_Dart_CreateIsolateGroupFromKernel',
    '_Dart_SetDartLibrarySourcesKernel',
  ]) {
    _require(
      symbols.contains(' $required'),
      '${library.path} lacks public symbol $required',
    );
  }
  return symbols.contains('InitOnce') && symbols.contains('SetupCoreLibraries');
}

Future<_HostResult> _runHost({
  required String mode,
  required File executable,
  required File application,
  File? platform,
}) async {
  final List<String> arguments = <String>[
    '--mode=$mode',
    '--application=${application.path}',
    if (platform != null) '--platform=${platform.path}',
  ];
  final Process process = await Process.start(executable.path, arguments);
  final Future<String> output = process.stdout.transform(utf8.decoder).join();
  final Future<String> diagnostics = process.stderr
      .transform(utf8.decoder)
      .join();
  int exitStatus;
  try {
    exitStatus = await process.exitCode.timeout(_hostTimeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    throw StateError('$mode public host exceeded $_hostTimeout');
  }
  final String stdoutText = await output;
  final String stderrText = await diagnostics;
  _require(
    exitStatus == 0,
    '$mode public host exited $exitStatus:\n$stdoutText\n$stderrText',
  );
  _require(stderrText.isEmpty, '$mode public host wrote stderr: $stderrText');
  stdout.write(stdoutText);

  final Map<String, String> markers = <String, String>{};
  for (final String line in const LineSplitter().convert(stdoutText)) {
    final int separator = line.indexOf('=');
    _require(
      line.startsWith('probe.') && separator > 'probe.'.length,
      'unexpected $mode host output: $line',
    );
    final String key = line.substring(0, separator);
    _require(!markers.containsKey(key), 'duplicate $mode marker $key');
    markers[key] = line.substring(separator + 1);
  }
  _require(markers['probe.mode'] == mode, '$mode marker mismatch');
  _require(
    markers['probe.root_main_thread'] == 'true',
    '$mode native host was not on the process main thread',
  );
  _require(
    markers['probe.vm_cleanup'] == 'true',
    '$mode VM cleanup did not complete: ${markers['probe.shutdown_error']}',
  );
  _require(
    markers['probe.host_shutdown_idempotent'] == 'true',
    '$mode host shutdown was not idempotent',
  );
  return _HostResult(
    runtimeSupported: markers['probe.runtime_contract_supported'] == 'true',
  );
}

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

final class _HostResult {
  const _HostResult({required this.runtimeSupported});

  final bool runtimeSupported;
}
