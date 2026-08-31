#ifndef DART_APPKIT_RUNNER_APP_DELEGATE_H_
#define DART_APPKIT_RUNNER_APP_DELEGATE_H_

#import <AppKit/AppKit.h>

#include <memory>

#include "DartHost.h"
#include "DartMessagePump.h"
#include "RunnerConfiguration.h"

@interface DartAppKitAppDelegate : NSObject <NSApplicationDelegate> {
 @private
  dart_appkit::RunnerConfiguration configuration_;
  std::unique_ptr<dart_appkit::DartMessagePump> message_pump_;
  std::unique_ptr<dart_appkit::DartHost> dart_host_;
  int exit_code_;
  BOOL did_shutdown_;
}

@property(nonatomic, readonly) int exitCode;

- (instancetype)initWithConfiguration:
    (const dart_appkit::RunnerConfiguration&)configuration;

@end

#endif  // DART_APPKIT_RUNNER_APP_DELEGATE_H_
