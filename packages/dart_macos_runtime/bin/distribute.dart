import 'dart:io';

import 'package:dart_macos_runtime/src/tool/distribution_publisher.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runDistributionPublisherCommand(arguments);
}
