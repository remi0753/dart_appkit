import 'dart:convert';
import 'dart:io';

final class MacosApplicationManifestException implements Exception {
  const MacosApplicationManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class MacosDiagnosticsManifest {
  const MacosDiagnosticsManifest({
    required this.enabled,
    required this.applicationSupportName,
  });

  final bool enabled;
  final String applicationSupportName;
}

final class MacosApplicationManifest {
  const MacosApplicationManifest({
    required this.name,
    required this.executableName,
    required this.bundleIdentifier,
    required this.version,
    required this.minimumSystemVersion,
    required this.entrypoint,
    required this.resources,
    required this.diagnostics,
  });

  factory MacosApplicationManifest.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw MacosApplicationManifestException(
        'manifest is not valid JSON: ${error.message}',
      );
    }
    final Map<String, Object?> root = _object(decoded, 'manifest');
    _exactKeys(root, const <String>{
      'schemaVersion',
      'application',
      'dart',
      'resources',
      'diagnostics',
    }, 'manifest');
    if (root['schemaVersion'] != 1) {
      throw const MacosApplicationManifestException(
        'manifest.schemaVersion must be 1',
      );
    }

    final Map<String, Object?> application = _object(
      root['application'],
      'manifest.application',
    );
    _exactKeys(application, const <String>{
      'name',
      'executableName',
      'bundleIdentifier',
      'version',
      'minimumSystemVersion',
    }, 'manifest.application');
    final Map<String, Object?> dart = _object(root['dart'], 'manifest.dart');
    _exactKeys(dart, const <String>{'entrypoint'}, 'manifest.dart');
    final Map<String, Object?> diagnostics = _object(
      root['diagnostics'],
      'manifest.diagnostics',
    );
    _exactKeys(diagnostics, const <String>{
      'enabled',
      'applicationSupportName',
    }, 'manifest.diagnostics');

    final String name = _string(application['name'], 'application.name');
    final String executableName = _string(
      application['executableName'],
      'application.executableName',
    );
    final String bundleIdentifier = _string(
      application['bundleIdentifier'],
      'application.bundleIdentifier',
    );
    final String version = _string(
      application['version'],
      'application.version',
    );
    final String minimumSystemVersion = _string(
      application['minimumSystemVersion'],
      'application.minimumSystemVersion',
    );
    final String entrypoint = _relativePath(
      _string(dart['entrypoint'], 'dart.entrypoint'),
      'dart.entrypoint',
    );
    final List<Object?> resourceValues = switch (root['resources']) {
      final List<Object?> value => value,
      _ => throw const MacosApplicationManifestException(
        'manifest.resources must be an array',
      ),
    };
    final List<String> resources = <String>[
      for (var index = 0; index < resourceValues.length; ++index)
        _relativePath(
          _string(resourceValues[index], 'resources[$index]'),
          'resources[$index]',
        ),
    ];
    final Object? enabledValue = diagnostics['enabled'];
    if (enabledValue is! bool) {
      throw const MacosApplicationManifestException(
        'diagnostics.enabled must be a boolean',
      );
    }
    final String supportName = _string(
      diagnostics['applicationSupportName'],
      'diagnostics.applicationSupportName',
    );

    if (!_identifier.hasMatch(bundleIdentifier)) {
      throw const MacosApplicationManifestException(
        'application.bundleIdentifier is invalid',
      );
    }
    if (!_fileName.hasMatch(executableName)) {
      throw const MacosApplicationManifestException(
        'application.executableName must contain only letters, digits, ._-',
      );
    }
    if (!_version.hasMatch(version) ||
        !_minimumVersion.hasMatch(minimumSystemVersion)) {
      throw const MacosApplicationManifestException(
        'application version fields are invalid',
      );
    }
    if (resources.toSet().length != resources.length) {
      throw const MacosApplicationManifestException(
        'manifest.resources contains a duplicate path',
      );
    }
    return MacosApplicationManifest(
      name: name,
      executableName: executableName,
      bundleIdentifier: bundleIdentifier,
      version: version,
      minimumSystemVersion: minimumSystemVersion,
      entrypoint: entrypoint,
      resources: List<String>.unmodifiable(resources),
      diagnostics: MacosDiagnosticsManifest(
        enabled: enabledValue,
        applicationSupportName: supportName,
      ),
    );
  }

  static Future<MacosApplicationManifest> load(File file) async {
    try {
      return MacosApplicationManifest.parse(await file.readAsString());
    } on FileSystemException catch (error) {
      throw MacosApplicationManifestException(
        'could not read manifest ${file.path}: ${error.message}',
      );
    }
  }

  final String name;
  final String executableName;
  final String bundleIdentifier;
  final String version;
  final String minimumSystemVersion;
  final String entrypoint;
  final List<String> resources;
  final MacosDiagnosticsManifest diagnostics;

  static final RegExp _identifier = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9.-]{2,127}$',
  );
  static final RegExp _fileName = RegExp(r'^[A-Za-z0-9._-]+$');
  static final RegExp _version = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.+-]{0,63}$');
  static final RegExp _minimumVersion = RegExp(
    r'^[0-9]+\.[0-9]+(?:\.[0-9]+)?$',
  );
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw MacosApplicationManifestException('$path must be an object');
  }
  return value;
}

void _exactKeys(Map<String, Object?> value, Set<String> expected, String path) {
  final Set<String> actual = value.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw MacosApplicationManifestException(
      '$path must contain exactly: ${expected.join(', ')}',
    );
  }
}

String _string(Object? value, String path) {
  if (value is! String || value.isEmpty || value.contains('\u0000')) {
    throw MacosApplicationManifestException('$path must be a non-empty string');
  }
  return value;
}

String _relativePath(String value, String path) {
  final Uri uri = Uri.file(value);
  final List<String> segments = value.split('/');
  if (uri.isAbsolute ||
      value.contains('\\') ||
      segments.contains('') ||
      segments.contains('.') ||
      segments.contains('..')) {
    throw MacosApplicationManifestException(
      '$path must be a normalized relative path',
    );
  }
  return value;
}
