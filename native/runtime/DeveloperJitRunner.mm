#import <AppKit/AppKit.h>

#include <filesystem>
#include <iostream>
#include <memory>
#include <string>

#include "AppDelegate.h"
#include "RunnerArguments.h"
#include "RunnerConfiguration.h"
#include "RuntimeDiagnostics.h"
#include "RuntimeLifecycle.h"

@interface DartMacosRuntimeDeveloperDelegate : DartAppKitAppDelegate
@end

@implementation DartMacosRuntimeDeveloperDelegate

- (void)applicationWillTerminate:(NSNotification*)notification {
  [super applicationWillTerminate:notification];
  dart_macos_runtime::CompleteApplicationTermination(self.exitCode);
}

@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    std::unique_ptr<dart_macos_runtime::RuntimeDiagnosticsSession> diagnostics;
    std::string error;
    if (dart_macos_runtime::RuntimeDiagnosticsEnabledForCurrentProcess()) {
      dart_macos_runtime::RuntimeDiagnosticsOptions options;
      if (!dart_macos_runtime::RuntimeDiagnosticsOptionsForCurrentProcess(
              "developer-jit", &options, &error)) {
        std::cerr << "Runtime diagnostics startup failed: " << error << '\n';
        return dart_macos_runtime::kSoftwareExitCode;
      }
      diagnostics =
          std::make_unique<dart_macos_runtime::RuntimeDiagnosticsSession>();
      if (!diagnostics->Start(options, &error)) {
        std::cerr << "Runtime diagnostics startup failed: " << error << '\n';
        return dart_macos_runtime::kSoftwareExitCode;
      }
    }

    dart_appkit::RunnerConfiguration configuration;
    if (!dart_appkit::ParseRunnerArguments(argc, argv, &configuration,
                                           &error)) {
      std::cerr << "Runner argument error: " << error << '\n';
      std::cerr << dart_appkit::RunnerUsage(argv[0]);
      return dart_appkit::kRunnerUsageExitCode;
    }
    if (!std::filesystem::is_regular_file(configuration.kernel_path)) {
      std::cerr << "Kernel file does not exist: " << configuration.kernel_path
                << '\n';
      return dart_appkit::kRunnerInputExitCode;
    }

    NSApplication* application = [NSApplication sharedApplication];
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    DartMacosRuntimeDeveloperDelegate* delegate =
        [[DartMacosRuntimeDeveloperDelegate alloc]
            initWithConfiguration:configuration];
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
