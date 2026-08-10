# Package vending machine -- build, verify, test.
#
#   make test       C tests: verified URL validator + manifest parser
#   make verify     re-check the F* proofs and regenerate generated/, then
#                   require that the result matches what is committed
#   make manifest   build and sign the allowlist
#   make unikernel  cross-build vend.hvt in Docker (Solo5 needs Linux)
#   make run        run it (requires /dev/kvm; see README)
#
# Copyright (c) 2026. SPDX-License-Identifier: ISC

TOOLCHAIN  := .toolchain/everparse
FSTAR      := $(TOOLCHAIN)/bin/fstar.exe
KRML       := $(TOOLCHAIN)/bin/krml
THREED     := $(TOOLCHAIN)/bin/3d.exe
ULIB       := $(TOOLCHAIN)/lib/fstar/ulib
KRMLLIB    := $(TOOLCHAIN)/krmllib

BUILD      := build
CC         ?= cc
CFLAGS     := -std=c11 -Wall -Wextra -Wno-unused-parameter -Wno-parentheses -O2
INCLUDES   := -Igenerated -Iverified

FSTAR_OPTS := --include $(ULIB) --include $(KRMLLIB) --include proofs

PROOFS     := proofs/Vend.Url.Spec.fst proofs/Vend.Url.Properties.fst proofs/Vend.Url.fst

VERIFIED_C := generated/Vend_Url.c generated/VendManifest.c verified/vend_shim.c

.PHONY: all test test-url test-manifest verify proofs regen manifest \
        unikernel run toolchain clean distclean

all: test

# ---------------------------------------------------------------------------
# Tests -- these need no toolchain, only a C compiler, because generated/ is
# committed.
# ---------------------------------------------------------------------------

test: test-url test-manifest

$(BUILD):
	@mkdir -p $(BUILD)

test-url: | $(BUILD)
	@$(CC) $(CFLAGS) $(INCLUDES) -o $(BUILD)/test_url \
	    test/test_url.c generated/Vend_Url.c
	@$(BUILD)/test_url

test-manifest: | $(BUILD)
	@$(CC) $(CFLAGS) $(INCLUDES) -o $(BUILD)/test_manifest \
	    test/test_manifest.c verified/vend_shim.c generated/VendManifest.c
	@$(BUILD)/test_manifest

# ---------------------------------------------------------------------------
# Verification -- needs the EverParse toolchain.
# ---------------------------------------------------------------------------

toolchain:
	@bash scripts/fetch-toolchain.sh

$(FSTAR):
	@echo "EverParse toolchain missing; run 'make toolchain'" >&2
	@exit 1

# Re-check every proof. A failed proof fails the build.
proofs: $(FSTAR)
	@echo "==> checking F* proofs"
	@for f in $(PROOFS); do \
	   echo "    $$f"; \
	   $(FSTAR) $(FSTAR_OPTS) $$f || exit 1; \
	 done

# Regenerate C from the specs into a scratch directory.
regen: $(FSTAR)
	@echo "==> regenerating C from proofs/ and spec/"
	@rm -rf $(BUILD)/regen $(BUILD)/krml && mkdir -p $(BUILD)/regen $(BUILD)/krml
	@$(FSTAR) $(FSTAR_OPTS) --odir $(BUILD)/krml --codegen krml \
	    --extract 'Vend.Url +Vend.Url.Spec' proofs/Vend.Url.fst
	@$(KRML) -silent -skip-compilation -skip-makefiles -minimal \
	    -add-early-include '"vend_krml_compat.h"' \
	    -bundle 'Vend.Url=Vend.*' -tmpdir $(BUILD)/regen \
	    $(BUILD)/krml/out.krml
	@$(THREED) --batch --odir $(BUILD)/regen --fstar $(FSTAR) \
	    spec/VendManifest.3d
	@rm -f $(BUILD)/regen/Prims.h
	@echo "==> checking generated C carries no absolute paths"
	@if grep -l "$(HOME)" $(BUILD)/regen/*.c $(BUILD)/regen/*.h 2>/dev/null; then \
	   echo "    generated C embeds an absolute path; regenerate from the repo root" >&2; \
	   exit 1; \
	 fi

# The point of committing generated/: prove that what ships is what the specs
# produce. Any drift is a build failure.
verify: proofs regen
	@echo "==> diffing regenerated C against committed generated/"
	@fail=0; \
	 for f in Vend_Url.c Vend_Url.h VendManifest.c VendManifest.h \
	          VendManifestWrapper.c VendManifestWrapper.h \
	          EverParse.h EverParseEndianness.h; do \
	   if ! diff -q $(BUILD)/regen/$$f generated/$$f >/dev/null 2>&1; then \
	     echo "    DRIFT: generated/$$f does not match the spec"; \
	     fail=1; \
	   fi; \
	 done; \
	 if [ $$fail -ne 0 ]; then \
	   echo "generated/ is stale -- run 'make accept-regen'" >&2; exit 1; \
	 fi
	@echo "    generated/ matches the specs"
	@$(MAKE) --no-print-directory test

accept-regen: regen
	@cp $(BUILD)/regen/Vend_Url.c $(BUILD)/regen/Vend_Url.h \
	    $(BUILD)/regen/VendManifest.c $(BUILD)/regen/VendManifest.h \
	    $(BUILD)/regen/VendManifestWrapper.c $(BUILD)/regen/VendManifestWrapper.h \
	    $(BUILD)/regen/EverParse.h $(BUILD)/regen/EverParseEndianness.h \
	    generated/
	@echo "generated/ updated from the specs"

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

keys/manifest.key:
	@python3 scripts/build_manifest.py keygen --outdir keys

manifest: keys/manifest.key
	@python3 scripts/build_manifest.py build \
	    --packages spec/packages.txt --key keys/manifest.key --out manifest.bin
	@python3 scripts/build_manifest.py verify manifest.bin \
	    --pubkey keys/manifest.pub | head -1

# ---------------------------------------------------------------------------
# Unikernel -- Solo5 requires Linux, so this always runs in Docker.
# ---------------------------------------------------------------------------

unikernel:
	@docker build -f docker/Dockerfile.build -t pvm-build:latest .
	@docker run --rm -v "$(CURDIR)":/src -w /src pvm-build:latest \
	    bash scripts/build-unikernel.sh

run:
	@bash scripts/run-hvt.sh

clean:
	rm -rf $(BUILD)

distclean: clean
	rm -rf .toolchain unikernel/_build unikernel/dist manifest.bin keys
