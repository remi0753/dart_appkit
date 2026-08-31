#ifndef DART_APPKIT_RUNNER_RUNNER_ARGUMENTS_H_
#define DART_APPKIT_RUNNER_RUNNER_ARGUMENTS_H_

#include <string>
#include <string_view>

#include "RunnerConfiguration.h"

namespace dart_appkit {

inline constexpr int kRunnerUsageExitCode = 64;
inline constexpr int kRunnerInputExitCode = 66;
inline constexpr int kRunnerSoftwareExitCode = 70;

std::string RunnerUsage(std::string_view executable);

bool ParseRunnerArguments(int argc, const char* const argv[],
                          RunnerConfiguration* configuration,
                          std::string* out_error);

}  // namespace dart_appkit

#endif  // DART_APPKIT_RUNNER_RUNNER_ARGUMENTS_H_
