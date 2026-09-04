#include "dart_pty_macos.h"

int main(void) {
  DptySessionConfigV1 config = {0};
  DptySessionStatsV1 stats = {0};
  DptyError error = {0};
  uint32_t (*version)(void) = dpty_abi_version;
  config.struct_size = sizeof(config);
  stats.struct_size = sizeof(stats);
  return config.struct_size == 0 || stats.struct_size == 0 ||
         error.status != DPTY_STATUS_OK || version == NULL;
}
