#include <CoreFoundation/CoreFoundation.h>
#include <pthread.h>

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "DartMessagePump.h"

extern "C" void DartEngine_HandleMessage(Dart_Isolate isolate) {
  (void)isolate;
}

namespace {

int g_failures = 0;

void Check(bool condition, const char* expression, int line) {
  if (!condition) {
    std::fprintf(stderr, "FAIL line %d: %s\n", line, expression);
    ++g_failures;
  }
}

#define CHECK(expression) Check((expression), #expression, __LINE__)

class Recorder final {
 public:
  explicit Recorder(std::chrono::microseconds delay = {}) : delay_(delay) {}

  static void Handle(Dart_Isolate isolate, void* context) {
    auto* recorder = static_cast<Recorder*>(context);
    if (recorder->delay_.count() > 0) {
      std::this_thread::sleep_for(recorder->delay_);
    }
    const std::lock_guard<std::mutex> lock(recorder->mutex_);
    recorder->all_on_main_thread_ =
        recorder->all_on_main_thread_ && pthread_main_np() != 0;
    recorder->values_.push_back(reinterpret_cast<uintptr_t>(isolate));
  }

  size_t count() const {
    const std::lock_guard<std::mutex> lock(mutex_);
    return values_.size();
  }

  bool all_on_main_thread() const {
    const std::lock_guard<std::mutex> lock(mutex_);
    return all_on_main_thread_;
  }

  std::vector<uintptr_t> values() const {
    const std::lock_guard<std::mutex> lock(mutex_);
    return values_;
  }

 private:
  const std::chrono::microseconds delay_;
  mutable std::mutex mutex_;
  std::vector<uintptr_t> values_;
  bool all_on_main_thread_ = true;
};

Dart_Isolate FakeIsolate(uintptr_t value) {
  return reinterpret_cast<Dart_Isolate>(value);
}

bool RunMainLoopUntil(const Recorder& recorder, size_t expected_count,
                      std::chrono::milliseconds timeout) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (recorder.count() < expected_count &&
         std::chrono::steady_clock::now() < deadline) {
    (void)CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
  }
  return recorder.count() == expected_count;
}

void TestRejectsNonMainStartAndInvalidLimits() {
  dart_appkit::DartMessagePump pump;
  bool started = true;
  std::string error;
  std::thread worker([&] { started = pump.Start(&error); });
  worker.join();
  CHECK(!started);
  CHECK(error.find("main thread") != std::string::npos);

  dart_appkit::DartMessagePumpLimits limits;
  limits.max_messages_per_turn = 0;
  dart_appkit::DartMessagePump invalid(limits);
  CHECK(!invalid.Start(&error));
  CHECK(error.find("greater than zero") != std::string::npos);
}

void TestFifoMainThreadAndMessageBudget() {
  constexpr size_t kMessageCount = 200;
  constexpr size_t kBatchLimit = 7;

  dart_appkit::DartMessagePumpLimits limits;
  limits.max_messages_per_turn = kBatchLimit;
  limits.max_time_per_turn = std::chrono::seconds(1);
  Recorder recorder;
  dart_appkit::DartMessagePump pump(limits, Recorder::Handle, &recorder);
  std::string error;
  CHECK(pump.Start(&error));
  CHECK(pump.Start(&error));

  const DartEngine_MessageScheduler scheduler = pump.scheduler();
  std::thread producer([&] {
    for (uintptr_t value = 1; value <= kMessageCount; ++value) {
      scheduler.schedule_callback(FakeIsolate(value), scheduler.context);
    }
  });
  producer.join();

  CHECK(RunMainLoopUntil(recorder, kMessageCount,
                         std::chrono::milliseconds(3000)));
  CHECK(recorder.all_on_main_thread());
  const std::vector<uintptr_t> values = recorder.values();
  CHECK(values.size() == kMessageCount);
  for (uintptr_t index = 0; index < values.size(); ++index) {
    CHECK(values[index] == index + 1);
  }

  const dart_appkit::DartMessagePumpDebugStats stats = pump.debug_stats();
  CHECK(stats.accepted_notifications == kMessageCount);
  CHECK(stats.handled_messages == kMessageCount);
  CHECK(stats.max_messages_in_turn <= kBatchLimit);
  CHECK(stats.drain_turns >= (kMessageCount + kBatchLimit - 1) / kBatchLimit);
  CHECK(stats.resignaled_turns > 0);
  CHECK(pump.pending_message_count() == 0);

  pump.Stop();
  scheduler.schedule_callback(FakeIsolate(kMessageCount + 1),
                              scheduler.context);
  (void)CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false);
  CHECK(recorder.count() == kMessageCount);
  CHECK(pump.pending_message_count() == 0);
  CHECK(pump.debug_stats().accepted_notifications == kMessageCount);
}

void TestTimeBudgetSplitsSlowBurst() {
  constexpr size_t kMessageCount = 18;
  dart_appkit::DartMessagePumpLimits limits;
  limits.max_messages_per_turn = 1000;
  limits.max_time_per_turn = std::chrono::microseconds(1000);
  Recorder recorder(std::chrono::microseconds(400));
  dart_appkit::DartMessagePump pump(limits, Recorder::Handle, &recorder);
  std::string error;
  CHECK(pump.Start(&error));

  const DartEngine_MessageScheduler scheduler = pump.scheduler();
  for (uintptr_t value = 1; value <= kMessageCount; ++value) {
    scheduler.schedule_callback(FakeIsolate(value), scheduler.context);
  }

  CHECK(RunMainLoopUntil(recorder, kMessageCount,
                         std::chrono::milliseconds(3000)));
  const dart_appkit::DartMessagePumpDebugStats stats = pump.debug_stats();
  CHECK(stats.handled_messages == kMessageCount);
  CHECK(stats.drain_turns > 1);
  CHECK(stats.resignaled_turns > 0);
  CHECK(stats.max_messages_in_turn < kMessageCount);
  CHECK(stats.max_elapsed_micros >= limits.max_time_per_turn.count());
  pump.Stop();
}

}  // namespace

int main() {
  CHECK(pthread_main_np() != 0);
  TestRejectsNonMainStartAndInvalidLimits();
  TestFifoMainThreadAndMessageBudget();
  TestTimeBudgetSplitsSlowBurst();
  if (g_failures != 0) {
    std::fprintf(stderr, "%d Dart message pump test(s) failed\n", g_failures);
    return 1;
  }
  std::printf("all Dart message pump tests passed\n");
  return 0;
}
