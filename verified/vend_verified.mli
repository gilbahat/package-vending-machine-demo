(** Verified primitives, as seen from OCaml.

    Both functions below are thin bindings to C that was generated from a
    machine-checked specification. Nothing in this module is hand-written
    logic; the only hand-written code on this path is the ~40-line
    [vend_shim.c] and the stub file next to it.

    Copyright (c) 2026. SPDX-License-Identifier: ISC *)

(** The upstreams this machine is permitted to contact. Corresponds exactly to
    [Vend.Url.Spec.upstream] in the proof; each maps to one compile-time
    constant URL prefix baked into the verified C. *)
type upstream =
  | Pypi_index    (** https://pypi.org/simple/          *)
  | Pypi_files    (** https://files.pythonhosted.org/   *)
  | Npm_registry  (** https://registry.npmjs.org/       *)

val upstream_prefix : upstream -> string
(** The constant prefix for an upstream. Provided so that OCaml can build
    candidate URLs; it carries no authority of its own, because a URL is only
    dialled if {!validate_url} accepts it. *)

val upstream_host : upstream -> string
(** Hostname only, for opening the connection. *)

val validate_url : upstream -> string -> bool
(** [validate_url u url] is the security gate.

    Returns [true] only when [url] satisfies [Vend.Url.Spec.safe_url u], which
    guarantees, among other things, that [url] begins with [u]'s compile-time
    constant prefix and contains no byte that could redirect, split or
    traverse the request. See proofs/Vend.Url.Properties.fst for the theorem.

    Every URL the unikernel dials passes through here first, whether it was
    constructed locally or lifted out of an upstream response body. The latter
    is the dataflow exploited by CVE-2026-65923/-65924/-65925. *)

val manifest_check : string -> bool
(** [manifest_check body] validates the manifest body against
    spec/VendManifest.3d using the EverParse-generated parser, and additionally
    requires that the parse consume [body] exactly.

    The caller must verify the signature over [body] first. *)

val manifest_last_error : unit -> string
(** Why the last {!manifest_check} failed, as ["Struct.field: reason"]. *)

val self_check : unit -> bool
(** Check that the OCaml-side prefix strings agree with the constants compiled
    into the verified C.

    The strings returned by {!upstream_prefix} are a second copy of literals
    that live inside the proof. Drift cannot widen what this machine can reach
    -- a wrong prefix just makes every URL fail {!validate_url} -- but it would
    fail silently, as "nothing resolves". Call this at boot and refuse to start
    if it returns [false]. *)
