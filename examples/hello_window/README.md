# Hello Window

This example creates one native AppKit window from Dart, updates its text once
per second, logs resize/mouse/key events, and terminates after the native close
notification reaches Dart.

First bootstrap the pinned Engine from the repository root:

```shell
make engine
```

The launcher discovers that project-local checkout automatically. From this
directory, no Engine environment variables are required:

```shell
dart pub get
dart run dart_appkit:run bin/main.dart -- first-argument
```

Close the window to finish. For a repeatable unattended check, run this from
the repository root:

```shell
make example-smoke
```

The smoke mode logs Timer ticks, requests a native close after three seconds,
observes the close event in Dart, releases both native handles, and exits 0.
See [`../../docs/BUILDING_DART_ENGINE.md`](../../docs/BUILDING_DART_ENGINE.md)
for custom checkout locations and the generated shell environment.
