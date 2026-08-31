# Integration tests

Tests stay beside the layer they verify:

- `native/bridge/test`: ABI, ownership, UTF-8, thread, finalizer, and events
- `native/runner/test`: CLI parsing and bounded run-loop scheduling
- `packages/dart_appkit/test`: Dart lifecycle/event API, real bridge FFI, and
  launcher/bundle workflow
- `examples/hello_window`: strict analysis and real full-Kernel compilation

`make test` runs every Engine-independent check. The final visible integration
procedure and its external artifact gate are in `docs/VERIFICATION.md`.
