(**
  Vend.Url -- the verified implementation, in Pulse, extracted to C by Custard.

  ONE entry point: `validate_artifact_url`.

  Every URL the unikernel dials -- index URLs it builds itself from a client's
  package name, and artifact URLs lifted out of an upstream response body --
  passes through this single function first. Nothing else decides safety.

  That is a deliberate design choice. URL *construction* is left to ordinary
  unverified OCaml, because construction does not need to be trusted when the
  gate is: an incorrectly built URL is simply rejected. Concentrating the whole
  security argument in one proved function keeps the verified surface small
  enough that a reviewer can read all of it.

  The dataflow that matters is the second one. In the Artifactory SSRF CVEs
  (CVE-2026-65923 / -65924 / -65925), a URL lifted out of a response body
  became a request destination. Here such a URL is bytes in a buffer that this
  function must accept before anything dials it.

  The function holds only a fractional, read-only permission on the input, so
  it cannot write to it; it is allocation-free and performs no I/O. It is also
  exact: it accepts precisely the URLs satisfying `safe_url`, so nothing the
  spec admits is rejected either. The prefixes are `static const` tables, so
  the extracted C has no initialiser to call and the constants that decide
  the origin sit in read-only memory -- which is what makes it safe to link
  into a freestanding unikernel.

  Copyright (c) 2026. SPDX-License-Identifier: ISC
*)
module Vend.Url
#lang-pulse

open Pulse.Lib.Pervasives
open Vend.Url.Spec

module A   = Pulse.Lib.Array
module GA  = Pulse.Lib.GlobalArray
module SZ  = FStar.SizeT
module U8  = FStar.UInt8
module U32 = FStar.UInt32
module Seq = FStar.Seq

#set-options "--fuel 1 --ifuel 1 --z3rlimit 60"

(* ------------------------------------------------------------------ *)
(* Byte classification -- must agree with the spec definitionally.     *)
(* ------------------------------------------------------------------ *)

inline_for_extraction
let is_path_byte_impl (b:U8.t) : Tot (r:bool{r == is_path_byte b}) =
  let open FStar.UInt8 in
     (b >= 0x41uy && b <= 0x5Auy)   (* A-Z *)
  || (b >= 0x61uy && b <= 0x7Auy)   (* a-z *)
  || (b >= 0x30uy && b <= 0x39uy)   (* 0-9 *)
  || b = 0x2Duy                     (* '-' *)
  || b = 0x2Euy                     (* '.' *)
  || b = 0x5Fuy                     (* '_' *)
  || b = 0x7Euy                     (* '~' *)
  || b = 0x2Fuy                     (* '/' *)

inline_for_extraction
let is_name_byte_impl (b:U8.t) : Tot (r:bool{r == is_name_byte b}) =
  is_path_byte_impl b && not (b = slash)

(* ------------------------------------------------------------------ *)
(* The scan: restricted byte set, and no '/' followed by '/' or '.'    *)
(* ------------------------------------------------------------------ *)

(** Decides `Vend.Url.Spec.tail_ok` from [start]. The loop stops at the first
    position that fails, or at [len]; the invariant is that every position it
    has stepped over passed, so `tail_ok` from [start] is `tail_ok` from [i]. *)
fn scan (b:A.array U8.t) (len:SZ.t) (start:SZ.t{SZ.v start <= SZ.v len})
        (#p:perm) (#s:erased bytes{SZ.v len <= Seq.length s})
  preserves A.pts_to b #p s
  returns r:bool
  ensures pure (r <==> tail_ok (Seq.slice s 0 (SZ.v len)) (SZ.v start) == true)
{
  A.pts_to_len b;
  let mut i = start;
  while (
    let vi = !i;
    if SZ.(vi < len) {
      let x = b.(vi);
      if not (is_path_byte_impl x) { false }
      else if SZ.(vi + 1sz < len) {
        let y = b.(SZ.(vi + 1sz));
        not (x = slash && (y = slash || y = dot))
      } else { true }
    } else { false })
  invariant live i
  invariant pure (
    SZ.v start <= SZ.v !i /\ SZ.v !i <= SZ.v len /\
    tail_ok (Seq.slice s 0 (SZ.v len)) (SZ.v start) ==
    tail_ok (Seq.slice s 0 (SZ.v len)) (SZ.v !i))
  decreases (SZ.v len - SZ.v !i)
  {
    i := SZ.(!i + 1sz);
  };
  SZ.(!i = len)
}

(* ------------------------------------------------------------------ *)
(* Prefix comparison against a compile-time constant                    *)
(* ------------------------------------------------------------------ *)

(** Compare `b[0..plen)` against `pa[0..plen)`, where `pa` holds an upstream
    prefix. *)
fn prefix_cmp (b:A.array U8.t) (pa:A.array U8.t) (plen:SZ.t)
              (#p #q:perm) (#s:erased bytes{SZ.v plen <= Seq.length s})
              (#ps:erased bytes{SZ.v plen <= Seq.length ps})
  preserves A.pts_to b #p s ** A.pts_to pa #q ps
  returns r:bool
  ensures pure (r <==> (forall (j:nat). j < SZ.v plen ==> Seq.index s j == Seq.index ps j))
{
  A.pts_to_len b;
  A.pts_to_len pa;
  let mut i = 0sz;
  while (
    let vi = !i;
    if SZ.(vi < plen) { (b.(vi) = pa.(vi)) } else { false })
  invariant live i
  invariant pure (
    SZ.v !i <= SZ.v plen /\
    (forall (j:nat). j < SZ.v !i ==> Seq.index s j == Seq.index ps j))
  decreases (SZ.v plen - SZ.v !i)
  {
    i := SZ.(!i + 1sz);
  };
  SZ.(!i = plen)
}

(* ------------------------------------------------------------------ *)
(* The prefixes, as read-only tables in the program image              *)
(* ------------------------------------------------------------------ *)

(* `normalize_term` reduces each spec prefix to a literal byte list, which
   Custard emits as a `static const uint8_t[]` initialiser; the constants
   therefore appear verbatim in the generated C. `normalize_term_spec` tells
   the proof that the reduced list is the spec's. *)
let pypi_index_prefix
  : a:GA.static_array U8.t{GA.static_array_elems a == prefix_seq PypiIndex}
  = normalize_term_spec (prefix_list PypiIndex);
    GA.mk_static_array (normalize_term (prefix_list PypiIndex))

let pypi_files_prefix
  : a:GA.static_array U8.t{GA.static_array_elems a == prefix_seq PypiFiles}
  = normalize_term_spec (prefix_list PypiFiles);
    GA.mk_static_array (normalize_term (prefix_list PypiFiles))

let npm_registry_prefix
  : a:GA.static_array U8.t{GA.static_array_elems a == prefix_seq NpmRegistry}
  = normalize_term_spec (prefix_list NpmRegistry);
    GA.mk_static_array (normalize_term (prefix_list NpmRegistry))

(* The lengths as C constants. The spec defines `prefix_len` rather than
   stating these, so each is checked against it here by normalisation. *)
inline_for_extraction
let prefix_len_sz (u:upstream) : n:SZ.t{SZ.v n == prefix_len u} =
  match u with
  | PypiIndex   -> assert_norm (List.Tot.length (prefix_list PypiIndex) == 24); 24sz
  | PypiFiles   -> assert_norm (List.Tot.length (prefix_list PypiFiles) == 31); 31sz
  | NpmRegistry -> assert_norm (List.Tot.length (prefix_list NpmRegistry) == 27); 27sz

(* ------------------------------------------------------------------ *)
(* The validator                                                        *)
(* ------------------------------------------------------------------ *)

(** Core validator, parameterised by an already-materialised prefix array.
    The length check comes first, and is also what proves `len` fits a
    `size_t`. *)
fn validate_with (u:erased upstream) (pa:A.array U8.t) (plen:SZ.t{SZ.v plen == prefix_len u})
                 (b:A.array U8.t) (len:U32.t)
                 (#p #q:perm) (#s:erased bytes{U32.v len <= Seq.length s})
  preserves A.pts_to b #p s ** A.pts_to pa #q (prefix_seq u)
  returns r:bool
  ensures pure (r <==> safe_url u (Seq.slice s 0 (U32.v len)))
{
  if U32.(len > 512ul) { false }
  else {
    SZ.fits_at_least_16 (U32.v len);
    let n = SZ.uint32_to_sizet len;
    if SZ.(n <= plen) { false }
    else if not (prefix_cmp b pa plen) {
      assert pure (~(Seq.equal (Seq.slice (Seq.slice s 0 (U32.v len)) 0 (SZ.v plen))
                               (prefix_seq u)));
      false
    }
    else {
      (* prefix_cmp gives pointwise equality; lift it to Seq.equal *)
      Seq.lemma_eq_intro
        (Seq.slice (Seq.slice s 0 (U32.v len)) 0 (SZ.v plen))
        (prefix_seq u);
      A.pts_to_len b;
      let first = b.(plen);
      if (first = slash || first = dot) { false }
      else { scan b n plen }
    }
  }
}

(** Upstream tags as they cross the C boundary. Kept as a separate small type
    so the C API takes an enum rather than a raw integer. *)
type upstream_tag = | TagPypiIndex | TagPypiFiles | TagNpmRegistry

(* Spec-only: appears in the postcondition below and nowhere at runtime. *)
noextract
let of_tag (t:upstream_tag) : upstream =
  match t with
  | TagPypiIndex   -> PypiIndex
  | TagPypiFiles   -> PypiFiles
  | TagNpmRegistry -> NpmRegistry

(* A static array yields a read-only permission that is never given back:
   the table outlives every caller, so it is simply dropped. *)
inline_for_extraction
fn validate_against (u:upstream)
    (pfx:GA.static_array U8.t{GA.static_array_elems pfx == prefix_seq u})
    (b:A.array U8.t) (len:U32.t)
    (#p:perm) (#s:erased bytes{U32.v len <= Seq.length s})
  preserves A.pts_to b #p s
  returns r:bool
  ensures pure (r <==> safe_url u (Seq.slice s 0 (U32.v len)))
{
  let pa = GA.array_of_static_array pfx;
  with q. assert (A.pts_to pa #q (GA.static_array_elems pfx));
  rewrite (A.pts_to pa #q (GA.static_array_elems pfx)) as (A.pts_to pa #q (prefix_seq u));
  let r = validate_with u pa (prefix_len_sz u) b len;
  drop_ (A.pts_to pa #q (prefix_seq u));
  r
}

(** VALIDATE A URL THAT ARRIVED AS UPSTREAM DATA.

    This is the SSRF gate. `b[0..len)` is an untrusted candidate URL extracted
    from a PyPI simple-index page or an npm packument. Returning true means the
    bytes satisfy `safe_url`, hence address the compile-time-constant origin
    and nothing else; returning false means they do not.

    The C switch over the tag has no default arm: C code that forges a tag
    outside the enum gets the npm check, so it can still only obtain a URL that
    is safe for *some* upstream. The OCaml caller cannot construct such a tag. *)
fn validate_artifact_url (t:upstream_tag) (b:A.array U8.t) (len:U32.t)
    (#p:perm) (#s:erased bytes{U32.v len <= Seq.length s})
  preserves A.pts_to b #p s
  returns r:bool
  ensures pure (r <==> safe_url (of_tag t) (Seq.slice s 0 (U32.v len)))
{
  match t {
    TagPypiIndex   -> { validate_against PypiIndex   pypi_index_prefix   b len }
    TagPypiFiles   -> { validate_against PypiFiles   pypi_files_prefix   b len }
    TagNpmRegistry -> { validate_against NpmRegistry npm_registry_prefix b len }
  }
}
