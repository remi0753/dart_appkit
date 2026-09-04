#import <AppKit/AppKit.h>

#include <cstdio>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

#include "BridgeInternal.h"
#include "DartMessagePump.h"
#include "ObjectRegistry.h"
#include "ReleaseAotHost.h"
#include "RuntimeDiagnostics.h"
#include "RuntimeLifecycle.h"

@interface DartMacosRuntimeReleaseDelegate : NSObject <NSApplicationDelegate> {
 @private
  std::string snapshot_path_;
  std::vector<std::string> application_arguments_;
  std::unique_ptr<dart_appkit::DartMessagePump> message_pump_;
  std::unique_ptr<dart_macos_runtime::ReleaseAotHost> dart_host_;
  int exit_code_;
  BOOL did_shutdown_;
}

@property(nonatomic, readonly) int exitCode;

- (instancetype)initWithSnapshotPath:(const std::string&)snapshotPath
                applicationArguments:
                    (const std::vector<std::string>&)applicationArguments;

@end

@implementation DartMacosRuntimeReleaseDelegate

- (instancetype)initWithSnapshotPath:(const std::string&)snapshotPath
                applicationArguments:
                    (const std::vector<std::string>&)applicationArguments {
  self = [super init];
  if (self != nil) {
    snapshot_path_ = snapshotPath;
    application_arguments_ = applicationArguments;
    exit_code_ = 0;
    did_shutdown_ = NO;
  }
  return self;
}

- (int)exitCode {
  return exit_code_;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;
  message_pump_ = std::make_unique<dart_appkit::DartMessagePump>();
  std::string error;
  if (!message_pump_->Start(&error)) {
    std::fprintf(stderr, "Release AOT startup failed: %s\n", error.c_str());
    exit_code_ = dart_macos_runtime::kSoftwareExitCode;
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
    return;
  }
  dart_host_ =
      std::make_unique<dart_macos_runtime::ReleaseAotHost>(message_pump_.get());
  if (!dart_host_->Start(snapshot_path_, application_arguments_, &error)) {
    std::fprintf(stderr, "Release AOT startup failed: %s\n", error.c_str());
    exit_code_ = dart_macos_runtime::kSoftwareExitCode;
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
    return;
  }
  [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return NO;
}

- (void)applicationDidBecomeActive:(NSNotification*)notification {
  (void)notification;
  dart_appkit::PostApplicationActiveChanged(true);
}

- (void)applicationDidResignActive:(NSNotification*)notification {
  (void)notification;
  dart_appkit::PostApplicationActiveChanged(false);
}

- (BOOL)applicationShouldHandleReopen:(NSApplication*)sender
                    hasVisibleWindows:(BOOL)hasVisibleWindows {
  (void)sender;
  dart_appkit::PostApplicationReopenRequested(hasVisibleWindows);
  return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication*)sender {
  (void)sender;
  switch (dart_appkit::HandleApplicationShouldTerminate()) {
    case dart_appkit::ApplicationTerminationDecision::kTerminateNow:
      return NSTerminateNow;
    case dart_appkit::ApplicationTerminationDecision::kTerminateLater:
      return NSTerminateLater;
  }
  return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  (void)notification;
  if (did_shutdown_) {
    return;
  }
  did_shutdown_ = YES;
  if (dart_host_ != nullptr && dart_host_->has_fatal_error()) {
    std::fprintf(stderr, "Dart isolate terminated with an error: %s\n",
                 dart_host_->fatal_error().c_str());
    exit_code_ = dart_macos_runtime::kSoftwareExitCode;
  }
  const size_t leaked_handles =
      dart_appkit::ObjectRegistry::Shared().live_count();
  if (leaked_handles != 0) {
    std::fprintf(stderr, "Runtime shutdown releasing %zu native handle(s)\n",
                 leaked_handles);
    exit_code_ = dart_macos_runtime::kSoftwareExitCode;
  }
  dart_appkit::ShutdownBridge();
  if (message_pump_ != nullptr) {
    message_pump_->Stop();
  }
  if (dart_host_ != nullptr) {
    dart_host_->Shutdown();
  }
}

@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    std::unique_ptr<dart_macos_runtime::RuntimeDiagnosticsSession> diagnostics;
    std::string error;
    if (dart_macos_runtime::RuntimeDiagnosticsEnabledForCurrentProcess()) {
      dart_macos_runtime::RuntimeDiagnosticsOptions options;
      if (!dart_macos_runtime::RuntimeDiagnosticsOptionsForCurrentProcess(
              "release-aot", &options, &error)) {
        std::fprintf(stderr, "Runtime diagnostics startup failed: %s\n",
                     error.c_str());
        return dart_macos_runtime::kSoftwareExitCode;
      }
      diagnostics =
          std::make_unique<dart_macos_runtime::RuntimeDiagnosticsSession>();
      if (!diagnostics->Start(options, &error)) {
        std::fprintf(stderr, "Runtime diagnostics startup failed: %s\n",
                     error.c_str());
        return dart_macos_runtime::kSoftwareExitCode;
      }
    }

    NSString* snapshot = [[NSBundle mainBundle] pathForResource:@"application"
                                                         ofType:@"aot"];
    if (snapshot == nil ||
        !std::filesystem::is_regular_file(snapshot.fileSystemRepresentation)) {
      std::fprintf(stderr, "Release AOT snapshot not found in app bundle\n");
      return dart_macos_runtime::kInputExitCode;
    }
    std::vector<std::string> arguments;
    for (int index = 1; index < argc; ++index) {
      arguments.emplace_back(argv[index]);
    }
    NSApplication* application = [NSApplication sharedApplication];
    application.activationPolicy = NSApplicationActivationPolicyRegular;
    DartMacosRuntimeReleaseDelegate* delegate =
        [[DartMacosRuntimeReleaseDelegate alloc]
            initWithSnapshotPath:std::string(snapshot.fileSystemRepresentation)
            applicationArguments:arguments];
    application.delegate = delegate;
    [application run];
    const int exit_code =
        dart_macos_runtime::EffectiveExitCode(delegate.exitCode);
    if (diagnostics != nullptr) {
      diagnostics->Finish(exit_code);
    }
    return exit_code;
  }
}
