(**
  Vend.Url -- the verified implementation, extracted to C by KaRaMeL.

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

  Everything below is memory-safe by Low* typechecking, allocation-free, and
  performs no I/O. The prefixes are stack-materialised from compile-time lists,
  so the extracted C has no globals and no initialiser to call -- which is what
  makes it safe to link into a freestanding unikernel.

  Copyright (c) 2026. SPDX-License-Identifier: ISC
*)
module Vend.Url

open FStar.HyperStack.ST
open Vend.Url.Spec

module B   = LowStar.Buffer
module MB  = LowStar.Monotonic.Buffer
module IB  = LowStar.ImmutableBuffer
module Lit = LowStar.Literal
module HS  = FStar.HyperStack
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
     (b >=^ 0x41uy && b <=^ 0x5Auy)   (* A-Z *)
  || (b >=^ 0x61uy && b <=^ 0x7Auy)   (* a-z *)
  || (b >=^ 0x30uy && b <=^ 0x39uy)   (* 0-9 *)
  || b =^ 0x2Duy                      (* '-' *)
  || b =^ 0x2Euy                      (* '.' *)
  || b =^ 0x5Fuy                      (* '_' *)
  || b =^ 0x7Euy                      (* '~' *)
  || b =^ 0x2Fuy                      (* '/' *)

inline_for_extraction
let is_name_byte_impl (b:U8.t) : Tot (r:bool{r == is_name_byte b}) =
  is_path_byte_impl b && not (b = slash)

(* ------------------------------------------------------------------ *)
(* The scan: restricted byte set, and no '/' followed by '/' or '.'    *)
(* ------------------------------------------------------------------ *)

(** Mirrors `Vend.Url.Spec.tail_ok` exactly, one index at a time. Tail
    recursive; KaRaMeL emits a loop. *)
let rec scan (b:B.buffer U8.t) (len:U32.t) (i:U32.t)
  : Stack bool
      (requires fun h ->
         B.live h b /\ U32.v len <= B.length b /\ U32.v i <= U32.v len)
      (ensures fun h0 r h1 ->
         h0 == h1 /\
         (r <==> tail_ok (Seq.slice (B.as_seq h0 b) 0 (U32.v len)) (U32.v i) == true))
      (decreases (U32.v len - U32.v i))
  = let h0 = get () in
    if U32.(i >=^ len) then true
    else begin
      let x = B.index b i in
      assert (Seq.index (Seq.slice (B.as_seq h0 b) 0 (U32.v len)) (U32.v i) == x);
      if not (is_path_byte_impl x) then false
      else begin
        let bad =
          if U32.(i +^ 1ul <^ len) then begin
            let y = B.index b U32.(i +^ 1ul) in
            assert (Seq.index (Seq.slice (B.as_seq h0 b) 0 (U32.v len)) (U32.v i + 1) == y);
            x = slash && (y = slash || y = dot)
          end else false
        in
        if bad then false else scan b len U32.(i +^ 1ul)
      end
    end

(* ------------------------------------------------------------------ *)
(* Prefix comparison against a compile-time constant                    *)
(* ------------------------------------------------------------------ *)

(** Compare `b[i..n)` against `p[i..n)`, where `p` holds an upstream prefix. *)
let rec prefix_cmp
      (b:B.buffer U8.t) (p:IB.ibuffer U8.t) (plen:U32.t) (i:U32.t)
  : Stack bool
      (requires fun h ->
         B.live h b /\ B.live h p /\
         U32.v plen <= B.length b /\ U32.v plen <= MB.length p /\
         U32.v i <= U32.v plen)
      (ensures fun h0 r h1 ->
         h0 == h1 /\
         (r <==> (forall (j:nat). (U32.v i <= j /\ j < U32.v plen) ==>
                    Seq.index (B.as_seq h0 b) j == Seq.index (MB.as_seq h0 p) j)))
      (decreases (U32.v plen - U32.v i))
  = if U32.(i >=^ plen) then true
    else begin
      let x = B.index b i in
      let y = MB.index p i in
      if x = y then prefix_cmp b p plen U32.(i +^ 1ul) else false
    end

(* ------------------------------------------------------------------ *)
(* The validator                                                        *)
(* ------------------------------------------------------------------ *)

(** Core validator, parameterised by an already-materialised prefix buffer. *)
inline_for_extraction
let validate_with
      (u:upstream) (p:IB.ibuffer U8.t) (plen:U32.t) (b:B.buffer U8.t) (len:U32.t)
  : Stack bool
      (requires fun h ->
         B.live h b /\ B.live h p /\
         U32.v len <= B.length b /\
         U32.v plen == prefix_len u /\
         MB.length p == prefix_len u /\
         Seq.equal (MB.as_seq h p) (prefix_seq u))
      (ensures fun h0 r h1 ->
         h0 == h1 /\
         (r ==> safe_url u (Seq.slice (B.as_seq h0 b) 0 (U32.v len))))
  = let h0 = get () in
    if U32.(len >^ 512ul) then false
    else if U32.(len <=^ plen) then false
    else if not (prefix_cmp b p plen 0ul) then false
    else begin
      let first = B.index b plen in
      if first = slash || first = dot then false
      else begin
        (* prefix_cmp gives pointwise equality; lift it to Seq.equal *)
        Seq.lemma_eq_intro
          (Seq.slice (Seq.slice (B.as_seq h0 b) 0 (U32.v len)) 0 (U32.v plen))
          (prefix_seq u);
        scan b len plen
      end
    end

(** Upstream tags as they cross the C boundary. Kept as a separate small type
    so the C API takes an enum rather than a raw integer. *)
type upstream_tag = | TagPypiIndex | TagPypiFiles | TagNpmRegistry

(* Spec-only: appears in the postcondition below and nowhere at runtime.
   Marked `noextract` so the generated C contains no unreachable-match
   handler, and therefore no dependency on stdio/stdlib. *)
noextract
let of_tag (t:upstream_tag) : upstream =
  match t with
  | TagPypiIndex   -> PypiIndex
  | TagPypiFiles   -> PypiFiles
  | TagNpmRegistry -> NpmRegistry

(** VALIDATE A URL THAT ARRIVED AS UPSTREAM DATA.

    This is the SSRF gate. `b[0..len)` is an untrusted candidate URL extracted
    from a PyPI simple-index page or an npm packument. Returning true means the
    bytes satisfy `safe_url`, hence address the compile-time-constant origin
    and nothing else. *)
let validate_artifact_url (t:upstream_tag) (b:B.buffer U8.t) (len:U32.t)
  : Stack bool
      (requires fun h -> B.live h b /\ U32.v len <= B.length b)
      (ensures fun h0 r h1 ->
         B.modifies B.loc_none h0 h1 /\
         (r ==> safe_url (of_tag t) (Seq.slice (B.as_seq h0 b) 0 (U32.v len))))
  = push_frame ();
    let r =
      match t with
      (* `buf_len_of_literal` extracts to a plain C string literal, so the
         constants appear verbatim in the generated C and there is no global
         to initialise. *)
      | TagPypiIndex ->
          let p, plen = Lit.buf_len_of_literal (prefix_string PypiIndex) in
          validate_with PypiIndex p plen b len
      | TagPypiFiles ->
          let p, plen = Lit.buf_len_of_literal (prefix_string PypiFiles) in
          validate_with PypiFiles p plen b len
      | TagNpmRegistry ->
          let p, plen = Lit.buf_len_of_literal (prefix_string NpmRegistry) in
          validate_with NpmRegistry p plen b len
    in
    pop_frame ();
    r
