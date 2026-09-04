#import <AppKit/AppKit.h>

#include "ReleaseAotHost.h"

#include <pthread.h>

#include <cstdio>
#include <cstdlib>
#include <string_view>
#include <utility>

#include "BridgeInternal.h"
#include "DartEventEncoder.h"
#include "DartMessagePump.h"
#include "include/dart_engine.h"
#include "include/dart_native_api.h"

#ifndef DMR_DART_SDK_VERSION
#define DMR_DART_SDK_VERSION "unknown"
#endif

namespace dart_macos_runtime {
namespace {

class EnteredIsolate final {
 public:
  explicit EnteredIsolate(Dart_Isolate isolate) {
    DartEngine_AcquireIsolate(isolate);
    Dart_EnterScope();
  }

  ~EnteredIsolate() {
    Dart_ExitScope();
    DartEngine_ReleaseIsolate();
  }

  EnteredIsolate(const EnteredIsolate&) = delete;
  EnteredIsolate& operator=(const EnteredIsolate&) = delete;
};

std::string CopyDartError(Dart_Handle handle) {
  if (!Dart_IsError(handle)) {
    return {};
  }
  const char* error = Dart_GetError(handle);
  return error == nullptr ? "unknown Dart error" : std::string(error);
}

std::string CopyAndFreeError(char* error) {
  if (error == nullptr) {
    return {};
  }
  std::string result(error);
  std::free(error);
  return result;
}

void RequestApplicationTermination() {
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp terminate:nil];
  });
}

}  // namespace

std::atomic<ReleaseAotHost*> ReleaseAotHost::active_host_{nullptr};

ReleaseAotHost::ReleaseAotHost(dart_appkit::DartMessagePump* message_pump)
    : message_pump_(message_pump) {}

ReleaseAotHost::~ReleaseAotHost() { Shutdown(); }

bool ReleaseAotHost::Start(const std::string& snapshot_path,
                           const std::vector<std::string>& arguments,
                           std::string* out_error) {
  if (pthread_main_np() == 0) {
    *out_error = "release AOT host must start on the process main thread";
    return false;
  }
  if (message_pump_ == nullptr || snapshot_path.empty()) {
    *out_error = "release AOT host configuration is incomplete";
    return false;
  }
  const char* version = Dart_VersionString();
  if (version == nullptr ||
      std::string_view(version).find(DMR_DART_SDK_VERSION) ==
          std::string_view::npos) {
    *out_error = "Dart Engine runtime version does not match application SDK " +
                 std::string(DMR_DART_SDK_VERSION);
    return false;
  }

  char* engine_error = nullptr;
  if (!DartEngine_Init(&engine_error)) {
    *out_error = "could not initialize release AOT Dart Engine";
    const std::string detail = CopyAndFreeError(engine_error);
    if (!detail.empty()) {
      *out_error += ": " + detail;
    }
    return false;
  }
  engine_started_ = true;
  DartEngine_SetDefaultMessageScheduler(message_pump_->scheduler());
  DartEngine_SetHandleMessageErrorCallback(HandleMessageError);

  const DartEngine_SnapshotData snapshot =
      DartEngine_AotSnapshotFromFile(snapshot_path.c_str(), &engine_error);
  if (engine_error != nullptr) {
    *out_error = "could not load release AOT snapshot: " +
                 CopyAndFreeError(engine_error);
    Shutdown();
    return false;
  }
  isolate_ = DartEngine_CreateIsolate(snapshot, &engine_error);
  if (isolate_ == nullptr || engine_error != nullptr) {
    *out_error = "could not create release AOT root isolate: " +
                 CopyAndFreeError(engine_error);
    isolate_ = nullptr;
    Shutdown();
    return false;
  }
  DartEngine_SetMessageScheduler(message_pump_->scheduler(), isolate_);
  active_host_.store(this, std::memory_order_release);
  dart_appkit::InstallEventPoster(PostNativeEvent, this);
  if (!InvokeMain(arguments, out_error)) {
    Shutdown();
    return false;
  }
  return true;
}

void ReleaseAotHost::Shutdown() {
  ReleaseAotHost* expected = this;
  active_host_.compare_exchange_strong(expected, nullptr,
                                       std::memory_order_acq_rel);
  dart_appkit::DisableEventPoster();
  if (engine_started_) {
    DartEngine_SetHandleMessageErrorCallback(nullptr);
    DartEngine_Shutdown();
    engine_started_ = false;
    isolate_ = nullptr;
  }
}

bool ReleaseAotHost::has_fatal_error() const {
  const std::lock_guard<std::mutex> lock(fatal_error_mutex_);
  return !fatal_error_.empty();
}

std::string ReleaseAotHost::fatal_error() const {
  const std::lock_guard<std::mutex> lock(fatal_error_mutex_);
  return fatal_error_;
}

bool ReleaseAotHost::InvokeMain(const std::vector<std::string>& arguments,
                                std::string* out_error) {
  EnteredIsolate entered(isolate_);
  Dart_Handle core = Dart_LookupLibrary(Dart_NewStringFromCString("dart:core"));
  if (Dart_IsError(core)) {
    *out_error = CopyDartError(core);
    return false;
  }
  Dart_Handle string_type = Dart_GetNonNullableType(
      core, Dart_NewStringFromCString("String"), 0, nullptr);
  if (Dart_IsError(string_type)) {
    *out_error = CopyDartError(string_type);
    return false;
  }
  Dart_Handle dart_arguments = Dart_NewListOfTypeFilled(
      string_type, Dart_NewStringFromCString(""), arguments.size());
  if (Dart_IsError(dart_arguments)) {
    *out_error = CopyDartError(dart_arguments);
    return false;
  }
  for (size_t index = 0; index < arguments.size(); ++index) {
    Dart_Handle result =
        Dart_ListSetAt(dart_arguments, index,
                       Dart_NewStringFromCString(arguments[index].c_str()));
    if (Dart_IsError(result)) {
      *out_error = CopyDartError(result);
      return false;
    }
  }
  Dart_Handle invocation_arguments[] = {dart_arguments};
  Dart_Handle result =
      Dart_Invoke(Dart_RootLibrary(), Dart_NewStringFromCString("main"), 1,
                  invocation_arguments);
  if (Dart_IsError(result)) {
    *out_error = "Dart main failed: " + CopyDartError(result);
    return false;
  }
  result = DartEngine_DrainMicrotasksQueue();
  if (Dart_IsError(result)) {
    *out_error = "Dart startup microtask failed: " + CopyDartError(result);
    return false;
  }
  return true;
}

void ReleaseAotHost::RecordFatalError(std::string message) {
  {
    const std::lock_guard<std::mutex> lock(fatal_error_mutex_);
    if (!fatal_error_.empty()) {
      return;
    }
    fatal_error_ = std::move(message);
  }
  std::fprintf(stderr, "Unhandled Dart message error: %s\n",
               fatal_error().c_str());
  RequestApplicationTermination();
}

void ReleaseAotHost::HandleMessageError(Dart_Handle error,
                                        Dart_Isolate destination_isolate) {
  (void)destination_isolate;
  ReleaseAotHost* host = active_host_.load(std::memory_order_acquire);
  if (host != nullptr) {
    host->RecordFatalError(CopyDartError(error));
  }
}

bool ReleaseAotHost::PostNativeEvent(int64_t dart_port,
                                     uint32_t event_protocol_version,
                                     const dart_appkit::NativeEvent& event,
                                     void* context) {
  (void)context;
  return dart_appkit::PostNativeEventToDartPort(dart_port,
                                                event_protocol_version, event);
}

}  // namespace dart_macos_runtime
