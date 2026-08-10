/*
 * vend_shim.c -- see vend_shim.h. Hand-written, therefore trusted, therefore
 * short.
 *
 * Copyright (c) 2026. SPDX-License-Identifier: ISC
 */
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "EverParse.h"
#include "VendManifest.h"
#include "vend_shim.h"

/* ------------------------------------------------------------------ */
/* Error capture                                                       */
/* ------------------------------------------------------------------ */

#define VEND_ERR_MAX 192
static char vend_last_error[VEND_ERR_MAX];

/* Minimal, allocation-free string assembly: "Struct.field: reason".
 * Deliberately avoids snprintf so that this file needs no stdio, which is
 * what lets it link into a Solo5 unikernel unchanged. */
static void err_set(const char *s, const char *f, const char *r)
{
    size_t o = 0;
    const char *parts[5];
    parts[0] = s ? s : "?";
    parts[1] = ".";
    parts[2] = f ? f : "?";
    parts[3] = ": ";
    parts[4] = r ? r : "?";

    for (int i = 0; i < 5; i++) {
        for (const char *p = parts[i]; *p && o + 1 < VEND_ERR_MAX; p++)
            vend_last_error[o++] = *p;
    }
    vend_last_error[o] = '\0';
}

/* Called by the EverParse-generated wrapper code on rejection. */
void VendManifestEverParseError(const char *StructName, const char *FieldName,
                                const char *Reason)
{
    err_set(StructName, FieldName, Reason);
}

const char *vend_manifest_last_error(void)
{
    return vend_last_error;
}

/* ------------------------------------------------------------------ */
/* Validation with exact consumption                                   */
/* ------------------------------------------------------------------ */

static void error_handler(const char *typename_s, const char *fieldname,
                          const char *reason, uint64_t error_code,
                          uint8_t *context, EVERPARSE_INPUT_BUFFER input,
                          uint64_t start_pos)
{
    EVERPARSE_ERROR_FRAME *frame = (EVERPARSE_ERROR_FRAME *)context;
    EverParseDefaultErrorHandler(typename_s, fieldname, reason, error_code,
                                 frame, input, start_pos);
}

bool vend_manifest_check(const uint8_t *base, uint32_t len)
{
    EVERPARSE_ERROR_FRAME frame;
    frame.filled = FALSE;
    vend_last_error[0] = '\0';

    /* The generated validator takes a non-const pointer but does not write
     * through it; the cast is confined to this one line. */
    uint64_t result = VendManifestValidateVendManifest(
        (uint8_t *)&frame, &error_handler, (uint8_t *)(uintptr_t)base, len, 0);

    if (EverParseIsError(result)) {
        if (frame.filled)
            VendManifestEverParseError(frame.typename_s, frame.fieldname,
                                       frame.reason);
        return false;
    }

    /* THE POINT OF THIS FILE. On success the result is the position reached.
     * Anything short of `len` means the blob carries bytes the grammar gave
     * no meaning to, and we refuse rather than silently ignore them. */
    if (result != (uint64_t)len) {
        err_set("VendManifest", "<trailing>", "bytes after the entry list");
        return false;
    }

    return true;
}
