#ifndef DART_APPKIT_RUNNER_DART_HOST_H_
#define DART_APPKIT_RUNNER_DART_HOST_H_

#include <atomic>
#include <mutex>
#include <string>

#include "BridgeInternal.h"
#include "DartMessagePump.h"
#include "RunnerConfiguration.h"
#include "include/dart_api.h"

namespace dart_appkit {

class DartHost final {
 public:
  explicit DartHost(DartMessagePump* message_pump);
  ~DartHost();

  bool Start(const RunnerConfiguration& configuration, std::string* out_error);
  void Shutdown();

  bool has_fatal_error() const;
  std::string fatal_error() const;

  DartHost(const DartHost&) = delete;
  DartHost& operator=(const DartHost&) = delete;

 private:
  static bool PostNativeEvent(int64_t dart_port,
                              uint32_t event_protocol_version,
                              const NativeEvent& event, void* context);
  static void HandleMessageError(Dart_Handle error,
                                 Dart_Isolate destination_isolate);
  bool InvokeMain(const std::vector<std::string>& arguments,
                  std::string* out_error);
  void RecordFatalError(std::string message);

  DartMessagePump* message_pump_;
  Dart_Isolate isolate_ = nullptr;
  bool engine_started_ = false;

  mutable std::mutex fatal_error_mutex_;
  std::string fatal_error_;

  static std::atomic<DartHost*> active_host_;
};

}  // namespace dart_appkit

#endif  // DART_APPKIT_RUNNER_DART_HOST_H_
