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

    int32_t worker_result = DMR_RUNTIME_OK;
    std::thread worker([&] { worker_result = dmr_runtime_set_exit_code(70); });
    worker.join();
    Expect(worker_result == DMR_RUNTIME_WRONG_THREAD,
           "worker-thread mutation is rejected");

    Expect(dmr_runtime_set_exit_code(70) == DMR_RUNTIME_OK,
           "first result is recorded");
    Expect(dmr_runtime_set_exit_code(70) == DMR_RUNTIME_OK,
           "same result is idempotent");
    Expect(dmr_runtime_set_exit_code(75) == DMR_RUNTIME_CONFLICT,
           "a different later result conflicts");
    Expect(dart_macos_runtime::EffectiveExitCode(0) == 70,
           "requested result is effective");
    Expect(dart_macos_runtime::EffectiveExitCode(66) == 66,
           "delegate failure has priority");
  }
  if (failures != 0) {
    return 1;
  }
  std::cout << "RuntimeLifecycle native contract passed\n";
  return 0;
}
