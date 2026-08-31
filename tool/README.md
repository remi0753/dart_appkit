# Development tooling

The user-facing executable is `packages/dart_appkit/bin/run.dart`; its testable
implementation lives under `packages/dart_appkit/lib/src/tool/launcher.dart`.
Run it from an application that depends on the path package:

```shell
dart run dart_appkit:run bin/main.dart -- application arguments
```

This top-level directory remains reserved for future repository-wide helpers;
there is no second launcher entrypoint.
