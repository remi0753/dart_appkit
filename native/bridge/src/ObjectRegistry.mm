#include "ObjectRegistry.h"

#include <limits>
#include <string>

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

DaHandle ObjectRegistry::Insert(id object, ObjectKind kind) {
  if (object == nil) {
    SetLastError(DA_STATUS_INVALID_ARGUMENT,
                 "cannot register a nil native object");
    return 0;
  }

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
  slot->occupied = true;
  ++live_count_;
  return Encode(index, slot->generation);
}

ObjectRegistry::Slot* ObjectRegistry::ValidatedSlot(DaHandle handle,
                                                    int32_t* out_status) {
  return const_cast<Slot*>(
      static_cast<const ObjectRegistry*>(this)->ValidatedSlot(handle,
                                                              out_status));
}

const ObjectRegistry::Slot* ObjectRegistry::ValidatedSlot(
    DaHandle handle, int32_t* out_status) const {
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
  if (!slot->occupied || slot->generation != generation ||
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

id ObjectRegistry::Lookup(DaHandle handle, ObjectKind expected_kind,
                          int32_t* out_status) {
  Slot* slot = ValidatedSlot(handle, out_status);
  if (slot == nullptr) {
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

id ObjectRegistry::LookupAny(DaHandle handle, ObjectKind* out_kind,
                             int32_t* out_status) {
  Slot* slot = ValidatedSlot(handle, out_status);
  if (slot == nullptr) {
    return nil;
  }
  if (out_kind != nullptr) {
    *out_kind = slot->kind;
  }
  return slot->object;
}

int32_t ObjectRegistry::Release(DaHandle handle) {
  uint32_t index = 0;
  uint32_t generation = 0;
  if (!Decode(handle, &index, &generation)) {
    return SetLastError(DA_STATUS_INVALID_HANDLE,
                        "invalid native object handle");
  }

  int32_t status = DA_STATUS_OK;
  Slot* slot = ValidatedSlot(handle, &status);
  if (slot == nullptr) {
    return status;
  }

  slot->object = nil;
  slot->occupied = false;
  if (slot->generation >= kMaxSignedGeneration) {
    slot->generation = 1;
  } else {
    ++slot->generation;
  }
  free_indices_.push_back(index);
  --live_count_;
  return DA_STATUS_OK;
}

std::vector<DaHandle> ObjectRegistry::LiveHandles() const {
  std::vector<DaHandle> handles;
  handles.reserve(live_count_);
  for (uint32_t index = 0; index < slots_.size(); ++index) {
    const Slot* slot = slots_[index].get();
    if (slot->occupied && slot->object != nil) {
      handles.push_back(Encode(index, slot->generation));
    }
  }
  return handles;
}

void ObjectRegistry::Clear() {
  slots_.clear();
  free_indices_.clear();
  live_count_ = 0;
}

}  // namespace dart_appkit
