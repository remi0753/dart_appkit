import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'api.dart';

const String _assetId = 'package:dart_pty_macos/dart_pty_macos.dart';
const int _abiVersion = 2;
const int _statusOk = 0;
const int _statusBackpressured = 4;
const int _eventStarted = 1;
const int _eventOutput = 2;
const int _eventExit = 3;
const int _eventError = 4;

typedef _EventNative = Void Function(
  Uint64,
  Uint32,
  Uint64,
  Pointer<Uint8>,
  Size,
  Int64,
  Int64,
  Int32,
  Pointer<Void>,
);

final class _SessionConfig extends Struct {
  @Size()
  external int structSize;

  @Uint32()
  external int abiVersion;

  external Pointer<Utf8> executable;
  external Pointer<Pointer<Utf8>> arguments;

  @Size()
  external int argumentCount;

  external Pointer<Pointer<Utf8>> environment;

  @Size()
  external int environmentCount;

  external Pointer<Utf8> workingDirectory;

  @Uint16()
  external int initialRows;

  @Uint16()
  external int initialColumns;

  @Size()
  external int readHighWaterBytes;

  @Size()
  external int readLowWaterBytes;

  @Size()
  external int writeCapacityBytes;

  external Pointer<NativeFunction<_EventNative>> callback;
  external Pointer<Void> callbackContext;
}

final class _NativeStats extends Struct {
  @Size()
  external int structSize;

  @Uint32()
  external int abiVersion;

  @Uint64()
  external int bytesRead;

  @Uint64()
  external int bytesWritten;

  @Uint64()
  external int readBatches;

  @Uint64()
  external int writeBackpressureRejections;

  @Uint64()
  external int maxReadInFlightBytes;

  @Uint64()
  external int maxWriteQueuedBytes;

  @Uint64()
  external int readPauseCount;

  @Int64()
  external int childPid;

  @Int32()
  external int hasExited;
}

@Native<Uint32 Function()>(symbol: 'dpty_abi_version', assetId: _assetId)
external int _nativeAbiVersion();

@Native<Int32 Function(Pointer<_SessionConfig>, Pointer<Uint64>)>(
  symbol: 'dpty_session_create',
  assetId: _assetId,
)
external int _sessionCreate(
  Pointer<_SessionConfig> config,
  Pointer<Uint64> output,
);

@Native<Int32 Function(Uint64)>(symbol: 'dpty_session_start', assetId: _assetId)
external int _sessionStart(int session);

@Native<Int32 Function(Uint64, Pointer<Uint8>, Size)>(
  symbol: 'dpty_session_write',
  assetId: _assetId,
)
external int _sessionWrite(int session, Pointer<Uint8> bytes, int length);

@Native<Int32 Function(Uint64, Uint64, Size)>(
  symbol: 'dpty_session_ack_output',
  assetId: _assetId,
)
external int _sessionAckOutput(int session, int sequence, int length);

@Native<Int32 Function(Uint64, Uint16, Uint16)>(
  symbol: 'dpty_session_resize',
  assetId: _assetId,
)
external int _sessionResize(int session, int rows, int columns);

@Native<Int32 Function(Uint64, Uint32)>(
  symbol: 'dpty_session_send_signal',
  assetId: _assetId,
)
external int _sessionSendSignal(int session, int signal);

@Native<Int32 Function(Uint64, Uint32)>(
  symbol: 'dpty_session_close',
  assetId: _assetId,
)
external int _sessionClose(int session, int gracePeriodMillis);

@Native<Int32 Function(Uint64)>(
  symbol: 'dpty_session_force_close',
  assetId: _assetId,
)
external int _sessionForceClose(int session);

@Native<Int32 Function(Uint64, Pointer<_NativeStats>)>(
  symbol: 'dpty_session_get_stats',
  assetId: _assetId,
)
external int _sessionGetStats(int session, Pointer<_NativeStats> stats);

@Native<Int32 Function(Uint64)>(
  symbol: 'dpty_session_destroy',
  assetId: _assetId,
)
external int _sessionDestroy(int session);

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _SessionCreateNative = Int32 Function(
  Pointer<_SessionConfig>,
  Pointer<Uint64>,
);
typedef _SessionCreateDart = int Function(
  Pointer<_SessionConfig>,
  Pointer<Uint64>,
);
typedef _SessionHandleNative = Int32 Function(Uint64);
typedef _SessionHandleDart = int Function(int);
typedef _SessionWriteNative = Int32 Function(Uint64, Pointer<Uint8>, Size);
typedef _SessionWriteDart = int Function(int, Pointer<Uint8>, int);
typedef _SessionAckNative = Int32 Function(Uint64, Uint64, Size);
typedef _SessionAckDart = int Function(int, int, int);
typedef _SessionResizeNative = Int32 Function(Uint64, Uint16, Uint16);
typedef _SessionResizeDart = int Function(int, int, int);
typedef _SessionUint32Native = Int32 Function(Uint64, Uint32);
typedef _SessionUint32Dart = int Function(int, int);
typedef _SessionStatsNative = Int32 Function(Uint64, Pointer<_NativeStats>);
typedef _SessionStatsDart = int Function(int, Pointer<_NativeStats>);

final class _PtyFunctions {
  _PtyFunctions.nativeAssets()
    : abiVersion = _nativeAbiVersion,
      sessionCreate = _sessionCreate,
      sessionStart = _sessionStart,
      sessionWrite = _sessionWrite,
      sessionAckOutput = _sessionAckOutput,
      sessionResize = _sessionResize,
      sessionSendSignal = _sessionSendSignal,
      sessionClose = _sessionClose,
      sessionForceClose = _sessionForceClose,
      sessionGetStats = _sessionGetStats,
      sessionDestroy = _sessionDestroy;

  _PtyFunctions.dynamic(DynamicLibrary library)
    : abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
        'dpty_abi_version',
      ),
      sessionCreate = library
          .lookupFunction<_SessionCreateNative, _SessionCreateDart>(
            'dpty_session_create',
          ),
      sessionStart = library
          .lookupFunction<_SessionHandleNative, _SessionHandleDart>(
            'dpty_session_start',
          ),
      sessionWrite = library
          .lookupFunction<_SessionWriteNative, _SessionWriteDart>(
            'dpty_session_write',
          ),
      sessionAckOutput = library
          .lookupFunction<_SessionAckNative, _SessionAckDart>(
            'dpty_session_ack_output',
          ),
      sessionResize = library
          .lookupFunction<_SessionResizeNative, _SessionResizeDart>(
            'dpty_session_resize',
          ),
      sessionSendSignal = library
          .lookupFunction<_SessionUint32Native, _SessionUint32Dart>(
            'dpty_session_send_signal',
          ),
      sessionClose = library
          .lookupFunction<_SessionUint32Native, _SessionUint32Dart>(
            'dpty_session_close',
          ),
      sessionForceClose = library
          .lookupFunction<_SessionHandleNative, _SessionHandleDart>(
            'dpty_session_force_close',
          ),
      sessionGetStats = library
          .lookupFunction<_SessionStatsNative, _SessionStatsDart>(
            'dpty_session_get_stats',
          ),
      sessionDestroy = library
          .lookupFunction<_SessionHandleNative, _SessionHandleDart>(
            'dpty_session_destroy',
          );

  final _AbiVersionDart abiVersion;
  final _SessionCreateDart sessionCreate;
  final _SessionHandleDart sessionStart;
  final _SessionWriteDart sessionWrite;
  final _SessionAckDart sessionAckOutput;
  final _SessionResizeDart sessionResize;
  final _SessionUint32Dart sessionSendSignal;
  final _SessionUint32Dart sessionClose;
  final _SessionHandleDart sessionForceClose;
  final _SessionStatsDart sessionGetStats;
  final _SessionHandleDart sessionDestroy;
}

final Map<int, _MacosPtyProcess> _sessions = <int, _MacosPtyProcess>{};
final NativeCallable<_EventNative> _eventCallback =
    NativeCallable<_EventNative>.listener(_dispatchEvent)
      ..keepIsolateAlive = false;

void _refreshCallbackKeepAlive() {
  _eventCallback.keepIsolateAlive = _sessions.isNotEmpty;
}

void _dispatchEvent(
  int session,
  int eventType,
  int sequence,
  Pointer<Uint8> data,
  int length,
  int value1,
  int value2,
  int systemError,
  Pointer<Void> _,
) {
  final _MacosPtyProcess? process = _sessions[session];
  if (process == null) {
    return;
  }
  switch (eventType) {
    case _eventStarted:
      process._didStart(value1);
      return;
    case _eventOutput:
      if (data == nullptr || length <= 0) {
        process._didFail(
          const PtyException('native PTY returned an invalid output event'),
        );
        return;
      }
      final Uint8List bytes = Uint8List.fromList(data.asTypedList(length));
      process._didOutput(sequence, bytes);
      return;
    case _eventExit:
      process._didExit(value1, value2);
      return;
    case _eventError:
      process._didFail(
        PtyException(
          'native PTY reactor failed',
          status: value1,
          systemError: systemError,
        ),
      );
      return;
    default:
      process._didFail(
        PtyException('native PTY returned unknown event $eventType'),
      );
      return;
  }
}

Future<PtyProcess> startPty(
  PtyCommand command, {
  PtyBackend? backend,
  PtySize initialSize = const PtySize(rows: 24, columns: 80),
  int readHighWaterBytes = 1024 * 1024,
  int readLowWaterBytes = 512 * 1024,
  int writeCapacityBytes = 1024 * 1024,
}) {
  final PtyBackend selected = backend ?? MacosPtyBackend.shared;
  return selected.start(
    command,
    initialSize: initialSize,
    readHighWaterBytes: readHighWaterBytes,
    readLowWaterBytes: readLowWaterBytes,
    writeCapacityBytes: writeCapacityBytes,
  );
}

final class MacosPtyBackend implements PtyBackend {
  MacosPtyBackend._(this._functions);

  static final MacosPtyBackend shared = MacosPtyBackend._(
    _PtyFunctions.nativeAssets(),
  );

  factory MacosPtyBackend.open(String libraryPath) {
    final File library = File(libraryPath);
    if (!library.isAbsolute || !library.existsSync()) {
      throw ArgumentError.value(
        libraryPath,
        'libraryPath',
        'must name an existing absolute dylib path',
      );
    }
    return MacosPtyBackend._(
      _PtyFunctions.dynamic(DynamicLibrary.open(library.path)),
    );
  }

  final _PtyFunctions _functions;

  @override
  Future<PtyProcess> start(
    PtyCommand command, {
    PtySize initialSize = const PtySize(rows: 24, columns: 80),
    int readHighWaterBytes = 1024 * 1024,
    int readLowWaterBytes = 512 * 1024,
    int writeCapacityBytes = 1024 * 1024,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('dart_pty_macos requires macOS');
    }
    if (_functions.abiVersion() != _abiVersion) {
      throw const PtyException('native PTY ABI version mismatch');
    }
    if (readHighWaterBytes <= 0 ||
        readLowWaterBytes < 0 ||
        readLowWaterBytes >= readHighWaterBytes ||
        writeCapacityBytes <= 0) {
      throw ArgumentError('PTY queue watermarks are invalid');
    }

    final Map<String, String> environment = <String, String>{
      if (command.includeParentEnvironment) ...Platform.environment,
      ...command.environment,
    };
    final String executableName = command.executable
        .split('/')
        .where((String part) => part.isNotEmpty)
        .last;
    final List<String> arguments = <String>[
      command.loginShell ? '-$executableName' : executableName,
      ...command.arguments,
    ];
    final List<String> environmentEntries = <String>[
      for (final String key in environment.keys.toList()..sort())
        '$key=${environment[key]}',
    ];
    final Arena arena = Arena();
    try {
      final Pointer<_SessionConfig> config = arena<_SessionConfig>();
      final Pointer<Pointer<Utf8>> argumentPointers = arena<Pointer<Utf8>>(
        arguments.length,
      );
      for (var index = 0; index < arguments.length; ++index) {
        argumentPointers[index] = arguments[index].toNativeUtf8(
          allocator: arena,
        );
      }
      final Pointer<Pointer<Utf8>> environmentPointers =
          environmentEntries.isEmpty
          ? nullptr
          : arena<Pointer<Utf8>>(environmentEntries.length);
      for (var index = 0; index < environmentEntries.length; ++index) {
        environmentPointers[index] = environmentEntries[index].toNativeUtf8(
          allocator: arena,
        );
      }
      config.ref
        ..structSize = sizeOf<_SessionConfig>()
        ..abiVersion = _abiVersion
        ..executable = command.executable.toNativeUtf8(allocator: arena)
        ..arguments = argumentPointers
        ..argumentCount = arguments.length
        ..environment = environmentPointers
        ..environmentCount = environmentEntries.length
        ..workingDirectory =
            (command.workingDirectory ?? Directory.current.path).toNativeUtf8(
              allocator: arena,
            )
        ..initialRows = initialSize.rows
        ..initialColumns = initialSize.columns
        ..readHighWaterBytes = readHighWaterBytes
        ..readLowWaterBytes = readLowWaterBytes
        ..writeCapacityBytes = writeCapacityBytes
        ..callback = _eventCallback.nativeFunction
        ..callbackContext = nullptr;
      final Pointer<Uint64> output = arena<Uint64>();
      final int createStatus = _functions.sessionCreate(config, output);
      if (createStatus != _statusOk || output.value == 0) {
        throw PtyException(
          'native PTY session creation failed',
          status: createStatus,
        );
      }
      final _MacosPtyProcess process = _MacosPtyProcess(
        output.value,
        _functions,
      );
      _sessions[output.value] = process;
      _refreshCallbackKeepAlive();
      final int startStatus = _functions.sessionStart(output.value);
      if (startStatus != _statusOk) {
        _sessions.remove(output.value);
        _refreshCallbackKeepAlive();
        _functions.sessionDestroy(output.value);
        throw PtyException(
          'native PTY session start failed',
          status: startStatus,
        );
      }
      await process._started.future;
      return process;
    } finally {
      arena.releaseAll();
    }
  }
}

final class _MacosPtyProcess implements PtyProcess {
  _MacosPtyProcess(this._handle, this._functions);

  final int _handle;
  final _PtyFunctions _functions;
  final Completer<void> _started = Completer<void>();
  final Completer<PtyExit> _exit = Completer<PtyExit>();
  final StreamController<Uint8List> _output = StreamController<Uint8List>(
    sync: true,
  );
  int _pid = -1;
  bool _finished = false;
  bool _disposed = false;
  PtyStats? _finalStats;

  @override
  int get pid => _pid;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<PtyExit> get exit => _exit.future;

  @override
  PtyStats? get finalStats => _finalStats;

  @override
  PtyWriteResult write(Uint8List bytes) {
    _requireRunning();
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
    final Pointer<Uint8> nativeBytes = malloc<Uint8>(bytes.length);
    try {
      nativeBytes.asTypedList(bytes.length).setAll(0, bytes);
      final int status = _functions.sessionWrite(
        _handle,
        nativeBytes,
        bytes.length,
      );
      if (status == _statusBackpressured) {
        return PtyWriteResult.backpressured;
      }
      _checkStatus(status, 'PTY write');
      return PtyWriteResult.accepted;
    } finally {
      malloc.free(nativeBytes);
    }
  }

  @override
  void resize(PtySize size) {
    _requireRunning();
    _checkStatus(
      _functions.sessionResize(_handle, size.rows, size.columns),
      'PTY resize',
    );
  }

  @override
  void sendSignal(PtySignal signal) {
    _requireRunning();
    _checkStatus(
      _functions.sessionSendSignal(_handle, signal.index + 1),
      'PTY signal',
    );
  }

  @override
  void close({Duration gracePeriod = const Duration(seconds: 2)}) {
    if (_finished) {
      return;
    }
    final int milliseconds = gracePeriod.inMilliseconds;
    if (milliseconds < 0 || milliseconds > 60000) {
      throw ArgumentError.value(
        gracePeriod,
        'gracePeriod',
        'must be between zero and 60 seconds',
      );
    }
    _checkStatus(_functions.sessionClose(_handle, milliseconds), 'PTY close');
  }

  @override
  void forceClose() {
    if (_finished || _disposed) {
      return;
    }
    _checkStatus(_functions.sessionForceClose(_handle), 'PTY force close');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    if (!_finished) {
      close();
      try {
        await exit;
      } on PtyException {
        // Native failure has already released the finished session.
      }
    }
    _disposed = true;
  }

  void _didStart(int pid) {
    if (_finished || _started.isCompleted) {
      _didFail(const PtyException('native PTY started more than once'));
      return;
    }
    _pid = pid;
    _started.complete();
  }

  void _didOutput(int sequence, Uint8List bytes) {
    final int status = _functions.sessionAckOutput(
      _handle,
      sequence,
      bytes.length,
    );
    if (status != _statusOk) {
      _didFail(
        PtyException(
          'native PTY output acknowledgement failed',
          status: status,
        ),
      );
      return;
    }
    if (!_finished) {
      _output.add(bytes);
    }
  }

  void _didExit(int exitCode, int signal) {
    if (_finished) {
      return;
    }
    _finished = true;
    _finalStats = _readStats();
    final int destroyStatus = _functions.sessionDestroy(_handle);
    _sessions.remove(_handle);
    _refreshCallbackKeepAlive();
    if (destroyStatus != _statusOk) {
      _didFail(
        PtyException('native PTY destroy failed', status: destroyStatus),
      );
      return;
    }
    if (!_started.isCompleted) {
      _started.completeError(
        const PtyException('native PTY exited before reporting start'),
      );
    }
    _exit.complete(
      PtyExit(exitCode: exitCode, signal: signal == 0 ? null : signal),
    );
    unawaited(_output.close());
  }

  void _didFail(PtyException error) {
    if (_finished && _exit.isCompleted) {
      return;
    }
    _finished = true;
    _finalStats = _readStats();
    _sessions.remove(_handle);
    _refreshCallbackKeepAlive();
    _functions.sessionDestroy(_handle);
    final bool failedBeforeStart = !_started.isCompleted;
    if (failedBeforeStart) {
      _started.completeError(error);
    }
    if (!failedBeforeStart && !_exit.isCompleted) {
      _exit.completeError(error);
    }
    _output.addError(error);
    unawaited(_output.close());
  }

  PtyStats? _readStats() {
    final Pointer<_NativeStats> stats = calloc<_NativeStats>();
    try {
      stats.ref
        ..structSize = sizeOf<_NativeStats>()
        ..abiVersion = _abiVersion;
      if (_functions.sessionGetStats(_handle, stats) != _statusOk) {
        return null;
      }
      return PtyStats(
        bytesRead: stats.ref.bytesRead,
        bytesWritten: stats.ref.bytesWritten,
        readBatches: stats.ref.readBatches,
        writeBackpressureRejections: stats.ref.writeBackpressureRejections,
        maxReadInFlightBytes: stats.ref.maxReadInFlightBytes,
        maxWriteQueuedBytes: stats.ref.maxWriteQueuedBytes,
        readPauseCount: stats.ref.readPauseCount,
        childPid: stats.ref.childPid,
        hasExited: stats.ref.hasExited != 0,
      );
    } finally {
      calloc.free(stats);
    }
  }

  void _requireRunning() {
    if (_finished || _disposed) {
      throw StateError('PTY process has finished');
    }
  }
}

void _checkStatus(int status, String operation) {
  if (status != _statusOk) {
    throw PtyException('$operation failed', status: status);
  }
}
