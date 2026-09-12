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

enum MacosRunnerActivationPolicy { regular, accessory, prohibited }

final class MacosRunnerMessagePumpManifest {
  const MacosRunnerMessagePumpManifest({
    required this.maxMessagesPerTurn,
    required this.maxTimePerTurnMicros,
  });

  static const int defaultMaxMessagesPerTurn = 64;
  static const int maximumMaxMessagesPerTurn = 1024;
  static const int defaultMaxTimePerTurnMicros = 4000;
  static const int maximumMaxTimePerTurnMicros = 16000;

  final int maxMessagesPerTurn;
  final int maxTimePerTurnMicros;
}

final class MacosRunnerManifest {
  const MacosRunnerManifest({
    required this.activationPolicy,
    required this.activateOnLaunch,
    required this.terminateAfterLastWindowClosed,
    required this.reopenHandled,
    required this.messagePump,
  });

  final MacosRunnerActivationPolicy activationPolicy;
  final bool activateOnLaunch;
  final bool terminateAfterLastWindowClosed;
  final bool reopenHandled;
  final MacosRunnerMessagePumpManifest messagePump;
}

final class MacosNativeCapabilityManifest {
  const MacosNativeCapabilityManifest({
    required this.id,
    required this.package,
    required this.library,
    required this.abiVersion,
    required this.abiVersionSymbol,
    required this.initializerSymbol,
  });

  final String id;
  final String package;
  final String library;
  final int abiVersion;
  final String abiVersionSymbol;
  final String initializerSymbol;
}

final class MacosNativeAssetManifest {
  const MacosNativeAssetManifest({
    required this.id,
    required this.package,
    required this.library,
    required this.abiVersion,
    required this.abiVersionSymbol,
  });

  final String id;
  final String package;
  final String library;
  final int abiVersion;
  final String abiVersionSymbol;
}

final class MacosDartHelperManifest {
  const MacosDartHelperManifest({required this.name, required this.entrypoint});

  final String name;
  final String entrypoint;
}

enum MacosApplicationServiceAction { primary, secondary }

final class MacosApplicationServiceManifest {
  const MacosApplicationServiceManifest({
    required this.action,
    required this.menuItem,
  });

  static const int maximumMenuItemUtf8Bytes = 256;

  final MacosApplicationServiceAction action;
  final String menuItem;
}

final class MacosScriptingDefinitionManifest {
  const MacosScriptingDefinitionManifest({required this.path});

  static const int maximumPathUtf8Bytes = 1024;
  static const int maximumFileBytes = 1024 * 1024;

  final String path;

  String get bundleName => path.split('/').last;
}

/// One dependency-owned Swift App Intents module compiled into the app.
final class MacosAppIntentsManifest {
  const MacosAppIntentsManifest({
    required this.package,
    required this.source,
    required this.moduleName,
    required this.library,
  });

  static const int maximumSourcePathUtf8Bytes = 1024;
  static const int maximumSourceFileBytes = 1024 * 1024;
  static const int maximumMetadataFileBytes = 4 * 1024 * 1024;

  final String package;
  final String source;
  final String moduleName;
  final String library;
}

final class MacosApplicationManifest {
  const MacosApplicationManifest({
    required this.name,
    required this.executableName,
    required this.bundleIdentifier,
    required this.version,
    required this.minimumSystemVersion,
    required this.entrypoint,
    this.services = const <MacosApplicationServiceManifest>[],
    this.scriptingDefinition,
    this.appIntents,
    required this.dartHelpers,
    required this.resources,
    required this.nativeAssets,
    required this.nativeCapabilities,
    required this.diagnostics,
    required this.runner,
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
    _requiredAndOptionalKeys(
      root,
      const <String>{
        'schemaVersion',
        'application',
        'dart',
        'resources',
        'nativeCapabilities',
        'diagnostics',
      },
      const <String>{
        'dartHelpers',
        'nativeAssets',
        'runner',
        'services',
        'scriptingDefinition',
        'appIntents',
      },
      'manifest',
    );
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
    final Map<String, Object?> runner = switch (root['runner']) {
      null => const <String, Object?>{},
      final Object value => _object(value, 'manifest.runner'),
    };
    _requiredAndOptionalKeys(runner, const <String>{}, const <String>{
      'activationPolicy',
      'activateOnLaunch',
      'terminateAfterLastWindowClosed',
      'reopenHandled',
      'messagePump',
    }, 'manifest.runner');
    final Map<String, Object?> messagePump = switch (runner['messagePump']) {
      null => const <String, Object?>{},
      final Object value => _object(value, 'manifest.runner.messagePump'),
    };
    _requiredAndOptionalKeys(messagePump, const <String>{}, const <String>{
      'maxMessagesPerTurn',
      'maxTimePerTurnMicros',
    }, 'manifest.runner.messagePump');
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
    final Object? serviceValue = root['services'];
    final List<Object?> serviceValues = switch (serviceValue) {
      null => const <Object?>[],
      final List<Object?> value => value,
      _ => throw const MacosApplicationManifestException(
        'manifest.services must be an array',
      ),
    };
    final List<MacosApplicationServiceManifest> services =
        <MacosApplicationServiceManifest>[
          for (var index = 0; index < serviceValues.length; ++index)
            _applicationService(serviceValues[index], index),
        ];
    final MacosScriptingDefinitionManifest? scriptingDefinition =
        switch (root['scriptingDefinition']) {
          null => null,
          final Object value => _scriptingDefinition(value),
        };
    final MacosAppIntentsManifest? appIntents = switch (root['appIntents']) {
      null => null,
      final Object value => _appIntents(value),
    };
    final MacosRunnerActivationPolicy activationPolicy =
        switch (runner['activationPolicy']) {
          null => MacosRunnerActivationPolicy.regular,
          'regular' => MacosRunnerActivationPolicy.regular,
          'accessory' => MacosRunnerActivationPolicy.accessory,
          'prohibited' => MacosRunnerActivationPolicy.prohibited,
          _ => throw const MacosApplicationManifestException(
            'runner.activationPolicy must be regular, accessory, or prohibited',
          ),
        };
    final bool activateOnLaunch = _optionalBoolean(
      runner['activateOnLaunch'],
      'runner.activateOnLaunch',
      defaultValue: true,
    );
    final bool terminateAfterLastWindowClosed = _optionalBoolean(
      runner['terminateAfterLastWindowClosed'],
      'runner.terminateAfterLastWindowClosed',
      defaultValue: false,
    );
    final bool reopenHandled = _optionalBoolean(
      runner['reopenHandled'],
      'runner.reopenHandled',
      defaultValue: true,
    );
    final int maxMessagesPerTurn = _optionalBoundedInteger(
      messagePump['maxMessagesPerTurn'],
      'runner.messagePump.maxMessagesPerTurn',
      defaultValue: MacosRunnerMessagePumpManifest.defaultMaxMessagesPerTurn,
      maximum: MacosRunnerMessagePumpManifest.maximumMaxMessagesPerTurn,
    );
    final int maxTimePerTurnMicros = _optionalBoundedInteger(
      messagePump['maxTimePerTurnMicros'],
      'runner.messagePump.maxTimePerTurnMicros',
      defaultValue: MacosRunnerMessagePumpManifest.defaultMaxTimePerTurnMicros,
      maximum: MacosRunnerMessagePumpManifest.maximumMaxTimePerTurnMicros,
    );
    final Object? helperValue = root['dartHelpers'];
    final List<Object?> helperValues = switch (helperValue) {
      null => const <Object?>[],
      final List<Object?> value => value,
      _ => throw const MacosApplicationManifestException(
        'manifest.dartHelpers must be an array',
      ),
    };
    final List<MacosDartHelperManifest> dartHelpers = <MacosDartHelperManifest>[
      for (var index = 0; index < helperValues.length; ++index)
        _dartHelper(helperValues[index], index),
    ];
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
    final List<Object?> capabilityValues = switch (root['nativeCapabilities']) {
      final List<Object?> value => value,
      _ => throw const MacosApplicationManifestException(
        'manifest.nativeCapabilities must be an array',
      ),
    };
    final List<MacosNativeCapabilityManifest> nativeCapabilities =
        <MacosNativeCapabilityManifest>[
          for (var index = 0; index < capabilityValues.length; ++index)
            _capability(capabilityValues[index], index),
        ];
    final Object? nativeAssetValue = root['nativeAssets'];
    final List<Object?> nativeAssetValues = switch (nativeAssetValue) {
      null => const <Object?>[],
      final List<Object?> value => value,
      _ => throw const MacosApplicationManifestException(
        'manifest.nativeAssets must be an array',
      ),
    };
    final List<MacosNativeAssetManifest> nativeAssets =
        <MacosNativeAssetManifest>[
          for (var index = 0; index < nativeAssetValues.length; ++index)
            _nativeAsset(nativeAssetValues[index], index),
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
    if (!_safeFileName(executableName)) {
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
    if (scriptingDefinition != null &&
        resources.contains(scriptingDefinition.bundleName)) {
      throw const MacosApplicationManifestException(
        'manifest.scriptingDefinition conflicts with a bundled resource',
      );
    }
    if (appIntents != null &&
        !_minimumMacosVersionAtLeast13(minimumSystemVersion)) {
      throw const MacosApplicationManifestException(
        'manifest.appIntents requires application.minimumSystemVersion 13.0 or later',
      );
    }
    if (resources.any(
      (String path) =>
          path == 'Metadata.appintents' ||
          path.startsWith('Metadata.appintents/'),
    )) {
      throw const MacosApplicationManifestException(
        'manifest.resources reserves Metadata.appintents for the runtime',
      );
    }
    if (services.map((value) => value.action).toSet().length !=
        services.length) {
      throw const MacosApplicationManifestException(
        'manifest.services contains a duplicate action',
      );
    }
    if (services.map((value) => value.menuItem).toSet().length !=
        services.length) {
      throw const MacosApplicationManifestException(
        'manifest.services contains a duplicate menu item',
      );
    }
    if (dartHelpers.map((value) => value.name).toSet().length !=
        dartHelpers.length) {
      throw const MacosApplicationManifestException(
        'manifest.dartHelpers contains a duplicate name',
      );
    }
    if (nativeCapabilities.map((value) => value.id).toSet().length !=
        nativeCapabilities.length) {
      throw const MacosApplicationManifestException(
        'manifest.nativeCapabilities contains a duplicate id',
      );
    }
    final List<String> nativeIds = <String>[
      ...nativeAssets.map((MacosNativeAssetManifest value) => value.id),
      ...nativeCapabilities.map(
        (MacosNativeCapabilityManifest value) => value.id,
      ),
    ];
    final List<String> nativeLibraries = <String>[
      ...nativeAssets.map((MacosNativeAssetManifest value) => value.library),
      ...nativeCapabilities.map(
        (MacosNativeCapabilityManifest value) => value.library,
      ),
      if (appIntents != null) appIntents.library,
    ];
    if (nativeIds.toSet().length != nativeIds.length ||
        nativeLibraries.toSet().length != nativeLibraries.length) {
      throw const MacosApplicationManifestException(
        'manifest native asset ids and libraries must be unique',
      );
    }
    return MacosApplicationManifest(
      name: name,
      executableName: executableName,
      bundleIdentifier: bundleIdentifier,
      version: version,
      minimumSystemVersion: minimumSystemVersion,
      entrypoint: entrypoint,
      services: List<MacosApplicationServiceManifest>.unmodifiable(services),
      scriptingDefinition: scriptingDefinition,
      appIntents: appIntents,
      dartHelpers: List<MacosDartHelperManifest>.unmodifiable(dartHelpers),
      resources: List<String>.unmodifiable(resources),
      nativeAssets: List<MacosNativeAssetManifest>.unmodifiable(nativeAssets),
      nativeCapabilities: List<MacosNativeCapabilityManifest>.unmodifiable(
        nativeCapabilities,
      ),
      diagnostics: MacosDiagnosticsManifest(
        enabled: enabledValue,
        applicationSupportName: supportName,
      ),
      runner: MacosRunnerManifest(
        activationPolicy: activationPolicy,
        activateOnLaunch: activateOnLaunch,
        terminateAfterLastWindowClosed: terminateAfterLastWindowClosed,
        reopenHandled: reopenHandled,
        messagePump: MacosRunnerMessagePumpManifest(
          maxMessagesPerTurn: maxMessagesPerTurn,
          maxTimePerTurnMicros: maxTimePerTurnMicros,
        ),
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
  final List<MacosApplicationServiceManifest> services;
  final MacosScriptingDefinitionManifest? scriptingDefinition;
  final MacosAppIntentsManifest? appIntents;
  final List<MacosDartHelperManifest> dartHelpers;
  final List<String> resources;
  final List<MacosNativeAssetManifest> nativeAssets;
  final List<MacosNativeCapabilityManifest> nativeCapabilities;
  final MacosDiagnosticsManifest diagnostics;
  final MacosRunnerManifest runner;

  static final RegExp _identifier = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9.-]{2,127}$',
  );
  static final RegExp _fileName = RegExp(r'^[A-Za-z0-9._-]+$');
  static bool _safeFileName(String value) =>
      value != '.' && value != '..' && _fileName.hasMatch(value);
  static final RegExp _version = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.+-]{0,63}$');
  static final RegExp _minimumVersion = RegExp(
    r'^[0-9]+\.[0-9]+(?:\.[0-9]+)?$',
  );
}

MacosAppIntentsManifest _appIntents(Object? value) {
  const String path = 'manifest.appIntents';
  final Map<String, Object?> object = _object(value, path);
  _exactKeys(object, const <String>{
    'package',
    'source',
    'moduleName',
    'library',
  }, path);
  final String package = _string(object['package'], '$path.package');
  final String source = _relativePath(
    _string(object['source'], '$path.source'),
    '$path.source',
  );
  final String moduleName = _string(object['moduleName'], '$path.moduleName');
  final String library = _string(object['library'], '$path.library');
  if (!_packageName.hasMatch(package) ||
      !source.endsWith('.swift') ||
      utf8.encode(source).length >
          MacosAppIntentsManifest.maximumSourcePathUtf8Bytes ||
      !_swiftModuleName.hasMatch(moduleName) ||
      !_libraryName.hasMatch(library)) {
    throw const MacosApplicationManifestException(
      'manifest.appIntents contains an invalid package, Swift source, module, or library',
    );
  }
  return MacosAppIntentsManifest(
    package: package,
    source: source,
    moduleName: moduleName,
    library: library,
  );
}

bool _minimumMacosVersionAtLeast13(String value) {
  final int major = int.parse(value.split('.').first);
  return major >= 13;
}

MacosScriptingDefinitionManifest _scriptingDefinition(Object? value) {
  const String path = 'manifest.scriptingDefinition';
  final Map<String, Object?> object = _object(value, path);
  _exactKeys(object, const <String>{'path'}, path);
  final String source = _relativePath(
    _string(object['path'], '$path.path'),
    '$path.path',
  );
  if (!source.endsWith('.sdef') ||
      utf8.encode(source).length >
          MacosScriptingDefinitionManifest.maximumPathUtf8Bytes) {
    throw const MacosApplicationManifestException(
      'manifest.scriptingDefinition.path must be a bounded .sdef path',
    );
  }
  return MacosScriptingDefinitionManifest(path: source);
}

MacosApplicationServiceManifest _applicationService(Object? value, int index) {
  final String path = 'services[$index]';
  final Map<String, Object?> object = _object(value, path);
  _exactKeys(object, const <String>{'action', 'menuItem'}, path);
  final MacosApplicationServiceAction action = switch (object['action']) {
    'primary' => MacosApplicationServiceAction.primary,
    'secondary' => MacosApplicationServiceAction.secondary,
    _ => throw MacosApplicationManifestException(
      '$path.action must be primary or secondary',
    ),
  };
  final String menuItem = _string(object['menuItem'], '$path.menuItem');
  if (!_safeServiceMenuItem(menuItem)) {
    throw MacosApplicationManifestException(
      '$path.menuItem must be bounded display-safe text without a slash',
    );
  }
  return MacosApplicationServiceManifest(action: action, menuItem: menuItem);
}

bool _safeServiceMenuItem(String value) {
  if (value.trim() != value ||
      value.contains('/') ||
      utf8.encode(value).length >
          MacosApplicationServiceManifest.maximumMenuItemUtf8Bytes) {
    return false;
  }
  for (final int scalar in value.runes) {
    final bool unsafe =
        scalar <= 0x1f ||
        scalar >= 0x7f && scalar <= 0x9f ||
        scalar == 0xa0 ||
        scalar == 0xad ||
        scalar == 0x61c ||
        scalar == 0x1680 ||
        scalar == 0x180e ||
        scalar >= 0x2000 && scalar <= 0x200f ||
        scalar >= 0x2028 && scalar <= 0x202f ||
        scalar >= 0x205f && scalar <= 0x206f ||
        scalar == 0x3000 ||
        scalar == 0xfeff;
    if (unsafe) return false;
  }
  return true;
}

bool _optionalBoolean(
  Object? value,
  String path, {
  required bool defaultValue,
}) {
  if (value == null) {
    return defaultValue;
  }
  if (value is! bool) {
    throw MacosApplicationManifestException('$path must be a boolean');
  }
  return value;
}

int _optionalBoundedInteger(
  Object? value,
  String path, {
  required int defaultValue,
  required int maximum,
}) {
  if (value == null) {
    return defaultValue;
  }
  if (value is! int) {
    throw MacosApplicationManifestException('$path must be an integer');
  }
  if (value <= 0 || value > maximum) {
    throw MacosApplicationManifestException(
      '$path must be positive and no greater than $maximum',
    );
  }
  return value;
}

MacosDartHelperManifest _dartHelper(Object? value, int index) {
  final String path = 'dartHelpers[$index]';
  final Map<String, Object?> object = _object(value, path);
  _exactKeys(object, const <String>{'name', 'entrypoint'}, path);
  final String name = _string(object['name'], '$path.name');
  if (!MacosApplicationManifest._safeFileName(name)) {
    throw MacosApplicationManifestException(
      '$path.name must contain only letters, digits, ._-',
    );
  }
  return MacosDartHelperManifest(
    name: name,
    entrypoint: _relativePath(
      _string(object['entrypoint'], '$path.entrypoint'),
      '$path.entrypoint',
    ),
  );
}

MacosNativeAssetManifest _nativeAsset(Object? value, int index) {
  final String path = 'nativeAssets[$index]';
  final Map<String, Object?> object = _object(value, path);
  _exactKeys(object, const <String>{
    'id',
    'package',
    'library',
    'abiVersion',
    'abiVersionSymbol',
  }, path);
  final String id = _string(object['id'], '$path.id');
  final String package = _string(object['package'], '$path.package');
  final String library = _string(object['library'], '$path.library');
  final String abiVersionSymbol = _string(
    object['abiVersionSymbol'],
    '$path.abiVersionSymbol',
  );
  final Object? abiVersionValue = object['abiVersion'];
  if (!_capabilityId.hasMatch(id) ||
      !_packageName.hasMatch(package) ||
      !_libraryName.hasMatch(library) ||
      !_symbol.hasMatch(abiVersionSymbol) ||
      abiVersionValue is! int ||
      abiVersionValue <= 0 ||
      abiVersionValue > 65535) {
    throw MacosApplicationManifestException(
      '$path contains an invalid asset identifier, library, symbol, or ABI',
    );
  }
  return MacosNativeAssetManifest(
    id: id,
    package: package,
    library: library,
    abiVersion: abiVersionValue,
    abiVersionSymbol: abiVersionSymbol,
  );
}

MacosNativeCapabilityManifest _capability(Object? value, int index) {
  final String path = 'nativeCapabilities[$index]';
  final Map<String, Object?> object = _object(value, path);
  _exactKeys(object, const <String>{
    'id',
    'package',
    'library',
    'abiVersion',
    'abiVersionSymbol',
    'initializerSymbol',
  }, path);
  final String id = _string(object['id'], '$path.id');
  final String package = _string(object['package'], '$path.package');
  final String library = _string(object['library'], '$path.library');
  final Object? abiVersionValue = object['abiVersion'];
  if (!_capabilityId.hasMatch(id) ||
      !_packageName.hasMatch(package) ||
      !_libraryName.hasMatch(library) ||
      !_symbol.hasMatch(
        _string(object['abiVersionSymbol'], '$path.abiVersionSymbol'),
      ) ||
      !_symbol.hasMatch(
        _string(object['initializerSymbol'], '$path.initializerSymbol'),
      ) ||
      abiVersionValue is! int ||
      abiVersionValue <= 0 ||
      abiVersionValue > 65535) {
    throw MacosApplicationManifestException(
      '$path contains an invalid capability identifier, library, symbol, or ABI',
    );
  }
  return MacosNativeCapabilityManifest(
    id: id,
    package: package,
    library: library,
    abiVersion: abiVersionValue,
    abiVersionSymbol: object['abiVersionSymbol']! as String,
    initializerSymbol: object['initializerSymbol']! as String,
  );
}

final RegExp _capabilityId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$');
final RegExp _packageName = RegExp(r'^[a-z][a-z0-9_]{1,63}$');
final RegExp _libraryName = RegExp(r'^lib[A-Za-z0-9._-]+\.dylib$');
final RegExp _symbol = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{1,127}$');
final RegExp _swiftModuleName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{1,127}$');

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

void _requiredAndOptionalKeys(
  Map<String, Object?> value,
  Set<String> required,
  Set<String> optional,
  String path,
) {
  final Set<String> actual = value.keys.toSet();
  final Set<String> allowed = <String>{...required, ...optional};
  if (!actual.containsAll(required) || actual.difference(allowed).isNotEmpty) {
    throw MacosApplicationManifestException(
      '$path must contain ${required.join(', ')} and only optional keys: '
      '${optional.join(', ')}',
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
