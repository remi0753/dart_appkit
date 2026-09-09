part of '../api.dart';

/// Immutable application conditions for one lowercase URL scheme.
final class ExternalUrlSchemePolicy {
  factory ExternalUrlSchemePolicy({
    required String scheme,
    bool requiresAuthority = false,
    bool allowsAuthority = true,
    bool requiresHost = false,
    bool allowsCredentials = false,
    bool requiresPath = false,
  }) {
    final String normalizedScheme = scheme.toLowerCase();
    if (scheme.isEmpty ||
        !_isAsciiScheme(scheme) ||
        utf8.encode(normalizedScheme).length >
            dartAppKitExternalUrlSchemeMaximumUtf8Bytes) {
      throw ArgumentError.value(
        scheme,
        'scheme',
        'must be a non-empty ASCII URL scheme within the byte limit',
      );
    }
    if (!allowsAuthority && (requiresAuthority || requiresHost)) {
      throw ArgumentError.value(
        allowsAuthority,
        'allowsAuthority',
        'cannot forbid authority while requiring authority or host',
      );
    }
    return ExternalUrlSchemePolicy._(
      scheme: normalizedScheme,
      requiresAuthority: requiresAuthority,
      allowsAuthority: allowsAuthority,
      requiresHost: requiresHost,
      allowsCredentials: allowsCredentials,
      requiresPath: requiresPath,
    );
  }

  const ExternalUrlSchemePolicy._({
    required this.scheme,
    required this.requiresAuthority,
    required this.allowsAuthority,
    required this.requiresHost,
    required this.allowsCredentials,
    required this.requiresPath,
  });

  final String scheme;
  final bool requiresAuthority;
  final bool allowsAuthority;
  final bool requiresHost;
  final bool allowsCredentials;
  final bool requiresPath;

  int get _nativeFlags =>
      (requiresAuthority ? dartAppKitExternalUrlPolicyRequireAuthority : 0) |
      (!allowsAuthority ? dartAppKitExternalUrlPolicyForbidAuthority : 0) |
      (requiresHost ? dartAppKitExternalUrlPolicyRequireHost : 0) |
      (!allowsCredentials ? dartAppKitExternalUrlPolicyForbidCredentials : 0) |
      (requiresPath ? dartAppKitExternalUrlPolicyRequirePath : 0);
}

/// Immutable deny-by-default set of application-owned URL scheme rules.
final class ExternalUrlPolicy {
  factory ExternalUrlPolicy(Iterable<ExternalUrlSchemePolicy> schemes) {
    final Map<String, ExternalUrlSchemePolicy> rules =
        <String, ExternalUrlSchemePolicy>{};
    for (final ExternalUrlSchemePolicy rule in schemes) {
      if (rules.containsKey(rule.scheme)) {
        throw ArgumentError.value(
          rule.scheme,
          'schemes',
          'contains a duplicate scheme',
        );
      }
      rules[rule.scheme] = rule;
    }
    return ExternalUrlPolicy._(
      Map<String, ExternalUrlSchemePolicy>.unmodifiable(rules),
    );
  }

  const ExternalUrlPolicy._(this._rules);

  /// Compatibility policy for HTTP, HTTPS, and non-authority mailto URLs.
  static final ExternalUrlPolicy defaultPolicy = ExternalUrlPolicy(
    <ExternalUrlSchemePolicy>[
      ExternalUrlSchemePolicy(
        scheme: 'http',
        requiresAuthority: true,
        requiresHost: true,
      ),
      ExternalUrlSchemePolicy(
        scheme: 'https',
        requiresAuthority: true,
        requiresHost: true,
      ),
      ExternalUrlSchemePolicy(
        scheme: 'mailto',
        allowsAuthority: false,
        requiresPath: true,
      ),
    ],
  );

  final Map<String, ExternalUrlSchemePolicy> _rules;

  List<ExternalUrlSchemePolicy> get schemes =>
      List<ExternalUrlSchemePolicy>.unmodifiable(_rules.values);

  ExternalUrlSchemePolicy? policyForScheme(String scheme) =>
      _rules[scheme.toLowerCase()];
}

/// An absolute external URL that passed an immutable application policy.
///
/// Instances can only be created by [parse] or [tryParse]. Passing this type to
/// [AppKitApplication.openExternalUrl] makes validation an explicit caller-side
/// step. The native bridge repeats the validation before reaching AppKit.
final class AllowedExternalUrl {
  const AllowedExternalUrl._(this.value, this.scheme);

  /// Maximum UTF-8 size accepted by both the Dart and native boundaries.
  static const int maximumUtf8Bytes = dartAppKitExternalUrlMaximumUtf8Bytes;

  /// Parses [source] or throws [FormatException] when it is not safe to open.
  factory AllowedExternalUrl.parse(String source, {ExternalUrlPolicy? policy}) {
    final AllowedExternalUrl? result = tryParse(source, policy: policy);
    if (result == null) {
      throw FormatException('external URL is not allowed', source);
    }
    return result;
  }

  /// Returns an allowlisted URL, or `null` for malformed or unsafe input.
  static AllowedExternalUrl? tryParse(
    String source, {
    ExternalUrlPolicy? policy,
  }) {
    if (source.isEmpty ||
        source.length > maximumUtf8Bytes ||
        _containsMalformedUtf16(source) ||
        utf8.encode(source).length > maximumUtf8Bytes) {
      return null;
    }
    if (_containsUnsafeScalar(source) || _containsUnsafeEscape(source)) {
      return null;
    }

    final int colon = source.indexOf(':');
    if (colon <= 0) {
      return null;
    }
    final String rawScheme = source.substring(0, colon);
    if (!_isAsciiScheme(rawScheme)) {
      return null;
    }
    final String scheme = rawScheme.toLowerCase();
    final ExternalUrlSchemePolicy? schemePolicy =
        (policy ?? ExternalUrlPolicy.defaultPolicy).policyForScheme(scheme);
    if (schemePolicy == null) {
      return null;
    }

    final Uri? uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme.isEmpty ||
        uri.scheme.toLowerCase() != scheme) {
      return null;
    }
    if (schemePolicy.requiresAuthority && !uri.hasAuthority ||
        !schemePolicy.allowsAuthority && uri.hasAuthority ||
        schemePolicy.requiresHost && uri.host.isEmpty ||
        !schemePolicy.allowsCredentials && uri.userInfo.isNotEmpty ||
        schemePolicy.requiresPath && uri.path.isEmpty) {
      return null;
    }
    return AllowedExternalUrl._(source, scheme);
  }

  /// The exact validated URL text passed to the native bridge.
  final String value;

  /// Lowercase ASCII scheme selected by the parsing policy.
  final String scheme;

  @override
  String toString() => value;
}

bool _containsMalformedUtf16(String value) {
  for (int index = 0; index < value.length; index += 1) {
    final int unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= value.length) return true;
      final int next = value.codeUnitAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) return true;
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return true;
    }
  }
  return false;
}

bool _isAsciiScheme(String value) {
  for (int index = 0; index < value.length; index += 1) {
    final int unit = value.codeUnitAt(index);
    final bool alpha =
        (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);
    final bool continuation =
        alpha ||
        (unit >= 0x30 && unit <= 0x39) ||
        unit == 0x2b ||
        unit == 0x2d ||
        unit == 0x2e;
    if ((index == 0 && !alpha) || (index > 0 && !continuation)) {
      return false;
    }
  }
  return true;
}

bool _containsUnsafeScalar(String value) {
  for (final int scalar in value.runes) {
    if (_isUnsafeScalar(scalar, allowAsciiSpace: false)) {
      return true;
    }
  }
  return false;
}

bool _containsUnsafeEscape(String value) {
  for (int index = 0; index < value.length; index += 1) {
    if (value.codeUnitAt(index) != 0x25) {
      continue;
    }
    if (index + 2 >= value.length) {
      return true;
    }
    final int high = _hexValue(value.codeUnitAt(index + 1));
    final int low = _hexValue(value.codeUnitAt(index + 2));
    if (high < 0 || low < 0) {
      return true;
    }
    final int byte = (high << 4) | low;
    if (byte <= 0x1f || byte == 0x5c || byte == 0x7f) {
      return true;
    }
    index += 2;
  }
  try {
    final String decoded = Uri.decodeComponent(value);
    if (decoded != value) {
      for (final int scalar in decoded.runes) {
        if (_isUnsafeScalar(scalar, allowAsciiSpace: true)) {
          return true;
        }
      }
    }
    return false;
  } on FormatException {
    return true;
  }
}

bool _isUnsafeScalar(int scalar, {required bool allowAsciiSpace}) {
  return scalar < 0x20 ||
      (scalar == 0x20 && !allowAsciiSpace) ||
      scalar == 0x5c ||
      (scalar >= 0x7f && scalar <= 0x9f) ||
      scalar == 0xa0 ||
      scalar == 0xad ||
      scalar == 0x61c ||
      scalar == 0x1680 ||
      scalar == 0x180e ||
      (scalar >= 0x2000 && scalar <= 0x200f) ||
      (scalar >= 0x2028 && scalar <= 0x202f) ||
      (scalar >= 0x205f && scalar <= 0x206f) ||
      scalar == 0x3000 ||
      scalar == 0xfeff;
}

int _hexValue(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  if (unit >= 0x41 && unit <= 0x46) return unit - 0x41 + 10;
  if (unit >= 0x61 && unit <= 0x66) return unit - 0x61 + 10;
  return -1;
}
