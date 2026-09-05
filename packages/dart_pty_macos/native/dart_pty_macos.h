#ifndef DART_PTY_MACOS_NATIVE_DART_PTY_MACOS_H_
#define DART_PTY_MACOS_NATIVE_DART_PTY_MACOS_H_

#include <stddef.h>
#include <stdint.h>

#define DPTY_ABI_VERSION 2u

#if defined(__cplusplus)
extern "C" {
#endif

typedef uint64_t DptySessionHandle;

typedef enum DptyStatus {
  DPTY_STATUS_OK = 0,
  DPTY_STATUS_INVALID_ARGUMENT = 1,
  DPTY_STATUS_INVALID_HANDLE = 2,
  DPTY_STATUS_WRONG_STATE = 3,
  DPTY_STATUS_BACKPRESSURED = 4,
  DPTY_STATUS_SYSTEM_ERROR = 5,
  DPTY_STATUS_TIMED_OUT = 6,
} DptyStatus;

typedef enum DptyEventType {
  DPTY_EVENT_STARTED = 1,
  DPTY_EVENT_OUTPUT = 2,
  DPTY_EVENT_EXIT = 3,
  DPTY_EVENT_ERROR = 4,
} DptyEventType;

typedef enum DptySignal {
  DPTY_SIGNAL_INTERRUPT = 1,
  DPTY_SIGNAL_SUSPEND = 2,
  DPTY_SIGNAL_QUIT = 3,
  DPTY_SIGNAL_HANGUP = 4,
  DPTY_SIGNAL_TERMINATE = 5,
  DPTY_SIGNAL_KILL = 6,
} DptySignal;

// OUTPUT data remains valid until its exact sequence/length pair is
// acknowledged. Other events have data=null and length=sequence=0.
// STARTED: value1=child pid.
// EXIT: value1=portable exit code, value2=terminating signal or 0.
// ERROR: value1=DptyStatus, system_error=errno or 0.
typedef void (*dpty_event_callback_v1)(DptySessionHandle session,
                                       uint32_t event_type, uint64_t sequence,
                                       const uint8_t* data, size_t length,
                                       int64_t value1, int64_t value2,
                                       int32_t system_error, void* context);

typedef struct DptySessionConfigV1 {
  size_t struct_size;
  uint32_t abi_version;
  const char* executable;
  const char* const* arguments;
  size_t argument_count;
  const char* const* environment;
  size_t environment_count;
  const char* working_directory;
  uint16_t initial_rows;
  uint16_t initial_columns;
  size_t read_high_water_bytes;
  size_t read_low_water_bytes;
  size_t write_capacity_bytes;
  dpty_event_callback_v1 callback;
  void* callback_context;
} DptySessionConfigV1;

typedef struct DptySessionStatsV1 {
  size_t struct_size;
  uint32_t abi_version;
  uint64_t bytes_read;
  uint64_t bytes_written;
  uint64_t read_batches;
  uint64_t write_backpressure_rejections;
  uint64_t max_read_in_flight_bytes;
  uint64_t max_write_queued_bytes;
  uint64_t read_pause_count;
  int64_t child_pid;
  int32_t has_exited;
} DptySessionStatsV1;

typedef struct DptyError {
  int32_t status;
  int32_t system_error;
  const char* message;
  size_t message_length;
} DptyError;

__attribute__((visibility("default"))) uint32_t dpty_abi_version(void);

__attribute__((visibility("default"))) int32_t dpty_session_create(
    const DptySessionConfigV1* config, DptySessionHandle* out_session);

// Starts the reactor and returns without waiting for fork, exec, or I/O.
__attribute__((visibility("default"))) int32_t
dpty_session_start(DptySessionHandle session);

// Copies accepted bytes into a bounded queue. Never waits for FD readiness.
__attribute__((visibility("default"))) int32_t dpty_session_write(
    DptySessionHandle session, const uint8_t* bytes, size_t length);

__attribute__((visibility("default"))) int32_t dpty_session_ack_output(
    DptySessionHandle session, uint64_t sequence, size_t length);

__attribute__((visibility("default"))) int32_t
dpty_session_resize(DptySessionHandle session, uint16_t rows, uint16_t columns);

// Sends the selected signal to the PTY foreground process group when known.
__attribute__((visibility("default"))) int32_t
dpty_session_send_signal(DptySessionHandle session, uint32_t signal);

// Requests SIGHUP immediately and SIGKILL after grace_period_millis.
__attribute__((visibility("default"))) int32_t
dpty_session_close(DptySessionHandle session, uint32_t grace_period_millis);

// Requests immediate SIGKILL escalation. Valid before or during graceful close,
// idempotent, and returns without waiting for process exit or reaping.
__attribute__((visibility("default"))) int32_t
dpty_session_force_close(DptySessionHandle session);

__attribute__((visibility("default"))) int32_t dpty_session_get_stats(
    DptySessionHandle session, DptySessionStatsV1* out_stats);

// Valid only after EXIT or ERROR and after all OUTPUT records are acknowledged.
__attribute__((visibility("default"))) int32_t
dpty_session_destroy(DptySessionHandle session);

__attribute__((visibility("default"))) int32_t
dpty_get_last_error(DptyError* out_error);

__attribute__((visibility("default"))) uint64_t
dpty_debug_live_session_count(void);

#if defined(__cplusplus)
}
#endif

#endif  // DART_PTY_MACOS_NATIVE_DART_PTY_MACOS_H_
