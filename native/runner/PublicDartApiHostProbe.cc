#include <dlfcn.h>
#include <pthread.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <iostream>
#include <mutex>
#include <new>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

#include "include/dart_api.h"
#include "include/dart_native_api.h"

namespace dart_appkit {
namespace {

using Clock = std::chrono::steady_clock;

struct IsolateState {
  bool is_root = false;
};

struct ProbeState {
  std::mutex mutex;
  std::condition_variable condition;
  std::deque<Dart_Isolate> root_messages;
  bool report_received = false;
  std::string report_kind;
  std::string report_detail;
  std::string message_error;
  std::atomic<int> child_initializations{0};
  std::atomic<int> isolate_shutdowns{0};
  std::atomic<int> isolate_cleanups{0};
  std::atomic<int> group_cleanups{0};
};

ProbeState* g_probe_state = nullptr;

std::string Sanitize(std::string value) {
  for (char& character : value) {
    if (character == '\n' || character == '\r') {
      character = '|';
    }
  }
  return value;
}

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

char* CopyError(const char* message) {
  const size_t length = std::strlen(message);
  auto* result = static_cast<char*>(std::malloc(length + 1));
  if (result != nullptr) {
    std::memcpy(result, message, length + 1);
  }
  return result;
}

std::vector<uint8_t> ReadBytes(const std::string& path, std::string* error) {
  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input) {
    *error = "could not open " + path;
    return {};
  }
  const std::streamsize size = input.tellg();
  if (size <= 0) {
    *error = "input is empty: " + path;
    return {};
  }
  input.seekg(0, std::ios::beg);
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  if (!input.read(reinterpret_cast<char*>(bytes.data()), size)) {
    *error = "could not read " + path;
    return {};
  }
  return bytes;
}

void* OpenFile(const char* name, bool write) {
  return std::fopen(name, write ? "wb" : "rb");
}

void ReadFile(uint8_t** data, intptr_t* file_length, void* stream) {
  *data = nullptr;
  *file_length = -1;
  auto* file = static_cast<FILE*>(stream);
  if (file == nullptr || std::fseek(file, 0, SEEK_END) != 0) {
    return;
  }
  const long length = std::ftell(file);
  if (length < 0 || std::fseek(file, 0, SEEK_SET) != 0) {
    return;
  }
  auto* buffer =
      static_cast<uint8_t*>(std::malloc(static_cast<size_t>(length)));
  if (buffer == nullptr && length != 0) {
    return;
  }
  const size_t read = std::fread(buffer, 1, static_cast<size_t>(length), file);
  if (read != static_cast<size_t>(length)) {
    std::free(buffer);
    return;
  }
  *data = buffer;
  *file_length = static_cast<intptr_t>(length);
}

void WriteFile(const void* data, intptr_t length, void* stream) {
  auto* file = static_cast<FILE*>(stream);
  if (file != nullptr && length > 0) {
    std::ignore = std::fwrite(data, 1, static_cast<size_t>(length), file);
  }
}

void CloseFile(void* stream) {
  auto* file = static_cast<FILE*>(stream);
  if (file != nullptr) {
    std::ignore = std::fclose(file);
  }
}

bool SupplyEntropy(uint8_t* buffer, intptr_t length) {
  if (buffer == nullptr || length < 0) {
    return false;
  }
  arc4random_buf(buffer, static_cast<size_t>(length));
  return true;
}

void RootMessageNotify(Dart_Isolate destination_isolate) {
  ProbeState* state = g_probe_state;
  if (state == nullptr) {
    return;
  }
  {
    const std::lock_guard<std::mutex> lock(state->mutex);
    state->root_messages.push_back(destination_isolate);
  }
  state->condition.notify_all();
}

bool InitializeChild(void** child_isolate_data, char** error) {
  auto* state = new (std::nothrow) IsolateState();
  if (state == nullptr) {
    *error = CopyError("could not allocate public-host child state");
    return false;
  }
  *child_isolate_data = state;
  if (g_probe_state != nullptr) {
    g_probe_state->child_initializations.fetch_add(1,
                                                   std::memory_order_relaxed);
  }
  return true;
}

void ShutdownIsolate(void* isolate_group_data, void* isolate_data) {
  (void)isolate_group_data;
  (void)isolate_data;
  if (g_probe_state != nullptr) {
    g_probe_state->isolate_shutdowns.fetch_add(1, std::memory_order_relaxed);
  }
}

void CleanupIsolate(void* isolate_group_data, void* isolate_data) {
  (void)isolate_group_data;
  auto* state = static_cast<IsolateState*>(isolate_data);
  if (g_probe_state != nullptr) {
    g_probe_state->isolate_cleanups.fetch_add(1, std::memory_order_relaxed);
  }
  if (state != nullptr && !state->is_root) {
    delete state;
  }
}

void CleanupGroup(void* isolate_group_data) {
  (void)isolate_group_data;
  if (g_probe_state != nullptr) {
    g_probe_state->group_cleanups.fetch_add(1, std::memory_order_relaxed);
  }
}

std::string CObjectValue(Dart_CObject* object) {
  if (object == nullptr) {
    return "null";
  }
  switch (object->type) {
    case Dart_CObject_kNull:
      return "null";
    case Dart_CObject_kBool:
      return object->value.as_bool ? "true" : "false";
    case Dart_CObject_kInt32:
      return std::to_string(object->value.as_int32);
    case Dart_CObject_kInt64:
      return std::to_string(object->value.as_int64);
    case Dart_CObject_kString:
      return object->value.as_string == nullptr
                 ? ""
                 : std::string(object->value.as_string);
    default:
      return "<unsupported>";
  }
}

void HandleNativeReport(Dart_Port destination_port, Dart_CObject* message) {
  (void)destination_port;
  ProbeState* state = g_probe_state;
  if (state == nullptr || message == nullptr ||
      message->type != Dart_CObject_kArray ||
      message->value.as_array.length < 1) {
    return;
  }
  const intptr_t length = message->value.as_array.length;
  Dart_CObject** values = message->value.as_array.values;
  std::string detail;
  for (intptr_t index = 1; index < length; ++index) {
    if (!detail.empty()) {
      detail += ";";
    }
    detail += CObjectValue(values[index]);
  }
  {
    const std::lock_guard<std::mutex> lock(state->mutex);
    state->report_received = true;
    state->report_kind = CObjectValue(values[0]);
    state->report_detail = Sanitize(std::move(detail));
  }
  state->condition.notify_all();
}

class PublicDartApiHost final {
 public:
  PublicDartApiHost() { root_state_.is_root = true; }

  ~PublicDartApiHost() { Shutdown(); }

  bool Start(std::string_view mode, const std::string& application_path,
             const std::string& platform_path, std::string* error) {
    if (pthread_main_np() == 0) {
      *error = "native host did not start on the process main thread";
      return false;
    }
    if (g_probe_state != nullptr) {
      *error = "another public-host probe is active";
      return false;
    }
    g_probe_state = &state_;

    is_aot_ = mode == "aot";
    if (!is_aot_ && mode != "jit") {
      *error = "mode must be jit or aot";
      return false;
    }

    if (!is_aot_) {
      platform_bytes_ = ReadBytes(platform_path, error);
      if (!error->empty()) {
        return false;
      }
      Dart_SetDartLibrarySourcesKernel(platform_bytes_.data(),
                                       platform_bytes_.size());
    }

    std::vector<const char*> flags;
    if (is_aot_) {
      flags.push_back("--precompilation");
    }
    char* dart_error = Dart_SetVMFlags(flags.size(), flags.data());
    if (dart_error != nullptr) {
      *error = "Dart_SetVMFlags failed: " + CopyAndFreeError(dart_error);
      return false;
    }

    Dart_InitializeParams parameters{};
    parameters.version = DART_INITIALIZE_PARAMS_CURRENT_VERSION;
    parameters.initialize_isolate = InitializeChild;
    parameters.shutdown_isolate = ShutdownIsolate;
    parameters.cleanup_isolate = CleanupIsolate;
    parameters.cleanup_group = CleanupGroup;
    parameters.file_open = OpenFile;
    parameters.file_read = ReadFile;
    parameters.file_write = WriteFile;
    parameters.file_close = CloseFile;
    parameters.entropy_source = SupplyEntropy;
    parameters.start_kernel_isolate = false;
    dart_error = Dart_Initialize(&parameters);
    if (dart_error != nullptr) {
      *error = "Dart_Initialize failed: " + CopyAndFreeError(dart_error);
      return false;
    }
    vm_initialized_ = true;

    Dart_IsolateFlags isolate_flags;
    Dart_IsolateFlagsInitialize(&isolate_flags);
    const std::string script_uri = "file://" + application_path;
    if (is_aot_) {
      snapshot_library_ =
          dlopen(application_path.c_str(), RTLD_NOW | RTLD_LOCAL);
      if (snapshot_library_ == nullptr) {
        const char* loader_error = dlerror();
        *error = "dlopen failed: " + std::string(loader_error == nullptr
                                                     ? "unknown error"
                                                     : loader_error);
        return false;
      }
      const auto* snapshot_data = static_cast<const uint8_t*>(
          dlsym(snapshot_library_, kSnapshotDataCSymbol));
      const auto* snapshot_text = static_cast<const uint8_t*>(
          dlsym(snapshot_library_, kSnapshotTextCSymbol));
      if (snapshot_data == nullptr || snapshot_text == nullptr) {
        *error = "AOT snapshot lacks documented Dart snapshot symbols";
        return false;
      }
      root_ = Dart_CreateIsolateGroup(script_uri.c_str(), "main", snapshot_data,
                                      snapshot_text, &isolate_flags, &state_,
                                      &root_state_, &dart_error);
    } else {
      application_bytes_ = ReadBytes(application_path, error);
      if (!error->empty()) {
        return false;
      }
      root_ = Dart_CreateIsolateGroupFromKernel(
          script_uri.c_str(), "main", application_bytes_.data(),
          application_bytes_.size(), &isolate_flags, &state_, &root_state_,
          &dart_error);
    }
    if (root_ == nullptr || dart_error != nullptr) {
      *error = "root isolate creation failed: " + CopyAndFreeError(dart_error);
      root_ = nullptr;
      return false;
    }

    Dart_SetMessageNotifyCallback(RootMessageNotify);
    Dart_EnterScope();
    if (!is_aot_) {
      Dart_Handle result = Dart_FinalizeLoading(false);
      if (!Dart_IsError(result)) {
        result = Dart_LoadScriptFromKernel(application_bytes_.data(),
                                           application_bytes_.size());
      }
      if (Dart_IsError(result)) {
        *error = "public root setup failed: " + CopyDartError(result);
        Dart_ExitScope();
        Dart_ShutdownIsolate();
        root_ = nullptr;
        return false;
      }
    }
    Dart_ExitScope();
    Dart_ExitIsolate();

    report_port_ = Dart_NewNativePort("dart-appkit-public-host-report",
                                      HandleNativeReport, false);
    if (report_port_ == ILLEGAL_PORT) {
      *error = "Dart_NewNativePort failed";
      return false;
    }
    return true;
  }

  bool InvokeSynchronous(std::string* error) {
    Dart_EnterIsolate(root_);
    Dart_EnterScope();
    Dart_Handle result = Dart_Invoke(
        Dart_RootLibrary(),
        Dart_NewStringFromCString("publicHostSynchronousProbe"), 0, nullptr);
    int64_t value = 0;
    if (!Dart_IsError(result)) {
      result = Dart_IntegerToInt64(result, &value);
    }
    if (Dart_IsError(result)) {
      *error = CopyDartError(result);
    }
    Dart_ExitScope();
    Dart_ExitIsolate();
    return error->empty() && value == 42;
  }

  bool InvokePlatformScript(std::string* value, std::string* error) {
    Dart_EnterIsolate(root_);
    Dart_EnterScope();
    Dart_Handle result = Dart_Invoke(
        Dart_RootLibrary(),
        Dart_NewStringFromCString("publicHostPlatformScriptProbe"), 0, nullptr);
    const char* text = nullptr;
    if (!Dart_IsError(result)) {
      result = Dart_StringToCString(result, &text);
    }
    if (Dart_IsError(result)) {
      *error = CopyDartError(result);
    } else if (text != nullptr) {
      *value = text;
    }
    Dart_ExitScope();
    Dart_ExitIsolate();
    return error->empty() && !value->empty();
  }

  bool InvokeMicrotask(std::string* detail, std::string* error) {
    ResetReport();
    Dart_EnterIsolate(root_);
    Dart_EnterScope();
    Dart_Handle arguments[] = {Dart_NewSendPort(report_port_)};
    Dart_Handle result = Dart_Invoke(
        Dart_RootLibrary(),
        Dart_NewStringFromCString("publicHostMicrotaskProbe"), 1, arguments);
    if (Dart_IsError(result)) {
      *error = CopyDartError(result);
    }
    Dart_ExitScope();
    Dart_ExitIsolate();
    if (!error->empty()) {
      return false;
    }
    return PumpUntilReport("microtask", std::chrono::seconds(2), detail, error);
  }

  bool InvokeLifecycle(std::string* detail, std::string* error) {
    ResetReport();
    Dart_EnterIsolate(root_);
    Dart_EnterScope();
    Dart_Handle arguments[] = {
        Dart_NewSendPort(report_port_),
        Dart_NewInteger(reinterpret_cast<intptr_t>(&CurrentThreadIsMain)),
    };
    Dart_Handle result = Dart_Invoke(
        Dart_RootLibrary(),
        Dart_NewStringFromCString("publicHostLifecycleProbe"), 2, arguments);
    if (Dart_IsError(result)) {
      *error = CopyDartError(result);
    }
    Dart_ExitScope();
    Dart_ExitIsolate();
    if (!error->empty()) {
      return false;
    }
    if (!PumpUntilReport("lifecycle", std::chrono::seconds(5), detail, error)) {
      return false;
    }
    return detail->starts_with("ok;");
  }

  bool Shutdown() {
    if (shutdown_called_) {
      return shutdown_succeeded_;
    }
    shutdown_called_ = true;
    if (report_port_ != ILLEGAL_PORT && vm_initialized_) {
      std::ignore = Dart_CloseNativePort(report_port_);
      report_port_ = ILLEGAL_PORT;
    }
    if (root_ != nullptr) {
      Dart_EnterIsolate(root_);
      Dart_ShutdownIsolate();
      root_ = nullptr;
    }
    if (vm_initialized_) {
      char* error = Dart_Cleanup();
      if (error != nullptr) {
        shutdown_error_ = CopyAndFreeError(error);
      }
      vm_initialized_ = false;
    }
    if (snapshot_library_ != nullptr) {
      std::ignore = dlclose(snapshot_library_);
      snapshot_library_ = nullptr;
    }
    g_probe_state = nullptr;
    shutdown_succeeded_ = shutdown_error_.empty();
    return shutdown_succeeded_;
  }

  const std::string& shutdown_error() const { return shutdown_error_; }
  const ProbeState& state() const { return state_; }

  static intptr_t CurrentThreadIsMain() { return pthread_main_np() != 0; }

 private:
  void ResetReport() {
    const std::lock_guard<std::mutex> lock(state_.mutex);
    state_.report_received = false;
    state_.report_kind.clear();
    state_.report_detail.clear();
    state_.message_error.clear();
  }

  bool PumpUntilReport(std::string_view expected_kind,
                       std::chrono::milliseconds timeout, std::string* detail,
                       std::string* error) {
    const Clock::time_point deadline = Clock::now() + timeout;
    while (Clock::now() < deadline) {
      Dart_Isolate isolate = nullptr;
      {
        std::unique_lock<std::mutex> lock(state_.mutex);
        if (state_.report_received || !state_.message_error.empty()) {
          break;
        }
        if (state_.root_messages.empty()) {
          state_.condition.wait_until(lock, deadline);
        }
        if (!state_.root_messages.empty()) {
          isolate = state_.root_messages.front();
          state_.root_messages.pop_front();
        }
      }
      if (isolate != nullptr) {
        Dart_EnterIsolate(isolate);
        Dart_EnterScope();
        Dart_Handle result = Dart_HandleMessage();
        if (Dart_IsError(result)) {
          const std::lock_guard<std::mutex> lock(state_.mutex);
          state_.message_error = CopyDartError(result);
        }
        Dart_ExitScope();
        Dart_ExitIsolate();
      }
    }

    const std::lock_guard<std::mutex> lock(state_.mutex);
    if (!state_.message_error.empty()) {
      *error = state_.message_error;
      return false;
    }
    if (!state_.report_received) {
      *error =
          "timed out waiting for " + std::string(expected_kind) + " report";
      return false;
    }
    if (state_.report_kind != expected_kind) {
      *error = "received " + state_.report_kind + " while waiting for " +
               std::string(expected_kind);
      return false;
    }
    *detail = state_.report_detail;
    return true;
  }

  ProbeState state_;
  IsolateState root_state_;
  std::vector<uint8_t> platform_bytes_;
  std::vector<uint8_t> application_bytes_;
  Dart_Isolate root_ = nullptr;
  Dart_Port report_port_ = ILLEGAL_PORT;
  void* snapshot_library_ = nullptr;
  bool is_aot_ = false;
  bool vm_initialized_ = false;
  bool shutdown_called_ = false;
  bool shutdown_succeeded_ = false;
  std::string shutdown_error_;
};

struct Arguments {
  std::string mode;
  std::string application;
  std::string platform;
};

bool ParseArguments(int argc, char** argv, Arguments* arguments) {
  for (int index = 1; index < argc; ++index) {
    const std::string_view argument(argv[index]);
    const size_t separator = argument.find('=');
    if (separator == std::string_view::npos) {
      return false;
    }
    const std::string name(argument.substr(0, separator));
    const std::string value(argument.substr(separator + 1));
    if (name == "--mode") {
      arguments->mode = value;
    } else if (name == "--application") {
      arguments->application = value;
    } else if (name == "--platform") {
      arguments->platform = value;
    } else {
      return false;
    }
  }
  return (arguments->mode == "jit" || arguments->mode == "aot") &&
         !arguments->application.empty() &&
         (arguments->mode == "aot" || !arguments->platform.empty());
}

void PrintMarker(std::string_view name, bool value) {
  std::cout << "probe." << name << '=' << (value ? "true" : "false")
            << std::endl;
}

void PrintMarker(std::string_view name, const std::string& value) {
  std::cout << "probe." << name << '=' << Sanitize(value) << std::endl;
}

}  // namespace
}  // namespace dart_appkit

int main(int argc, char** argv) {
  using dart_appkit::Arguments;
  using dart_appkit::PrintMarker;
  using dart_appkit::PublicDartApiHost;

  Arguments arguments;
  if (!dart_appkit::ParseArguments(argc, argv, &arguments)) {
    std::cerr << "usage: public_dart_api_host_probe "
                 "--mode=jit|aot --application=PATH [--platform=PATH]"
              << std::endl;
    return 64;
  }

  PublicDartApiHost host;
  std::string start_error;
  const bool started = host.Start(arguments.mode, arguments.application,
                                  arguments.platform, &start_error);
  PrintMarker("mode", arguments.mode);
  PrintMarker("root_main_thread", pthread_main_np() != 0);
  PrintMarker("started", started);
  PrintMarker("start_error", start_error);

  bool synchronous = false;
  bool platform_script = false;
  bool microtasks = false;
  bool lifecycle = false;
  std::string synchronous_error;
  std::string platform_value;
  std::string platform_error;
  std::string microtask_detail;
  std::string microtask_error;
  std::string lifecycle_detail;
  std::string lifecycle_error;
  if (started) {
    synchronous = host.InvokeSynchronous(&synchronous_error);
    platform_script =
        host.InvokePlatformScript(&platform_value, &platform_error);
    microtasks = host.InvokeMicrotask(&microtask_detail, &microtask_error);
    lifecycle = host.InvokeLifecycle(&lifecycle_detail, &lifecycle_error);
  }
  PrintMarker("synchronous", synchronous);
  PrintMarker("synchronous_error", synchronous_error);
  PrintMarker("platform_script", platform_script);
  PrintMarker("platform_value", platform_value);
  PrintMarker("platform_error", platform_error);
  PrintMarker("microtasks", microtasks);
  PrintMarker("microtask_detail", microtask_detail);
  PrintMarker("microtask_error", microtask_error);
  PrintMarker("lifecycle", lifecycle);
  PrintMarker("lifecycle_detail", lifecycle_detail);
  PrintMarker("lifecycle_error", lifecycle_error);

  const bool first_shutdown = host.Shutdown();
  const bool second_shutdown = host.Shutdown();
  PrintMarker("vm_cleanup", first_shutdown);
  PrintMarker("shutdown_error", host.shutdown_error());
  PrintMarker("host_shutdown_idempotent", first_shutdown == second_shutdown);
  PrintMarker("child_initializations",
              std::to_string(host.state().child_initializations.load()));
  PrintMarker("isolate_shutdowns",
              std::to_string(host.state().isolate_shutdowns.load()));
  PrintMarker("isolate_cleanups",
              std::to_string(host.state().isolate_cleanups.load()));
  PrintMarker("group_cleanups",
              std::to_string(host.state().group_cleanups.load()));

  const bool supported = started && synchronous && platform_script &&
                         microtasks && lifecycle && first_shutdown &&
                         second_shutdown;
  PrintMarker("runtime_contract_supported", supported);
  return 0;
}
