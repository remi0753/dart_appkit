#ifndef DART_APPKIT_RUNNER_RUNNER_CONFIGURATION_H_
#define DART_APPKIT_RUNNER_RUNNER_CONFIGURATION_H_

#include <string>
#include <vector>

#ifdef __OBJC__
@class NSApplication;
@class NSDictionary;
#endif

namespace dart_appkit {

enum class RunnerActivationPolicy {
  kRegular,
  kAccessory,
  kProhibited,
};

struct RunnerConfiguration {
  std::string kernel_path;
  std::string expected_sdk_version;
  std::string expected_sdk_revision;
  std::vector<std::string> application_arguments;
  RunnerActivationPolicy activation_policy = RunnerActivationPolicy::kRegular;
  bool activate_on_launch = true;
  bool terminate_after_last_window_closed = false;
  bool reopen_handled = true;
};

#ifdef __OBJC__
bool LoadRunnerConfigurationFromInfoDictionary(
    NSDictionary* info_dictionary,
    RunnerConfiguration* configuration,
    std::string* out_error);

bool LoadRunnerConfigurationFromMainBundle(RunnerConfiguration* configuration,
                                           std::string* out_error);

bool ApplyRunnerActivationPolicy(NSApplication* application,
                                 const RunnerConfiguration& configuration,
                                 std::string* out_error);
#endif

}  // namespace dart_appkit

#endif  // DART_APPKIT_RUNNER_RUNNER_CONFIGURATION_H_
