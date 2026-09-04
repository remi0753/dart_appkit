import 'dart:io';

import 'package:dart_macos_runtime/src/tool/builder.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runBuilderCommand(arguments);
}
