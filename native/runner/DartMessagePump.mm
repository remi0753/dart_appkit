#include "DartMessagePump.h"

#include <pthread.h>
#include <algorithm>
#include <chrono>

namespace dart_appkit {

DartMessagePump::DartMessagePump(DartMessagePumpLimits limits,
                                 DartMessageHandler handler,
                                 void* handler_context)
    : limits_(limits),
      handler_(handler == nullptr ? DefaultHandleMessage : handler),
      handler_context_(handler_context) {}

DartMessagePump::~DartMessagePump() { Stop(); }

bool DartMessagePump::Start(std::string* out_error) {
  if (out_error != nullptr) {
    out_error->clear();
  }
  if (pthread_main_np() == 0) {
    if (out_error != nullptr) {
      *out_error = "Dart message pump must start on the process main thread";
    }
    return false;
  }
  if (limits_.max_messages_per_turn == 0 ||
      limits_.max_time_per_turn.count() <= 0) {
    if (out_error != nullptr) {
      *out_error = "Dart message pump limits must be greater than zero";
    }
    return false;
  }

  {
    const std::lock_guard<std::mutex> lock(mutex_);
    if (running_) {
      return true;
    }
  }

  CFRunLoopSourceContext source_context = {};
  source_context.info = this;
  source_context.perform = PerformSource;
  CFRunLoopSourceRef source =
      CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &source_context);
  if (source == nullptr) {
    if (out_error != nullptr) {
      *out_error = "could not create the Dart CFRunLoopSource";
    }
    return false;
  }

  CFRunLoopRef run_loop = CFRunLoopGetMain();
  CFRetain(run_loop);
  CFRunLoopAddSource(run_loop, source, kCFRunLoopCommonModes);
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    source_ = source;
    run_loop_ = run_loop;
    running_ = true;
  }
  return true;
}

void DartMessagePump::Stop() {
  CFRunLoopSourceRef source = nullptr;
  CFRunLoopRef run_loop = nullptr;
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    running_ = false;
    pending_.clear();
    source = source_;
    run_loop = run_loop_;
    source_ = nullptr;
    run_loop_ = nullptr;
  }

  if (source != nullptr) {
    if (run_loop != nullptr) {
      CFRunLoopRemoveSource(run_loop, source, kCFRunLoopCommonModes);
    }
    CFRunLoopSourceInvalidate(source);
    CFRelease(source);
  }
  if (run_loop != nullptr) {
    CFRelease(run_loop);
  }
}

DartEngine_MessageScheduler DartMessagePump::scheduler() {
  return DartEngine_MessageScheduler{ScheduleMessage, this};
}

void DartMessagePump::ScheduleMessage(Dart_Isolate isolate, void* context) {
  if (context == nullptr || isolate == nullptr) {
    return;
  }
  static_cast<DartMessagePump*>(context)->Enqueue(isolate);
}

void DartMessagePump::PerformSource(void* info) {
  if (info != nullptr) {
    static_cast<DartMessagePump*>(info)->DrainOneTurn();
  }
}

void DartMessagePump::DefaultHandleMessage(Dart_Isolate isolate,
                                           void* context) {
  (void)context;
  DartEngine_HandleMessage(isolate);
}

void DartMessagePump::Enqueue(Dart_Isolate isolate) {
  CFRunLoopSourceRef source = nullptr;
  CFRunLoopRef run_loop = nullptr;
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    if (!running_ || source_ == nullptr || run_loop_ == nullptr) {
      return;
    }
    pending_.push_back(isolate);
    ++stats_.accepted_notifications;
    source = source_;
    run_loop = run_loop_;
    CFRetain(source);
    CFRetain(run_loop);
  }
  SignalAndWake(source, run_loop);
  CFRelease(source);
  CFRelease(run_loop);
}

void DartMessagePump::DrainOneTurn() {
  if (pthread_main_np() == 0) {
    return;
  }

  const auto started = std::chrono::steady_clock::now();
  size_t handled_this_turn = 0;
  while (handled_this_turn < limits_.max_messages_per_turn) {
    Dart_Isolate isolate = nullptr;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (!running_ || pending_.empty()) {
        break;
      }
      isolate = pending_.front();
      pending_.pop_front();
    }

    handler_(isolate, handler_context_);
    ++handled_this_turn;
    if (std::chrono::steady_clock::now() - started >=
        limits_.max_time_per_turn) {
      break;
    }
  }

  const int64_t elapsed_micros =
      std::chrono::duration_cast<std::chrono::microseconds>(
          std::chrono::steady_clock::now() - started)
          .count();
  CFRunLoopSourceRef source = nullptr;
  CFRunLoopRef run_loop = nullptr;
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    if (handled_this_turn != 0) {
      stats_.handled_messages += handled_this_turn;
      ++stats_.drain_turns;
      stats_.max_messages_in_turn =
          std::max(stats_.max_messages_in_turn, handled_this_turn);
      stats_.max_elapsed_micros =
          std::max(stats_.max_elapsed_micros, elapsed_micros);
    }
    if (running_ && !pending_.empty() && source_ != nullptr &&
        run_loop_ != nullptr) {
      ++stats_.resignaled_turns;
      source = source_;
      run_loop = run_loop_;
      CFRetain(source);
      CFRetain(run_loop);
    }
  }

  if (source != nullptr && run_loop != nullptr) {
    SignalAndWake(source, run_loop);
    CFRelease(source);
    CFRelease(run_loop);
  }
}

void DartMessagePump::SignalAndWake(CFRunLoopSourceRef source,
                                    CFRunLoopRef run_loop) {
  CFRunLoopSourceSignal(source);
  CFRunLoopWakeUp(run_loop);
}

DartMessagePumpDebugStats DartMessagePump::debug_stats() const {
  const std::lock_guard<std::mutex> lock(mutex_);
  return stats_;
}

size_t DartMessagePump::pending_message_count() const {
  const std::lock_guard<std::mutex> lock(mutex_);
  return pending_.size();
}

}  // namespace dart_appkit
