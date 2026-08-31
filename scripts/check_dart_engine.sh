#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source "${script_dir}/dart_engine_env.sh"

fail() {
  print -u2 "Dart Engine configuration error: $1"
  print -u2 "See docs/BUILDING_DART_ENGINE.md for the revision-matched build contract."
  exit 1
}

if [[ -z "${DART_SDK:-}" ]]; then
  dart_executable=$(command -v dart 2>/dev/null || true)
  [[ -n "${dart_executable}" ]] || fail "DART_SDK is unset and dart is not on PATH"
  resolved_dart=$(realpath "${dart_executable}")
  DART_SDK=${resolved_dart:h:h}
fi

[[ -d "${DART_SDK}" ]] || fail "DART_SDK is not a directory: ${DART_SDK}"
[[ -f "${DART_SDK}/version" ]] || fail "missing ${DART_SDK}/version"
[[ -f "${DART_SDK}/revision" ]] || fail "missing ${DART_SDK}/revision"
[[ -f "${DART_SDK}/include/dart_api.h" ]] || fail "missing released SDK dart_api.h"
IFS= read -r sdk_version < "${DART_SDK}/version"
[[ "${sdk_version}" == "${DART_APPKIT_PINNED_DART_VERSION}" ]] || \
  fail "this prototype is pinned to Dart ${DART_APPKIT_PINNED_DART_VERSION}, found ${sdk_version}"

[[ -n "${DART_ENGINE_ROOT:-}" ]] || fail "DART_ENGINE_ROOT is required"
[[ -d "${DART_ENGINE_ROOT}" ]] || fail "DART_ENGINE_ROOT is not a directory: ${DART_ENGINE_ROOT}"
[[ -f "${DART_ENGINE_ROOT}/runtime/include/dart_api.h" ]] || \
  fail "DART_ENGINE_ROOT must point to the sdk directory of a Dart source checkout"
[[ -f "${DART_ENGINE_ROOT}/runtime/engine/include/dart_engine.h" ]] || \
  fail "the source checkout has no runtime/engine/include/dart_engine.h"

[[ -n "${DART_ENGINE_LIBRARY:-}" ]] || fail "DART_ENGINE_LIBRARY is required"
[[ -f "${DART_ENGINE_LIBRARY}" ]] || fail "engine library does not exist: ${DART_ENGINE_LIBRARY}"

sdk_revision=$(<"${DART_SDK}/revision")
[[ "${sdk_revision}" == "${DART_APPKIT_PINNED_DART_REVISION}" ]] || \
  fail "SDK revision ${sdk_revision} does not match pinned revision ${DART_APPKIT_PINNED_DART_REVISION}"
engine_revision=$(git -C "${DART_ENGINE_ROOT}" rev-parse HEAD 2>/dev/null || true)
[[ -n "${engine_revision}" ]] || fail "cannot read the Dart Engine checkout revision"
[[ "${sdk_revision}" == "${engine_revision}" ]] || \
  fail "revision mismatch: released SDK=${sdk_revision}, engine=${engine_revision}"

host_arch=$(uname -m)
library_arches=$(lipo -archs "${DART_ENGINE_LIBRARY}" 2>/dev/null || true)
[[ " ${library_arches} " == *" ${host_arch} "* ]] || \
  fail "engine library architectures '${library_arches}' do not include ${host_arch}"

[[ -x "${DART_ENGINE_KERNEL_COMPILER}" ]] || \
  fail "missing Engine Kernel compiler: ${DART_ENGINE_KERNEL_COMPILER}"
[[ -f "${DART_ENGINE_PLATFORM}" ]] || \
  fail "missing Engine platform Kernel: ${DART_ENGINE_PLATFORM}"

required_symbols=(
  _DartEngine_Init
  _DartEngine_CreateIsolate
  _DartEngine_AcquireIsolate
  _DartEngine_ReleaseIsolate
  _DartEngine_DrainMicrotasksQueue
  _DartEngine_HandleMessage
  _DartEngine_KernelFromFile
  _DartEngine_SetDefaultMessageScheduler
  _DartEngine_SetHandleMessageErrorCallback
  _DartEngine_SetMessageScheduler
  _DartEngine_Shutdown
  _Dart_PostCObject
  _Dart_VersionString
)
exported_symbols=$(nm -gU "${DART_ENGINE_LIBRARY}" 2>/dev/null || true)
for symbol in ${required_symbols[@]}; do
  [[ "${exported_symbols}" == *" ${symbol}"* ]] || fail "engine library is missing ${symbol}"
done

library_id=$(otool -D -arch "${host_arch}" "${DART_ENGINE_LIBRARY}" 2>/dev/null | sed -n '2p')
[[ "${library_id}" == "@rpath/libdart_engine_jit_shared.dylib" ]] || \
  fail "engine library install name is '${library_id}', expected @rpath/libdart_engine_jit_shared.dylib"

print "Dart Engine configuration is compatible"
print "  SDK version: ${sdk_version}"
print "  revision: ${sdk_revision}"
print "  architecture: ${host_arch}"
print "  library: ${DART_ENGINE_LIBRARY}"
print "  Kernel compiler: ${DART_ENGINE_KERNEL_COMPILER}"
print "  platform Kernel: ${DART_ENGINE_PLATFORM}"
