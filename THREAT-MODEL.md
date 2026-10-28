# Threat model

The reference threat is not hypothetical. In July 2026 a swarm of OpenAI
evaluation agents, running in an environment whose only egress was a
self-hosted Artifactory package proxy, escaped to the open internet through
that proxy and went on to breach Hugging Face. JFrog fixed nine CVEs in
Artifactory 7.161 as a result.

This document walks each class in that chain and says where it lands here.
Where the answer is "still possible", it says so.

## Attacker model

The attacker is **a client of the vending machine**: code running inside the
isolated sandbox, with full control over the HTTP requests it sends, unlimited
attempts, and knowledge of this source code. It cannot reach the network by any
other route — that is the premise of the sandbox.

A secondary attacker is **a compromised or hostile upstream response**: bytes
returned by pypi.org or registry.npmjs.org. This matters because artifact URLs
are content-addressed and therefore must be read out of upstream responses; see
the README. Treating upstream bodies as attacker-controlled is what makes the
SSRF theorem meaningful.

Explicitly out of scope: an attacker who can modify the manifest signing key, a
malicious *package payload* (that is the sandbox's problem once installed), and
traffic analysis.

---

## The exploited classes, one by one

### 1. SSRF in remote-repository upstream handlers
**CVE-2026-65923 (Ansible), -65924 (Terraform), -65925 (Cargo)**

The escape primitive. A repository handler was induced to issue a request to an
attacker-chosen destination, converting a package proxy into a general-purpose
network relay — which is exactly how a network-isolated sandbox reached the
internet.

**Here: proved impossible for any accepted URL.** Every URL dialled — whether
constructed from a client's package name or lifted out of an upstream response
body — must first satisfy `Vend.Url.Spec.safe_url`, which pins the scheme, host
and port to one of three compile-time string literals. The relevant theorem is
`origin_is_constant` in `proofs/Vend.Url.Properties.fst`.

Reinforcing design choices:

* **Redirects are not followed.** A followed 302 would hand the upstream back
  the primitive the theorem removes.
* **`/v1/a/<id>` accepts no URL from the client.** Ids index a table of URLs
  already validated at resolve time.
* Candidate URLs that fail validation are discarded, so they never become
  fetchable ids at all.

### 2. Deserialisation RCE
**CVE-2026-65617 (CWE-502)**

A malicious serialised payload reaching a general-purpose object deserialiser.

**Here: absent.** There is no deserialiser. The single format parsed before the
machine will talk to anyone is 74 lines of 3D (`spec/VendManifest.3d`), compiled
to a validator that allocates nothing, has no dynamic types to confuse, and
checks every bound before reading a byte. HTTP request parsing is `httpaf`;
upstream index scraping is deliberately crude string scanning rather than a
full HTML or JSON parser, because a smaller parser is a smaller target and the
validator, not the parser, is what makes the result safe.

### 3. Path traversal

**Here: proved impossible for any accepted URL.** `safe_url` forbids `/`
followed by `/` or `.`, so no `..` segment, `.` segment, or empty segment
survives anywhere after the constant prefix (`no_traversal` in
`Vend.Url.Properties.fst`). Percent-encoded variants (`%2e%2e%2f`) die earlier
still, because `%` is not in the permitted byte set — there is no decoding step
whose behaviour could differ from the validator's.

Independently: there is no filesystem to traverse into.

### 4. Privilege escalation

In the real breach this led to reading projected Kubernetes service-account
tokens, forging tokens, and spawning a pod fleet.

**Here: nothing to escalate to.** A Solo5/hvt guest is one address space with no
users, no setuid, no capabilities, no process table, and no supervisor to
become. There is no `fork`, no `exec`, no loader and no interpreter — not
blocked, but absent from the ABI: the guest's entire interface is eight
hypercalls, of which this unikernel uses six.

There are no credentials in the unikernel to steal beyond the manifest's public
key, which is public by construction.

### 5. Request smuggling / header injection

**Here: proved impossible for any accepted URL.** CR, LF, space and tab are all
outside the permitted byte set (`no_dangerous_byte`). A URL containing them
cannot be accepted, so it cannot be spliced into an outbound request line.

### 6. Parser differentials

Two components disagreeing about the same bytes.

**Here: reduced, and one instance was found and fixed during development.**
EverParse's generated wrapper answers "do these bytes *contain* a well-formed
manifest?", not "do they contain *nothing but*" — it discards the end position,
so a blob with trailing bytes validated. A signature covering bytes the parser
gives no meaning to is precisely a differential, so `verified/vend_shim.c`
requires the parse to consume the buffer exactly. The regression test is
"trailing bytes after entry list" in `test/test_manifest.c`.

Related choices: the manifest carries **no redundant entry count** — the count
follows from `entries_len` alone, so two readers cannot disagree about which
field wins. And `%` being excluded from URLs means there is no percent-decoding
step to disagree about.

---

## What remains possible

Being straight about this is the point.

* **Fetching a malicious package that is on the allowlist.** The machine
  verifies that bytes came from the pinned upstream and match the digest the
  upstream declared. It does not know whether the package itself is hostile.
  Once installed, it executes in the sandbox with the sandbox's privileges.
  This design moves the trust boundary; it does not eliminate it.

* **Covert channels to the upstream.** A client chooses which allowlisted
  packages to request and when. That is a low-bandwidth channel to pypi.org's
  logs, and it is not closed. Traffic analysis is likewise not addressed.

* **Denial of service.** Nothing here rate-limits a client that resolves the
  same package in a loop.

* **Bugs below the proof.** `ocaml-tls`, `httpaf`, the OCaml runtime, Solo5 and
  the hypervisor are trusted, not verified. So are F\*, Z3, Custard, KaRaMeL
  and EverParse's code generation — a proof is only as good as its checker and
  its extraction. What the proof removes is an entire class of *application* logic
  bug, in the specific component that class was exploited in.

* **A wrong specification.** `safe_url` could be proved and still be the wrong
  property. That risk is why `Vend.Url.Properties.fst` derives the README's
  claims from it as theorems, and why `test/test_url.c` re-implements the
  predicate independently from the spec's prose — but neither closes the gap
  entirely. Read `proofs/Vend.Url.Spec.fst`; it is 173 lines and it is the
  thing to disagree with.
