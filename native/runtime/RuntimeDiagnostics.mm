#import <Foundation/Foundation.h>

#include "RuntimeDiagnostics.h"

#include <fcntl.h>
#include <limits.h>
#include <os/log.h>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string_view>
#include <utility>

#include "dart_macos_runtime.h"

namespace dart_macos_runtime {
namespace {

constexpr std::string_view kCurrentRunFilename = "current-run.json";
constexpr std::string_view kPreviousUncleanRunFilename =
    "previous-unclean-run.json";

std::atomic<RuntimeDiagnosticsSession*> active_session{nullptr};

void SetError(std::string* out_error, std::string_view message) {
  if (out_error != nullptr) {
    *out_error = message;
  }
}

bool HasOnlyTokenCharacters(std::string_view value,
                            std::string_view extra_characters) {
  if (value.empty()) {
    return false;
  }
  for (const unsigned char character : value) {
    const bool alpha_numeric = (character >= 'a' && character <= 'z') ||
                               (character >= 'A' && character <= 'Z') ||
                               (character >= '0' && character <= '9');
    if (!alpha_numeric && extra_characters.find(static_cast<char>(character)) ==
                              std::string_view::npos) {
      return false;
    }
  }
  return true;
}

bool IsHexRevision(std::string_view value) {
  if (value.size() != 40) {
    return false;
  }
  for (const char character : value) {
    if (!((character >= '0' && character <= '9') ||
          (character >= 'a' && character <= 'f'))) {
      return false;
    }
  }
  return true;
}

bool ValidateOptions(const RuntimeDiagnosticsOptions& options,
                     std::string* out_error) {
  if (options.runtime_mode != "developer-jit" &&
      options.runtime_mode != "release-aot") {
    SetError(out_error, "invalid diagnostics runtime mode");
    return false;
  }
  if (options.architecture != "arm64" && options.architecture != "x86_64") {
    SetError(out_error, "invalid diagnostics architecture");
    return false;
  }
  if (options.bundle_identifier.size() > 128 ||
      !HasOnlyTokenCharacters(options.bundle_identifier, ".-")) {
    SetError(out_error, "invalid diagnostics bundle identifier");
    return false;
  }
  if (options.application_version.size() > 64 ||
      !HasOnlyTokenCharacters(options.application_version, ".+-")) {
    SetError(out_error, "invalid diagnostics application version");
    return false;
  }
  if (!IsHexRevision(options.dart_sdk_revision)) {
    SetError(out_error, "invalid diagnostics Dart SDK revision");
    return false;
  }
  if (options.metadata_directory.empty() ||
      options.metadata_directory.size() >= PATH_MAX ||
      options.metadata_directory.find('\0') != std::string::npos ||
      !std::filesystem::path(options.metadata_directory).is_absolute()) {
    SetError(out_error, "diagnostics metadata directory must be absolute");
    return false;
  }
  return true;
}

std::string JoinPath(std::string_view directory, std::string_view filename) {
  return (std::filesystem::path(directory) / filename).string();
}

NSString* CopyNSString(std::string_view value) {
  return [[NSString alloc] initWithBytes:value.data()
                                  length:value.size()
                                encoding:NSUTF8StringEncoding];
}

std::string CopyString(NSString* value) {
  if (value == nil || value.UTF8String == nullptr) {
    return {};
  }
  return value.UTF8String;
}

bool EnsurePrivateDirectory(std::string_view directory) {
  NSString* path = CopyNSString(directory);
  if (path == nil) {
    return false;
  }
  NSDictionary<NSFileAttributeKey, id>* attributes = @{
    NSFilePosixPermissions : @0700,
  };
  if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                 withIntermediateDirectories:YES
                                                  attributes:attributes
                                                       error:nil]) {
    return false;
  }
  const std::string copied(directory);
  struct stat status = {};
  return lstat(copied.c_str(), &status) == 0 && S_ISDIR(status.st_mode) &&
         !S_ISLNK(status.st_mode) && chmod(copied.c_str(), 0700) == 0;
}

bool WriteAll(int descriptor, const uint8_t* bytes, size_t length) {
  size_t offset = 0;
  while (offset < length) {
    const ssize_t count = write(descriptor, bytes + offset, length - offset);
    if (count > 0) {
      offset += static_cast<size_t>(count);
    } else if (count < 0 && errno == EINTR) {
      continue;
    } else {
      return false;
    }
  }
  return true;
}

bool WriteDataAtomically(std::string_view directory, std::string_view filename,
                         NSData* data) {
  if (data == nil || data.length == 0 ||
      data.length > kRuntimeDiagnosticsMaximumBytes) {
    return false;
  }
  const std::string destination = JoinPath(directory, filename);
  const std::string temporary = destination + ".tmp";
  unlink(temporary.c_str());
  const int descriptor =
      open(temporary.c_str(),
           O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (descriptor < 0) {
    return false;
  }
  bool success = WriteAll(descriptor, static_cast<const uint8_t*>(data.bytes),
                          data.length);
  if (success && fsync(descriptor) != 0) {
    success = false;
  }
  if (close(descriptor) != 0) {
    success = false;
  }
  if (success && rename(temporary.c_str(), destination.c_str()) != 0) {
    success = false;
  }
  if (success && chmod(destination.c_str(), 0600) != 0) {
    success = false;
  }
  if (!success) {
    unlink(temporary.c_str());
  }
  return success;
}

std::string CurrentTimestamp() {
  NSISO8601DateFormatter* formatter = [[NSISO8601DateFormatter alloc] init];
  formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                            NSISO8601DateFormatWithFractionalSeconds;
  formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  return CopyString([formatter stringFromDate:[NSDate date]]);
}

const char* PhaseName(uint32_t phase) {
  switch (phase) {
    case 0:
      return "host-starting";
    case DMR_DIAGNOSTIC_PHASE_ROOT_STARTING:
      return "root-starting";
    case DMR_DIAGNOSTIC_PHASE_ROOT_READY:
      return "root-ready";
    case DMR_DIAGNOSTIC_PHASE_SHUTDOWN_STARTED:
      return "shutdown-started";
    case DMR_DIAGNOSTIC_PHASE_ROOT_STOPPED:
      return "root-stopped";
    default:
      return nullptr;
  }
}

NSDictionary<NSString*, id>* ReadRunningRecord(std::string_view path) {
  const std::string copied(path);
  struct stat status = {};
  if (lstat(copied.c_str(), &status) != 0 || !S_ISREG(status.st_mode) ||
      S_ISLNK(status.st_mode) || (status.st_mode & 0077) != 0 ||
      status.st_size <= 0 ||
      status.st_size > static_cast<off_t>(kRuntimeDiagnosticsMaximumBytes)) {
    return nil;
  }
  NSData* data = [NSData dataWithContentsOfFile:CopyNSString(path)];
  if (data == nil || data.length == 0 ||
      data.length > kRuntimeDiagnosticsMaximumBytes) {
    return nil;
  }
  id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![value isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSDictionary<NSString*, id>* record = value;
  if (![record[@"format"] isEqualToString:@(kRuntimeDiagnosticsFormat)] ||
      [record[@"version"] unsignedIntValue] !=
          kRuntimeDiagnosticsFormatVersion ||
      ![record[@"outcome"] isEqualToString:@"running"] ||
      ![record[@"launch_id"] isKindOfClass:[NSString class]] ||
      [[NSUUID alloc] initWithUUIDString:record[@"launch_id"]] == nil) {
    return nil;
  }
  return record;
}

bool WriteRecord(std::string_view directory, std::string_view filename,
                 NSDictionary<NSString*, id>* record) {
  NSData* data = [NSJSONSerialization dataWithJSONObject:record
                                                 options:NSJSONWritingSortedKeys
                                                   error:nil];
  return WriteDataAtomically(directory, filename, data);
}

NSString* BundleString(NSBundle* bundle, NSString* key) {
  id value = [bundle objectForInfoDictionaryKey:key];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

bool BundleBool(NSBundle* bundle, NSString* key, bool default_value) {
  id value = [bundle objectForInfoDictionaryKey:key];
  return [value isKindOfClass:[NSNumber class]] ? [value boolValue]
                                                : default_value;
}

const char* CompiledArchitecture() {
#if defined(__arm64__)
  return "arm64";
#elif defined(__x86_64__)
  return "x86_64";
#else
  return "unsupported";
#endif
}

bool EnvironmentEnabled(const char* name) {
  const char* value = std::getenv(name);
  return value != nullptr && std::strcmp(value, "1") == 0;
}

void LogPersistenceFailure() {
  os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_ERROR,
                   "dart_macos_runtime diagnostics persistence failed");
}

}  // namespace

RuntimeDiagnosticsSession::~RuntimeDiagnosticsSession() {
  RuntimeDiagnosticsSession* expected = this;
  active_session.compare_exchange_strong(expected, nullptr,
                                         std::memory_order_acq_rel);
}

bool RuntimeDiagnosticsSession::Start(const RuntimeDiagnosticsOptions& options,
                                      std::string* out_error) {
  if (pthread_main_np() == 0) {
    SetError(out_error, "diagnostics must start on the process main thread");
    return false;
  }
  if (started_ || !ValidateOptions(options, out_error)) {
    if (started_) {
      SetError(out_error, "diagnostics session already started");
    }
    return false;
  }
  RuntimeDiagnosticsSession* expected = nullptr;
  if (!active_session.compare_exchange_strong(expected, this,
                                              std::memory_order_acq_rel)) {
    SetError(out_error, "another diagnostics session is active");
    return false;
  }

  runtime_mode_ = options.runtime_mode;
  architecture_ = options.architecture;
  bundle_identifier_ = options.bundle_identifier;
  application_version_ = options.application_version;
  dart_sdk_revision_ = options.dart_sdk_revision;
  metadata_directory_ = std::filesystem::path(options.metadata_directory)
                            .lexically_normal()
                            .string();
  strict_persistence_ = options.strict_persistence;
  launch_id_ = CopyString([NSUUID UUID].UUIDString);
  started_at_ = CurrentTimestamp();
  updated_at_ = started_at_;
  started_ = true;

  bool persisted = EnsurePrivateDirectory(metadata_directory_);
  if (persisted) {
    NSDictionary<NSString*, id>* prior =
        ReadRunningRecord(JoinPath(metadata_directory_, kCurrentRunFilename));
    if (prior != nil &&
        [prior[@"bundle_identifier"]
            isEqualToString:CopyNSString(bundle_identifier_)] &&
        [prior[@"runtime_mode"] isEqualToString:CopyNSString(runtime_mode_)] &&
        !WriteRecord(metadata_directory_, kPreviousUncleanRunFilename, prior)) {
      persisted = false;
    }
  }
  if (persisted && !PersistCurrentRecord()) {
    persisted = false;
  }
  persistence_healthy_ = persisted;
  if (!persisted) {
    LogPersistenceFailure();
    if (strict_persistence_) {
      started_ = false;
      RuntimeDiagnosticsSession* active = this;
      active_session.compare_exchange_strong(active, nullptr,
                                             std::memory_order_acq_rel);
      SetError(out_error, "could not persist strict diagnostics metadata");
      return false;
    }
  }
  os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_INFO,
                   "dart_macos_runtime session started: %{public}s",
                   runtime_mode_.c_str());
  return true;
}

int32_t RuntimeDiagnosticsSession::RecordPhase(uint32_t phase) {
  if (!started_) {
    return DMR_DIAGNOSTICS_NOT_STARTED;
  }
  if (pthread_main_np() == 0) {
    return DMR_DIAGNOSTICS_WRONG_THREAD;
  }
  if (phase == 0 || PhaseName(phase) == nullptr) {
    return DMR_DIAGNOSTICS_INVALID_PHASE;
  }
  if (finished_) {
    return DMR_DIAGNOSTICS_ALREADY_FINISHED;
  }
  if (phase < phase_) {
    return DMR_DIAGNOSTICS_PHASE_REGRESSION;
  }
  if (phase == phase_) {
    return DMR_DIAGNOSTICS_OK;
  }
  phase_ = phase;
  updated_at_ = CurrentTimestamp();
  if (persistence_healthy_ && !PersistCurrentRecord()) {
    persistence_healthy_ = false;
    LogPersistenceFailure();
  }
  return DMR_DIAGNOSTICS_OK;
}

bool RuntimeDiagnosticsSession::Finish(int32_t exit_code) {
  if (!started_ || pthread_main_np() == 0) {
    return false;
  }
  if (finished_) {
    return persistence_healthy_;
  }
  finished_ = true;
  has_exit_code_ = true;
  exit_code_ = exit_code;
  outcome_ = exit_code == 0 ? "clean" : "failure";
  updated_at_ = CurrentTimestamp();
  if (persistence_healthy_ && !PersistCurrentRecord()) {
    persistence_healthy_ = false;
    LogPersistenceFailure();
  }
  RuntimeDiagnosticsSession* active = this;
  active_session.compare_exchange_strong(active, nullptr,
                                         std::memory_order_acq_rel);
  return persistence_healthy_;
}

bool RuntimeDiagnosticsSession::PersistCurrentRecord() {
  NSDictionary<NSString*, id>* record = @{
    @"format" : @(kRuntimeDiagnosticsFormat),
    @"version" : @(kRuntimeDiagnosticsFormatVersion),
    @"launch_id" : CopyNSString(launch_id_),
    @"bundle_identifier" : CopyNSString(bundle_identifier_),
    @"application_version" : CopyNSString(application_version_),
    @"runtime_mode" : CopyNSString(runtime_mode_),
    @"architecture" : CopyNSString(architecture_),
    @"dart_sdk_revision" : CopyNSString(dart_sdk_revision_),
    @"process_id" : @(getpid()),
    @"started_at" : CopyNSString(started_at_),
    @"updated_at" : CopyNSString(updated_at_),
    @"phase" : @(PhaseName(phase_)),
    @"outcome" : CopyNSString(outcome_),
    @"exit_code" : has_exit_code_ ? @(exit_code_) : [NSNull null],
  };
  return WriteRecord(metadata_directory_, kCurrentRunFilename, record);
}

bool RuntimeDiagnosticsEnabledForCurrentProcess() {
  return BundleBool([NSBundle mainBundle], @"DMRDiagnosticsEnabled", false);
}

bool RuntimeDiagnosticsOptionsForCurrentProcess(
    const char* runtime_mode, RuntimeDiagnosticsOptions* out_options,
    std::string* out_error) {
  if (pthread_main_np() == 0 || runtime_mode == nullptr ||
      out_options == nullptr) {
    SetError(out_error, "diagnostics options require the process main thread");
    return false;
  }
  NSBundle* bundle = [NSBundle mainBundle];
  NSString* identifier = bundle.bundleIdentifier;
  NSString* version = BundleString(bundle, @"CFBundleShortVersionString");
  NSString* revision = BundleString(bundle, @"DMRDartSDKRevision");
  NSString* support_name =
      BundleString(bundle, @"DMRDiagnosticsApplicationSupportName");
  if (identifier == nil || version == nil || revision == nil ||
      support_name == nil) {
    SetError(out_error, "diagnostics bundle metadata is incomplete");
    return false;
  }

  const bool strict = EnvironmentEnabled("DMR_RUNTIME_DIAGNOSTICS_TEST");
  std::string directory;
  if (strict) {
    const char* override = std::getenv("DMR_RUNTIME_DIAGNOSTICS_DIRECTORY");
    if (override == nullptr || override[0] == '\0') {
      SetError(out_error, "strict diagnostics directory is missing");
      return false;
    }
    directory = override;
  } else {
    NSArray<NSURL*>* urls = [[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask];
    NSURL* base = urls.firstObject;
    if (base == nil) {
      SetError(out_error, "Application Support directory is unavailable");
      return false;
    }
    NSURL* output = [[[base URLByAppendingPathComponent:support_name
                                            isDirectory:YES]
        URLByAppendingPathComponent:@"Diagnostics"
                        isDirectory:YES]
        URLByAppendingPathComponent:CopyNSString(runtime_mode)
                        isDirectory:YES];
    directory = CopyString(output.path);
  }

  RuntimeDiagnosticsOptions options;
  options.runtime_mode = runtime_mode;
  options.architecture = CompiledArchitecture();
  options.bundle_identifier = CopyString(identifier);
  options.application_version = CopyString(version);
  options.dart_sdk_revision = CopyString(revision);
  options.metadata_directory =
      std::filesystem::path(directory).lexically_normal().string();
  options.strict_persistence = strict;
  if (!ValidateOptions(options, out_error)) {
    return false;
  }
  *out_options = std::move(options);
  return true;
}

bool RuntimeDiagnosticsFinishActiveSession(int32_t exit_code) {
  RuntimeDiagnosticsSession* session =
      active_session.load(std::memory_order_acquire);
  return session != nullptr && session->Finish(exit_code);
}

int32_t RuntimeDiagnosticsRecordActivePhase(uint32_t phase) {
  RuntimeDiagnosticsSession* session =
      active_session.load(std::memory_order_acquire);
  return session == nullptr ? DMR_DIAGNOSTICS_NOT_STARTED
                            : session->RecordPhase(phase);
}

}  // namespace dart_macos_runtime

extern "C" uint32_t dmr_runtime_diagnostics_abi_version(void) {
  return DMR_DIAGNOSTICS_ABI_VERSION;
}

extern "C" int32_t dmr_runtime_diagnostics_record_phase(uint32_t phase) {
  return dart_macos_runtime::RuntimeDiagnosticsRecordActivePhase(phase);
}
