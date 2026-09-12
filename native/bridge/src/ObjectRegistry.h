#ifndef DART_APPKIT_BRIDGE_SRC_OBJECT_REGISTRY_H_
#define DART_APPKIT_BRIDGE_SRC_OBJECT_REGISTRY_H_

#import <Foundation/Foundation.h>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

#include "dart_appkit.h"

namespace dart_appkit {

enum class ObjectKind : uint8_t {
  kWindow = 1,
  kView = 2,
  kTextView = 3,
  kMenu = 4,
  kMenuItem = 5,
  kGlobalHotKey = 6,
};

enum class ThreadDomain : uint8_t {
  kAppKitMain = 1,
};

const char* ObjectKindName(ObjectKind kind);
bool ObjectKindMatches(ObjectKind actual_kind, ObjectKind expected_kind);
const char* ThreadDomainName(ThreadDomain domain);
bool IsCurrentThreadInDomain(ThreadDomain domain);

class ObjectRegistry final {
 public:
  static ObjectRegistry& Shared();

  DaHandle Insert(id object, ObjectKind kind, ThreadDomain domain);
  id Lookup(DaHandle handle, ObjectKind expected_kind,
            ThreadDomain expected_domain, int32_t* out_status);

  int32_t BeginRelease(DaHandle handle, ThreadDomain expected_domain);
  id LookupPendingRelease(DaHandle handle, ThreadDomain expected_domain,
                          ObjectKind* out_kind, int32_t* out_status);
  id CompleteRelease(DaHandle handle, ThreadDomain expected_domain,
                     int32_t* out_status);

  size_t live_count() const;
  std::vector<DaHandle> LiveHandles() const;
  void Clear();

  ObjectRegistry(const ObjectRegistry&) = delete;
  ObjectRegistry& operator=(const ObjectRegistry&) = delete;

 private:
  enum class SlotState : uint8_t {
    kFree,
    kLive,
    kReleasePending,
    kRetired,
  };

  struct Slot {
    __strong id object = nil;
    ObjectKind kind = ObjectKind::kWindow;
    ThreadDomain domain = ThreadDomain::kAppKitMain;
    uint32_t generation = 1;
    SlotState state = SlotState::kFree;
  };

  ObjectRegistry() = default;

  static DaHandle Encode(uint32_t index, uint32_t generation);
  static bool Decode(DaHandle handle, uint32_t* out_index,
                     uint32_t* out_generation);
  const Slot* ValidatedSlotLocked(DaHandle handle, SlotState expected_state,
                                  int32_t* out_status) const;
  int32_t ValidateDomainLocked(const Slot& slot, ThreadDomain expected_domain,
                               bool require_current_thread) const;

  mutable std::mutex mutex_;
  std::vector<std::unique_ptr<Slot>> slots_;
  std::vector<uint32_t> free_indices_;
  size_t live_count_ = 0;
};

}  // namespace dart_appkit

#endif  // DART_APPKIT_BRIDGE_SRC_OBJECT_REGISTRY_H_
