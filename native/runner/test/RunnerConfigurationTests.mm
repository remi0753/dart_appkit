#import <AppKit/AppKit.h>

#include <cstdio>
#include <string>

#include "RunnerConfiguration.h"

namespace {

int g_failures = 0;

void Check(bool condition, const char* expression, int line) {
  if (!condition) {
    std::fprintf(stderr, "FAIL line %d: %s\n", line, expression);
    ++g_failures;
  }
}

#define CHECK(expression) Check((expression), #expression, __LINE__)

void TestDefaultsAndMissingMetadata() {
  dart_appkit::RunnerConfiguration configuration;
  std::string error;
  CHECK(dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{}, &configuration, &error));
  CHECK(error.empty());
  CHECK(configuration.activation_policy ==
        dart_appkit::RunnerActivationPolicy::kRegular);
  CHECK(configuration.activate_on_launch);
  CHECK(!configuration.terminate_after_last_window_closed);
  CHECK(configuration.reopen_handled);
  CHECK(configuration.message_pump_limits.max_messages_per_turn ==
        dart_appkit::kDefaultDartMessagesPerTurn);
  CHECK(configuration.message_pump_limits.max_time_per_turn.count() ==
        dart_appkit::kDefaultDartMessageTimeMicros);
}

void TestConfiguredValues() {
  NSDictionary* info = @{
    @"DMRRunnerConfiguration" : @{
      @"ActivationPolicy" : @"accessory",
      @"ActivateOnLaunch" : @NO,
      @"TerminateAfterLastWindowClosed" : @YES,
      @"ReopenHandled" : @NO,
      @"MessagePump" : @{
        @"MaxMessagesPerTurn" : @17,
        @"MaxTimePerTurnMicros" : @2500,
      },
    },
  };
  dart_appkit::RunnerConfiguration configuration;
  std::string error;
  CHECK(dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      info, &configuration, &error));
  CHECK(configuration.activation_policy ==
        dart_appkit::RunnerActivationPolicy::kAccessory);
  CHECK(!configuration.activate_on_launch);
  CHECK(configuration.terminate_after_last_window_closed);
  CHECK(!configuration.reopen_handled);
  CHECK(configuration.message_pump_limits.max_messages_per_turn == 17);
  CHECK(configuration.message_pump_limits.max_time_per_turn.count() == 2500);
}

void TestStrictFailureIsAtomic() {
  dart_appkit::RunnerConfiguration configuration;
  configuration.activation_policy =
      dart_appkit::RunnerActivationPolicy::kProhibited;
  configuration.reopen_handled = false;
  configuration.message_pump_limits.max_messages_per_turn = 23;
  std::string error;
  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{@"DMRRunnerConfiguration" : @{@"ActivationPolicy" : @"invalid"}},
      &configuration, &error));
  CHECK(!error.empty());
  CHECK(configuration.activation_policy ==
        dart_appkit::RunnerActivationPolicy::kProhibited);
  CHECK(!configuration.reopen_handled);
  CHECK(configuration.message_pump_limits.max_messages_per_turn == 23);

  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{@"DMRRunnerConfiguration" : @{@"Unknown" : @YES}}, &configuration,
      &error));
  CHECK(error.find("unknown key") != std::string::npos);
  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{@"DMRRunnerConfiguration" : @{@"ActivateOnLaunch" : @1}},
      &configuration, &error));
  CHECK(error.find("boolean") != std::string::npos);
  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{ @"DMRRunnerConfiguration" : @{ @"MessagePump" : @1 } },
      &configuration, &error));
  CHECK(error.find("dictionary") != std::string::npos);
  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{ @"DMRRunnerConfiguration" : @{
        @"MessagePump" : @{ @"Unknown" : @1 }
      } },
      &configuration, &error));
  CHECK(error.find("unknown key") != std::string::npos);
  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{ @"DMRRunnerConfiguration" : @{
        @"MessagePump" : @{ @"MaxMessagesPerTurn" : @0 }
      } },
      &configuration, &error));
  CHECK(error.find("hard bounds") != std::string::npos);
  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{ @"DMRRunnerConfiguration" : @{
        @"MessagePump" : @{
          @"MaxMessagesPerTurn" :
              @(dart_appkit::kMaximumDartMessagesPerTurn + 1)
        }
      } },
      &configuration, &error));
  CHECK(error.find("hard bounds") != std::string::npos);
  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{ @"DMRRunnerConfiguration" : @{
        @"MessagePump" : @{ @"MaxTimePerTurnMicros" : @1.5 }
      } },
      &configuration, &error));
  CHECK(error.find("integer") != std::string::npos);
  CHECK(configuration.message_pump_limits.max_messages_per_turn == 23);
}

void TestAlreadyEffectiveActivationPolicyIsAccepted() {
  NSApplication* application = [NSApplication sharedApplication];
  CHECK(application.activationPolicy ==
        NSApplicationActivationPolicyProhibited);

  dart_appkit::RunnerConfiguration configuration;
  configuration.activation_policy =
      dart_appkit::RunnerActivationPolicy::kProhibited;
  std::string error = "stale error";
  CHECK(dart_appkit::ApplyRunnerActivationPolicy(application, configuration,
                                                 &error));
  CHECK(error.empty());
  CHECK(application.activationPolicy ==
        NSApplicationActivationPolicyProhibited);
}

}  // namespace

int main() {
  TestDefaultsAndMissingMetadata();
  TestConfiguredValues();
  TestStrictFailureIsAtomic();
  TestAlreadyEffectiveActivationPolicyIsAccepted();
  if (g_failures != 0) {
    std::fprintf(stderr, "%d Runner configuration test(s) failed\n",
                 g_failures);
    return 1;
  }
  std::printf("all Runner configuration tests passed\n");
  return 0;
}
