import 'dart:ffi';
import 'dart:io';

@Native<Uint32 Function()>(
  symbol: 'daev_abi_version',
  assetId: 'package:dart_appkit_example_view/dart_appkit_example_view.dart',
)
external int _abiVersion();

@Native<Int32 Function()>(
  symbol: 'daev_debug_live_view_count',
  assetId: 'package:dart_appkit_example_view/dart_appkit_example_view.dart',
)
external int _liveViewCount();

void main() {
  if (_abiVersion() != 1) {
    stderr.writeln('unexpected example-view native asset ABI');
    exitCode = 1;
  }
  if (_liveViewCount() != 0) {
    stderr.writeln('example-view asset starts with a live view');
    exitCode = 1;
  }
  if (exitCode == 0) {
    stdout.writeln('example-view native asset hook passed');
  }
}
