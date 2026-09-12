import 'dart:io';

import 'package:dart_macos_runtime/src/tool/universal_assembler.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runUniversalAssemblerCommand(arguments);
}
