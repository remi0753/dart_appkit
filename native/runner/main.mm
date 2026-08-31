#import <AppKit/AppKit.h>

#include <filesystem>
#include <iostream>
#include <string>

#include "AppDelegate.h"
#include "RunnerArguments.h"
#include "RunnerConfiguration.h"

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    dart_appkit::RunnerConfiguration configuration;
    std::string error;
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
    DartAppKitAppDelegate* delegate =
        [[DartAppKitAppDelegate alloc] initWithConfiguration:configuration];
    application.delegate = delegate;
    [application run];
    return delegate.exitCode;
  }
}
