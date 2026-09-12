part of '../api.dart';

enum SavePanelDisposition { selected, cancelled }

/// Copied, product-neutral presentation for one modal save-destination choice.
final class SavePanelConfiguration {
  SavePanelConfiguration({
    required this.title,
    required this.defaultFileName,
    this.message = '',
    this.prompt = '',
    this.allowedFileExtension = '',
    this.canCreateDirectories = true,
  }) {
    _validateDisplayText(title, 'title', required: true);
    _validateDisplayText(message, 'message');
    _validateDisplayText(prompt, 'prompt');
    final List<int> nameBytes = utf8.encode(defaultFileName);
    if (nameBytes.isEmpty ||
        nameBytes.length > dartAppKitSavePanelDefaultNameMaximumUtf8Bytes ||
        !_isSafeDisplayText(
          defaultFileName,
          dartAppKitSavePanelDefaultNameMaximumUtf8Bytes,
        ) ||
        defaultFileName.contains('/') ||
        defaultFileName == '.' ||
        defaultFileName == '..') {
      throw ArgumentError.value(
        defaultFileName,
        'defaultFileName',
        'must be a bounded safe filename without path separators',
      );
    }
    if (!_isValidExtension(allowedFileExtension)) {
      throw ArgumentError.value(
        allowedFileExtension,
        'allowedFileExtension',
        'must be empty or 1–$dartAppKitSavePanelExtensionMaximumUtf8Bytes '
            'lowercase ASCII letters, digits, plus, hyphen, or underscore',
      );
    }
  }

  final String title;
  final String message;
  final String prompt;
  final String defaultFileName;
  final String allowedFileExtension;
  final bool canCreateDirectories;

  NativeSavePanelConfiguration get _native => NativeSavePanelConfiguration(
    title: title,
    message: message,
    prompt: prompt,
    defaultFileName: defaultFileName,
    allowedFileExtension: allowedFileExtension,
    canCreateDirectories: canCreateDirectories,
  );

  static void _validateDisplayText(
    String value,
    String name, {
    bool required = false,
  }) {
    if (required && value.isEmpty ||
        !_isSafeDisplayText(
          value,
          dartAppKitSavePanelDisplayTextMaximumUtf8Bytes,
        )) {
      throw ArgumentError.value(
        value,
        name,
        'must be ${required ? 'nonempty ' : ''}bounded safe display text',
      );
    }
  }

  static bool _isValidExtension(String value) {
    final List<int> bytes = utf8.encode(value);
    if (bytes.length > dartAppKitSavePanelExtensionMaximumUtf8Bytes) {
      return false;
    }
    for (final int byte in bytes) {
      final bool accepted =
          byte >= 0x61 && byte <= 0x7a ||
          byte >= 0x30 && byte <= 0x39 ||
          byte == 0x2b ||
          byte == 0x2d ||
          byte == 0x5f;
      if (!accepted) return false;
    }
    return true;
  }
}

/// One copied modal result. A cancelled result never contains a path.
final class SavePanelResult {
  const SavePanelResult._(this.disposition, this.path);

  const SavePanelResult.selected(String path)
    : this._(SavePanelDisposition.selected, path);

  const SavePanelResult.cancelled()
    : this._(SavePanelDisposition.cancelled, null);

  final SavePanelDisposition disposition;
  final String? path;

  bool get isSelected => disposition == SavePanelDisposition.selected;
}
