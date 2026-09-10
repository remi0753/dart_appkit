#import <AppKit/AppKit.h>

#include <iostream>
#include <thread>

#include "RuntimeLifecycle.h"
#include "dart_macos_runtime.h"

namespace {

int failures = 0;

void Expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "RuntimeLifecycle expectation failed: " << description << '\n';
    ++failures;
  }
}

}  // namespace

int main() {
  @autoreleasepool {
    dart_macos_runtime::ResetLifecycleForTesting();
    Expect(dmr_runtime_abi_version() == DMR_RUNTIME_ABI_VERSION, "ABI version");
    Expect(dmr_runtime_set_exit_code(0) == DMR_RUNTIME_INVALID_ARGUMENT,
           "zero is not a failure result");
    Expect(dmr_runtime_set_exit_code(256) == DMR_RUNTIME_INVALID_ARGUMENT,
           "results are bounded to process exit status");
    Expect(dmr_runtime_request_termination(-1) == DMR_RUNTIME_INVALID_ARGUMENT,
           "clean termination rejects negative results");
    Expect(dmr_runtime_request_termination(0) == DMR_RUNTIME_OK,
           "zero requests clean application termination");
    Expect(dart_macos_runtime::EffectiveExitCode(0) == 0,
           "clean termination does not invent a failure result");
    dart_macos_runtime::ResetLifecycleForTesting();

    int32_t worker_result = DMR_RUNTIME_OK;
    int32_t worker_termination_result = DMR_RUNTIME_OK;
    std::thread worker([&] {
      worker_result = dmr_runtime_set_exit_code(70);
      worker_termination_result = dmr_runtime_request_termination(0);
    });
    worker.join();
    Expect(worker_result == DMR_RUNTIME_WRONG_THREAD,
           "worker-thread mutation is rejected");
    Expect(worker_termination_result == DMR_RUNTIME_WRONG_THREAD,
           "worker-thread termination is rejected");

    Expect(dmr_runtime_set_exit_code(70) == DMR_RUNTIME_OK,
           "first result is recorded");
    Expect(dmr_runtime_set_exit_code(70) == DMR_RUNTIME_OK,
           "same result is idempotent");
    Expect(dmr_runtime_set_exit_code(75) == DMR_RUNTIME_CONFLICT,
           "a different later result conflicts");
    Expect(dart_macos_runtime::EffectiveExitCode(0) == 70,
           "requested result is effective");
    Expect(dmr_runtime_request_termination(0) == DMR_RUNTIME_OK,
           "clean termination preserves an earlier failure result");
    Expect(dart_macos_runtime::EffectiveExitCode(0) == 70,
           "clean termination does not replace an earlier failure result");
    Expect(dart_macos_runtime::EffectiveExitCode(66) == 66,
           "delegate failure has priority");

    unsetenv("DMR_RUNTIME_DIAGNOSTICS_TEST");
    setenv("DMR_RUNTIME_TEST_HOST_STARTUP_FAILURE", "1", 1);
    Expect(!dart_macos_runtime::HostStartupFailureRequested(),
           "host fault requires the test gate");
    setenv("DMR_RUNTIME_DIAGNOSTICS_TEST", "1", 1);
    Expect(dart_macos_runtime::HostStartupFailureRequested(),
           "gated host fault is enabled");
    unsetenv("DMR_RUNTIME_TEST_HOST_STARTUP_FAILURE");
    unsetenv("DMR_RUNTIME_DIAGNOSTICS_TEST");
  }
  if (failures != 0) {
    return 1;
  }
  std::cout << "RuntimeLifecycle native contract passed\n";
  return 0;
}
