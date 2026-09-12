# dart_macos_runtime

`dart_macos_runtime` supplies the reusable macOS application layer above
`dart_appkit`. Applications provide Dart code and one strict JSON manifest;
the package builds a generic AppKit-main host, compiles the Dart root with the
matching unmodified Engine toolchain, assembles a signed `.app`, and can launch
it with inherited stdio.

The package owns application hosting, JIT/AOT bundle layout, lifecycle exit
status, declared-resource lookup, and privacy-bounded local-run diagnostics. It
does not own product worker protocols, PTYs, or application-specific views.

```shell
dart run dart_macos_runtime:build \
  --manifest macos_application.json \
  --mode developer-jit \
  --run -- --application-argument

dart run dart_macos_runtime:build \
  --manifest macos_application.json \
  --mode release-aot

dart run dart_macos_runtime:build \
  --manifest macos_application.json \
  --mode release-aot \
  --target-architecture x86_64
```

`--target-architecture` is a build-only Release AOT option accepting `arm64`
or `x86_64`. Omitting it targets the current architecture. A foreign target is
compiled from the current trusted Dart process using the matching Engine
Product output, native compiler target, Dart helper/build-hook target, and App
Intents target. Developer JIT rejects the option, and `--run` rejects a foreign
target; callers launch a verified foreign thin application separately when the
host supports the required compatibility runtime. A foreign target also
requires the matching Engine `ReleaseARM64/dart-sdk` or
`ReleaseX64/dart-sdk`; the builder verifies that SDK's version, revision, and
executable architecture plus the required VM/compiler artifacts before using
it for build hooks. Dart helpers use the selected Product Kernel compiler,
snapshotter, and generic native command host. Generate the target SDK from the
same pinned Engine checkout (for example, its `create_sdk` Ninja target) before
a foreign build.

Two independently verified thin Release AOT applications can be assembled in
either input order:

```sh
dart run dart_macos_runtime:universal \
  --input-app build/arm64/Example.app \
  --input-app build/x86_64/Example.app \
  --output-app build/universal/Example.app
```

The Universal assembler requires exactly one `arm64` and one `x86_64` input.
It rejects symbolic links, overlapping paths, mismatched inventories,
architecture-neutral byte drift, undeclared executable or Mach-O files,
invalid thin signatures, and inconsistent build evidence. Every declared code
entry is merged and revalidated as exactly `arm64 x86_64`; non-system absolute
dependencies are rejected. It writes deterministic schema-version-2 evidence
that retains the generic runtime declaration fields at top level,
ad-hoc signs nested code before the outer application, verifies the complete
signature strictly, and publishes through a same-directory atomic rename. A
failure before publication leaves any existing output unchanged.

Both modes use the same manifest and `main(List<String>)` application entry.
The builder generates the VM-retained AOT wrapper; application source does not
need an embedder-specific pragma.

Manifest version 1 contains these required fields plus the optional `runner`,
`services`, `scriptingDefinition`, `appIntents`, `dartHelpers`, and
`nativeAssets` values:

```json
{
  "schemaVersion": 1,
  "application": {
    "name": "Example",
    "displayName": "Example Application",
    "executableName": "example",
    "bundleIdentifier": "dev.example.application",
    "version": "1.0.0",
    "minimumSystemVersion": "14.0"
  },
  "services": [
    {
      "action": "primary",
      "menuItem": "Use Example Here"
    },
    {
      "action": "secondary",
      "menuItem": "Use Example in Alternate Mode"
    }
  ],
  "scriptingDefinition": {"path": "resources/Example.sdef"},
  "appIntents": {
    "package": "example_app_intents",
    "source": "native/ExampleAppIntents.swift",
    "moduleName": "ExampleAppIntents",
    "library": "libexample_app_intents.dylib"
  },
  "runner": {
    "activationPolicy": "regular",
    "activateOnLaunch": true,
    "terminateAfterLastWindowClosed": false,
    "reopenHandled": true,
    "messagePump": {
      "maxMessagesPerTurn": 64,
      "maxTimePerTurnMicros": 4000
    }
  },
  "dart": {"entrypoint": "bin/main.dart"},
  "dartHelpers": [
    {"name": "example_worker", "entrypoint": "bin/worker.dart"}
  ],
  "resources": ["assets/config.json"],
  "nativeAssets": [],
  "nativeCapabilities": [],
  "diagnostics": {
    "enabled": true,
    "applicationSupportName": "Example"
  }
}
```

`application.displayName` is optional and defaults to `application.name`. It
supplies the user-visible `CFBundleDisplayName`; applications may localize it
with ordinary bundle `InfoPlist.strings` resources.

The immutable `runner` policy is read before the AppKit run loop starts.
`activationPolicy` accepts `regular`, `accessory`, or `prohibited`; the other
values control forced launch activation, last-window termination, and the
delegate's reopen handled result. Omitting the object preserves the historical
regular/activate/continue/handled behavior. Reopen events remain asynchronous
and are posted to Dart for either handled result. The nested `messagePump`
object selects positive integer per-turn budgets. Its defaults are 64 messages
and 4000 microseconds, while immutable library hard maxima reject values above
1024 messages or 16000 microseconds.

The optional `services` array is closed to `primary` and `secondary` actions.
Each action may appear at most once and must have a unique, trimmed,
display-safe `menuItem` no larger than 256 UTF-8 bytes. The builder maps those
actions to the fixed `performPrimaryFolderService` and
`performSecondaryFolderService` AppKit provider messages and advertises
`public.item` through `NSSendFileTypes`; callers cannot inject selectors or
arbitrary property-list keys. The consuming application owns the meaning of
each action. The builder emits `NSServices` only when the array is non-empty,
validates the completed property list before signing, and records the same
ordered declarations in `runtime-build-manifest.json`.

The optional `scriptingDefinition` object contains exactly one normalized,
project-relative `.sdef` path of at most 1024 UTF-8 bytes. The source must be
non-empty and no larger than 1 MiB. Before staging, the builder validates it
against the system scripting-definition DTD with `xmllint --valid`, copies it
to the `Contents/Resources` root, emits exact `NSAppleScriptEnabled` and
`OSAScriptingDefinition` keys, and records source path, bundle name, and byte
count in `runtime-build-manifest.json`. Missing, absolute/remote/traversing,
invalid, oversized, and colliding declarations fail before signing. The
runtime defines packaging only; dictionary classes and command authority stay
in an optional application-owned capability.

The optional `appIntents` object declares exactly one dependency-owned Swift
source module. Its `package` must resolve exactly once through the application's
package configuration, `source` is a normalized package-relative `.swift` file
of at most 1 MiB, `moduleName` is a Swift identifier, and `library` is a unique
`lib*.dylib` bundle filename. App Intents require a minimum macOS version of 13
or later. The builder uses the selected Xcode toolchain to emit compiler
constant values, link the module with an `@rpath` install name, and run
`appintentsmetadataprocessor`. It accepts only the expected
`Metadata.appintents/version.json` and `extract.actionsdata` outputs, verifies
that their tools version matches Xcode, links the image into the generic host,
and stages the image and metadata in `Frameworks` and `Resources`. The source,
target, image size, Xcode build, and exact metadata files are recorded in
`runtime-build-manifest.json`. Extracted JSON objects are written in canonical
key order so independently built thin applications have identical neutral
metadata. Omitting `appIntents` preserves the existing bundle layout. Intent
declarations and command authority remain the owning dependency's
responsibility.

Resource paths are normalized project-relative paths. Runtime-owned filenames
cannot be replaced. `MacosRuntime.bundleResourcePath` accepts only normalized
bundle-relative names and rejects traversal.

Each `dartHelpers` entry names a project-relative Dart entrypoint and a safe
bundle filename. Developer JIT uses the official hook-aware CLI build to stage
a self-contained executable. Release AOT compiles a separate Mach-O AOT
snapshot and stages a generic AOT command host in `Contents/Helpers`; the
snapshot is recorded in the build manifest and staged below
`Contents/Resources/DartHelpers`. This split allows both entries to be merged
independently into valid Universal Mach-O images. Applications obtain the
complete executable and argument prefix through
`MacosRuntime.bundleHelperCommand`; `bundleHelperPath` remains available for
legacy self-contained helpers. Helper protocol and launch policy remain
application responsibilities.

`nativeCapabilities` entries declare the dependency package, dylib filename,
ABI version symbol, initializer symbol, and ABI version. The builder runs the
official Dart build-hook pipeline, stages only declared images in Frameworks,
and records them in `runtime-build-manifest.json`. A dependency facade calls
`MacosNativeCapability.load(id)` on the root UI isolate; it validates and
initializes exactly once, then retains the image until process exit.

The optional `nativeAssets` array declares a dependency package, dylib,
independent ABI version, and version symbol without an AppKit initializer. It
is intended for platform capabilities such as PTY/process I/O. These images are
built and staged by the same hook pipeline, but are opened and validated by
their owning Dart package rather than registered as AppKit extensions.
