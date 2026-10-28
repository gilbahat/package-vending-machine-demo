/*
 * vend_shim.h -- the thin, TRUSTED boundary around the generated validators.
 *
 * Everything in generated/ is produced from a spec, by EverParse or by F*'s
 * Custard extractor. This file is not: it is hand-written C, and it is
 * therefore part of the trusted computing base. It is kept deliberately small
 * -- a few dozen lines -- so that it can be read in full.
 *
 * It exists for one reason. EverParse's generated wrapper answers "do these
 * bytes contain a well-formed VendManifest?" but not "do these bytes contain
 * NOTHING BUT a well-formed VendManifest?" -- it discards the end position, so
 * a blob with trailing garbage validates. That is a parser differential: the
 * signature covers N bytes while the parser gives meaning to only M < N of
 * them. `vend_manifest_check` closes it by requiring exact consumption.
 *
 * Copyright (c) 2026. SPDX-License-Identifier: ISC
 */
#ifndef VEND_SHIM_H
#define VEND_SHIM_H

#include <stdint.h>
#include <stdbool.h>

/* Fixed size of the VendManifest header, per spec/VendManifest.3d:
 *   magic(4) + format_version(2) + reserved(2) + entries_len(4)             */
#define VEND_MANIFEST_HEADER_LEN 12

/*
 * Validate a manifest blob, requiring that the parse consume every byte.
 * Returns true only if the whole buffer is exactly one VendManifest.
 *
 * The caller is expected to have verified the blob's signature first; this
 * function makes no claim about authenticity, only about shape.
 */
bool vend_manifest_check(const uint8_t *base, uint32_t len);

/*
 * Why the last vend_manifest_check failed, as "Struct.field: reason".
 * Returns an empty string if the last call succeeded. Never NULL.
 */
const char *vend_manifest_last_error(void);

#endif /* VEND_SHIM_H */
