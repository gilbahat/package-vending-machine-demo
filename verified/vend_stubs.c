/*
 * vend_stubs.c -- the OCaml/C boundary. Hand-written, therefore trusted,
 * therefore short.
 *
 * Neither verified function allocates, blocks, calls back into OCaml, or
 * retains its argument, so the OCaml string pointers are stable for the
 * duration of the call and no GC interaction is required. That is what makes
 * [@@noalloc] sound on the OCaml side.
 *
 * Copyright (c) 2026. SPDX-License-Identifier: ISC
 */
#include <stdint.h>
#include <stdbool.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>

#include "Vend_Url.h"
#include "vend_shim.h"

/* Pin the OCaml-side tag numbering to the C enum. If the generated header
 * ever renumbers, this fails to compile rather than silently mapping PyPI
 * requests onto the npm prefix. */
_Static_assert(VEND_URL_TAGPYPIINDEX   == 0, "tag numbering drifted");
_Static_assert(VEND_URL_TAGPYPIFILES   == 1, "tag numbering drifted");
_Static_assert(VEND_URL_TAGNPMREGISTRY == 2, "tag numbering drifted");

CAMLprim value caml_vend_validate_url(value tag, value url)
{
    /* No allocation below, so no CAMLparam/CAMLreturn dance is needed. */
    bool ok = Vend_Url_validate_artifact_url(
        (Vend_Url_upstream_tag)Int_val(tag),
        (uint8_t *)String_val(url),
        (uint32_t)caml_string_length(url));
    return Val_bool(ok);
}

CAMLprim value caml_vend_manifest_check(value body)
{
    bool ok = vend_manifest_check((const uint8_t *)String_val(body),
                                  (uint32_t)caml_string_length(body));
    return Val_bool(ok);
}

CAMLprim value caml_vend_manifest_last_error(value unit)
{
    (void)unit;
    return caml_copy_string(vend_manifest_last_error());
}
