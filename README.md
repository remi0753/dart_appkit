# Dart AppKit Embedder

A small native macOS host that runs a Dart root isolate on AppKit's process main
thread without Flutter. The native Runner owns `NSApplication` and its run loop;
Dart calls a narrow C ABI; AppKit events return through a Dart native port; and
Dart message work is limited per run-loop turn.

The reusable surface is deliberately small: one window, generic, text, and
registered native-provider views, menus and menu-item actions, periodic
`Timer` updates, lifecycle/window/input events, plain-text pasteboard snapshots,
explicit native ownership, and a restart-based developer command.

Native events use a protocol version independent from the C ABI version. The
legacy port-registration API continues to emit version 1; version 2 retains
the original event set with source generation, nanosecond monotonic time, and
operation identity. Version 3 adds focus, visibility, occlusion,
backing-scale, and screen state. Current Dart/native pairs negotiate version 4,
which adds application active/reopen/termination and user-close request events
plus menu-item actions while preserving older records. The Dart API decodes all
four versions.

Native handles record an owning thread domain in addition to their encoded
generation. Explicit UI release remains main-thread-only. Finalizers and other
off-domain callers use one asynchronous claim path that invalidates the handle
before returning and completes teardown on the AppKit main queue. Pending
release is included in shutdown cleanup and cannot reuse its registry slot.

## Current status

The bridge, Dart API, Runner, bounded scheduler, launcher, `.app` bundle,
revision-pinned Dart checkout bootstrap, and hello-window example are complete.
The official arm64 Engine dylib has been built from the exact Dart 3.13.2 SDK
revision, and the Engine-backed GUI smoke test passes through Timer activity,
native close delivery, handle release, and process exit 0. The accepted runtime
contract is one stock Engine root for the GUI process lifetime; the SDK source
must stay at the exact official revision with no tracked changes.

The released SDK does not contain `libdart_engine_jit_shared.dylib`, so
`make engine` builds the required artifact from unmodified official source. The
project never substitutes standalone `dart run` as the GUI host, because that
would not put the isolate on the macOS main thread. A full public `dart_api.h`
host was tested in ARM64 JIT and AOT and rejected because Dart's platform,
microtask, and worker bootstrap is not exposed by the stock shared library; no
private Dart implementation is copied or called to fill that gap.

The repository also contains the separate `dart_macos_runtime` package. It
turns a strict JSON application manifest plus a Dart `main(List<String>)` into
the same generic AppKit-main application in Developer JIT or Release AOT form.
The application does not compile a runner or depend on native implementation
paths. `dart_appkit:run` remains available as the compatible lightweight JIT
developer command.

- [Roadmap and current position](ROADMAP.md)
- [Chronological findings and decisions](docs/WORKLOG.md)
- [Final verification matrix](docs/VERIFICATION.md)
- [Engine build contract](docs/BUILDING_DART_ENGINE.md)

## Prerequisites

- macOS 14 or later on the host architecture
- Xcode command-line build tools and the macOS SDK
- Dart 3.13.2
- Chromium `depot_tools` with `gclient` on `PATH`
- At least 15 GiB of free space recommended for the checkout and build

## Run the example

Fetch, build, and validate the pinned Engine once:

```shell
make engine
```

Then launch an unattended three-second smoke test or an interactive window:

```shell
make example-smoke
make run-example
```

Build the same example through the reusable manifest-driven runtime:

```shell
cd examples/hello_window
dart run dart_macos_runtime:build \
  --manifest macos_application.json --mode developer-jit --run \
  -- --auto-close-after=3
dart run dart_macos_runtime:build \
  --manifest macos_application.json --mode release-aot --run \
  -- --auto-close-after=3
```

No Engine exports are required for the default project-local checkout. The
launcher validates the SDK/Engine pair, reuses an unchanged native build,
compiles with the matching Engine Kernel toolchain, assembles
`DartAppKitRunner.app`, launches its executable with inherited stdio, and
returns the Runner's exit status. For ad-hoc shell work, the bootstrap also
generates `.dart_tool/dart-engine/env.zsh`.

The example should count once per second while the UI remains interactive. It
logs input, resize, and Quit-menu action events; closing the window must log
that close reached Dart, release every handle, and request normal application
termination.

## Dart API shape

```dart
final app = await AppKitApplication.attach();
final View view = TextView()..text = 'Hello';
final window = Window(
  frame: const Rect.fromLTWH(120, 120, 640, 360),
  title: 'Dart AppKit',
)
  ..contentView = view
  ..show();
final Menu mainMenu = Menu();
final MenuItem closeItem = MenuItem(
  title: 'Close',
  keyEquivalent: 'w',
  modifiers: const ModifierKeys(ModifierKeys.commandBit),
);
mainMenu.addItem(closeItem);
app.mainMenu = mainMenu;

await window.onClosed.first;
window.dispose();
view.dispose();
await app.terminate();
```

A native product can register an `NSView` subclass through the separate
Objective-C++ `dart_appkit_custom_view.h` extension surface before Dart starts.
Dart then creates a normal owned generic-view handle with
`View.custom('product.ProviderName')`; Objective-C pointers never cross FFI.

Application entrypoints use `main(List<String> arguments)`. UI calls belong on
the embedded root isolate. Ordinary in-process workers are not part of the
pinned stock Engine host contract. Products that need dynamic background work
must own official Dart JIT/AOT worker processes and explicit IPC; only the root
UI process may call AppKit.

## Local checks

```shell
make test
```

This runs C/C++ ABI checks, AppKit bridge tests, Runner strict compilation,
Runner CLI, pre-VM shell-link and message-pump tests, Dart
analysis/API/launcher tests, the real FFI dylib smoke test, example analysis,
and full-Kernel compilation. `make runner` is intentionally a separate
Engine-dependent target. Run `make help` for the complete target list.

`make engine-check` additionally enforces the exact official SDK revision and
clean tracked source. `make public-dart-api-host-probe` reproduces the bounded
ARM64 JIT/AOT evidence for rejecting a direct public-API replacement host; it
is an architectural conformance target, not a production host.

## Layout

```text
native/runner/          Original compatible JIT host and bounded message pump
native/runtime/         Generic lifecycle, diagnostics, and JIT/AOT hosts
native/bridge/          Stable C ABI and AppKit object implementation
packages/dart_appkit/   Dart FFI/API and dart_appkit:run executable
packages/dart_macos_runtime/ Manifest, host facade, and application builder
examples/hello_window/  Timer, events, close, and shutdown proof
scripts/                SDK/Engine validation and Engine build helper
docs/                   Architecture, ABI, verification, and work log
```

Production identity signing/notarization, sandboxing, VM Service, hot reload,
widgets, and terminal capabilities remain outside this repository layer.

## License

Dart AppKit Embedder's own source is available under the
[MIT License](LICENSE). Dart SDK source and generated Engine artifacts are
separately licensed and are intentionally excluded from Git. See
[Third-party notices](THIRD_PARTY_NOTICES.md) before distributing a generated
dylib or application bundle.
