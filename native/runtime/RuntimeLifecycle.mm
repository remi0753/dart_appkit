#import <AppKit/AppKit.h>

#include "RuntimeLifecycle.h"

#include <pthread.h>

#include <atomic>
#include <cstdlib>

#include "RuntimeDiagnostics.h"
#include "dart_macos_runtime.h"

namespace dart_macos_runtime {
namespace {

std::atomic<int32_t> requested_exit_code{0};
std::atomic<bool> termination_requested{false};

int32_t RecordExitCode(int32_t exit_code) {
  if (pthread_main_np() == 0) {
    return DMR_RUNTIME_WRONG_THREAD;
  }
  if (exit_code <= 0 || exit_code > 255) {
    return DMR_RUNTIME_INVALID_ARGUMENT;
  }
  int32_t expected = 0;
  if (requested_exit_code.compare_exchange_strong(expected, exit_code,
                                                  std::memory_order_acq_rel)) {
    return DMR_RUNTIME_OK;
  }
  return expected == exit_code ? DMR_RUNTIME_OK : DMR_RUNTIME_CONFLICT;
}

}  // namespace

int EffectiveExitCode(int delegate_exit_code) {
  return delegate_exit_code != 0
             ? delegate_exit_code
             : requested_exit_code.load(std::memory_order_acquire);
}

bool HostStartupFailureRequested() {
  const char* gate = std::getenv("DMR_RUNTIME_DIAGNOSTICS_TEST");
  const char* requested = std::getenv("DMR_RUNTIME_TEST_HOST_STARTUP_FAILURE");
  return gate != nullptr && requested != nullptr && gate[0] == '1' &&
         gate[1] == '\0' && requested[0] == '1' && requested[1] == '\0';
}

void CompleteApplicationTermination(int delegate_exit_code) {
  const int exit_code = EffectiveExitCode(delegate_exit_code);
  RuntimeDiagnosticsFinishActiveSession(exit_code);
  if (exit_code != 0) {
    std::fflush(nullptr);
    std::_Exit(exit_code);
  }
}

void ResetLifecycleForTesting() {
  requested_exit_code.store(0, std::memory_order_release);
  termination_requested.store(false, std::memory_order_release);
}

}  // namespace dart_macos_runtime

extern "C" uint32_t dmr_runtime_abi_version(void) {
  return DMR_RUNTIME_ABI_VERSION;
}

extern "C" int32_t dmr_runtime_set_exit_code(int32_t exit_code) {
  return dart_macos_runtime::RecordExitCode(exit_code);
}

extern "C" int32_t dmr_runtime_request_termination(int32_t exit_code) {
  const int32_t result = dart_macos_runtime::RecordExitCode(exit_code);
  if (result != DMR_RUNTIME_OK) {
    return result;
  }
  bool expected = false;
  if (dart_macos_runtime::termination_requested.compare_exchange_strong(
          expected, true, std::memory_order_acq_rel)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
  }
  return DMR_RUNTIME_OK;
}
