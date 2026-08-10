#!/usr/bin/env bash
#
# replay.sh -- fire the breach's exploit classes at a RUNNING vending machine.
#
#   usage: attack/replay.sh [base-url]      (default http://10.0.0.2:8080)
#
# This exercises the HTTP surface. Note what a client can actually supply here:
# an ecosystem, a package name, and an artifact id. It cannot supply a URL at
# all -- that is the design. The SSRF cases that matter most are therefore
# tested directly against the verified validator in test/test_url.c, where a
# hostile *upstream response* can be simulated; `make test` runs those and
# needs no unikernel.
#
# What this script demonstrates is that the HTTP layer does not hand the
# validator anything it was not designed to see, and that non-allowlisted
# packages are refused outright.
#
# Copyright (c) 2026. SPDX-License-Identifier: ISC

set -uo pipefail

BASE="${1:-http://10.0.0.2:8080}"
pass=0
fail=0

# Issue a raw request path (no curl URL normalisation) and report the status.
raw_get() {
  local path="$1"
  curl -s -o /dev/null -w '%{http_code}' --path-as-is --max-time 10 "${BASE}${path}" 2>/dev/null
}

expect_status() {
  local what="$1" path="$2" want="$3"
  local got
  got="$(raw_get "$path")"
  if [ "$got" = "$want" ]; then
    printf '  ok    %-52s %s\n' "$what" "$got"
    pass=$((pass + 1))
  else
    printf '  FAIL  %-52s expected %s, got %s\n' "$what" "$want" "$got"
    fail=$((fail + 1))
  fi
}

echo "replaying exploit classes against ${BASE}"
echo "-------------------------------------------------------------------"

# --- the machine works at all ---------------------------------------
expect_status "status endpoint"                  "/v1/status"        200
expect_status "allowlist endpoint"               "/v1/allowlist"     200
expect_status "resolve an allowlisted package"   "/v1/pypi/numpy"    200

# --- allowlist enforcement -------------------------------------------
expect_status "package not on the allowlist"     "/v1/pypi/not-a-real-package-xyz" 400
expect_status "npm package not on the allowlist" "/v1/npm/not-a-real-package-xyz"  400

# --- path traversal in the package name ------------------------------
expect_status "raw ../ in the name"              "/v1/pypi/../../etc/passwd"   404
expect_status "percent-encoded traversal"        "/v1/pypi/%2e%2e%2fetc"       400
expect_status "double-encoded traversal"         "/v1/pypi/%252e%252e%252f"    400

# --- SSRF attempts through the name ----------------------------------
expect_status "absolute URL as a package name"   "/v1/pypi/https://evil.example/x" 404
expect_status "userinfo trick in the name"       "/v1/pypi/x@evil.example"     400
expect_status "cloud metadata host as a name"    "/v1/pypi/169.254.169.254"    400
expect_status "scheme switch as a name"          "/v1/pypi/file:///etc/passwd" 404

# --- artifact ids ------------------------------------------------------
expect_status "unknown artifact id"              "/v1/a/deadbeef"              400
expect_status "traversal in an artifact id"      "/v1/a/../../v1/status"       404
expect_status "empty artifact id"                "/v1/a/"                      404

# --- routing -----------------------------------------------------------
expect_status "unknown route"                    "/admin"                      404
expect_status "root"                             "/"                           404

# --- methods -----------------------------------------------------------
for m in POST PUT DELETE PATCH; do
  got="$(curl -s -o /dev/null -w '%{http_code}' -X "$m" --max-time 10 "${BASE}/v1/status" 2>/dev/null)"
  if [ "$got" = "405" ]; then
    printf '  ok    %-52s %s\n' "$m is refused (this machine is read-only)" "$got"
    pass=$((pass + 1))
  else
    printf '  FAIL  %-52s expected 405, got %s\n' "$m is refused" "$got"
    fail=$((fail + 1))
  fi
done

echo
echo "-------------------------------------------------------------------"
echo "The counter below should be non-zero only if an upstream offered a URL"
echo "the verified validator refused:"
curl -s --max-time 10 "${BASE}/v1/status" 2>/dev/null || echo "  (unreachable)"
echo

if [ "$fail" -eq 0 ]; then
  echo "PASSED: $pass checks"
else
  echo "FAILED: $fail of $((pass + fail)) checks"
fi
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
