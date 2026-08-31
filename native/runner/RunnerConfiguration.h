#ifndef DART_APPKIT_RUNNER_RUNNER_CONFIGURATION_H_
#define DART_APPKIT_RUNNER_RUNNER_CONFIGURATION_H_

#include <string>
#include <vector>

namespace dart_appkit {

struct RunnerConfiguration {
  std::string kernel_path;
  std::string expected_sdk_version;
  std::string expected_sdk_revision;
  std::vector<std::string> application_arguments;
};

}  // namespace dart_appkit

#endif  // DART_APPKIT_RUNNER_RUNNER_CONFIGURATION_H_
