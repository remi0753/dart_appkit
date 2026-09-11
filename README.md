# Dart AppKit Embedder

A small native macOS host that runs a Dart root isolate on AppKit's process main
thread without Flutter. The native Runner owns `NSApplication` and its run loop;
Dart calls a narrow C ABI; AppKit events return through a Dart native port; and
Dart message work is limited per run-loop turn.

The reusable surface is deliberately small: native windows and tab groups,
generic, text, registered native-provider, and two-child split views, explicit
first-responder selection, menus and menu-item actions, periodic `Timer`
updates, lifecycle/window/input events, cached application light/dark
appearance, 64 MiB-bounded plain-text pasteboard
snapshots, allowlisted external URL opening, explicit native ownership,
per-window key-event routing, mutable outer frames, asynchronous native
fullscreen state, a bounded attributed multiline text editor, and a
restart-based developer command.

Native events use a protocol version independent from the C ABI version. The
legacy port-registration API continues to emit version 1; version 2 retains
the original event set with source generation, nanosecond monotonic time, and
operation identity. Version 3 adds focus, visibility, occlusion,
backing-scale, and screen state. Version 4 adds application
active/reopen/termination and user-close request events
plus menu-item actions while preserving older records. Version 5 adds precision
scroll input. Version 6 adds outer window-frame and native-fullscreen state.
Current Dart/native pairs negotiate version 7, which adds a deduplicated
application effective-appearance snapshot and change event. The Dart API
strictly decodes all seven versions and suppresses newer records for older
negotiated sinks.

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
developer command. `dart_terminal_renderer_macos` demonstrates the production
package boundary for a terminal-specific `MTKView`: its build hook, native ABI,
and implementation remain outside both the application and generic hosts.
`dart_pty_macos` applies the same dependency-owned model to an AppKit-free,
bounded asynchronous PTY/process reactor and a deterministic Dart fake backend.
Application-owned Dart worker entrypoints can be declared as `dartHelpers`;
the generic builder produces self-contained executables under
`Contents/Helpers`, while protocol and supervision policy remain in Dart.

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
  configuration: const WindowConfiguration(),
)
  ..contentView = view
  ..show();
final Menu mainMenu = Menu(
  configuration: const MenuConfiguration(autoEnablesItems: false),
);
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

`WindowConfiguration` selects titled, closable, miniaturizable, and resizable
styles independently at creation. Its const default preserves the historical
four-style window; setting all four flags false creates a borderless window.
The configured ABI is additive, and current Dart bindings use an older native
image only for the compatibility default.

`ViewConfiguration` selects whether a package-created base view accepts first
responder and whether it follows superview width and height independently.
`TextViewConfiguration` adds system, monospaced-system, or exact named font;
bounded logical padding; dynamic label/window-background roles; and fixed sRGB
foreground/background colors. Its nested view configuration controls the same
focus and autoresizing behavior. Defaults preserve the original focusable,
width/height-sizable, monospaced 18-point regular text with 20-point padding,
label foreground, and window background. Registered custom views remain wholly
provider-owned.

`TextEditor` is a separate, scrollable `NSTextView` surface for multiline
editing. `setDocument` publishes one bounded plain-text buffer, UTF-16
selection, and ordered non-overlapping foreground/underline runs atomically;
`setStyleRuns` changes only attributes and does not replace the native text
storage or selection. `isEditable` therefore switches interaction in place,
so applications can keep identical syntax colors in command and editing modes.
An optional `TextEditorLineHighlight` paints one logical line across the full
editor width without changing its foreground, underline, selection, or caret;
document replacement clears it so an old UTF-16 location cannot leak into a
new buffer. `scrollSelectionToVisible` explicitly reveals the current checked
selection without changing the buffer, attributes, highlight, or selection, so
Dart-owned command navigation can follow the viewport without changing the
semantics of ordinary programmatic selection.
Snapshots return text, selection, editability, and marked-text presence.
Text is limited to 16 MiB of UTF-8 and style projections to 65,536 runs. The
surface retains native scrolling, selection, first-responder routing, IME
composition, and Undo infrastructure; typed change/composition events and the
broader controlled-input contract remain later control work.

`MenuConfiguration` selects whether AppKit automatically validates item
enabled state through its target. The compatibility default is `false`, so
explicit `MenuItem.isEnabled` updates remain authoritative; applications that
participate in AppKit validation can opt into auto-enablement per menu.

Native tabs use one `Window` per tab, preserving independent window event and
content-view ownership. `Window.addTabbedWindow` appends another window to the
receiver's native tab group; `selectTab` and `removeFromTabGroup` select and
detach without synthesizing Dart identity. `TwoPaneSplitView` is explicitly a
narrow helper: it remains substitutable as a generic `View`, but composes
exactly two ordered children around one thin non-collapsible divider, constrains
that divider by per-child logical minimum extents, and supports equalize and
binary one-child zoom. The historical `SplitView` name is a deprecated source
alias, not the future general split-container contract. After installing the
split root as content, `Window.makeFirstResponder` can target any attached
descendant view.

`Window.representedFilePath` sets or clears an absolute local path through the
standard `NSWindow.representedURL` proxy-icon/path-menu surface.
`Window.tabAccessory` accepts a bounded sRGB `WindowTabColor`, logical width and
height up to 256 points, and rectangle or ellipse shape. The source-compatible
`Window.tabColor` property remains an 8×8 ellipse helper. Both values are
copied, cached by the Dart wrapper, main-thread checked, and retained by the
existing window; neither allocates a new registry handle or assigns product
appearance policy to the bridge.

`Window.frame` is a mutable, finite, positive outer-frame value. Native move and
resize callbacks publish the resulting AppKit frame, including coordinates on
screens with negative origins. `Window.setFullscreen` requests AppKit's native
asynchronous transition; `isFullscreen` changes only when a deduplicated
completion event arrives. Repeating the current or pending target is a no-op,
while an opposite request during a transition is rejected instead of guessing
at AppKit's eventual state.

Windows default to `KeyEventRouting.dartAndAppKit`, which mirrors key events to
Dart and retains ordinary AppKit responder behavior. Raw-input surfaces can set
`window.keyEventRouting = KeyEventRouting.dartOnly`; native main-menu key
equivalents keep priority, while remaining keys reach Dart without also falling
through an unhandled AppKit responder path. An IME-capable custom view can use
`KeyEventRouting.appKitOnly`; menu equivalents still win, while every remaining
key enters only the first-responder/input-client chain and is not pre-posted to
the window's Dart event stream.

A native capability can register an `NSView` factory through the versioned
plain-C `dart_appkit_native_extension.h` service table. The runtime builder runs
dependency build hooks, stages declared dylibs, and retains a loaded image for
the process lifetime. A dependency's Dart facade initializes the image and then
creates a normal owned generic-view handle with `View.custom`; Objective-C
pointers never enter application Dart or a product runner.

External URL rules are application-owned. Pass an immutable
`ExternalUrlPolicy` to `AppKitApplication.attach`, then parse untrusted text
with the same policy before calling `openExternalUrl`. The compatibility
default allows HTTP and HTTPS with a host and no credentials, plus
non-authority `mailto`; applications may instead define their own schemes and
authority, host, credential, and path requirements. The library always retains
its 4096-byte limit and malformed, control, invisible, backslash, and unsafe
escape rejection, and the native boundary repeats those checks.

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
packages/dart_appkit_example_view/ Build-hook native capability proof
packages/dart_terminal_renderer_macos/ Terminal MTKView native capability
packages/dart_pty_macos/ AppKit-independent PTY/process capability
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
