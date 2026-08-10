/*
 * test_manifest.c -- adversarial tests for the EverParse-generated manifest
 * validator.
 *
 * The manifest is the vending machine's trust root: it says which package
 * names may be vended at all. These tests exercise the malformed-input cases
 * that a hand-written parser typically gets wrong -- truncation, length fields
 * that disagree with the buffer, out-of-range tags, and trailing bytes.
 *
 * Copyright (c) 2026. SPDX-License-Identifier: ISC
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include "vend_shim.h"

/* ------------------------------------------------------------------ */
/* A tiny builder, so the tests read as intent rather than hex.        */
/* ------------------------------------------------------------------ */

typedef struct {
    uint8_t  buf[4096];
    uint32_t len;
} blob;

static void put8(blob *b, uint8_t v)   { b->buf[b->len++] = v; }
static void put16(blob *b, uint16_t v) { put8(b, v >> 8); put8(b, v & 0xFF); }
static void put32(blob *b, uint32_t v) { put16(b, v >> 16); put16(b, v & 0xFFFF); }

static void put_entry(blob *b, uint8_t eco, const char *name, int name_len_override)
{
    size_t n = strlen(name);
    put8(b, eco);
    put8(b, name_len_override >= 0 ? (uint8_t)name_len_override : (uint8_t)n);
    memcpy(b->buf + b->len, name, n);
    b->len += (uint32_t)n;
}

/* Build a well-formed manifest over the given names, then let the caller
 * corrupt it. Returns offset of the entries_len field for convenience. */
static void build(blob *b, uint32_t magic, uint16_t ver, uint16_t reserved)
{
    b->len = 0;
    put32(b, magic);
    put16(b, ver);
    put16(b, reserved);
    put32(b, 0);            /* entries_len, patched by finish() */
}

static void finish(blob *b)
{
    uint32_t entries_len = b->len - 12;
    b->buf[8]  = (uint8_t)(entries_len >> 24);
    b->buf[9]  = (uint8_t)(entries_len >> 16);
    b->buf[10] = (uint8_t)(entries_len >> 8);
    b->buf[11] = (uint8_t)(entries_len);
}

#define MAGIC 0x564D4331u   /* "VMC1" */

static int failures = 0;

static void expect(const char *what, blob *b, bool want)
{
    bool got = vend_manifest_check(b->buf, b->len);
    if (got != want) {
        printf("  FAIL  %-46s expected %s, got %s\n", what,
               want ? "ACCEPT" : "REJECT", got ? "ACCEPT" : "REJECT");
        failures++;
    } else {
        printf("  ok    %-46s %-6s %s\n", what, want ? "ACCEPT" : "REJECT",
               want ? "" : vend_manifest_last_error());
    }
}

/* Validate the body of a real signed manifest produced by
 * scripts/build_manifest.py, so the writer and the parser are checked against
 * each other rather than only against my own test builder. */
static int check_file(const char *path)
{
    static uint8_t file[1 << 20];
    FILE *f = fopen(path, "rb");
    if (!f) { printf("cannot open %s\n", path); return 1; }
    size_t n = fread(file, 1, sizeof(file), f);
    fclose(f);

    if (n < 64) { printf("%s: shorter than a signature\n", path); return 1; }

    /* bytes 0..63 are the Ed25519 signature; the body follows */
    bool ok = vend_manifest_check(file + 64, (uint32_t)(n - 64));
    printf("%s: %zu bytes, body %zu bytes -> %s%s%s\n", path, n, n - 64,
           ok ? "ACCEPTED" : "REJECTED",
           ok ? "" : " -- ", ok ? "" : vend_manifest_last_error());
    return ok ? 0 : 1;
}

int main(int argc, char **argv)
{
    blob b;

    if (argc == 2) return check_file(argv[1]);

    printf("EverParse-generated manifest validator\n");
    printf("-------------------------------------------------------------\n");

    /* ---- well-formed ------------------------------------------------ */
    build(&b, MAGIC, 1, 0);
    put_entry(&b, 0, "numpy", -1);
    put_entry(&b, 0, "typing-extensions", -1);
    put_entry(&b, 1, "left-pad", -1);
    finish(&b);
    expect("valid manifest, 3 entries", &b, true);

    build(&b, MAGIC, 1, 0);
    finish(&b);
    expect("valid manifest, zero entries", &b, true);

    /* ---- header ----------------------------------------------------- */
    build(&b, 0xDEADBEEFu, 1, 0);
    put_entry(&b, 0, "numpy", -1);
    finish(&b);
    expect("wrong magic", &b, false);

    build(&b, MAGIC, 2, 0);
    put_entry(&b, 0, "numpy", -1);
    finish(&b);
    expect("unsupported format version", &b, false);

    build(&b, MAGIC, 1, 0x0001);
    put_entry(&b, 0, "numpy", -1);
    finish(&b);
    expect("reserved field not zero", &b, false);

    /* ---- length-field disagreements --------------------------------- */
    build(&b, MAGIC, 1, 0);
    put_entry(&b, 0, "numpy", -1);
    finish(&b);
    b.buf[11] += 8;                       /* entries_len runs past the buffer */
    expect("entries_len exceeds the buffer", &b, false);

    build(&b, MAGIC, 1, 0);
    put_entry(&b, 0, "numpy", -1);
    finish(&b);
    b.len -= 3;                           /* truncate mid-name */
    expect("buffer truncated mid-entry", &b, false);

    build(&b, MAGIC, 1, 0);
    put_entry(&b, 0, "numpy", -1);
    finish(&b);
    b.len += 4;                           /* trailing bytes beyond entries_len */
    expect("trailing bytes after entry list", &b, false);

    build(&b, MAGIC, 1, 0);
    put_entry(&b, 0, "numpy", -1);
    finish(&b);
    b.buf[11] -= 1;                       /* entries_len splits the last entry */
    expect("entries_len splits the final entry", &b, false);

    /* ---- per-entry constraints -------------------------------------- */
    build(&b, MAGIC, 1, 0);
    put_entry(&b, 2, "numpy", -1);        /* ecosystem out of range */
    finish(&b);
    expect("unknown ecosystem tag", &b, false);

    build(&b, MAGIC, 1, 0);
    put_entry(&b, 0, "", 0);              /* name_len == 0 */
    finish(&b);
    expect("zero-length package name", &b, false);

    build(&b, MAGIC, 1, 0);
    put_entry(&b, 0, "x", 129);           /* name_len over the cap */
    finish(&b);
    expect("name_len above the 128 cap", &b, false);

    /* A name_len that claims more than remains: classic buffer overread. */
    build(&b, MAGIC, 1, 0);
    put_entry(&b, 0, "numpy", 120);
    finish(&b);
    expect("name_len overruns the entry list", &b, false);

    /* ---- truncation at every prefix length -------------------------- */
    build(&b, MAGIC, 1, 0);
    put_entry(&b, 0, "numpy", -1);
    put_entry(&b, 1, "left-pad", -1);
    finish(&b);
    uint32_t full = b.len;
    int bad_prefix = 0;
    for (uint32_t n = 0; n < full; n++) {
        if (vend_manifest_check(b.buf, n)) bad_prefix++;
    }
    if (bad_prefix) {
        printf("  FAIL  %-46s %d proper prefixes accepted\n",
               "every truncation rejected", bad_prefix);
        failures++;
    } else {
        printf("  ok    %-46s %u prefixes, all rejected\n",
               "every truncation rejected", full);
    }

    printf("\n%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures ? 1 : 0;
}
