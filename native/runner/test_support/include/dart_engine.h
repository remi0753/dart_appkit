// Declaration-only Dart 3.13.2 compatibility header for Runner syntax checks.
// Production builds always include the official header from DART_ENGINE_ROOT.
#ifndef DART_APPKIT_RUNNER_TEST_SUPPORT_DART_ENGINE_H_
#define DART_APPKIT_RUNNER_TEST_SUPPORT_DART_ENGINE_H_

#include "include/dart_api.h"

typedef enum {
  DartEngine_SnapshotKind_Kernel,
  DartEngine_SnapshotKind_AOT,
} DartEngine_SnapshotKind;

typedef struct DartEngine_SnapshotData {
  const char* script_uri;
  DartEngine_SnapshotKind kind;
  union {
    struct {
      const uint8_t* kernel_buffer;
      intptr_t kernel_buffer_size;
    };
    struct {
      const uint8_t* snapshot_data;
      const uint8_t* snapshot_text;
    };
  };
} DartEngine_SnapshotData;

DART_EXPORT bool DartEngine_Init(char** error);
DART_EXPORT void DartEngine_Shutdown(void);
DART_EXPORT DartEngine_SnapshotData DartEngine_KernelFromFile(const char* path,
                                                              char** error);
DART_EXPORT Dart_Isolate
DartEngine_CreateIsolate(DartEngine_SnapshotData snapshot_data, char** error);
DART_EXPORT void DartEngine_AcquireIsolate(Dart_Isolate isolate);
DART_EXPORT void DartEngine_ReleaseIsolate(void);

typedef void (*DartEngine_HandleMessageErrorCallback)(
    Dart_Handle error, Dart_Isolate destination_isolate);
DART_EXPORT void DartEngine_SetHandleMessageErrorCallback(
    DartEngine_HandleMessageErrorCallback callback);
DART_EXPORT Dart_Handle DartEngine_DrainMicrotasksQueue(void);
DART_EXPORT void DartEngine_HandleMessage(Dart_Isolate isolate);

typedef void (*DartEngine_ScheduleMessageCallback)(Dart_Isolate isolate,
                                                   void* context);
typedef struct DartEngine_MessageScheduler {
  DartEngine_ScheduleMessageCallback schedule_callback;
  void* context;
} DartEngine_MessageScheduler;

DART_EXPORT void DartEngine_SetDefaultMessageScheduler(
    DartEngine_MessageScheduler scheduler);
DART_EXPORT void DartEngine_SetMessageScheduler(
    DartEngine_MessageScheduler scheduler, Dart_Isolate isolate);

#endif  // DART_APPKIT_RUNNER_TEST_SUPPORT_DART_ENGINE_H_
