import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef NativeCapabilityInitializer = void Function({
  required String libraryPath,
  required int abiVersion,
  required String abiVersionSymbol,
  required String initializerSymbol,
});

final class MacosNativeCapabilityException implements Exception {
  const MacosNativeCapabilityException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : '$message (status $status)';
}

typedef _VersionNative = Uint32 Function();
typedef _VersionDart = int Function();
typedef _HostServicesNative = Pointer<Void> Function(Uint32);
typedef _HostServicesDart = Pointer<Void> Function(int);
typedef _InitializeNative = Int32 Function(Pointer<Void>);
typedef _InitializeDart = int Function(Pointer<Void>);

final class MacosNativeCapability {
  const MacosNativeCapability._(this.id, this.libraryPath);

  final String id;
  final String libraryPath;

  static final Map<String, MacosNativeCapability> _loaded =
      <String, MacosNativeCapability>{};
  static NativeCapabilityInitializer _initializer = _initializeNative;

  static MacosNativeCapability load(String id, {String? resolvedExecutable}) {
    final MacosNativeCapability? existing = _loaded[id];
    if (existing != null) {
      return existing;
    }
    final File executable = File(
      resolvedExecutable ?? Platform.resolvedExecutable,
    ).absolute;
    final Directory contents = executable.parent.parent;
    final File manifestFile = File(
      contents.uri
          .resolve('Resources/runtime-build-manifest.json')
          .toFilePath(),
    );
    if (!manifestFile.existsSync()) {
      throw const MacosNativeCapabilityException(
        'runtime native capability manifest is missing',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(manifestFile.readAsStringSync());
    } on Object catch (error) {
      throw MacosNativeCapabilityException(
        'runtime native capability manifest is invalid: $error',
      );
    }
    if (decoded is! Map<String, Object?> ||
        decoded['nativeCapabilities'] is! List<Object?>) {
      throw const MacosNativeCapabilityException(
        'runtime native capability manifest has no capability list',
      );
    }
    final List<Object?> values =
        decoded['nativeCapabilities']! as List<Object?>;
    Map<String, Object?>? declaration;
    for (final Object? value in values) {
      if (value is Map<String, Object?> && value['id'] == id) {
        if (declaration != null) {
          throw MacosNativeCapabilityException(
            'native capability is declared more than once: $id',
          );
        }
        declaration = value;
      }
    }
    if (declaration == null) {
      throw MacosNativeCapabilityException(
        'native capability is not declared by the application: $id',
      );
    }
    final String library = _manifestString(declaration, 'library', id);
    final String abiVersionSymbol = _manifestString(
      declaration,
      'abiVersionSymbol',
      id,
    );
    final String initializerSymbol = _manifestString(
      declaration,
      'initializerSymbol',
      id,
    );
    final Object? abiVersionValue = declaration['abiVersion'];
    if (abiVersionValue is! int || abiVersionValue <= 0) {
      throw MacosNativeCapabilityException(
        'native capability ABI is invalid: $id',
      );
    }
    if (!_libraryName.hasMatch(library) ||
        !_symbol.hasMatch(abiVersionSymbol) ||
        !_symbol.hasMatch(initializerSymbol)) {
      throw MacosNativeCapabilityException(
        'native capability library or symbol is invalid: $id',
      );
    }
    final File libraryFile = File(
      contents.uri.resolve('Frameworks/$library').toFilePath(),
    );
    if (!libraryFile.existsSync()) {
      throw MacosNativeCapabilityException(
        'native capability image is missing: ${libraryFile.path}',
      );
    }
    _initializer(
      libraryPath: libraryFile.path,
      abiVersion: abiVersionValue,
      abiVersionSymbol: abiVersionSymbol,
      initializerSymbol: initializerSymbol,
    );
    final MacosNativeCapability capability = MacosNativeCapability._(
      id,
      libraryFile.path,
    );
    _loaded[id] = capability;
    return capability;
  }

  static void _initializeNative({
    required String libraryPath,
    required int abiVersion,
    required String abiVersionSymbol,
    required String initializerSymbol,
  }) {
    final DynamicLibrary image;
    try {
      image = DynamicLibrary.open(libraryPath);
    } on ArgumentError catch (error) {
      throw MacosNativeCapabilityException(
        'could not load native capability image: $error',
      );
    }
    final _VersionDart readVersion;
    final _InitializeDart initialize;
    final _HostServicesDart hostServices;
    try {
      readVersion = image.lookupFunction<_VersionNative, _VersionDart>(
        abiVersionSymbol,
      );
      initialize = image.lookupFunction<_InitializeNative, _InitializeDart>(
        initializerSymbol,
      );
      hostServices = DynamicLibrary.process()
          .lookupFunction<_HostServicesNative, _HostServicesDart>(
            'da_native_extension_services',
          );
    } on ArgumentError catch (error) {
      throw MacosNativeCapabilityException(
        'native capability symbol is missing: $error',
      );
    }
    final int actualVersion = readVersion();
    if (actualVersion != abiVersion) {
      throw MacosNativeCapabilityException(
        'native capability ABI mismatch: expected $abiVersion, '
        'found $actualVersion',
      );
    }
    final Pointer<Void> services = hostServices(1);
    if (services == nullptr) {
      throw const MacosNativeCapabilityException(
        'AppKit native extension service ABI 1 is unavailable',
      );
    }
    final int status = initialize(services);
    if (status != 0) {
      throw MacosNativeCapabilityException(
        'native capability initialization failed',
        status: status,
      );
    }
    _retainedImages.add(image);
  }

  static final List<DynamicLibrary> _retainedImages = <DynamicLibrary>[];

  static void setInitializerForTesting(NativeCapabilityInitializer value) {
    _initializer = value;
  }

  static void resetForTesting() {
    _loaded.clear();
    _initializer = _initializeNative;
  }
}

String _manifestString(
  Map<String, Object?> declaration,
  String key,
  String id,
) {
  final Object? value = declaration[key];
  if (value is! String || value.isEmpty) {
    throw MacosNativeCapabilityException(
      'native capability $id has invalid $key',
    );
  }
  return value;
}

final RegExp _libraryName = RegExp(r'^lib[A-Za-z0-9._-]+\.dylib$');
final RegExp _symbol = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{1,127}$');
