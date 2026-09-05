import 'dart:io';

import 'font_catalog_test.dart';
import 'native_asset_test.dart';
import 'raster_test.dart';
import 'shaping_test.dart';

void main() {
  runNativeAssetTests();
  runFontCatalogTests();
  runRasterTests();
  runShapingTests();
  if (exitCode != 0) {
    throw StateError('terminal renderer native asset smoke failed');
  }
  stdout.writeln('terminal renderer Dart tests passed');
}
