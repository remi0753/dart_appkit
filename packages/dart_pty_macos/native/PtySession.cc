#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <deque>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "PtySpawnInternal.h"
#include "dart_pty_macos.h"

namespace {

constexpr size_t kMaximumStringBytes = 1024 * 1024;
constexpr size_t kMaximumVectorEntries = 16 * 1024;
constexpr size_t kMaximumQueueBytes = 64 * 1024 * 1024;
constexpr size_t kReadBatchBytes = 64 * 1024;
constexpr uint32_t kMaximumCloseGraceMillis = 60 * 1000;
constexpr uintptr_t kControlEventIdentifier = 1;

thread_local DptyError g_last_error = {};
thread_local std::string g_last_error_message;

int32_t SetError(DptyStatus status, int32_t system_error, const char* message) {
  g_last_error_message = message == nullptr ? "" : message;
  g_last_error.status = status;
  g_last_error.system_error = system_error;
  g_last_error.message =
      g_last_error_message.empty() ? nullptr : g_last_error_message.c_str();
  g_last_error.message_length = g_last_error_message.size();
  return status;
}

void ClearError() { (void)SetError(DPTY_STATUS_OK, 0, nullptr); }

bool CopyString(const char* source, const char* field, std::string* target,
                bool allow_empty = false) {
  if (source == nullptr || target == nullptr) {
    (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL, field);
    return false;
  }
  const size_t length = strnlen(source, kMaximumStringBytes + 1);
  if ((!allow_empty && length == 0) || length > kMaximumStringBytes) {
    (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL, field);
    return false;
  }
  target->assign(source, length);
  return true;
}

struct OwnedConfig {
  std::string executable;
  std::vector<std::string> arguments;
  std::vector<std::string> environment;
  std::optional<std::string> working_directory;
  uint16_t rows = 0;
  uint16_t columns = 0;
  size_t read_high_water = 0;
  size_t read_low_water = 0;
  size_t write_capacity = 0;
  dpty_event_callback_v1 callback = nullptr;
  void* callback_context = nullptr;
};

bool CopyConfig(const DptySessionConfigV1* source, OwnedConfig* target) {
  if (source == nullptr || target == nullptr ||
      source->struct_size < sizeof(DptySessionConfigV1) ||
      source->abi_version != DPTY_ABI_VERSION || source->callback == nullptr ||
      source->arguments == nullptr || source->argument_count == 0 ||
      source->argument_count > kMaximumVectorEntries ||
      source->environment_count > kMaximumVectorEntries ||
      (source->environment_count != 0 && source->environment == nullptr) ||
      source->initial_rows == 0 || source->initial_columns == 0 ||
      source->read_high_water_bytes == 0 ||
      source->read_low_water_bytes >= source->read_high_water_bytes ||
      source->read_high_water_bytes > kMaximumQueueBytes ||
      source->write_capacity_bytes == 0 ||
      source->write_capacity_bytes > kMaximumQueueBytes) {
    (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                   "PTY session configuration is invalid");
    return false;
  }
  if (!CopyString(source->executable, "PTY executable is invalid",
                  &target->executable) ||
      target->executable.front() != '/') {
    (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                   "PTY executable must be an absolute path");
    return false;
  }
  target->arguments.reserve(source->argument_count);
  for (size_t index = 0; index < source->argument_count; ++index) {
    std::string value;
    if (!CopyString(source->arguments[index], "PTY argument is invalid", &value,
                    true)) {
      return false;
    }
    target->arguments.push_back(std::move(value));
  }
  target->environment.reserve(source->environment_count);
  for (size_t index = 0; index < source->environment_count; ++index) {
    std::string value;
    if (!CopyString(source->environment[index],
                    "PTY environment entry is invalid", &value) ||
        value.front() == '=' || value.find('=') == std::string::npos) {
      (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                     "PTY environment entry must be KEY=value");
      return false;
    }
    target->environment.push_back(std::move(value));
  }
  if (source->working_directory != nullptr) {
    std::string directory;
    if (!CopyString(source->working_directory,
                    "PTY working directory is invalid", &directory) ||
        directory.front() != '/') {
      (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                     "PTY working directory must be an absolute path");
      return false;
    }
    target->working_directory = std::move(directory);
  }
  target->rows = source->initial_rows;
  target->columns = source->initial_columns;
  target->read_high_water = source->read_high_water_bytes;
  target->read_low_water = source->read_low_water_bytes;
  target->write_capacity = source->write_capacity_bytes;
  target->callback = source->callback;
  target->callback_context = source->callback_context;
  return true;
}

struct OutputBatch {
  uint64_t sequence = 0;
  std::vector<uint8_t> bytes;
};

struct PendingResize {
  uint16_t rows = 0;
  uint16_t columns = 0;
};

class Session final : public std::enable_shared_from_this<Session> {
 public:
  explicit Session(OwnedConfig config) : config_(std::move(config)) {}

  ~Session() {
    if (thread_.joinable()) {
      thread_.join();
    }
  }

  void SetHandle(DptySessionHandle handle) { handle_ = handle; }

  int32_t Start() {
    const std::lock_guard<std::mutex> lock(mutex_);
    if (state_ != State::kCreated) {
      return SetError(DPTY_STATUS_WRONG_STATE, 0,
                      "PTY session has already been started");
    }
    state_ = State::kRunning;
    try {
      std::shared_ptr<Session> self = shared_from_this();
      thread_ = std::thread([self] { self->Run(); });
    } catch (...) {
      state_ = State::kFinished;
      return SetError(DPTY_STATUS_SYSTEM_ERROR, EAGAIN,
                      "could not create PTY reactor thread");
    }
    return DPTY_STATUS_OK;
  }

  int32_t Write(const uint8_t* bytes, size_t length) {
    if (bytes == nullptr || length == 0) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY write requires non-empty bytes");
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (state_ != State::kRunning || closing_) {
        return SetError(DPTY_STATUS_WRONG_STATE, 0,
                        "PTY session does not accept writes");
      }
      if (length > config_.write_capacity ||
          write_queued_bytes_ > config_.write_capacity - length) {
        ++write_backpressure_rejections_;
        return SetError(DPTY_STATUS_BACKPRESSURED, 0,
                        "PTY write queue is full");
      }
      writes_.emplace_back(bytes, bytes + length);
      write_queued_bytes_ += length;
      max_write_queued_bytes_ =
          std::max(max_write_queued_bytes_, write_queued_bytes_);
    }
    Wake();
    return DPTY_STATUS_OK;
  }

  int32_t Acknowledge(uint64_t sequence, size_t length) {
    bool should_wake = false;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (outstanding_.empty() || outstanding_.front().sequence != sequence ||
          outstanding_.front().bytes.size() != length) {
        return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                        "PTY output acknowledgement is out of order");
      }
      read_in_flight_bytes_ -= outstanding_.front().bytes.size();
      outstanding_.pop_front();
      should_wake =
          read_paused_ && read_in_flight_bytes_ <= config_.read_low_water;
    }
    if (should_wake) {
      Wake();
    }
    return DPTY_STATUS_OK;
  }

  int32_t Resize(uint16_t rows, uint16_t columns) {
    if (rows == 0 || columns == 0) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY size must be nonzero");
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (state_ != State::kRunning || closing_) {
        return SetError(DPTY_STATUS_WRONG_STATE, 0,
                        "PTY session cannot be resized");
      }
      pending_resize_ = PendingResize{rows, columns};
    }
    Wake();
    return DPTY_STATUS_OK;
  }

  int32_t SendSignal(uint32_t signal) {
    const int native_signal = NativeSignal(signal);
    if (native_signal == 0) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY signal is invalid");
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (state_ != State::kRunning || closing_) {
        return SetError(DPTY_STATUS_WRONG_STATE, 0,
                        "PTY session cannot receive a signal");
      }
      pending_signals_.push_back(native_signal);
    }
    Wake();
    return DPTY_STATUS_OK;
  }

  int32_t Close(uint32_t grace_period_millis) {
    if (grace_period_millis > kMaximumCloseGraceMillis) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY close grace period exceeds 60 seconds");
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (state_ == State::kFinished) {
        return DPTY_STATUS_OK;
      }
      if (state_ != State::kRunning) {
        return SetError(DPTY_STATUS_WRONG_STATE, 0,
                        "PTY session has not started");
      }
      if (!closing_) {
        closing_ = true;
        close_grace_millis_ = grace_period_millis;
      }
    }
    Wake();
    return DPTY_STATUS_OK;
  }

  int32_t GetStats(DptySessionStatsV1* output) const {
    if (output == nullptr || output->struct_size < sizeof(DptySessionStatsV1) ||
        output->abi_version != DPTY_ABI_VERSION) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY stats buffer is incompatible");
    }
    const std::lock_guard<std::mutex> lock(mutex_);
    output->bytes_read = bytes_read_;
    output->bytes_written = bytes_written_;
    output->read_batches = read_batches_;
    output->write_backpressure_rejections = write_backpressure_rejections_;
    output->max_read_in_flight_bytes = max_read_in_flight_bytes_;
    output->max_write_queued_bytes = max_write_queued_bytes_;
    output->read_pause_count = read_pause_count_;
    output->child_pid = child_pid_;
    output->has_exited = state_ == State::kFinished ? 1 : 0;
    return DPTY_STATUS_OK;
  }

  bool CanDestroy() const {
    const std::lock_guard<std::mutex> lock(mutex_);
    return state_ == State::kFinished && outstanding_.empty();
  }

  void Join() {
    if (thread_.joinable()) {
      thread_.join();
    }
  }

 private:
  enum class State { kCreated, kRunning, kFinished };

  static int NativeSignal(uint32_t signal) {
    switch (signal) {
      case DPTY_SIGNAL_INTERRUPT:
        return SIGINT;
      case DPTY_SIGNAL_SUSPEND:
        return SIGTSTP;
      case DPTY_SIGNAL_QUIT:
        return SIGQUIT;
      case DPTY_SIGNAL_HANGUP:
        return SIGHUP;
      case DPTY_SIGNAL_TERMINATE:
        return SIGTERM;
      case DPTY_SIGNAL_KILL:
        return SIGKILL;
      default:
        return 0;
    }
  }

  void Wake() const {
    const int descriptor = kqueue_fd_.load(std::memory_order_acquire);
    if (descriptor < 0) {
      return;
    }
    struct kevent trigger = {};
    EV_SET(&trigger, kControlEventIdentifier, EVFILT_USER, 0, NOTE_TRIGGER, 0,
           nullptr);
    (void)kevent(descriptor, &trigger, 1, nullptr, 0, nullptr);
  }

  void Emit(uint32_t type, uint64_t sequence, const uint8_t* bytes,
            size_t length, int64_t value1, int64_t value2,
            int32_t system_error) const {
    config_.callback(handle_, type, sequence, bytes, length, value1, value2,
                     system_error, config_.callback_context);
  }

  void FinishError(DptyStatus status, int32_t system_error) {
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      state_ = State::kFinished;
      child_pid_ = -1;
    }
    Emit(DPTY_EVENT_ERROR, 0, nullptr, 0, status, 0, system_error);
  }

  void Run() {
    std::vector<char*> argv;
    argv.reserve(config_.arguments.size() + 1);
    for (std::string& value : config_.arguments) {
      argv.push_back(value.data());
    }
    argv.push_back(nullptr);
    std::vector<char*> environment;
    environment.reserve(config_.environment.size() + 1);
    for (std::string& value : config_.environment) {
      environment.push_back(value.data());
    }
    environment.push_back(nullptr);

    DptyPreparedSpawnConfig spawn_config = {};
    spawn_config.executable = config_.executable.c_str();
    spawn_config.argv = argv.data();
    spawn_config.envp = environment.data();
    spawn_config.working_directory = config_.working_directory.has_value()
                                         ? config_.working_directory->c_str()
                                         : nullptr;
    spawn_config.initial_size.ws_row = config_.rows;
    spawn_config.initial_size.ws_col = config_.columns;
    DptyPreparedSpawnResult spawn_result = {};
    int32_t system_error = 0;
    const int32_t spawn_status =
        dpty_spawn_prepared(&spawn_config, &spawn_result, &system_error);
    if (spawn_status != DPTY_STATUS_OK) {
      FinishError(static_cast<DptyStatus>(spawn_status), system_error);
      return;
    }
    master_fd_ = spawn_result.master_fd;
    exec_error_fd_ = spawn_result.exec_error_fd;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      child_pid_ = spawn_result.child_pid;
    }

    if (!CheckExec(&system_error)) {
      TerminateAndReap(SIGKILL);
      CloseDescriptors();
      FinishError(DPTY_STATUS_SYSTEM_ERROR, system_error);
      return;
    }
    if (!ConfigureKqueue(&system_error)) {
      TerminateAndReap(SIGKILL);
      CloseDescriptors();
      FinishError(DPTY_STATUS_SYSTEM_ERROR, system_error);
      return;
    }

    Emit(DPTY_EVENT_STARTED, 0, nullptr, 0, spawn_result.child_pid, 0, 0);
    ProcessControl();
    EventLoop();
    CloseDescriptors();
  }

  bool CheckExec(int32_t* out_error) {
    struct pollfd descriptor = {};
    descriptor.fd = exec_error_fd_;
    descriptor.events = POLLIN | POLLHUP;
    int poll_status = 0;
    do {
      poll_status = poll(&descriptor, 1, 5000);
    } while (poll_status < 0 && errno == EINTR);
    if (poll_status <= 0) {
      *out_error = poll_status == 0 ? ETIMEDOUT : errno;
      return false;
    }
    int child_error = 0;
    ssize_t bytes = 0;
    do {
      bytes = read(exec_error_fd_, &child_error, sizeof(child_error));
    } while (bytes < 0 && errno == EINTR);
    (void)close(exec_error_fd_);
    exec_error_fd_ = -1;
    if (bytes == static_cast<ssize_t>(sizeof(child_error))) {
      *out_error = child_error;
      return false;
    }
    if (bytes < 0) {
      *out_error = errno;
      return false;
    }
    return true;
  }

  bool ConfigureKqueue(int32_t* out_error) {
    const int descriptor = kqueue();
    if (descriptor < 0) {
      *out_error = errno;
      return false;
    }
    struct kevent changes[4] = {};
    EV_SET(&changes[0], static_cast<uintptr_t>(master_fd_), EVFILT_READ,
           EV_ADD | EV_CLEAR, 0, 0, nullptr);
    EV_SET(&changes[1], static_cast<uintptr_t>(master_fd_), EVFILT_WRITE,
           EV_ADD | EV_CLEAR | EV_DISABLE, 0, 0, nullptr);
    EV_SET(&changes[2], static_cast<uintptr_t>(child_pid_), EVFILT_PROC,
           EV_ADD | EV_CLEAR, NOTE_EXIT, 0, nullptr);
    EV_SET(&changes[3], kControlEventIdentifier, EVFILT_USER, EV_ADD | EV_CLEAR,
           0, 0, nullptr);
    if (kevent(descriptor, changes, 4, nullptr, 0, nullptr) != 0) {
      *out_error = errno;
      (void)close(descriptor);
      return false;
    }
    kqueue_fd_.store(descriptor, std::memory_order_release);
    return true;
  }

  void EventLoop() {
    while (!finished_reaping_) {
      struct timespec timeout = {};
      timeout.tv_nsec = 100 * 1000 * 1000;
      struct kevent events[8] = {};
      const int count = kevent(kqueue_fd_.load(std::memory_order_acquire),
                               nullptr, 0, events, 8, &timeout);
      if (count < 0 && errno != EINTR) {
        TerminateAndReap(SIGKILL);
        FinishError(DPTY_STATUS_SYSTEM_ERROR, errno);
        return;
      }
      if (count > 0) {
        for (int index = 0; index < count; ++index) {
          if (events[index].filter == EVFILT_READ) {
            ReadAvailable();
          } else if (events[index].filter == EVFILT_WRITE) {
            FlushWrites();
          } else if (events[index].filter == EVFILT_PROC) {
            ReapChild();
          }
        }
      }
      ProcessControl();
      ReapChild();
      if (child_reaped_) {
        ReadAvailable();
        bool outstanding_capacity = false;
        {
          const std::lock_guard<std::mutex> lock(mutex_);
          outstanding_capacity =
              read_in_flight_bytes_ < config_.read_high_water;
        }
        if (master_eof_ || !outstanding_capacity) {
          if (!outstanding_capacity) {
            continue;
          }
          FinishExit();
        }
      }
    }
  }

  void ProcessControl() {
    std::optional<PendingResize> resize;
    std::deque<int> signals;
    bool begin_close = false;
    uint32_t grace_millis = 0;
    bool resume_read = false;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      resize = pending_resize_;
      pending_resize_.reset();
      signals.swap(pending_signals_);
      if (closing_ && !close_started_) {
        close_started_ = true;
        begin_close = true;
        grace_millis = close_grace_millis_;
      }
      resume_read =
          read_paused_ && read_in_flight_bytes_ <= config_.read_low_water;
    }
    if (resize.has_value() && master_fd_ >= 0) {
      struct winsize size = {};
      size.ws_row = resize->rows;
      size.ws_col = resize->columns;
      (void)ioctl(master_fd_, TIOCSWINSZ, &size);
    }
    for (const int signal : signals) {
      SendToForeground(signal);
    }
    if (begin_close) {
      SendToProcessGroups(SIGHUP);
      close_kill_deadline_ = std::chrono::steady_clock::now() +
                             std::chrono::milliseconds(grace_millis);
    }
    if (close_started_ && !child_reaped_ &&
        std::chrono::steady_clock::now() >= close_kill_deadline_) {
      SendToProcessGroups(SIGKILL);
      close_kill_deadline_ = std::chrono::steady_clock::time_point::max();
    }
    if (resume_read) {
      SetReadEnabled(true);
      ReadAvailable();
    }
    FlushWrites();
  }

  void ReadAvailable() {
    if (master_fd_ < 0 || master_eof_) {
      return;
    }
    for (;;) {
      size_t available = 0;
      bool pause_read = false;
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        if (read_in_flight_bytes_ >= config_.read_high_water) {
          if (!read_paused_) {
            read_paused_ = true;
            ++read_pause_count_;
          }
          pause_read = true;
        } else {
          available = std::min(kReadBatchBytes,
                               config_.read_high_water - read_in_flight_bytes_);
        }
      }
      if (pause_read) {
        SetReadEnabled(false);
        return;
      }
      std::vector<uint8_t> bytes(available);
      const ssize_t count = read(master_fd_, bytes.data(), bytes.size());
      if (count > 0) {
        bytes.resize(static_cast<size_t>(count));
        uint64_t sequence = 0;
        const uint8_t* data = nullptr;
        size_t length = 0;
        {
          const std::lock_guard<std::mutex> lock(mutex_);
          sequence = next_sequence_++;
          outstanding_.push_back(OutputBatch{sequence, std::move(bytes)});
          OutputBatch& batch = outstanding_.back();
          data = batch.bytes.data();
          length = batch.bytes.size();
          read_in_flight_bytes_ += length;
          bytes_read_ += length;
          ++read_batches_;
          max_read_in_flight_bytes_ =
              std::max(max_read_in_flight_bytes_, read_in_flight_bytes_);
        }
        Emit(DPTY_EVENT_OUTPUT, sequence, data, length, 0, 0, 0);
        continue;
      }
      if (count == 0 || (count < 0 && errno == EIO)) {
        master_eof_ = true;
        SetReadEnabled(false);
        return;
      }
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        return;
      }
      master_eof_ = true;
      SetReadEnabled(false);
      return;
    }
  }

  void FlushWrites() {
    if (master_fd_ < 0 || child_reaped_) {
      return;
    }
    for (;;) {
      const uint8_t* data = nullptr;
      size_t length = 0;
      bool empty = false;
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        if (writes_.empty()) {
          empty = true;
        } else {
          data = writes_.front().data() + write_offset_;
          length = writes_.front().size() - write_offset_;
        }
      }
      if (empty) {
        SetWriteEnabled(false);
        return;
      }
      const ssize_t count = write(master_fd_, data, length);
      if (count > 0) {
        const size_t consumed = static_cast<size_t>(count);
        const std::lock_guard<std::mutex> lock(mutex_);
        write_offset_ += consumed;
        write_queued_bytes_ -= consumed;
        bytes_written_ += consumed;
        if (write_offset_ == writes_.front().size()) {
          writes_.pop_front();
          write_offset_ = 0;
        }
        continue;
      }
      if (count < 0 && errno == EINTR) {
        continue;
      }
      if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
        SetWriteEnabled(true);
      }
      return;
    }
  }

  void SetReadEnabled(bool enabled) {
    const int descriptor = kqueue_fd_.load(std::memory_order_acquire);
    if (descriptor < 0 || master_fd_ < 0) {
      return;
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (read_enabled_ == enabled) {
        return;
      }
      read_enabled_ = enabled;
      if (enabled) {
        read_paused_ = false;
      }
    }
    struct kevent change = {};
    EV_SET(&change, static_cast<uintptr_t>(master_fd_), EVFILT_READ,
           enabled ? EV_ENABLE : EV_DISABLE, 0, 0, nullptr);
    (void)kevent(descriptor, &change, 1, nullptr, 0, nullptr);
  }

  void SetWriteEnabled(bool enabled) {
    const int descriptor = kqueue_fd_.load(std::memory_order_acquire);
    if (descriptor < 0 || master_fd_ < 0 || write_enabled_ == enabled) {
      return;
    }
    write_enabled_ = enabled;
    struct kevent change = {};
    EV_SET(&change, static_cast<uintptr_t>(master_fd_), EVFILT_WRITE,
           enabled ? EV_ENABLE : EV_DISABLE, 0, 0, nullptr);
    (void)kevent(descriptor, &change, 1, nullptr, 0, nullptr);
  }

  void SendToForeground(int signal) {
    pid_t target = master_fd_ >= 0 ? tcgetpgrp(master_fd_) : -1;
    if (target <= 0) {
      const std::lock_guard<std::mutex> lock(mutex_);
      target = child_pid_;
    }
    if (target > 0) {
      (void)kill(-target, signal);
    }
  }

  void SendToProcessGroups(int signal) {
    pid_t child = -1;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      child = child_pid_;
    }
    const pid_t foreground = master_fd_ >= 0 ? tcgetpgrp(master_fd_) : -1;
    if (foreground > 0) {
      (void)kill(-foreground, signal);
    }
    if (child > 0 && child != foreground) {
      (void)kill(-child, signal);
      (void)kill(child, signal);
    }
  }

  void ReapChild() {
    if (child_reaped_) {
      return;
    }
    pid_t child = -1;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      child = child_pid_;
    }
    if (child <= 0) {
      return;
    }
    int status = 0;
    const pid_t waited = waitpid(child, &status, WNOHANG);
    if (waited == child) {
      child_reaped_ = true;
      child_status_ = status;
    }
  }

  void FinishExit() {
    int64_t exit_code = 0;
    int64_t signal = 0;
    if (WIFEXITED(child_status_)) {
      exit_code = WEXITSTATUS(child_status_);
    } else if (WIFSIGNALED(child_status_)) {
      signal = WTERMSIG(child_status_);
      exit_code = 128 + signal;
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      state_ = State::kFinished;
    }
    finished_reaping_ = true;
    Emit(DPTY_EVENT_EXIT, 0, nullptr, 0, exit_code, signal, 0);
  }

  void TerminateAndReap(int signal) {
    SendToProcessGroups(signal);
    pid_t child = -1;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      child = child_pid_;
    }
    if (child > 0) {
      while (waitpid(child, nullptr, 0) < 0 && errno == EINTR) {
      }
    }
  }

  void CloseDescriptors() {
    const int descriptor = kqueue_fd_.exchange(-1, std::memory_order_acq_rel);
    if (descriptor >= 0) {
      (void)close(descriptor);
    }
    if (exec_error_fd_ >= 0) {
      (void)close(exec_error_fd_);
      exec_error_fd_ = -1;
    }
    if (master_fd_ >= 0) {
      (void)close(master_fd_);
      master_fd_ = -1;
    }
  }

  OwnedConfig config_;
  DptySessionHandle handle_ = 0;
  mutable std::mutex mutex_;
  std::thread thread_;
  State state_ = State::kCreated;
  std::atomic<int> kqueue_fd_{-1};
  int master_fd_ = -1;
  int exec_error_fd_ = -1;
  pid_t child_pid_ = -1;
  bool child_reaped_ = false;
  int child_status_ = 0;
  bool master_eof_ = false;
  bool finished_reaping_ = false;
  bool read_enabled_ = true;
  bool write_enabled_ = false;
  uint64_t next_sequence_ = 0;
  std::deque<OutputBatch> outstanding_;
  size_t read_in_flight_bytes_ = 0;
  bool read_paused_ = false;
  std::deque<std::vector<uint8_t>> writes_;
  size_t write_offset_ = 0;
  size_t write_queued_bytes_ = 0;
  std::optional<PendingResize> pending_resize_;
  std::deque<int> pending_signals_;
  bool closing_ = false;
  bool close_started_ = false;
  uint32_t close_grace_millis_ = 0;
  std::chrono::steady_clock::time_point close_kill_deadline_ =
      std::chrono::steady_clock::time_point::max();
  uint64_t bytes_read_ = 0;
  uint64_t bytes_written_ = 0;
  uint64_t read_batches_ = 0;
  uint64_t write_backpressure_rejections_ = 0;
  size_t max_read_in_flight_bytes_ = 0;
  size_t max_write_queued_bytes_ = 0;
  uint64_t read_pause_count_ = 0;
};

class SessionRegistry final {
 public:
  DptySessionHandle Insert(const std::shared_ptr<Session>& session) {
    const std::lock_guard<std::mutex> lock(mutex_);
    uint32_t index = 0;
    if (free_indices_.empty()) {
      if (slots_.size() >= std::numeric_limits<uint32_t>::max()) {
        return 0;
      }
      index = static_cast<uint32_t>(slots_.size());
      slots_.push_back(Slot{});
    } else {
      index = free_indices_.back();
      free_indices_.pop_back();
    }
    Slot& slot = slots_[index];
    slot.session = session;
    ++live_count_;
    return Encode(index, slot.generation);
  }

  std::shared_ptr<Session> Lookup(DptySessionHandle handle) const {
    uint32_t index = 0;
    uint32_t generation = 0;
    if (!Decode(handle, &index, &generation)) {
      return nullptr;
    }
    const std::lock_guard<std::mutex> lock(mutex_);
    if (index >= slots_.size()) {
      return nullptr;
    }
    const Slot& slot = slots_[index];
    if (slot.generation != generation || slot.session == nullptr) {
      return nullptr;
    }
    return slot.session;
  }

  std::shared_ptr<Session> Remove(DptySessionHandle handle) {
    uint32_t index = 0;
    uint32_t generation = 0;
    if (!Decode(handle, &index, &generation)) {
      return nullptr;
    }
    const std::lock_guard<std::mutex> lock(mutex_);
    if (index >= slots_.size()) {
      return nullptr;
    }
    Slot& slot = slots_[index];
    if (slot.generation != generation || slot.session == nullptr) {
      return nullptr;
    }
    std::shared_ptr<Session> session = std::move(slot.session);
    ++slot.generation;
    if (slot.generation == 0) {
      slot.generation = 1;
    }
    free_indices_.push_back(index);
    --live_count_;
    return session;
  }

  uint64_t live_count() const {
    const std::lock_guard<std::mutex> lock(mutex_);
    return live_count_;
  }

 private:
  struct Slot {
    uint32_t generation = 1;
    std::shared_ptr<Session> session;
  };

  static DptySessionHandle Encode(uint32_t index, uint32_t generation) {
    return (static_cast<uint64_t>(generation) << 32) |
           (static_cast<uint64_t>(index) + 1);
  }

  static bool Decode(DptySessionHandle handle, uint32_t* index,
                     uint32_t* generation) {
    const uint32_t encoded_index = static_cast<uint32_t>(handle);
    const uint32_t encoded_generation = static_cast<uint32_t>(handle >> 32);
    if (encoded_index == 0 || encoded_generation == 0) {
      return false;
    }
    *index = encoded_index - 1;
    *generation = encoded_generation;
    return true;
  }

  mutable std::mutex mutex_;
  std::deque<Slot> slots_;
  std::vector<uint32_t> free_indices_;
  uint64_t live_count_ = 0;
};

SessionRegistry g_registry;

std::shared_ptr<Session> LookupSession(DptySessionHandle handle) {
  std::shared_ptr<Session> session = g_registry.Lookup(handle);
  if (session == nullptr) {
    (void)SetError(DPTY_STATUS_INVALID_HANDLE, 0,
                   "PTY session handle is stale or invalid");
  }
  return session;
}

}  // namespace

extern "C" __attribute__((visibility("default"))) uint32_t
dpty_abi_version(void) {
  return DPTY_ABI_VERSION;
}

extern "C" __attribute__((visibility("default"))) int32_t dpty_session_create(
    const DptySessionConfigV1* config, DptySessionHandle* out_session) {
  ClearError();
  if (out_session == nullptr) {
    return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                    "PTY output session pointer is null");
  }
  *out_session = 0;
  try {
    OwnedConfig copied;
    if (!CopyConfig(config, &copied)) {
      return g_last_error.status;
    }
    std::shared_ptr<Session> session =
        std::make_shared<Session>(std::move(copied));
    const DptySessionHandle handle = g_registry.Insert(session);
    if (handle == 0) {
      return SetError(DPTY_STATUS_SYSTEM_ERROR, ENOMEM,
                      "PTY session registry is exhausted");
    }
    session->SetHandle(handle);
    *out_session = handle;
    return DPTY_STATUS_OK;
  } catch (...) {
    return SetError(DPTY_STATUS_SYSTEM_ERROR, ENOMEM,
                    "could not allocate PTY session");
  }
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_start(DptySessionHandle session) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE : value->Start();
}

extern "C" __attribute__((visibility("default"))) int32_t dpty_session_write(
    DptySessionHandle session, const uint8_t* bytes, size_t length) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->Write(bytes, length);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_ack_output(DptySessionHandle session, uint64_t sequence,
                        size_t length) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->Acknowledge(sequence, length);
}

extern "C" __attribute__((visibility("default"))) int32_t dpty_session_resize(
    DptySessionHandle session, uint16_t rows, uint16_t columns) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->Resize(rows, columns);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_send_signal(DptySessionHandle session, uint32_t signal) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->SendSignal(signal);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_close(DptySessionHandle session, uint32_t grace_period_millis) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->Close(grace_period_millis);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_get_stats(DptySessionHandle session,
                       DptySessionStatsV1* out_stats) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->GetStats(out_stats);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_destroy(DptySessionHandle session) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  if (value == nullptr) {
    return DPTY_STATUS_INVALID_HANDLE;
  }
  if (!value->CanDestroy()) {
    return SetError(
        DPTY_STATUS_WRONG_STATE, 0,
        "PTY session has not finished or has unacknowledged output");
  }
  std::shared_ptr<Session> removed = g_registry.Remove(session);
  if (removed == nullptr) {
    return SetError(DPTY_STATUS_INVALID_HANDLE, 0,
                    "PTY session handle became stale");
  }
  removed->Join();
  return DPTY_STATUS_OK;
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_get_last_error(DptyError* out_error) {
  if (out_error == nullptr) {
    return DPTY_STATUS_INVALID_ARGUMENT;
  }
  *out_error = g_last_error;
  return DPTY_STATUS_OK;
}

extern "C" __attribute__((visibility("default"))) uint64_t
dpty_debug_live_session_count(void) {
  return g_registry.live_count();
}
