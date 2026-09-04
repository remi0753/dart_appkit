import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_macos_runtime/dart_macos_runtime.dart';

const String exampleViewCapabilityId = 'dart_appkit_example_view';
const String exampleViewProviderIdentifier = 'dev.dart-appkit.example-view';

abstract final class ExampleViewCapability {
  static MacosNativeCapability? _capability;

  static void initialize() {
    _capability ??= MacosNativeCapability.load(exampleViewCapabilityId);
  }

  static View createView() {
    if (_capability == null) {
      throw StateError('ExampleViewCapability.initialize() must be called');
    }
    return View.custom(exampleViewProviderIdentifier);
  }
}
