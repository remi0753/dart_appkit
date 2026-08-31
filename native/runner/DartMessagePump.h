#ifndef DART_APPKIT_RUNNER_DART_MESSAGE_PUMP_H_
#define DART_APPKIT_RUNNER_DART_MESSAGE_PUMP_H_

#include <CoreFoundation/CoreFoundation.h>

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>

#include "include/dart_api.h"
#include "include/dart_engine.h"

namespace dart_appkit {

struct DartMessagePumpLimits {
  size_t max_messages_per_turn = 64;
  std::chrono::microseconds max_time_per_turn = std::chrono::microseconds(4000);
};

struct DartMessagePumpDebugStats {
  uint64_t accepted_notifications = 0;
  uint64_t handled_messages = 0;
  uint64_t drain_turns = 0;
  uint64_t resignaled_turns = 0;
  size_t max_messages_in_turn = 0;
  int64_t max_elapsed_micros = 0;
};

using DartMessageHandler = void (*)(Dart_Isolate isolate, void* context);

class DartMessagePump final {
 public:
  explicit DartMessagePump(DartMessagePumpLimits limits = {},
                           DartMessageHandler handler = nullptr,
                           void* handler_context = nullptr);
  ~DartMessagePump();

  bool Start(std::string* out_error);
  void Stop();
  DartEngine_MessageScheduler scheduler();
  DartMessagePumpDebugStats debug_stats() const;
  size_t pending_message_count() const;

  DartMessagePump(const DartMessagePump&) = delete;
  DartMessagePump& operator=(const DartMessagePump&) = delete;

 private:
  static void ScheduleMessage(Dart_Isolate isolate, void* context);
  static void PerformSource(void* info);
  static void DefaultHandleMessage(Dart_Isolate isolate, void* context);

  void Enqueue(Dart_Isolate isolate);
  void DrainOneTurn();
  void SignalAndWake(CFRunLoopSourceRef source, CFRunLoopRef run_loop);

  const DartMessagePumpLimits limits_;
  const DartMessageHandler handler_;
  void* const handler_context_;

  mutable std::mutex mutex_;
  std::deque<Dart_Isolate> pending_;
  CFRunLoopSourceRef source_ = nullptr;
  CFRunLoopRef run_loop_ = nullptr;
  bool running_ = false;
  DartMessagePumpDebugStats stats_;
};

}  // namespace dart_appkit

#endif  // DART_APPKIT_RUNNER_DART_MESSAGE_PUMP_H_
