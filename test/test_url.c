/*
 * test_url.c -- adversarial tests for the verified URL validator.
 *
 * Two things happen here.
 *
 *  1. A table of concrete payloads, each annotated with the class of
 *     Artifactory CVE it mirrors, is run through
 *     Vend_Url_validate_artifact_url and checked against its expected verdict.
 *
 *  2. A fuzzer generates random byte strings and random mutations of valid
 *     URLs, and asserts that ANY input the validator accepts satisfies an
 *     INDEPENDENTLY IMPLEMENTED copy of the security predicate (below). The
 *     point of re-implementing it here is that a bug in the extraction
 *     pipeline -- rather than in the proof -- would still be caught.
 *
 * Copyright (c) 2026. SPDX-License-Identifier: ISC
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include "Vend_Url.h"

_Noreturn void vend_panic(const char *msg)
{
    fprintf(stderr, "PANIC: %s\n", msg);
    abort();
}

/* ------------------------------------------------------------------ */
/* An independent restatement of Vend.Url.Spec.safe_url.               */
/* Deliberately written from the prose in the spec, not from the       */
/* generated C, so that it can disagree with it.                       */
/* ------------------------------------------------------------------ */

static const char *prefix_for(Vend_Url_upstream_tag t)
{
    switch (t) {
    case Vend_Url_TagPypiIndex:   return "https://pypi.org/simple/";
    case Vend_Url_TagPypiFiles:   return "https://files.pythonhosted.org/";
    case Vend_Url_TagNpmRegistry: return "https://registry.npmjs.org/";
    default:                      abort();
    }
}

static bool ref_is_path_byte(uint8_t c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') ||
           c == '-' || c == '.' || c == '_' || c == '~' || c == '/';
}

static bool ref_safe_url(Vend_Url_upstream_tag t, const uint8_t *s, uint32_t len)
{
    const char *p = prefix_for(t);
    uint32_t n = (uint32_t)strlen(p);

    if (len > 512) return false;
    if (len <= n)  return false;
    if (memcmp(s, p, n) != 0) return false;
    if (s[n] == '/' || s[n] == '.') return false;

    for (uint32_t i = n; i < len; i++) {
        if (!ref_is_path_byte(s[i])) return false;
        if (i + 1 < len && s[i] == '/' && (s[i + 1] == '/' || s[i + 1] == '.'))
            return false;
    }
    return true;
}

/* ------------------------------------------------------------------ */
/* Table-driven adversarial cases                                      */
/* ------------------------------------------------------------------ */

struct tcase {
    const char             *name;      /* what is being attempted        */
    const char             *cve;       /* the class it mirrors           */
    Vend_Url_upstream_tag   tag;
    const char             *url;
    size_t                  len;       /* 0 => use strlen               */
    bool                    expect;    /* expected verdict              */
};

#define ACCEPT true
#define REJECT false

static struct tcase cases[] = {
  /* ---- legitimate traffic the vending machine MUST serve ---------- */
  { "pypi simple index for a package", "-", Vend_Url_TagPypiIndex,
    "https://pypi.org/simple/numpy/", 0, ACCEPT },
  { "pypi wheel, content-addressed path", "-", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/packages/1a/2b/3c/"
    "numpy-2.1.0-cp312-cp312-manylinux_2_17_x86_64.whl", 0, ACCEPT },
  { "pypi sdist with ~ and _ in name", "-", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/packages/aa/bb/typing_extensions-4.12.2.tar.gz",
    0, ACCEPT },
  { "npm packument", "-", Vend_Url_TagNpmRegistry,
    "https://registry.npmjs.org/left-pad", 0, ACCEPT },
  { "npm scoped tarball with /-/ separator", "-", Vend_Url_TagNpmRegistry,
    "https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz", 0, ACCEPT },

  /* ---- SSRF: redirect the fetch to an attacker-chosen host --------- */
  { "userinfo authority confusion", "CVE-2026-65923/-65924/-65925 (SSRF)",
    Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org@evil.example/payload", 0, REJECT },
  { "allowed host appears, but not at position 0", "SSRF",
    Vend_Url_TagPypiFiles,
    "https://evil.example/files.pythonhosted.org/payload", 0, REJECT },
  { "backslash host confusion", "SSRF", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org\\@evil.example/x", 0, REJECT },
  { "empty segment reopening authority", "SSRF", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org//evil.example/x", 0, REJECT },
  { "scheme switch to file://", "SSRF", Vend_Url_TagPypiFiles,
    "file:///etc/passwd", 0, REJECT },
  { "scheme switch to gopher://", "SSRF", Vend_Url_TagPypiFiles,
    "gopher://127.0.0.1:11211/_stats", 0, REJECT },
  { "cloud metadata endpoint", "SSRF", Vend_Url_TagPypiFiles,
    "http://169.254.169.254/latest/meta-data/", 0, REJECT },
  { "wrong upstream for this URL", "SSRF", Vend_Url_TagNpmRegistry,
    "https://files.pythonhosted.org/packages/aa/bb/x.whl", 0, REJECT },

  /* ---- path traversal --------------------------------------------- */
  { "raw ../ traversal", "path traversal", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/../../etc/passwd", 0, REJECT },
  { "single-dot segment", "path traversal", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/./secret", 0, REJECT },
  { "percent-encoded traversal", "path traversal + encoding differential",
    Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/%2e%2e%2f%2e%2e%2fetc/passwd", 0, REJECT },
  { "double-encoded traversal", "path traversal", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/%252e%252e%252fetc", 0, REJECT },

  /* ---- request smuggling ------------------------------------------ */
  { "CRLF header injection", "request splitting", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/a\r\nHost:%20evil.example", 0, REJECT },
  { "bare LF injection", "request splitting", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/a\nX-Evil: 1", 0, REJECT },
  { "space splits the request line", "request splitting", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/a b", 0, REJECT },
  { "query string smuggles a second URL", "SSRF", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/x?next=https://evil.example", 0, REJECT },
  { "fragment hides an authority", "SSRF", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/x#@evil.example", 0, REJECT },

  /* ---- parser differentials --------------------------------------- */
  { "NUL truncation", "C string truncation", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/good\0.evil.example/x", 51, REJECT },
  { "non-ASCII homograph", "IDN/punycode homograph", Vend_Url_TagPypiFiles,
    /* Cyrillic 'а' (U+0430) in place of ASCII 'a'; split so the hex escape
       does not swallow the following 'd'. */
    "https://files.pythonhosted.org/\xd0\xb0" "dmin", 0, REJECT },
  { "tab in path", "request splitting", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/a\tb", 0, REJECT },

  /* ---- boundary conditions ---------------------------------------- */
  { "prefix only, nothing after", "-", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/", 0, REJECT },
  { "empty input", "-", Vend_Url_TagPypiFiles, "", 0, REJECT },
  { "prefix truncated by one byte", "-", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.or", 0, REJECT },
  { "suffix starts with slash", "-", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org//", 0, REJECT },
  { "suffix starts with dot", "-", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org/.hidden", 0, REJECT },
  { "http instead of https", "SSRF", Vend_Url_TagPypiFiles,
    "http://files.pythonhosted.org/x", 0, REJECT },
  { "uppercase host", "-", Vend_Url_TagPypiFiles,
    "https://FILES.PYTHONHOSTED.ORG/x", 0, REJECT },
  { "explicit port appended to host", "SSRF", Vend_Url_TagPypiFiles,
    "https://files.pythonhosted.org:8080/x", 0, REJECT },
};

/* ------------------------------------------------------------------ */

static int failures = 0;

static void check_case(const struct tcase *c)
{
    size_t len = c->len ? c->len : strlen(c->url);
    bool got = Vend_Url_validate_artifact_url(c->tag, (uint8_t *)c->url,
                                              (uint32_t)len);

    if (got != c->expect) {
        printf("  FAIL  %-42s expected %s, got %s\n", c->name,
               c->expect ? "ACCEPT" : "REJECT", got ? "ACCEPT" : "REJECT");
        failures++;
        return;
    }
    /* Anything accepted must independently satisfy the predicate. */
    if (got && !ref_safe_url(c->tag, (const uint8_t *)c->url, (uint32_t)len)) {
        printf("  FAIL  %-42s accepted but violates the predicate\n", c->name);
        failures++;
        return;
    }
    printf("  ok    %-42s %s%s%s\n", c->name,
           c->expect ? "ACCEPT" : "REJECT",
           strcmp(c->cve, "-") ? "   <- " : "",
           strcmp(c->cve, "-") ? c->cve : "");
}

/* ------------------------------------------------------------------ */
/* Fuzzing: accept must imply the independent predicate.               */
/* ------------------------------------------------------------------ */

static uint64_t rng_state = 0x2026070900000001ULL;

static uint32_t rnd(void)
{
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return (uint32_t)(rng_state >> 32);
}

static const char *seeds[] = {
    "https://pypi.org/simple/numpy/",
    "https://files.pythonhosted.org/packages/1a/2b/numpy-2.1.0.whl",
    "https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz",
};

static int fuzz(int rounds)
{
    uint8_t buf[700];
    int accepted = 0;

    for (int i = 0; i < rounds; i++) {
        Vend_Url_upstream_tag tag = (Vend_Url_upstream_tag)(rnd() % 3);
        uint32_t len;

        if (i % 3 == 0) {
            /* wholly random bytes */
            len = rnd() % sizeof(buf);
            for (uint32_t j = 0; j < len; j++) buf[j] = (uint8_t)(rnd() & 0xFF);
        } else {
            /* mutate a valid URL: the interesting neighbourhood */
            const char *s = seeds[rnd() % 3];
            len = (uint32_t)strlen(s);
            if (len > sizeof(buf)) len = sizeof(buf);
            memcpy(buf, s, len);
            int muts = 1 + (int)(rnd() % 3);
            for (int m = 0; m < muts; m++) {
                uint32_t op = rnd() % 3;
                if (op == 0 && len > 0) {          /* substitute */
                    buf[rnd() % len] = (uint8_t)(rnd() & 0xFF);
                } else if (op == 1 && len < sizeof(buf)) {  /* insert */
                    uint32_t at = rnd() % (len + 1);
                    memmove(buf + at + 1, buf + at, len - at);
                    buf[at] = (uint8_t)(rnd() & 0xFF);
                    len++;
                } else if (len > 0) {              /* delete */
                    uint32_t at = rnd() % len;
                    memmove(buf + at, buf + at + 1, len - at - 1);
                    len--;
                }
            }
        }

        bool got = Vend_Url_validate_artifact_url(tag, buf, len);
        bool ref = ref_safe_url(tag, buf, len);
        if (got != ref) {
            printf("  FAIL  fuzz divergence at round %d: validator=%s ref=%s\n",
                   i, got ? "ACCEPT" : "REJECT", ref ? "ACCEPT" : "REJECT");
            printf("        len=%u tag=%u bytes=", len, tag);
            for (uint32_t j = 0; j < len && j < 80; j++)
                printf("%02x", buf[j]);
            printf("\n");
            failures++;
            return accepted;
        }
        if (got) accepted++;
    }
    return accepted;
}

int main(void)
{
    size_t n = sizeof(cases) / sizeof(cases[0]);

    printf("verified URL validator -- adversarial cases\n");
    printf("-------------------------------------------------------------\n");
    for (size_t i = 0; i < n; i++) check_case(&cases[i]);

    printf("\nfuzzing (random bytes + mutations of valid URLs)\n");
    printf("-------------------------------------------------------------\n");
    int rounds = 200000;
    int accepted = fuzz(rounds);
    if (!failures)
        printf("  ok    %d rounds, %d accepted, validator agreed with the\n"
               "        independent predicate on every single input\n",
               rounds, accepted);

    printf("\n%s: %zu cases, %d failure(s)\n",
           failures ? "FAILED" : "PASSED", n, failures);
    return failures ? 1 : 0;
}
