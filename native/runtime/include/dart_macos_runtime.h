#ifndef DART_MACOS_RUNTIME_INCLUDE_DART_MACOS_RUNTIME_H_
#define DART_MACOS_RUNTIME_INCLUDE_DART_MACOS_RUNTIME_H_

#include <stdint.h>

#define DMR_RUNTIME_ABI_VERSION 1u

#define DMR_RUNTIME_OK 0
#define DMR_RUNTIME_WRONG_THREAD 1
#define DMR_RUNTIME_INVALID_ARGUMENT 2
#define DMR_RUNTIME_CONFLICT 3

#define DMR_DIAGNOSTICS_ABI_VERSION 1u
#define DMR_DIAGNOSTIC_PHASE_ROOT_STARTING 1u
#define DMR_DIAGNOSTIC_PHASE_ROOT_READY 2u
#define DMR_DIAGNOSTIC_PHASE_SHUTDOWN_STARTED 3u
#define DMR_DIAGNOSTIC_PHASE_ROOT_STOPPED 4u

#define DMR_DIAGNOSTICS_OK 0
#define DMR_DIAGNOSTICS_NOT_STARTED 1
#define DMR_DIAGNOSTICS_WRONG_THREAD 2
#define DMR_DIAGNOSTICS_INVALID_PHASE 3
#define DMR_DIAGNOSTICS_PHASE_REGRESSION 4
#define DMR_DIAGNOSTICS_ALREADY_FINISHED 5

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t dmr_runtime_abi_version(void);

// Records a non-zero process result. The first value wins. This call is valid
// only on the process main thread.
__attribute__((visibility("default"))) int32_t
dmr_runtime_set_exit_code(int32_t exit_code);

// Optionally records a process result in 0..255 and asynchronously asks
// NSApplication to terminate. Zero requests clean termination without
// replacing a previously recorded non-zero result. Repeating the same request
// is idempotent.
__attribute__((visibility("default"))) int32_t
dmr_runtime_request_termination(int32_t exit_code);

__attribute__((visibility("default"))) uint32_t
dmr_runtime_diagnostics_abi_version(void);

__attribute__((visibility("default"))) int32_t
dmr_runtime_diagnostics_record_phase(uint32_t phase);

#if defined(__cplusplus)
}
#endif

#endif  // DART_MACOS_RUNTIME_INCLUDE_DART_MACOS_RUNTIME_H_
