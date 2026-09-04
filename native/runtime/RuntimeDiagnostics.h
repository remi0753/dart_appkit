#ifndef DART_MACOS_RUNTIME_RUNTIME_DIAGNOSTICS_H_
#define DART_MACOS_RUNTIME_RUNTIME_DIAGNOSTICS_H_

#include <stdint.h>

#include <cstddef>
#include <string>

namespace dart_macos_runtime {

inline constexpr const char* kRuntimeDiagnosticsSubsystem =
    "dev.dart-macos-runtime";
inline constexpr const char* kRuntimeDiagnosticsFormat =
    "dart-macos-runtime-local-run-metadata";
inline constexpr uint32_t kRuntimeDiagnosticsFormatVersion = 1;
inline constexpr size_t kRuntimeDiagnosticsMaximumBytes = 16 * 1024;

struct RuntimeDiagnosticsOptions {
  std::string runtime_mode;
  std::string architecture;
  std::string bundle_identifier;
  std::string application_version;
  std::string dart_sdk_revision;
  std::string metadata_directory;
  bool strict_persistence = false;
};

class RuntimeDiagnosticsSession final {
 public:
  RuntimeDiagnosticsSession() = default;
  ~RuntimeDiagnosticsSession();

  bool Start(const RuntimeDiagnosticsOptions& options, std::string* out_error);
  int32_t RecordPhase(uint32_t phase);
  bool Finish(int32_t exit_code);

  bool started() const { return started_; }
  bool finished() const { return finished_; }
  bool persistence_healthy() const { return persistence_healthy_; }
  const std::string& metadata_directory() const { return metadata_directory_; }

  RuntimeDiagnosticsSession(const RuntimeDiagnosticsSession&) = delete;
  RuntimeDiagnosticsSession& operator=(const RuntimeDiagnosticsSession&) =
      delete;

 private:
  bool PersistCurrentRecord();

  std::string runtime_mode_;
  std::string architecture_;
  std::string bundle_identifier_;
  std::string application_version_;
  std::string dart_sdk_revision_;
  std::string metadata_directory_;
  std::string launch_id_;
  std::string started_at_;
  std::string updated_at_;
  std::string outcome_ = "running";
  uint32_t phase_ = 0;
  int32_t exit_code_ = 0;
  bool has_exit_code_ = false;
  bool strict_persistence_ = false;
  bool persistence_healthy_ = true;
  bool started_ = false;
  bool finished_ = false;
};

bool RuntimeDiagnosticsOptionsForCurrentProcess(
    const char* runtime_mode, RuntimeDiagnosticsOptions* out_options,
    std::string* out_error);
bool RuntimeDiagnosticsEnabledForCurrentProcess();
bool RuntimeDiagnosticsFinishActiveSession(int32_t exit_code);
int32_t RuntimeDiagnosticsRecordActivePhase(uint32_t phase);

}  // namespace dart_macos_runtime

#endif  // DART_MACOS_RUNTIME_RUNTIME_DIAGNOSTICS_H_
