#ifndef DART_APPKIT_RUNNER_RUNNER_CONFIGURATION_H_
#define DART_APPKIT_RUNNER_RUNNER_CONFIGURATION_H_

#include <chrono>
#include <cstddef>
#include <cstdint>
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

inline constexpr size_t kDefaultDartMessagesPerTurn = 64;
inline constexpr size_t kMaximumDartMessagesPerTurn = 1024;
inline constexpr int64_t kDefaultDartMessageTimeMicros = 4000;
inline constexpr int64_t kMaximumDartMessageTimeMicros = 16000;

struct DartMessagePumpLimits {
  size_t max_messages_per_turn = kDefaultDartMessagesPerTurn;
  std::chrono::microseconds max_time_per_turn =
      std::chrono::microseconds(kDefaultDartMessageTimeMicros);
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
  DartMessagePumpLimits message_pump_limits;
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
