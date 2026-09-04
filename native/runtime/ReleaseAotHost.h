#ifndef DART_MACOS_RUNTIME_RELEASE_AOT_HOST_H_
#define DART_MACOS_RUNTIME_RELEASE_AOT_HOST_H_

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

#include "include/dart_api.h"

namespace dart_appkit {
class DartMessagePump;
struct NativeEvent;
}  // namespace dart_appkit

namespace dart_macos_runtime {

class ReleaseAotHost final {
 public:
  explicit ReleaseAotHost(dart_appkit::DartMessagePump* message_pump);
  ~ReleaseAotHost();

  bool Start(const std::string& snapshot_path,
             const std::vector<std::string>& arguments, std::string* out_error);
  void Shutdown();
  bool has_fatal_error() const;
  std::string fatal_error() const;

  ReleaseAotHost(const ReleaseAotHost&) = delete;
  ReleaseAotHost& operator=(const ReleaseAotHost&) = delete;

 private:
  bool InvokeMain(const std::vector<std::string>& arguments,
                  std::string* out_error);
  void RecordFatalError(std::string message);
  static void HandleMessageError(Dart_Handle error,
                                 Dart_Isolate destination_isolate);
  static bool PostNativeEvent(int64_t dart_port,
                              uint32_t event_protocol_version,
                              const dart_appkit::NativeEvent& event,
                              void* context);

  dart_appkit::DartMessagePump* message_pump_;
  Dart_Isolate isolate_ = nullptr;
  bool engine_started_ = false;
  mutable std::mutex fatal_error_mutex_;
  std::string fatal_error_;

  static std::atomic<ReleaseAotHost*> active_host_;
};

}  // namespace dart_macos_runtime

#endif  // DART_MACOS_RUNTIME_RELEASE_AOT_HOST_H_
