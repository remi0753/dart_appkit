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
```

Both modes use the same manifest and `main(List<String>)` application entry.
The builder generates the VM-retained AOT wrapper; application source does not
need an embedder-specific pragma.

Manifest version 1 contains these required fields plus the optional `runner`,
`dartHelpers`, and `nativeAssets` values:

```json
{
  "schemaVersion": 1,
  "application": {
    "name": "Example",
    "executableName": "example",
    "bundleIdentifier": "dev.example.application",
    "version": "1.0.0",
    "minimumSystemVersion": "14.0"
  },
  "runner": {
    "activationPolicy": "regular",
    "activateOnLaunch": true,
    "terminateAfterLastWindowClosed": false,
    "reopenHandled": true
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

The immutable `runner` policy is read before the AppKit run loop starts.
`activationPolicy` accepts `regular`, `accessory`, or `prohibited`; the other
values control forced launch activation, last-window termination, and the
delegate's reopen handled result. Omitting the object preserves the historical
regular/activate/continue/handled behavior. Reopen events remain asynchronous
and are posted to Dart for either handled result.

Resource paths are normalized project-relative paths. Runtime-owned filenames
cannot be replaced. `MacosRuntime.bundleResourcePath` accepts only normalized
bundle-relative names and rejects traversal.

Each `dartHelpers` entry names a project-relative Dart entrypoint and a safe
bundle filename. The builder uses the official hook-aware CLI build to compile
it as a self-contained executable,
stages it in `Contents/Helpers`, records it in the build manifest, and makes it
available through `MacosRuntime.bundleHelperPath`. Helper protocol and launch
policy remain application responsibilities.

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
