#include <cstdio>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

#include "include/dart_api.h"
#include "include/dart_engine.h"

#ifndef DMR_DART_SDK_VERSION
#define DMR_DART_SDK_VERSION "unknown"
#endif

namespace {

constexpr int kUsageExitCode = 64;
constexpr int kSoftwareExitCode = 70;
constexpr int kDartErrorExitCode = 255;

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

Dart_Handle InvokeMain(int argc, const char* argv[]) {
  Dart_Handle core = Dart_LookupLibrary(Dart_NewStringFromCString("dart:core"));
  if (Dart_IsError(core)) {
    return core;
  }
  Dart_Handle string_type = Dart_GetNonNullableType(
      core, Dart_NewStringFromCString("String"), 0, nullptr);
  if (Dart_IsError(string_type)) {
    return string_type;
  }
  Dart_Handle arguments = Dart_NewListOfTypeFilled(
      string_type, Dart_NewStringFromCString(""), argc - 2);
  if (Dart_IsError(arguments)) {
    return arguments;
  }
  for (int index = 2; index < argc; ++index) {
    Dart_Handle result = Dart_ListSetAt(arguments, index - 2,
                                        Dart_NewStringFromCString(argv[index]));
    if (Dart_IsError(result)) {
      return result;
    }
  }
  Dart_Handle invocation_arguments[] = {arguments};
  return Dart_Invoke(Dart_RootLibrary(), Dart_NewStringFromCString("main"), 1,
                     invocation_arguments);
}

}  // namespace

int main(int argc, const char* argv[]) {
  if (argc < 2 || argv[1] == nullptr || argv[1][0] == '\0') {
    std::fprintf(stderr, "Usage: %s <AOT-snapshot> [arguments...]\n", argv[0]);
    return kUsageExitCode;
  }
  const char* version = Dart_VersionString();
  if (version == nullptr ||
      std::string_view(version).find(DMR_DART_SDK_VERSION) ==
          std::string_view::npos) {
    std::fprintf(stderr, "Dart Engine runtime version mismatch\n");
    return kSoftwareExitCode;
  }

  char* engine_error = nullptr;
  if (!DartEngine_Init(&engine_error)) {
    std::fprintf(stderr, "Dart Engine initialization failed: %s\n",
                 CopyAndFreeError(engine_error).c_str());
    return kSoftwareExitCode;
  }

  int exit_code = 0;
  const DartEngine_SnapshotData snapshot =
      DartEngine_AotSnapshotFromFile(argv[1], &engine_error);
  if (engine_error != nullptr) {
    std::fprintf(stderr, "AOT snapshot loading failed: %s\n",
                 CopyAndFreeError(engine_error).c_str());
    exit_code = kSoftwareExitCode;
  } else {
    Dart_Isolate isolate = DartEngine_CreateIsolate(snapshot, &engine_error);
    if (isolate == nullptr || engine_error != nullptr) {
      std::fprintf(stderr, "Dart isolate creation failed: %s\n",
                   CopyAndFreeError(engine_error).c_str());
      exit_code = kSoftwareExitCode;
    } else {
      EnteredIsolate entered(isolate);
      Dart_SetMessageNotifyCallback(nullptr);
      Dart_Handle result = InvokeMain(argc, argv);
      if (!Dart_IsError(result)) {
        result = DartEngine_DrainMicrotasksQueue();
      }
      if (!Dart_IsError(result)) {
        result = Dart_RunLoop();
      }
      if (Dart_IsError(result)) {
        std::fprintf(stderr, "%s\n", CopyDartError(result).c_str());
        exit_code = kDartErrorExitCode;
      }
    }
  }
  DartEngine_Shutdown();
  return exit_code;
}
