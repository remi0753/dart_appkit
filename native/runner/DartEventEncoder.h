#ifndef DART_APPKIT_RUNNER_DART_EVENT_ENCODER_H_
#define DART_APPKIT_RUNNER_DART_EVENT_ENCODER_H_

#include <cstdint>

#include "BridgeInternal.h"

namespace dart_appkit {

bool PostNativeEventToDartPort(int64_t dart_port,
                               uint32_t event_protocol_version,
                               const NativeEvent& event);

}  // namespace dart_appkit

#endif  // DART_APPKIT_RUNNER_DART_EVENT_ENCODER_H_
