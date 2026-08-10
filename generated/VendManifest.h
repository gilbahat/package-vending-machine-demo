

#ifndef VendManifest_H
#define VendManifest_H

#if defined(__cplusplus)
extern "C" {
#endif

#include "EverParse.h"

#define VENDMANIFEST____ECOSYSTEM_PYPI (0U)

#define VENDMANIFEST____ECOSYSTEM_NPM (1U)

#define VENDMANIFEST____MAX_NAME_LEN (128U)

uint64_t
VendManifestValidateVendManifest(
  uint8_t *Ctxt,
  void
  (*ErrorHandlerFn)(
    EVERPARSE_STRING x0,
    EVERPARSE_STRING x1,
    EVERPARSE_STRING x2,
    uint64_t x3,
    uint8_t *x4,
    uint8_t *x5,
    uint64_t x6
  ),
  uint8_t *Input,
  uint64_t InputLength,
  uint64_t StartPosition
);

#if defined(__cplusplus)
}
#endif

#define VendManifest_H_DEFINED
#endif /* VendManifest_H */
