import 'dart:io';

import 'package:dart_appkit/src/native/ffi_native_bindings.dart';
import 'package:dart_appkit/src/native/native_bindings.dart';

Never _fail(String message) {
  stderr.writeln('legacy event bridge smoke test failed: $message');
  exit(1);
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    _fail('expected one legacy bridge dylib path');
  }
  final FfiNativeBindings bindings = FfiNativeBindings.open(arguments.single);
  final NativeValueResult<int> compatible = bindings
      .applicationSetEventPortVersioned(
        port: 4242,
        minimumVersion: 1,
        maximumVersion: 2,
      );
  if (!compatible.isSuccess || compatible.value != 1) {
    _fail('new Dart bindings did not fall back to legacy version 1');
  }

  final NativeValueResult<int> incompatible = bindings
      .applicationSetEventPortVersioned(
        port: 4242,
        minimumVersion: 2,
        maximumVersion: 2,
      );
  if (incompatible.isSuccess || incompatible.status != 8) {
    _fail('legacy fallback accepted an unsupported event version');
  }
  final NativeValueResult<int> malformed = bindings
      .applicationSetEventPortVersioned(
        port: 4242,
        minimumVersion: 0,
        maximumVersion: 2,
      );
  if (malformed.isSuccess || malformed.status != 1) {
    _fail('legacy fallback accepted an invalid event version range');
  }
  final NativeValueResult<int> genericView = bindings.viewCreate();
  if (genericView.isSuccess || genericView.status != 8) {
    _fail('legacy bridge did not reject the additive generic-view API');
  }
  stdout.writeln('legacy event bridge fallback smoke test passed');
}
