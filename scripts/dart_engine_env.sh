#!/bin/zsh

# This file is intentionally sourceable. Project commands also use these
# defaults directly, so sourcing it is only needed for ad-hoc shell work.

typeset _dart_appkit_engine_env_source=${(%):-%N}

_dart_appkit_configure_engine_environment() {
  local script_dir=${_dart_appkit_engine_env_source:A:h}
  local project_root=${script_dir:h}
  local dart_executable
  local resolved_dart
  local release_arch
  local toolchain_arch

  export DART_APPKIT_PINNED_DART_VERSION=3.13.2
  export DART_APPKIT_PINNED_DART_REVISION=60a57cd42d64dc03e9f07aa60a2e250755c1ef28
  export DART_APPKIT_DART_REPOSITORY=https://dart.googlesource.com/sdk.git

  if [[ -z "${DART_SDK:-}" ]]; then
    dart_executable=$(command -v dart 2>/dev/null || true)
    if [[ -n "${dart_executable}" ]]; then
      resolved_dart=$(realpath "${dart_executable}")
      export DART_SDK=${resolved_dart:h:h}
    fi
  fi

  if [[ -z "${DART_ENGINE_WORKSPACE:-}" ]]; then
    if [[ -n "${DART_ENGINE_ROOT:-}" ]]; then
      export DART_ENGINE_WORKSPACE=${DART_ENGINE_ROOT:A:h}
    else
      export DART_ENGINE_WORKSPACE="${project_root}/.dart_tool/dart-engine"
    fi
  fi
  if [[ -z "${DART_ENGINE_ROOT:-}" ]]; then
    export DART_ENGINE_ROOT="${DART_ENGINE_WORKSPACE}/sdk"
  fi

  if [[ -z "${DART_ENGINE_LIBRARY:-}" ]]; then
    case $(uname -m) in
      arm64)
        release_arch=ARM64
        ;;
      x86_64)
        release_arch=X64
        ;;
      *)
        release_arch=UNSUPPORTED
        ;;
    esac
    export DART_ENGINE_LIBRARY="${DART_ENGINE_ROOT}/xcodebuild/Release${release_arch}/libdart_engine_jit_shared.dylib"
  fi

  case $(uname -m) in
    arm64) toolchain_arch=arm64 ;;
    x86_64) toolchain_arch=x64 ;;
    *) toolchain_arch=unsupported ;;
  esac
  if [[ -z "${DART_ENGINE_KERNEL_COMPILER:-}" ]]; then
    export DART_ENGINE_KERNEL_COMPILER="${DART_ENGINE_LIBRARY:h}/bootstrap_gen_kernel.exe"
  fi
  if [[ -z "${DART_ENGINE_PLATFORM:-}" ]]; then
    export DART_ENGINE_PLATFORM="${DART_ENGINE_LIBRARY:h}/clang_${toolchain_arch}_shared/vm_platform.dill"
  fi
}

_dart_appkit_configure_engine_environment
unfunction _dart_appkit_configure_engine_environment
unset _dart_appkit_engine_env_source
