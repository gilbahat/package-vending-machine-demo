/*
 * vend_krml_compat.h -- the entire C runtime dependency of the verified code.
 *
 * KaRaMeL's default `krmllib.h` pulls in <stdio.h> and <stdlib.h> to implement
 * its host-error macros. A Solo5 unikernel has neither. Generating with
 * `krml -minimal` and supplying this header instead keeps the verified
 * validator dependent on nothing but <stdint.h> and <stdbool.h>, which are
 * freestanding headers every conforming compiler provides without a libc.
 *
 * The macros below are reachable only from the default arm of a switch over a
 * three-valued enum, i.e. only if the caller passes a tag outside the enum.
 * The F* proof rules that out for any well-typed caller; the abort is what
 * happens if C code violates the type anyway.
 *
 * Copyright (c) 2026. SPDX-License-Identifier: ISC
 */
#ifndef VEND_KRML_COMPAT_H
#define VEND_KRML_COMPAT_H

#include <stdint.h>
#include <stdbool.h>

/* Supplied by the host: Solo5 maps this to solo5_abort(), the test harness to
 * abort(). Declared, never defined, here. `_Noreturn` matters -- without it
 * the compiler cannot see that the unreachable switch arm does not fall
 * through, and warns about a missing return. */
_Noreturn void vend_panic(const char *msg);

#define KRML_HOST_EPRINTF(...) ((void)0)
#define KRML_HOST_EXIT(n)      vend_panic("verified code: unreachable state")
#define KRML_HOST_PRINTF(...)  ((void)0)

#ifndef KRML_MAYBE_UNUSED_VAR
#define KRML_MAYBE_UNUSED_VAR(x) (void)(x)
#endif

#ifndef KRML_NOINLINE
#define KRML_NOINLINE
#endif

#ifndef KRML_ATTRIBUTE_TARGET
#define KRML_ATTRIBUTE_TARGET(x)
#endif

#endif /* VEND_KRML_COMPAT_H */
