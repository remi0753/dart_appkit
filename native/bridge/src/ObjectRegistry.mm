#include "ObjectRegistry.h"

#include <pthread.h>

#include <limits>
#include <mutex>
#include <string>
#include <utility>

#include "BridgeInternal.h"

namespace dart_appkit {
namespace {

constexpr uint64_t kIndexMask = 0xffffffffULL;
constexpr uint32_t kMaxSignedGeneration =
    static_cast<uint32_t>(std::numeric_limits<int32_t>::max());

}  // namespace

const char* ObjectKindName(ObjectKind kind) {
  switch (kind) {
    case ObjectKind::kWindow:
      return "window";
    case ObjectKind::kTextView:
      return "text view";
  }
  return "unknown";
}

const char* ThreadDomainName(ThreadDomain domain) {
  switch (domain) {
    case ThreadDomain::kAppKitMain:
      return "AppKit main";
  }
  return "unknown";
}

bool IsCurrentThreadInDomain(ThreadDomain domain) {
  switch (domain) {
    case ThreadDomain::kAppKitMain:
      return pthread_main_np() != 0;
  }
  return false;
}

ObjectRegistry& ObjectRegistry::Shared() {
  static ObjectRegistry registry;
  return registry;
}

DaHandle ObjectRegistry::Encode(uint32_t index, uint32_t generation) {
  const uint64_t one_based_index = static_cast<uint64_t>(index) + 1;
  return (static_cast<uint64_t>(generation) << 32) | one_based_index;
}

bool ObjectRegistry::Decode(DaHandle handle, uint32_t* out_index,
                            uint32_t* out_generation) {
  if (handle == 0 || out_index == nullptr || out_generation == nullptr) {
    return false;
  }

  const uint64_t one_based_index = handle & kIndexMask;
  const uint64_t generation = handle >> 32;
  if (one_based_index == 0 || generation == 0 ||
      one_based_index > std::numeric_limits<uint32_t>::max()) {
    return false;
  }

  *out_index = static_cast<uint32_t>(one_based_index - 1);
  *out_generation = static_cast<uint32_t>(generation);
  return true;
}

DaHandle ObjectRegistry::Insert(id object, ObjectKind kind,
                                ThreadDomain domain) {
  if (object == nil) {
    SetLastError(DA_STATUS_INVALID_ARGUMENT,
                 "cannot register a nil native object");
    return 0;
  }
  if (!IsCurrentThreadInDomain(domain)) {
    SetLastError(DA_STATUS_WRONG_THREAD,
                 "native object must be registered on its owning domain");
    return 0;
  }

  const std::lock_guard<std::mutex> lock(mutex_);
  uint32_t index = 0;
  Slot* slot = nullptr;
  if (!free_indices_.empty()) {
    index = free_indices_.back();
    free_indices_.pop_back();
    slot = slots_[index].get();
  } else {
    if (slots_.size() >= std::numeric_limits<uint32_t>::max()) {
      SetLastError(DA_STATUS_INTERNAL_ERROR,
                   "native object registry exhausted its handle space");
      return 0;
    }
    index = static_cast<uint32_t>(slots_.size());
    slots_.push_back(std::make_unique<Slot>());
    slot = slots_.back().get();
  }

  slot->object = object;
  slot->kind = kind;
  slot->domain = domain;
  slot->state = SlotState::kLive;
  ++live_count_;
  return Encode(index, slot->generation);
}

const ObjectRegistry::Slot* ObjectRegistry::ValidatedSlotLocked(
    DaHandle handle, SlotState expected_state, int32_t* out_status) const {
  uint32_t index = 0;
  uint32_t generation = 0;
  if (!Decode(handle, &index, &generation) || index >= slots_.size()) {
    if (out_status != nullptr) {
      *out_status = SetLastError(DA_STATUS_INVALID_HANDLE,
                                 "invalid native object handle");
    }
    return nullptr;
  }

  const Slot* slot = slots_[index].get();
  if (slot->state != expected_state || slot->generation != generation ||
      slot->object == nil) {
    if (out_status != nullptr) {
      *out_status = SetLastError(DA_STATUS_INVALID_HANDLE,
                                 "stale or released native object handle");
    }
    return nullptr;
  }

  if (out_status != nullptr) {
    *out_status = DA_STATUS_OK;
  }
  return slot;
}

int32_t ObjectRegistry::ValidateDomainLocked(
    const Slot& slot, ThreadDomain expected_domain,
    bool require_current_thread) const {
  if (slot.domain != expected_domain) {
    const std::string message = std::string("native object belongs to the ") +
                                ThreadDomainName(slot.domain) +
                                " domain, not the requested " +
                                ThreadDomainName(expected_domain) + " domain";
    return SetLastError(DA_STATUS_WRONG_THREAD, message);
  }
  if (require_current_thread && !IsCurrentThreadInDomain(expected_domain)) {
    const std::string message =
        std::string("native object access must run on the ") +
        ThreadDomainName(expected_domain) + " domain";
    return SetLastError(DA_STATUS_WRONG_THREAD, message);
  }
  return DA_STATUS_OK;
}

id ObjectRegistry::Lookup(DaHandle handle, ObjectKind expected_kind,
                          ThreadDomain expected_domain, int32_t* out_status) {
  const std::lock_guard<std::mutex> lock(mutex_);
  const Slot* slot = ValidatedSlotLocked(handle, SlotState::kLive, out_status);
  if (slot == nullptr) {
    return nil;
  }
  const int32_t domain_status =
      ValidateDomainLocked(*slot, expected_domain, true);
  if (domain_status != DA_STATUS_OK) {
    if (out_status != nullptr) {
      *out_status = domain_status;
    }
    return nil;
  }
  if (slot->kind != expected_kind) {
    if (out_status != nullptr) {
      const std::string message =
          std::string("expected ") + ObjectKindName(expected_kind) +
          " handle but received " + ObjectKindName(slot->kind);
      *out_status = SetLastError(DA_STATUS_WRONG_HANDLE_TYPE, message);
    }
    return nil;
  }
  return slot->object;
}

int32_t ObjectRegistry::BeginRelease(DaHandle handle,
                                     ThreadDomain expected_domain) {
  const std::lock_guard<std::mutex> lock(mutex_);
  int32_t status = DA_STATUS_OK;
  const Slot* validated =
      ValidatedSlotLocked(handle, SlotState::kLive, &status);
  if (validated == nullptr) {
    return status;
  }
  status = ValidateDomainLocked(*validated, expected_domain, false);
  if (status != DA_STATUS_OK) {
    return status;
  }
  Slot* slot = const_cast<Slot*>(validated);
  slot->state = SlotState::kReleasePending;
  return DA_STATUS_OK;
}

id ObjectRegistry::LookupPendingRelease(DaHandle handle,
                                        ThreadDomain expected_domain,
                                        ObjectKind* out_kind,
                                        int32_t* out_status) {
  const std::lock_guard<std::mutex> lock(mutex_);
  const Slot* slot =
      ValidatedSlotLocked(handle, SlotState::kReleasePending, out_status);
  if (slot == nullptr) {
    return nil;
  }
  const int32_t domain_status =
      ValidateDomainLocked(*slot, expected_domain, true);
  if (domain_status != DA_STATUS_OK) {
    if (out_status != nullptr) {
      *out_status = domain_status;
    }
    return nil;
  }
  if (out_kind != nullptr) {
    *out_kind = slot->kind;
  }
  return slot->object;
}

id ObjectRegistry::CompleteRelease(DaHandle handle,
                                   ThreadDomain expected_domain,
                                   int32_t* out_status) {
  uint32_t index = 0;
  uint32_t generation = 0;
  if (!Decode(handle, &index, &generation)) {
    if (out_status != nullptr) {
      *out_status = SetLastError(DA_STATUS_INVALID_HANDLE,
                                 "invalid native object handle");
    }
    return nil;
  }

  __strong id released_object = nil;
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    int32_t status = DA_STATUS_OK;
    const Slot* validated =
        ValidatedSlotLocked(handle, SlotState::kReleasePending, &status);
    if (validated == nullptr) {
      if (out_status != nullptr) {
        *out_status = status;
      }
      return nil;
    }
    status = ValidateDomainLocked(*validated, expected_domain, true);
    if (status != DA_STATUS_OK) {
      if (out_status != nullptr) {
        *out_status = status;
      }
      return nil;
    }

    Slot* slot = const_cast<Slot*>(validated);
    released_object = slot->object;
    slot->object = nil;
    --live_count_;
    if (slot->generation >= kMaxSignedGeneration) {
      slot->state = SlotState::kRetired;
    } else {
      ++slot->generation;
      slot->state = SlotState::kFree;
      free_indices_.push_back(index);
    }
  }
  if (out_status != nullptr) {
    *out_status = DA_STATUS_OK;
  }
  return released_object;
}

size_t ObjectRegistry::live_count() const {
  const std::lock_guard<std::mutex> lock(mutex_);
  return live_count_;
}

std::vector<DaHandle> ObjectRegistry::LiveHandles() const {
  const std::lock_guard<std::mutex> lock(mutex_);
  std::vector<DaHandle> handles;
  handles.reserve(live_count_);
  for (uint32_t index = 0; index < slots_.size(); ++index) {
    const Slot* slot = slots_[index].get();
    if ((slot->state == SlotState::kLive ||
         slot->state == SlotState::kReleasePending) &&
        slot->object != nil) {
      handles.push_back(Encode(index, slot->generation));
    }
  }
  return handles;
}

void ObjectRegistry::Clear() {
  std::vector<std::unique_ptr<Slot>> released_slots;
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    released_slots = std::move(slots_);
    free_indices_.clear();
    live_count_ = 0;
  }
  released_slots.clear();
}

}  // namespace dart_appkit
