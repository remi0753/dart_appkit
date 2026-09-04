#include "dart_macos_runtime.h"

int main(void) {
  return DMR_RUNTIME_ABI_VERSION == 1u && DMR_DIAGNOSTICS_ABI_VERSION == 1u ? 0
                                                                            : 1;
}
