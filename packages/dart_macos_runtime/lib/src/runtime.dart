import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

const int _runtimeAbiVersion = 1;
const int _diagnosticsAbiVersion = 1;

enum RuntimeDiagnosticPhase {
  rootStarting(1),
  rootReady(2),
  shutdownStarted(3),
  rootStopped(4);

  const RuntimeDiagnosticPhase(this.nativeValue);
  final int nativeValue;
}

final class MacosRuntimeException implements Exception {
  const MacosRuntimeException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : '$message (status $status)';
}

final class MacosRuntimeHelperCommand {
  const MacosRuntimeHelperCommand({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

typedef _VersionNative = Uint32 Function();
typedef _VersionDart = int Function();
typedef _IntStatusNative = Int32 Function(Int32);
typedef _IntStatusDart = int Function(int);
typedef _UintStatusNative = Int32 Function(Uint32);
typedef _UintStatusDart = int Function(int);

abstract interface class RuntimeBindings {
  int runtimeAbiVersion();
  int diagnosticsAbiVersion();
  int setExitCode(int exitCode);
  int requestTermination(int exitCode);
  int recordDiagnosticPhase(int phase);
}

final class ProcessRuntimeBindings implements RuntimeBindings {
  ProcessRuntimeBindings([DynamicLibrary? library])
    : _library = library ?? DynamicLibrary.process();

  final DynamicLibrary _library;

  late final _VersionDart _runtimeVersion = _library
      .lookupFunction<_VersionNative, _VersionDart>('dmr_runtime_abi_version');
  late final _VersionDart _diagnosticsVersion = _library
      .lookupFunction<_VersionNative, _VersionDart>(
        'dmr_runtime_diagnostics_abi_version',
      );
  late final _IntStatusDart _setExitCode = _library
      .lookupFunction<_IntStatusNative, _IntStatusDart>(
        'dmr_runtime_set_exit_code',
      );
  late final _IntStatusDart _requestTermination = _library
      .lookupFunction<_IntStatusNative, _IntStatusDart>(
        'dmr_runtime_request_termination',
      );
  late final _UintStatusDart _recordPhase = _library
      .lookupFunction<_UintStatusNative, _UintStatusDart>(
        'dmr_runtime_diagnostics_record_phase',
      );

  @override
  int runtimeAbiVersion() => _runtimeVersion();

  @override
  int diagnosticsAbiVersion() => _diagnosticsVersion();

  @override
  int setExitCode(int exitCode) => _setExitCode(exitCode);

  @override
  int requestTermination(int exitCode) => _requestTermination(exitCode);

  @override
  int recordDiagnosticPhase(int phase) => _recordPhase(phase);
}

abstract final class MacosRuntime {
  static RuntimeBindings _bindings = ProcessRuntimeBindings();

  static void validateHost() {
    final int runtime = _bindings.runtimeAbiVersion();
    final int diagnostics = _bindings.diagnosticsAbiVersion();
    if (runtime != _runtimeAbiVersion ||
        diagnostics != _diagnosticsAbiVersion) {
      throw MacosRuntimeException(
        'incompatible macOS runtime ABI: runtime=$runtime, '
        'diagnostics=$diagnostics',
      );
    }
  }

  static void setExitCode(int exitCode) {
    _checkStatus(_bindings.setExitCode(exitCode), 'set process exit code');
  }

  /// Requests host termination with a process result in 0 through 255.
  ///
  /// Zero requests a clean exit and preserves any earlier non-zero result.
  static void requestTermination({required int exitCode}) {
    _checkStatus(
      _bindings.requestTermination(exitCode),
      'request application termination',
    );
  }

  static void recordDiagnosticPhase(RuntimeDiagnosticPhase phase) {
    final int status = _bindings.recordDiagnosticPhase(phase.nativeValue);
    if (status != 0 && status != 1) {
      throw MacosRuntimeException(
        'could not record runtime phase ${phase.name}',
        status: status,
      );
    }
  }

  static String bundleResourcePath(
    String relativePath, {
    String? resolvedExecutable,
  }) {
    _validateRelativePath(relativePath);
    final File executable = File(
      resolvedExecutable ?? Platform.resolvedExecutable,
    ).absolute;
    final Directory resources = executable.parent.parent.childDirectory(
      'Resources',
    );
    final File resource = resources.childFile(relativePath);
    if (!resource.existsSync()) {
      throw MacosRuntimeException(
        'declared bundle resource does not exist: $relativePath',
      );
    }
    return resource.absolute.path;
  }

  static String bundleFrameworkPath(
    String libraryName, {
    String? resolvedExecutable,
  }) {
    if (!_libraryName.hasMatch(libraryName)) {
      throw const MacosRuntimeException(
        'bundle framework name must be a dylib filename',
      );
    }
    final File executable = File(
      resolvedExecutable ?? Platform.resolvedExecutable,
    ).absolute;
    final File library = executable.parent.parent
        .childDirectory('Frameworks')
        .childFile(libraryName);
    if (!library.existsSync()) {
      throw MacosRuntimeException(
        'declared bundle framework does not exist: $libraryName',
      );
    }
    return library.absolute.path;
  }

  static String bundleHelperPath(
    String helperName, {
    String? resolvedExecutable,
  }) {
    if (!_helperName.hasMatch(helperName)) {
      throw const MacosRuntimeException(
        'bundle helper name contains invalid characters',
      );
    }
    final File executable = File(
      resolvedExecutable ?? Platform.resolvedExecutable,
    ).absolute;
    final File helper = executable.parent.parent
        .childDirectory('Helpers')
        .childFile(helperName);
    if (!helper.existsSync()) {
      throw MacosRuntimeException(
        'declared bundle helper does not exist: $helperName',
      );
    }
    return helper.absolute.path;
  }

  static MacosRuntimeHelperCommand bundleHelperCommand(
    String helperName, {
    String? resolvedExecutable,
  }) {
    final String executable = bundleHelperPath(
      helperName,
      resolvedExecutable: resolvedExecutable,
    );
    final File rootExecutable = File(
      resolvedExecutable ?? Platform.resolvedExecutable,
    ).absolute;
    final Directory resources = rootExecutable.parent.parent.childDirectory(
      'Resources',
    );
    final File manifestFile = resources.childFile(
      'runtime-build-manifest.json',
    );
    if (!manifestFile.existsSync()) {
      throw const MacosRuntimeException(
        'runtime build manifest does not exist',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(manifestFile.readAsStringSync());
    } on Object {
      throw const MacosRuntimeException('runtime build manifest is invalid');
    }
    if (decoded is! Map<String, Object?> ||
        decoded['dartHelpers'] is! List<Object?>) {
      throw const MacosRuntimeException('runtime build manifest is invalid');
    }
    final List<Map<String, Object?>> declarations =
        (decoded['dartHelpers']! as List<Object?>)
            .whereType<Map<String, Object?>>()
            .where((Map<String, Object?> value) => value['name'] == helperName)
            .toList();
    if (declarations.length != 1) {
      throw MacosRuntimeException(
        'runtime build manifest does not declare helper: $helperName',
      );
    }
    final Object? relativePayload = declarations.single['payload'];
    if (relativePayload == null) {
      return MacosRuntimeHelperCommand(
        executable: executable,
        arguments: const <String>[],
      );
    }
    if (relativePayload is! String) {
      throw const MacosRuntimeException(
        'runtime build manifest has an invalid helper payload',
      );
    }
    _validateRelativePath(relativePayload);
    final File payload = resources.childFile(relativePayload);
    if (!payload.existsSync()) {
      throw MacosRuntimeException(
        'declared bundle helper payload does not exist: $relativePayload',
      );
    }
    return MacosRuntimeHelperCommand(
      executable: executable,
      arguments: List<String>.unmodifiable(<String>[payload.absolute.path]),
    );
  }

  static void _checkStatus(int status, String operation) {
    if (status != 0) {
      throw MacosRuntimeException('could not $operation', status: status);
    }
  }

  static void _validateRelativePath(String value) {
    final List<String> segments = value.split('/');
    if (value.isEmpty ||
        Uri.file(value).isAbsolute ||
        value.contains('\\') ||
        value.contains('\u0000') ||
        segments.contains('') ||
        segments.contains('.') ||
        segments.contains('..')) {
      throw const MacosRuntimeException(
        'bundle resource name must be a normalized relative path',
      );
    }
  }

  static void setBindingsForTesting(RuntimeBindings bindings) {
    _bindings = bindings;
  }
}

final RegExp _libraryName = RegExp(r'^lib[A-Za-z0-9._-]+\.dylib$');
final RegExp _helperName = RegExp(r'^[A-Za-z0-9._-]+$');

extension on Directory {
  Directory childDirectory(String name) =>
      Directory(uri.resolve('$name/').toFilePath());

  File childFile(String name) => File(uri.resolve(name).toFilePath());
}
