#ifndef DART_APPKIT_BRIDGE_SRC_OBJECT_REGISTRY_H_
#define DART_APPKIT_BRIDGE_SRC_OBJECT_REGISTRY_H_

#import <Foundation/Foundation.h>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

#include "dart_appkit.h"

namespace dart_appkit {

enum class ObjectKind : uint8_t {
  kWindow = 1,
  kTextView = 2,
};

const char* ObjectKindName(ObjectKind kind);

class ObjectRegistry final {
 public:
  static ObjectRegistry& Shared();

  DaHandle Insert(id object, ObjectKind kind);
  id Lookup(DaHandle handle, ObjectKind expected_kind, int32_t* out_status);
  id LookupAny(DaHandle handle, ObjectKind* out_kind, int32_t* out_status);
  int32_t Release(DaHandle handle);

  size_t live_count() const { return live_count_; }
  std::vector<DaHandle> LiveHandles() const;
  void Clear();

  ObjectRegistry(const ObjectRegistry&) = delete;
  ObjectRegistry& operator=(const ObjectRegistry&) = delete;

 private:
  struct Slot {
    __strong id object = nil;
    ObjectKind kind = ObjectKind::kWindow;
    uint32_t generation = 1;
    bool occupied = false;
  };

  ObjectRegistry() = default;

  static DaHandle Encode(uint32_t index, uint32_t generation);
  static bool Decode(DaHandle handle, uint32_t* out_index,
                     uint32_t* out_generation);
  Slot* ValidatedSlot(DaHandle handle, int32_t* out_status);
  const Slot* ValidatedSlot(DaHandle handle, int32_t* out_status) const;

  std::vector<std::unique_ptr<Slot>> slots_;
  std::vector<uint32_t> free_indices_;
  size_t live_count_ = 0;
};

}  // namespace dart_appkit

#endif  // DART_APPKIT_BRIDGE_SRC_OBJECT_REGISTRY_H_
