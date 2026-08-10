(* See vend_verified.mli. Copyright (c) 2026. SPDX-License-Identifier: ISC *)

type upstream =
  | Pypi_index
  | Pypi_files
  | Npm_registry

(* These integers are the C enum values in generated/Vend_Url.h
   (Vend_Url_TagPypiIndex = 0, TagPypiFiles = 1, TagNpmRegistry = 2).
   The stub asserts the correspondence at compile time. *)
let tag_of_upstream = function
  | Pypi_index -> 0
  | Pypi_files -> 1
  | Npm_registry -> 2

(* These strings duplicate the literals inside the verified C. They are used
   only to BUILD candidate URLs; if one ever drifts from the proof's constant,
   the resulting URL simply fails validate_url and nothing is dialled, so the
   duplication cannot widen what this machine can reach. {!self_check} below
   turns that silent failure into a loud one at boot. *)
let upstream_prefix = function
  | Pypi_index -> "https://pypi.org/simple/"
  | Pypi_files -> "https://files.pythonhosted.org/"
  | Npm_registry -> "https://registry.npmjs.org/"

let upstream_host = function
  | Pypi_index -> "pypi.org"
  | Pypi_files -> "files.pythonhosted.org"
  | Npm_registry -> "registry.npmjs.org"

external validate_url_c : int -> string -> bool = "caml_vend_validate_url"
  [@@noalloc]

let validate_url u url = validate_url_c (tag_of_upstream u) url

external manifest_check : string -> bool = "caml_vend_manifest_check"
  [@@noalloc]

external manifest_last_error : unit -> string = "caml_vend_manifest_last_error"

let self_check () =
  List.for_all
    (fun u ->
      (* A minimal well-formed URL for this upstream must be accepted, and the
         same path under a different upstream's prefix must not be. Together
         these pin each OCaml prefix string to the constant compiled into the
         verified C. *)
      validate_url u (upstream_prefix u ^ "x")
      && (not (validate_url u (upstream_prefix u)))
      && not (validate_url u ("https://evil.example/" ^ upstream_prefix u)))
    [ Pypi_index; Pypi_files; Npm_registry ]
