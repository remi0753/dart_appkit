import 'dart:io';

import 'package:dart_appkit/src/tool/launcher.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runLauncherCommand(arguments);
}
