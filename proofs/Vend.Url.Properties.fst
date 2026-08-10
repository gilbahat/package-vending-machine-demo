(**
  Vend.Url.Properties -- the claims in the README, machine-checked.

  `Vend.Url.Spec.safe_url` is written for ease of implementation: a prefix
  check plus two pointwise conditions. That formulation is easy to satisfy but
  it is not obviously the property a security reviewer wants. This module
  closes that gap by deriving, from `safe_url` alone, the statements the README
  actually makes.

  Nothing here is used at runtime. It exists so that the README's claims are
  theorems rather than assertions.

  Copyright (c) 2026. SPDX-License-Identifier: ISC
*)
module Vend.Url.Properties

open Vend.Url.Spec

module Seq = FStar.Seq
module U8  = FStar.UInt8

(* ------------------------------------------------------------------ *)
(* Step 1: the permitted byte set excludes every dangerous byte.       *)
(* ------------------------------------------------------------------ *)

(** No permitted byte is a dangerous one. Pure arithmetic over the two
    character-class definitions; Z3 discharges it directly. *)
let permitted_excludes_dangerous (b:byte)
  : Lemma (is_path_byte b ==> not (excluded b))
  = ()

(* ------------------------------------------------------------------ *)
(* Step 2: `tail_ok` really does constrain every position it covers.   *)
(* ------------------------------------------------------------------ *)

(** `tail_ok s i` is defined by recursion from `i`; this eliminates it at an
    arbitrary later index `j`. *)
let rec tail_ok_elim (s:bytes) (i:nat) (j:nat)
  : Lemma (requires tail_ok s i == true /\ i <= j /\ j < Seq.length s)
          (ensures  is_path_byte (Seq.index s j) /\ not (bad_pair s j))
          (decreases (j - i))
  = if i = j then ()
    else tail_ok_elim s (i + 1) j

(* ------------------------------------------------------------------ *)
(* Step 3: the properties the README claims.                           *)
(* ------------------------------------------------------------------ *)

(** CLAIM: the origin is a compile-time constant.

    Every accepted URL begins with the literal bytes of its upstream's prefix.
    Since those prefixes each end in '/', the scheme, host and port are fully
    determined before any input-derived byte appears. *)
let origin_is_constant (u:upstream) (s:bytes)
  : Lemma (requires safe_url u s)
          (ensures  Seq.length s > prefix_len u /\
                    Seq.equal (Seq.slice s 0 (prefix_len u)) (prefix_seq u))
  = ()

(** CLAIM: no dangerous byte survives anywhere after the prefix.

    This is the clause that kills scheme switching (':'), authority confusion
    ('@', '\'), query/fragment smuggling ('?', '#'), percent-encoding
    differentials ('%'), HTTP request splitting (CR, LF), C string truncation
    (NUL), and IDN/punycode homographs (bytes >= 0x80). *)
let no_dangerous_byte (u:upstream) (s:bytes) (j:nat{j < Seq.length s})
  : Lemma (requires safe_url u s /\ prefix_len u <= j)
          (ensures  not (excluded (Seq.index s j)))
  = tail_ok_elim s (prefix_len u) j;
    permitted_excludes_dangerous (Seq.index s j)

(** CLAIM: no path traversal can escape the prefix.

    A '/' is never followed by '.' or by another '/', so no ".." segment, no
    "." segment and no empty segment exists anywhere after the prefix. A
    traversal therefore cannot walk above the pinned path. *)
let no_traversal (u:upstream) (s:bytes) (j:nat{j + 1 < Seq.length s})
  : Lemma (requires safe_url u s /\ prefix_len u <= j)
          (ensures  not (Seq.index s j = slash &&
                         (Seq.index s (j + 1) = slash || Seq.index s (j + 1) = dot)))
  = tail_ok_elim s (prefix_len u) j

(** CLAIM: the boundary between prefix and suffix is not exploitable.

    The prefix ends in '/', so a suffix beginning with '/' or '.' would form a
    bad pair straddling the boundary. `safe_url` rules that out explicitly. *)
let boundary_is_safe (u:upstream) (s:bytes)
  : Lemma (requires safe_url u s)
          (ensures  Seq.index s (prefix_len u) <> slash /\
                    Seq.index s (prefix_len u) <> dot)
  = ()

(** CLAIM: accepted URLs are bounded, so the fixed output buffer suffices and
    no length arithmetic can overflow. *)
let is_bounded (u:upstream) (s:bytes)
  : Lemma (requires safe_url u s)
          (ensures  Seq.length s <= max_url_len)
  = ()

(* ------------------------------------------------------------------ *)
(* Step 4: the headline theorem, as one statement.                     *)
(* ------------------------------------------------------------------ *)

(** THE THEOREM.

    If the vending machine accepts a URL, then that URL is the constant
    upstream prefix followed only by bytes that are individually harmless and
    that jointly contain no traversal. There is no input a client can supply,
    and no bytes an upstream can return, that make an accepted URL address any
    host other than the one fixed at compile time. *)
let theorem (u:upstream) (s:bytes)
  : Lemma (requires safe_url u s)
          (ensures
            (* origin fixed at compile time *)
            Seq.equal (Seq.slice s 0 (prefix_len u)) (prefix_seq u) /\
            (* bounded *)
            Seq.length s <= max_url_len /\
            (* nothing dangerous, and no traversal, after the prefix *)
            (forall (j:nat). (prefix_len u <= j /\ j < Seq.length s) ==>
                             not (excluded (Seq.index s j))) /\
            (forall (j:nat). (prefix_len u <= j /\ j + 1 < Seq.length s) ==>
                             not (Seq.index s j = slash &&
                                  (Seq.index s (j + 1) = slash ||
                                   Seq.index s (j + 1) = dot))))
  = origin_is_constant u s;
    is_bounded u s;
    FStar.Classical.forall_intro
      (FStar.Classical.move_requires (no_dangerous_byte u s));
    FStar.Classical.forall_intro
      (FStar.Classical.move_requires (no_traversal u s))
