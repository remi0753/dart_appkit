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
}

void TestConfiguredValues() {
  NSDictionary* info = @{
    @"DMRRunnerConfiguration" : @{
      @"ActivationPolicy" : @"accessory",
      @"ActivateOnLaunch" : @NO,
      @"TerminateAfterLastWindowClosed" : @YES,
      @"ReopenHandled" : @NO,
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
}

void TestStrictFailureIsAtomic() {
  dart_appkit::RunnerConfiguration configuration;
  configuration.activation_policy =
      dart_appkit::RunnerActivationPolicy::kProhibited;
  configuration.reopen_handled = false;
  std::string error;
  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{@"DMRRunnerConfiguration" : @{@"ActivationPolicy" : @"invalid"}},
      &configuration, &error));
  CHECK(!error.empty());
  CHECK(configuration.activation_policy ==
        dart_appkit::RunnerActivationPolicy::kProhibited);
  CHECK(!configuration.reopen_handled);

  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{@"DMRRunnerConfiguration" : @{@"Unknown" : @YES}}, &configuration,
      &error));
  CHECK(error.find("unknown key") != std::string::npos);
  CHECK(!dart_appkit::LoadRunnerConfigurationFromInfoDictionary(
      @{@"DMRRunnerConfiguration" : @{@"ActivateOnLaunch" : @1}},
      &configuration, &error));
  CHECK(error.find("boolean") != std::string::npos);
}

}  // namespace

int main() {
  TestDefaultsAndMissingMetadata();
  TestConfiguredValues();
  TestStrictFailureIsAtomic();
  if (g_failures != 0) {
    std::fprintf(stderr, "%d Runner configuration test(s) failed\n",
                 g_failures);
    return 1;
  }
  std::printf("all Runner configuration tests passed\n");
  return 0;
}
