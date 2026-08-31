# Building the revision-matched Dart Engine

The released Dart SDK can run and analyze this project, but it does not include
the shared Engine required by the native AppKit host. This project is pinned to
Dart 3.13.2 and Git revision:

```text
60a57cd42d64dc03e9f07aa60a2e250755c1ef28
```

The checkout, Engine dylib, Kernel compiler, and platform Kernel must all come
from that exact revision. Kernel and VM snapshot formats are intentionally
unstable, so matching only the SDK version is insufficient.

## One-command setup

Install Dart 3.13.2, Xcode command-line tools, and Chromium `depot_tools` with
`gclient` on `PATH`, then run from the repository root:

```shell
make engine
```

The underlying command is also available directly:

```shell
./scripts/bootstrap_dart_engine.sh
```

The bootstrap performs the complete workflow:

1. Resolves the active released SDK and checks both version and pinned
   revision.
2. Configures the official `https://dart.googlesource.com/sdk.git` repository
   under `.dart_tool/dart-engine`.
3. Uses `gclient sync --no-history` at the exact revision and downloads the
   required build dependencies.
4. Refuses to sync over tracked local changes and verifies the checkout's
   origin and `HEAD`.
5. Builds the official release target
   `runtime/engine:dart_engine_jit_shared` for the host architecture.
6. Validates headers, architecture, exported symbols, install name, the
   matching Kernel compiler, and the matching platform Kernel.
7. Writes `.dart_tool/dart-engine/env.zsh` for optional ad-hoc shell work.

The default checkout and build consumed about 10 GiB in the verified arm64
environment. The script warns when less than 15 GiB is available. A repeated
run is incremental; after the first build, Ninja reports no work when inputs
are unchanged.

## Automatic environment configuration

Project commands require no manual exports when the default location is used:

```shell
make runner
make example-smoke
make run-example
```

The Makefile and Dart launcher derive these paths automatically:

- `DART_SDK`
- `DART_ENGINE_ROOT`
- `DART_ENGINE_LIBRARY`
- `DART_ENGINE_KERNEL_COMPILER`
- `DART_ENGINE_PLATFORM`

For custom shell commands, load the generated values with:

```shell
source .dart_tool/dart-engine/env.zsh
```

To keep the large checkout elsewhere, choose its gclient workspace before the
first bootstrap:

```shell
DART_ENGINE_WORKSPACE=/absolute/path/to/dart-engine-workspace make engine
```

`DART_ENGINE_ROOT` must be that workspace's `sdk` directory. Explicit launcher
flags and environment variables continue to override project defaults.

## Why the Engine Kernel compiler is required

The release JIT Engine initializes development-mode `dart:io` entry points.
The ordinary released SDK's platform Kernel is built for a different product
configuration, even at the same Git revision. Applications are therefore
compiled with the Engine build's `bootstrap_gen_kernel.exe` and
`clang_<arch>_shared/vm_platform.dill`. Using `dart compile kernel` produced a
runtime `_NetworkProfiling` entry-point error during the first real smoke test;
using the matching Engine toolchain is the supported and verified path.

## Verification and execution

Validate the current configuration without rebuilding:

```shell
make engine-check
```

Run the unattended GUI smoke test:

```shell
make example-smoke
```

It launches the AppKit window, logs Timer progress, closes the native window
after three seconds, observes the close event in Dart, releases native handles,
and must exit 0. For an interactive window, use `make run-example`.
