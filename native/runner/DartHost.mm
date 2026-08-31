#include "DartHost.h"

#import <AppKit/AppKit.h>

#include <pthread.h>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <string_view>

#include "include/dart_engine.h"
#include "include/dart_native_api.h"

#ifndef DA_DART_ENGINE_REVISION
#define DA_DART_ENGINE_REVISION "unknown"
#endif

namespace dart_appkit {
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

}  // namespace

std::atomic<DartHost*> DartHost::active_host_{nullptr};

DartHost::DartHost(DartMessagePump* message_pump)
    : message_pump_(message_pump) {}

DartHost::~DartHost() { Shutdown(); }

bool DartHost::Start(const RunnerConfiguration& configuration,
                     std::string* out_error) {
  if (pthread_main_np() == 0) {
    *out_error =
        "DartHost must start the root isolate on the process main thread";
    return false;
  }
  if (message_pump_ == nullptr) {
    *out_error = "DartHost requires a message pump";
    return false;
  }
  if (configuration.kernel_path.empty()) {
    *out_error = "Kernel path is empty";
    return false;
  }

  const char* runtime_version = Dart_VersionString();
  if (!configuration.expected_sdk_version.empty() &&
      (runtime_version == nullptr ||
       std::string_view(runtime_version)
               .find(configuration.expected_sdk_version) ==
           std::string_view::npos)) {
    *out_error = "Dart Engine runtime version does not match launcher SDK " +
                 configuration.expected_sdk_version;
    return false;
  }
  if (!configuration.expected_sdk_revision.empty() &&
      configuration.expected_sdk_revision != DA_DART_ENGINE_REVISION) {
    *out_error = "Dart Engine revision " +
                 std::string(DA_DART_ENGINE_REVISION) +
                 " does not match launcher SDK revision " +
                 configuration.expected_sdk_revision;
    return false;
  }

  char* engine_error = nullptr;
  if (!DartEngine_Init(&engine_error)) {
    const std::string detail = CopyAndFreeError(engine_error);
    *out_error = "could not initialize Dart Engine";
    if (!detail.empty()) {
      *out_error += ": " + detail;
    }
    return false;
  }
  engine_started_ = true;
  DartEngine_SetDefaultMessageScheduler(message_pump_->scheduler());
  DartEngine_SetHandleMessageErrorCallback(HandleMessageError);

  const DartEngine_SnapshotData snapshot = DartEngine_KernelFromFile(
      configuration.kernel_path.c_str(), &engine_error);
  if (engine_error != nullptr) {
    *out_error = "could not read Kernel: " + CopyAndFreeError(engine_error);
    Shutdown();
    return false;
  }

  isolate_ = DartEngine_CreateIsolate(snapshot, &engine_error);
  if (engine_error != nullptr || isolate_ == nullptr) {
    *out_error =
        "could not create root isolate: " + CopyAndFreeError(engine_error);
    isolate_ = nullptr;
    Shutdown();
    return false;
  }
  DartEngine_SetMessageScheduler(message_pump_->scheduler(), isolate_);
  active_host_.store(this, std::memory_order_release);
  InstallEventPoster(PostNativeEvent, this);

  if (!InvokeMain(configuration.application_arguments, out_error)) {
    Shutdown();
    return false;
  }
  return true;
}

bool DartHost::InvokeMain(const std::vector<std::string>& arguments,
                          std::string* out_error) {
  EnteredIsolate entered(isolate_);

  Dart_Handle core_library =
      Dart_LookupLibrary(Dart_NewStringFromCString("dart:core"));
  if (Dart_IsError(core_library)) {
    *out_error = CopyDartError(core_library);
    return false;
  }
  Dart_Handle string_type = Dart_GetNonNullableType(
      core_library, Dart_NewStringFromCString("String"), 0, nullptr);
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

void DartHost::Shutdown() {
  DartHost* expected = this;
  active_host_.compare_exchange_strong(expected, nullptr,
                                       std::memory_order_acq_rel);
  DisableEventPoster();
  DartEngine_SetHandleMessageErrorCallback(nullptr);
  if (engine_started_) {
    DartEngine_Shutdown();
    engine_started_ = false;
    isolate_ = nullptr;
  }
}

bool DartHost::has_fatal_error() const {
  const std::lock_guard<std::mutex> lock(fatal_error_mutex_);
  return !fatal_error_.empty();
}

std::string DartHost::fatal_error() const {
  const std::lock_guard<std::mutex> lock(fatal_error_mutex_);
  return fatal_error_;
}

void DartHost::RecordFatalError(std::string message) {
  {
    const std::lock_guard<std::mutex> lock(fatal_error_mutex_);
    if (!fatal_error_.empty()) {
      return;
    }
    fatal_error_ = std::move(message);
  }
  std::fprintf(stderr, "Unhandled Dart message error: %s\n",
               fatal_error().c_str());
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp terminate:nil];
  });
}

void DartHost::HandleMessageError(Dart_Handle error,
                                  Dart_Isolate destination_isolate) {
  (void)destination_isolate;
  DartHost* host = active_host_.load(std::memory_order_acquire);
  if (host != nullptr) {
    host->RecordFatalError(CopyDartError(error));
  }
}

void DartHost::SetInt64(Dart_CObject* object, int64_t value) {
  object->type = Dart_CObject_kInt64;
  object->value.as_int64 = value;
}

void DartHost::SetDouble(Dart_CObject* object, double value) {
  object->type = Dart_CObject_kDouble;
  object->value.as_double = value;
}

void DartHost::SetBool(Dart_CObject* object, bool value) {
  object->type = Dart_CObject_kBool;
  object->value.as_bool = value;
}

void DartHost::SetString(Dart_CObject* object, const std::string& value) {
  object->type = Dart_CObject_kString;
  object->value.as_string = value.c_str();
}

bool DartHost::PostNativeEvent(int64_t dart_port, const NativeEvent& event,
                               void* context) {
  (void)context;
  std::array<Dart_CObject, 9> values{};
  std::array<Dart_CObject*, 9> pointers{};
  for (size_t index = 0; index < pointers.size(); ++index) {
    pointers[index] = &values[index];
  }

  SetInt64(&values[0], DA_ABI_VERSION);
  SetInt64(&values[1], event.type);
  SetInt64(&values[2], static_cast<int64_t>(event.window));
  SetInt64(&values[3], event.monotonic_micros);

  intptr_t length = 4;
  switch (event.type) {
    case DA_EVENT_WINDOW_CLOSED:
      break;
    case DA_EVENT_WINDOW_RESIZED:
      length = 6;
      SetDouble(&values[4], event.width);
      SetDouble(&values[5], event.height);
      break;
    case DA_EVENT_MOUSE_DOWN:
    case DA_EVENT_MOUSE_UP:
    case DA_EVENT_MOUSE_MOVED:
    case DA_EVENT_MOUSE_DRAGGED:
      length = 9;
      SetDouble(&values[4], event.x);
      SetDouble(&values[5], event.y);
      SetInt64(&values[6], event.button);
      SetInt64(&values[7], event.modifiers);
      SetInt64(&values[8], event.click_count);
      break;
    case DA_EVENT_KEY_DOWN:
    case DA_EVENT_KEY_UP:
      length = 9;
      SetInt64(&values[4], event.key_code);
      SetInt64(&values[5], event.modifiers);
      SetBool(&values[6], event.is_repeat);
      SetString(&values[7], event.characters);
      SetString(&values[8], event.characters_ignoring_modifiers);
      break;
    default:
      return false;
  }

  Dart_CObject message{};
  message.type = Dart_CObject_kArray;
  message.value.as_array.length = length;
  message.value.as_array.values = pointers.data();
  return Dart_PostCObject(dart_port, &message);
}

}  // namespace dart_appkit
