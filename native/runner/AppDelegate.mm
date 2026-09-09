#include "AppDelegate.h"

#include <cstdio>
#include <string>

#include "BridgeInternal.h"
#include "ObjectRegistry.h"
#include "RunnerArguments.h"

@implementation DartAppKitAppDelegate

- (instancetype)initWithConfiguration:
    (const dart_appkit::RunnerConfiguration&)configuration {
  self = [super init];
  if (self != nil) {
    configuration_ = configuration;
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
  message_pump_ = std::make_unique<dart_appkit::DartMessagePump>(
      configuration_.message_pump_limits);
  std::string error;
  if (!message_pump_->Start(&error)) {
    std::fprintf(stderr, "Runner startup failed: %s\n", error.c_str());
    exit_code_ = dart_appkit::kRunnerSoftwareExitCode;
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
    return;
  }

  dart_host_ = std::make_unique<dart_appkit::DartHost>(message_pump_.get());
  if (!dart_host_->Start(configuration_, &error)) {
    std::fprintf(stderr, "Runner startup failed: %s\n", error.c_str());
    exit_code_ = dart_appkit::kRunnerSoftwareExitCode;
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
    return;
  }
  if (configuration_.activate_on_launch) {
    [NSApp activateIgnoringOtherApps:YES];
  }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return configuration_.terminate_after_last_window_closed;
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
  return configuration_.reopen_handled;
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
    exit_code_ = dart_appkit::kRunnerSoftwareExitCode;
  }

  const size_t leaked_handles =
      dart_appkit::ObjectRegistry::Shared().live_count();
  if (leaked_handles != 0) {
    std::fprintf(stderr,
                 "Dart AppKit shutdown releasing %zu live native handle(s)\n",
                 leaked_handles);
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
