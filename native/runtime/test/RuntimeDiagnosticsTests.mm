#import <Foundation/Foundation.h>

#include <sys/stat.h>

#include <iostream>
#include <string>
#include <thread>

#include "RuntimeDiagnostics.h"
#include "dart_macos_runtime.h"

namespace {

int failures = 0;

void Expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "RuntimeDiagnostics expectation failed: " << description
              << '\n';
    ++failures;
  }
}

std::string CopyString(NSString* value) {
  return value == nil || value.UTF8String == nullptr ? "" : value.UTF8String;
}

dart_macos_runtime::RuntimeDiagnosticsOptions ValidOptions(
    NSString* directory) {
  dart_macos_runtime::RuntimeDiagnosticsOptions options;
  options.runtime_mode = "developer-jit";
#if defined(__arm64__)
  options.architecture = "arm64";
#else
  options.architecture = "x86_64";
#endif
  options.bundle_identifier = "dev.dart-macos-runtime.test";
  options.application_version = "0.1.0-test";
  options.dart_sdk_revision = "60a57cd42d64dc03e9f07aa60a2e250755c1ef28";
  options.metadata_directory = CopyString(directory);
  options.strict_persistence = true;
  return options;
}

NSDictionary<NSString*, id>* ReadJson(NSString* directory, NSString* filename) {
  NSString* path = [directory stringByAppendingPathComponent:filename];
  NSData* data = [NSData dataWithContentsOfFile:path];
  id value = data == nil ? nil
                         : [NSJSONSerialization JSONObjectWithData:data
                                                           options:0
                                                             error:nil];
  return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

mode_t Permissions(NSString* path) {
  struct stat status = {};
  return lstat(path.fileSystemRepresentation, &status) == 0
             ? status.st_mode & 0777
             : 0;
}

}  // namespace

int main() {
  @autoreleasepool {
    NSString* root = [NSTemporaryDirectory()
        stringByAppendingPathComponent:
            [NSString stringWithFormat:@"dart-macos-runtime-%@",
                                       [NSUUID UUID].UUIDString]];
    NSString* records = [root stringByAppendingPathComponent:@"records"];
    auto options = ValidOptions(records);

    Expect(dmr_runtime_diagnostics_abi_version() == DMR_DIAGNOSTICS_ABI_VERSION,
           "diagnostics ABI version");
    Expect(
        dmr_runtime_diagnostics_record_phase(
            DMR_DIAGNOSTIC_PHASE_ROOT_STARTING) == DMR_DIAGNOSTICS_NOT_STARTED,
        "phase without session is rejected");

    {
      dart_macos_runtime::RuntimeDiagnosticsSession invalid;
      auto invalid_options = options;
      invalid_options.metadata_directory = "relative";
      std::string error;
      Expect(!invalid.Start(invalid_options, &error) && !error.empty(),
             "relative persistence location is rejected");
    }
    {
      dart_macos_runtime::RuntimeDiagnosticsSession off_main;
      std::string error;
      bool started = true;
      std::thread worker([&] { started = off_main.Start(options, &error); });
      worker.join();
      Expect(!started && !error.empty(), "off-main start is rejected");
    }

    {
      dart_macos_runtime::RuntimeDiagnosticsSession first;
      std::string error;
      Expect(first.Start(options, &error), "first session starts");
      Expect(first.persistence_healthy(), "first record persists");
      Expect(Permissions(records) == 0700, "directory is owner-only");
      Expect(Permissions([records
                 stringByAppendingPathComponent:@"current-run.json"]) == 0600,
             "record is owner-only");
      Expect(dmr_runtime_diagnostics_record_phase(
                 DMR_DIAGNOSTIC_PHASE_ROOT_STARTING) == DMR_DIAGNOSTICS_OK,
             "root-starting phase");
      Expect(dmr_runtime_diagnostics_record_phase(
                 DMR_DIAGNOSTIC_PHASE_ROOT_READY) == DMR_DIAGNOSTICS_OK,
             "root-ready phase");
      Expect(dmr_runtime_diagnostics_record_phase(
                 DMR_DIAGNOSTIC_PHASE_ROOT_STARTING) ==
                 DMR_DIAGNOSTICS_PHASE_REGRESSION,
             "phase regression is rejected");
      NSDictionary<NSString*, id>* current =
          ReadJson(records, @"current-run.json");
      Expect(
          [current[@"format"]
              isEqualToString:@(dart_macos_runtime::kRuntimeDiagnosticsFormat)],
          "generic metadata format");
      Expect([current[@"phase"] isEqualToString:@"root-ready"],
             "phase is persisted");
    }

    {
      dart_macos_runtime::RuntimeDiagnosticsSession second;
      std::string error;
      Expect(second.Start(options, &error), "second session starts");
      NSDictionary<NSString*, id>* previous =
          ReadJson(records, @"previous-unclean-run.json");
      Expect([previous[@"outcome"] isEqualToString:@"running"],
             "unclean predecessor is retained");
      Expect(second.Finish(0), "clean finish persists");
      NSDictionary<NSString*, id>* current =
          ReadJson(records, @"current-run.json");
      Expect([current[@"outcome"] isEqualToString:@"clean"],
             "clean outcome is persisted");
      Expect([current[@"exit_code"] intValue] == 0, "exit result is persisted");
    }

    NSArray<NSString*>* files =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:records
                                                            error:nil];
    Expect(files.count == 2, "retention is bounded to two records");
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
  }
  if (failures != 0) {
    return 1;
  }
  std::cout << "RuntimeDiagnostics native contract passed\n";
  return 0;
}
