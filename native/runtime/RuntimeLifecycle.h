#ifndef DART_MACOS_RUNTIME_RUNTIME_LIFECYCLE_H_
#define DART_MACOS_RUNTIME_RUNTIME_LIFECYCLE_H_

#include <stdint.h>

namespace dart_macos_runtime {

inline constexpr int kUsageExitCode = 64;
inline constexpr int kInputExitCode = 66;
inline constexpr int kSoftwareExitCode = 70;

int EffectiveExitCode(int delegate_exit_code);
void CompleteApplicationTermination(int delegate_exit_code);
void ResetLifecycleForTesting();

}  // namespace dart_macos_runtime

#endif  // DART_MACOS_RUNTIME_RUNTIME_LIFECYCLE_H_
