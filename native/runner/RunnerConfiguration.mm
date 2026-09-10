#import <AppKit/AppKit.h>

#include <CoreFoundation/CoreFoundation.h>

#include <string>
#include <utility>

#include "RunnerConfiguration.h"

namespace dart_appkit {
namespace {

NSString* const kRunnerConfigurationKey = @"DMRRunnerConfiguration";
NSString* const kActivationPolicyKey = @"ActivationPolicy";
NSString* const kActivateOnLaunchKey = @"ActivateOnLaunch";
NSString* const kTerminateAfterLastWindowClosedKey =
    @"TerminateAfterLastWindowClosed";
NSString* const kReopenHandledKey = @"ReopenHandled";
NSString* const kMessagePumpKey = @"MessagePump";
NSString* const kMaxMessagesPerTurnKey = @"MaxMessagesPerTurn";
NSString* const kMaxTimePerTurnMicrosKey = @"MaxTimePerTurnMicros";

bool IsBoolean(id value) {
  return value != nil &&
         CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

bool ReadOptionalBoolean(NSDictionary* dictionary, NSString* key, bool* output,
                         std::string* out_error) {
  id value = [dictionary objectForKey:key];
  if (value == nil) {
    return true;
  }
  if (!IsBoolean(value)) {
    *out_error = std::string("Runner Info.plist value must be a boolean: ") +
                 key.UTF8String;
    return false;
  }
  *output = [(NSNumber*)value boolValue];
  return true;
}

bool ReadOptionalBoundedInteger(NSDictionary* dictionary, NSString* key,
                                int64_t maximum, int64_t* output,
                                std::string* out_error) {
  id value = [dictionary objectForKey:key];
  if (value == nil) {
    return true;
  }
  if (![value isKindOfClass:[NSNumber class]] || IsBoolean(value) ||
      CFNumberIsFloatType((__bridge CFNumberRef)value)) {
    *out_error = std::string("Runner Info.plist value must be an integer: ") +
                 key.UTF8String;
    return false;
  }
  const int64_t number = [(NSNumber*)value longLongValue];
  if (number <= 0 || number > maximum) {
    *out_error =
        std::string("Runner Info.plist integer is outside hard bounds: ") +
        key.UTF8String;
    return false;
  }
  *output = number;
  return true;
}

}  // namespace

bool LoadRunnerConfigurationFromInfoDictionary(
    NSDictionary* info_dictionary,
    RunnerConfiguration* configuration,
    std::string* out_error) {
  if (configuration == nullptr || out_error == nullptr) {
    return false;
  }
  out_error->clear();
  if (info_dictionary == nil) {
    return true;
  }

  id value = [info_dictionary objectForKey:kRunnerConfigurationKey];
  if (value == nil) {
    return true;
  }
  if (![value isKindOfClass:[NSDictionary class]]) {
    *out_error = "DMRRunnerConfiguration must be a dictionary";
    return false;
  }
  NSDictionary* dictionary = (NSDictionary*)value;
  NSSet<NSString*>* allowed_keys = [NSSet
      setWithObjects:kActivationPolicyKey, kActivateOnLaunchKey,
                     kTerminateAfterLastWindowClosedKey, kReopenHandledKey,
                     kMessagePumpKey, nil];
  for (id key in dictionary) {
    if (![key isKindOfClass:[NSString class]] ||
        ![allowed_keys containsObject:(NSString*)key]) {
      *out_error = "DMRRunnerConfiguration contains an unknown key";
      return false;
    }
  }

  RunnerConfiguration candidate = *configuration;
  id activation_value = [dictionary objectForKey:kActivationPolicyKey];
  if (activation_value != nil) {
    if (![activation_value isKindOfClass:[NSString class]]) {
      *out_error = "Runner ActivationPolicy must be a string";
      return false;
    }
    NSString* activation = (NSString*)activation_value;
    if ([activation isEqualToString:@"regular"]) {
      candidate.activation_policy = RunnerActivationPolicy::kRegular;
    } else if ([activation isEqualToString:@"accessory"]) {
      candidate.activation_policy = RunnerActivationPolicy::kAccessory;
    } else if ([activation isEqualToString:@"prohibited"]) {
      candidate.activation_policy = RunnerActivationPolicy::kProhibited;
    } else {
      *out_error = "Runner ActivationPolicy is invalid";
      return false;
    }
  }
  if (!ReadOptionalBoolean(dictionary, kActivateOnLaunchKey,
                           &candidate.activate_on_launch, out_error) ||
      !ReadOptionalBoolean(dictionary, kTerminateAfterLastWindowClosedKey,
                           &candidate.terminate_after_last_window_closed,
                           out_error) ||
      !ReadOptionalBoolean(dictionary, kReopenHandledKey,
                           &candidate.reopen_handled, out_error)) {
    return false;
  }
  id message_pump_value = [dictionary objectForKey:kMessagePumpKey];
  if (message_pump_value != nil) {
    if (![message_pump_value isKindOfClass:[NSDictionary class]]) {
      *out_error = "Runner MessagePump must be a dictionary";
      return false;
    }
    NSDictionary* message_pump = (NSDictionary*)message_pump_value;
    NSSet<NSString*>* message_pump_keys = [NSSet
        setWithObjects:kMaxMessagesPerTurnKey, kMaxTimePerTurnMicrosKey, nil];
    for (id key in message_pump) {
      if (![key isKindOfClass:[NSString class]] ||
          ![message_pump_keys containsObject:(NSString*)key]) {
        *out_error = "Runner MessagePump contains an unknown key";
        return false;
      }
    }
    int64_t max_messages = static_cast<int64_t>(
        candidate.message_pump_limits.max_messages_per_turn);
    int64_t max_time_micros =
        candidate.message_pump_limits.max_time_per_turn.count();
    if (!ReadOptionalBoundedInteger(
            message_pump, kMaxMessagesPerTurnKey,
            static_cast<int64_t>(kMaximumDartMessagesPerTurn), &max_messages,
            out_error) ||
        !ReadOptionalBoundedInteger(
            message_pump, kMaxTimePerTurnMicrosKey,
            kMaximumDartMessageTimeMicros, &max_time_micros, out_error)) {
      return false;
    }
    candidate.message_pump_limits.max_messages_per_turn =
        static_cast<size_t>(max_messages);
    candidate.message_pump_limits.max_time_per_turn =
        std::chrono::microseconds(max_time_micros);
  }
  *configuration = std::move(candidate);
  return true;
}

bool LoadRunnerConfigurationFromMainBundle(RunnerConfiguration* configuration,
                                           std::string* out_error) {
  return LoadRunnerConfigurationFromInfoDictionary(
      NSBundle.mainBundle.infoDictionary, configuration, out_error);
}

bool ApplyRunnerActivationPolicy(NSApplication* application,
                                 const RunnerConfiguration& configuration,
                                 std::string* out_error) {
  if (application == nil || out_error == nullptr) {
    return false;
  }
  NSApplicationActivationPolicy policy;
  switch (configuration.activation_policy) {
    case RunnerActivationPolicy::kRegular:
      policy = NSApplicationActivationPolicyRegular;
      break;
    case RunnerActivationPolicy::kAccessory:
      policy = NSApplicationActivationPolicyAccessory;
      break;
    case RunnerActivationPolicy::kProhibited:
      policy = NSApplicationActivationPolicyProhibited;
      break;
  }
  if (application.activationPolicy == policy) {
    out_error->clear();
    return true;
  }
  if (![application setActivationPolicy:policy]) {
    *out_error = "AppKit rejected the configured activation policy";
    return false;
  }
  out_error->clear();
  return true;
}

}  // namespace dart_appkit
