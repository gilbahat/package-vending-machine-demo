(**
  Vend.Url.Spec -- the security predicate for upstream URLs.

  This module is pure specification. It contains no implementation and is meant
  to be read by a reviewer who does not know F*. Everything the vending machine
  claims about the URLs it will dial is defined here; `Vend.Url` then proves its
  implementation satisfies it.

  The threat being modelled is the one exploited in the July 2026 Artifactory
  zero-days (CVE-2026-65923 / -65924 / -65925): a package proxy is induced to
  issue a request to an attacker-chosen destination, giving a network-isolated
  sandbox a path to the open internet.

  Copyright (c) 2026. SPDX-License-Identifier: ISC
*)
module Vend.Url.Spec

module Seq  = FStar.Seq
module U8   = FStar.UInt8
module List = FStar.List.Tot
module Char = FStar.Char
module Str  = FStar.String

type byte  = U8.t
type bytes = Seq.seq byte

(* ------------------------------------------------------------------ *)
(* Byte literals                                                       *)
(* ------------------------------------------------------------------ *)

let slash : byte = 0x2Fuy   (* '/' *)
let dot   : byte = 0x2Euy   (* '.' *)

(** The only bytes permitted anywhere after the constant prefix.

    Deliberately far narrower than RFC 3986. Excluding everything else is what
    makes the downstream properties hold, and each exclusion kills a known
    class of proxy attack:

      ':'          scheme switch      (file://, gopher://, dict://)
      '@'          authority confusion (https://good.example@evil.example/)
      '\'          host confusion in lenient URL parsers
      '?' '#'      query / fragment smuggling
      '%'          percent-encoding differentials between our parser and libc's
      CR LF        HTTP request splitting
      NUL          C string truncation
      0x80-0xFF    non-ASCII, hence IDN / punycode homographs
      ' '          request-line splitting

    What remains is exactly the unreserved set of RFC 3986 plus '/'. *)
let is_path_byte (b:byte) : bool =
  let x = U8.v b in
     (x >= 0x41 && x <= 0x5A)   (* A-Z *)
  || (x >= 0x61 && x <= 0x7A)   (* a-z *)
  || (x >= 0x30 && x <= 0x39)   (* 0-9 *)
  || x = 0x2D                   (* '-' *)
  || x = 0x2E                   (* '.' *)
  || x = 0x5F                   (* '_' *)
  || x = 0x7E                   (* '~' *)
  || x = 0x2F                   (* '/' *)

(** Package names may not contain '/': a name is substituted into a URL path,
    so allowing '/' would let a name introduce path segments of its own. *)
let is_name_byte (b:byte) : bool =
  is_path_byte b && not (b = slash)

(* ------------------------------------------------------------------ *)
(* Upstream identities -- compile-time constants, never input-derived  *)
(* ------------------------------------------------------------------ *)

(** The three upstreams this machine will ever dial. A URL is admissible only
    if it *begins with* one of these literals; merely containing an allowed
    hostname somewhere is not enough. *)
type upstream =
  | PypiIndex     (* https://pypi.org/simple/            package version lists *)
  | PypiFiles     (* https://files.pythonhosted.org/     wheels and sdists     *)
  | NpmRegistry   (* https://registry.npmjs.org/         packuments + tarballs *)

(* F* string literals are sequences of Unicode code points. Restricting the
   prefixes to ASCII makes each code point exactly one byte, so the bytes
   compared at run time are the characters written below. *)
let is_ascii_char (c:Char.char) : bool = Char.int_of_char c < 128

let ascii_string = s:string{List.for_all is_ascii_char (Str.list_of_string s)}

(* On an ASCII character the `% 256` is the identity; it is there only so this
   is total on every character. *)
let byte_of_char (c:Char.char) : byte = U8.uint_to_t (Char.int_of_char c % 256)

(** The literal each upstream's URLs must begin with.

    These three strings are the entire outbound reach of the vending machine.
    Note that each ends in '/', which is what lets the boundary condition in
    `safe_url` be stated on the suffix alone. *)
(* `ascii_string` is a refinement -- List.for_all is_ascii_char over the
   string's code points -- which F* discharges by normalisation rather than by
   SMT, hence the assert_norm on each literal. *)
unfold
let prefix_string (u:upstream) : ascii_string =
  match u with
  | PypiIndex ->
      assert_norm (List.for_all is_ascii_char (Str.list_of_string "https://pypi.org/simple/"));
      "https://pypi.org/simple/"
  | PypiFiles ->
      assert_norm (List.for_all is_ascii_char (Str.list_of_string "https://files.pythonhosted.org/"));
      "https://files.pythonhosted.org/"
  | NpmRegistry ->
      assert_norm (List.for_all is_ascii_char (Str.list_of_string "https://registry.npmjs.org/"));
      "https://registry.npmjs.org/"

(** The prefix as a list of bytes, which is the form the implementation bakes
    into the program image. *)
let prefix_list (u:upstream) : list byte =
  List.map byte_of_char (Str.list_of_string (prefix_string u))

let prefix_seq (u:upstream) : bytes = Seq.seq_of_list (prefix_list u)

(* Defined as the length rather than asserted to equal a literal. The concrete
   values are 24, 31 and 27, but stating them here would only create an
   obligation to prove something already true by definition -- and one that has
   to be re-proved every time a prefix changes. *)
let prefix_len (u:upstream) : nat = Seq.length (prefix_seq u)

(** Bound on any URL we will construct or accept. Chosen so the whole thing
    fits a fixed stack buffer; no allocation occurs anywhere in this path. *)
let max_url_len : nat = 512

(* ------------------------------------------------------------------ *)
(* The predicate                                                       *)
(* ------------------------------------------------------------------ *)

(** A '/' may not be followed by '/' or '.'.

    One clause, three attacks. It forbids empty segments ("//", which some URL
    parsers read as the start of a new authority), "." segments, and ".."
    segments -- so no path traversal can escape the constant prefix, and the
    prefix therefore pins the origin for the whole URL. *)
let bad_pair (s:bytes) (i:nat) : bool =
  i + 1 < Seq.length s
  && Seq.index s i = slash
  && (Seq.index s (i + 1) = slash || Seq.index s (i + 1) = dot)

(** Every byte from [i] on is permitted, and starts no bad pair. *)
let rec tail_ok (s:bytes) (i:nat) : Tot bool (decreases (Seq.length s - i)) =
  if i >= Seq.length s then true
  else is_path_byte (Seq.index s i) && not (bad_pair s i) && tail_ok s (i + 1)

(** THE SECURITY PREDICATE.

    `safe_url u s` holds when `s` is a URL the vending machine may dial for
    upstream `u`. Read the clauses in order:

      1. bounded            -- fits the fixed buffer, no overflow
      2. non-empty suffix   -- something follows the prefix
      3. constant origin    -- s begins with u's literal, byte for byte
      4. no leading '/'/'.' -- the first suffix byte cannot start a bad pair
                               across the prefix boundary
      5. tail_ok            -- restricted byte set, and no bad pair anywhere

    Together these give: the scheme, host and port of `s` are fixed at compile
    time and cannot be influenced by any input, and no request smuggling,
    traversal or encoding trick can alter them. *)
let safe_url (u:upstream) (s:bytes) : prop =
  let n = prefix_len u in
  if Seq.length s <= max_url_len && Seq.length s > n
  then
    Seq.equal (Seq.slice s 0 n) (prefix_seq u) /\
    Seq.index s n <> slash /\
    Seq.index s n <> dot /\
    tail_ok s n == true
  else False

(* ------------------------------------------------------------------ *)
(* Consequences -- the properties a reviewer actually cares about      *)
(*                                                                     *)
(* These are corollaries of `safe_url`, proved in Vend.Url.Properties, *)
(* and exist so that a reader need not take the predicate on trust.    *)
(* ------------------------------------------------------------------ *)

(** No byte of a safe URL is one of the dangerous ASCII characters. *)
let excluded (b:byte) : bool =
  let x = U8.v b in
  x = 0x3A (* : *) || x = 0x40 (* @ *) || x = 0x5C (* \ *) ||
  x = 0x3F (* ? *) || x = 0x23 (* # *) || x = 0x25 (* % *) ||
  x = 0x0D (* CR *) || x = 0x0A (* LF *) || x = 0x00 (* NUL *) ||
  x = 0x20 (* SP *) || x >= 0x80 (* non-ASCII *)
