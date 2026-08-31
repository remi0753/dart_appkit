#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source "${script_dir}/dart_engine_env.sh"

fail() {
  print -u2 "Dart Engine build error: $1"
  exit 1
}

[[ -n "${DART_ENGINE_ROOT:-}" ]] || fail "set DART_ENGINE_ROOT to an existing gclient Dart sdk checkout"
[[ -x "${DART_ENGINE_ROOT}/tools/build.py" ]] || \
  fail "DART_ENGINE_ROOT must point to the sdk directory of a complete gclient checkout"

if [[ -z "${DART_SDK:-}" ]]; then
  dart_executable=$(command -v dart 2>/dev/null || true)
  [[ -n "${dart_executable}" ]] || fail "DART_SDK is unset and dart is not on PATH"
  resolved_dart=$(realpath "${dart_executable}")
  DART_SDK=${resolved_dart:h:h}
fi

[[ -f "${DART_SDK}/revision" ]] || fail "missing released SDK revision metadata"
[[ -f "${DART_SDK}/version" ]] || fail "missing released SDK version metadata"
sdk_version=$(<"${DART_SDK}/version")
[[ "${sdk_version}" == "${DART_APPKIT_PINNED_DART_VERSION}" ]] || \
  fail "this prototype is pinned to Dart ${DART_APPKIT_PINNED_DART_VERSION}, found ${sdk_version}"
sdk_revision=$(<"${DART_SDK}/revision")
[[ "${sdk_revision}" == "${DART_APPKIT_PINNED_DART_REVISION}" ]] || \
  fail "SDK revision ${sdk_revision} does not match pinned revision ${DART_APPKIT_PINNED_DART_REVISION}"
engine_revision=$(git -C "${DART_ENGINE_ROOT}" rev-parse HEAD 2>/dev/null || true)
[[ "${sdk_revision}" == "${engine_revision}" ]] || \
  fail "checkout revision ${engine_revision} does not match SDK revision ${sdk_revision}"

case $(uname -m) in
  arm64) dart_arch=arm64 ;;
  x86_64) dart_arch=x64 ;;
  *) fail "unsupported host architecture: $(uname -m)" ;;
esac

print "Building Dart Engine JIT shared library for ${dart_arch} at revision ${sdk_revision}"
cd "${DART_ENGINE_ROOT}"
./tools/build.py --mode=release --arch="${dart_arch}" runtime/engine:dart_engine_jit_shared

output_arch=${(U)dart_arch}
output_path="${DART_ENGINE_ROOT}/xcodebuild/Release${output_arch}/libdart_engine_jit_shared.dylib"
[[ -f "${output_path}" ]] || fail "build completed but expected artifact is missing: ${output_path}"
print "DART_ENGINE_LIBRARY=${output_path}"
