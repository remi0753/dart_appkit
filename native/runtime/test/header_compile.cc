#include <type_traits>

#include "dart_macos_runtime.h"

static_assert(std::is_same_v<decltype(dmr_runtime_abi_version()), uint32_t>);
static_assert(std::is_same_v<decltype(dmr_runtime_set_exit_code(70)), int32_t>);

int main() { return 0; }
