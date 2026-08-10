(** Resolve.ml -- turning upstream responses into candidate artifacts.

    THIS MODULE HANDLES UNTRUSTED DATA. Everything it parses arrived over the
    network from pypi.org or registry.npmjs.org. It is ordinary, unverified
    OCaml, and that is deliberate: it does not need to be trusted, because
    every URL it produces must still pass {!Vend_verified.validate_url} before
    anything is dialled. A bug here can cause a candidate to be dropped or
    mis-labelled; it cannot cause a request to an unintended host.

    Parsing is intentionally crude. We do not implement an HTML parser -- we
    scan for href attributes. A real HTML parser would be a much larger attack
    surface for no benefit, since the validator, not the parser, is what makes
    the result safe.

    Copyright (c) 2026. SPDX-License-Identifier: ISC *)

type candidate = {
  url : string;       (** absolute upstream URL, fragment stripped *)
  filename : string;  (** last path segment, for display *)
  version : string;   (** best-effort, see {!version_of_filename} *)
  sha256 : string option;  (** as declared by the upstream index *)
}

(* ------------------------------------------------------------------ *)
(* Small string helpers                                                *)
(* ------------------------------------------------------------------ *)

let starts_with ~prefix s =
  let n = String.length prefix in
  String.length s >= n && String.sub s 0 n = prefix

let ends_with ~suffix s =
  let n = String.length suffix and m = String.length s in
  m >= n && String.sub s (m - n) n = suffix

(* Index of [sub] in [s] at or after [from], or None. *)
let find_from s sub from =
  let n = String.length s and m = String.length sub in
  if m = 0 then Some from
  else begin
    let rec go i =
      if i + m > n then None
      else if String.sub s i m = sub then Some i
      else go (i + 1)
    in
    go (max 0 from)
  end

let last_segment url =
  match String.rindex_opt url '/' with
  | None -> url
  | Some i -> String.sub url (i + 1) (String.length url - i - 1)

(* ------------------------------------------------------------------ *)
(* Versions                                                            *)
(* ------------------------------------------------------------------ *)

(** Best-effort version extraction from a distribution filename.

    Wheels are "{name}-{version}(-{build})?-{python}-{abi}-{platform}.whl" and
    sdists are "{name}-{version}.tar.gz". Both put the version immediately
    after the first '-' that follows the name. Since names themselves may
    contain '-' (or '_' after normalisation), this is a heuristic and is used
    only for display and filtering -- never for building a URL. *)
let version_of_filename filename =
  let strip_ext f =
    let exts = [ ".tar.gz"; ".tar.bz2"; ".tar.xz"; ".whl"; ".zip"; ".egg"; ".tgz" ] in
    match List.find_opt (fun e -> ends_with ~suffix:e f) exts with
    | Some e -> String.sub f 0 (String.length f - String.length e)
    | None -> f
  in
  let base = strip_ext filename in
  let parts = String.split_on_char '-' base in
  match parts with
  | [] | [ _ ] -> ""
  | _ :: rest ->
      (* The version is the first component that begins with a digit. *)
      let is_versionish s = s <> "" && s.[0] >= '0' && s.[0] <= '9' in
      (match List.find_opt is_versionish rest with
       | Some v -> v
       | None -> List.nth rest 0)

(* ------------------------------------------------------------------ *)
(* PyPI: PEP 503 simple index                                          *)
(* ------------------------------------------------------------------ *)

(* Extract the value of the first href="..." at or after [pos]. *)
let next_href html pos =
  match find_from html "href=\"" pos with
  | None -> None
  | Some i ->
      let start = i + 6 in
      (match String.index_from_opt html start '"' with
       | None -> None
       | Some stop -> Some (String.sub html start (stop - start), stop + 1))

(** Split "url#sha256=abc" into the URL and the declared digest.

    The fragment is stripped BEFORE validation, which matters: '#' is not in
    the validator's permitted byte set, so a URL retaining its fragment would
    be rejected outright. Stripping here is what lets a legitimate PyPI href
    validate, and it is safe because everything after '#' is discarded rather
    than interpreted. *)
let split_fragment href =
  match String.index_opt href '#' with
  | None -> (href, None)
  | Some i ->
      let url = String.sub href 0 i in
      let frag = String.sub href (i + 1) (String.length href - i - 1) in
      let digest =
        if starts_with ~prefix:"sha256=" frag then
          Some (String.sub frag 7 (String.length frag - 7))
        else None
      in
      (url, digest)

(** Parse a PEP 503 simple-index page into candidates.

    Relative hrefs are dropped: PyPI serves absolute URLs, and resolving
    relative ones would mean reimplementing URL joining, which is exactly the
    kind of code that produces SSRF. *)
let pypi_candidates html =
  let rec go pos acc =
    match next_href html pos with
    | None -> List.rev acc
    | Some (href, next) ->
        let url, sha256 = split_fragment href in
        let acc =
          if starts_with ~prefix:"https://" url then begin
            let filename = last_segment url in
            { url; filename; version = version_of_filename filename; sha256 }
            :: acc
          end else acc
        in
        go next acc
  in
  go 0 []

(* ------------------------------------------------------------------ *)
(* npm: packument JSON                                                 *)
(* ------------------------------------------------------------------ *)

(* We want versions.<v>.dist.{tarball,shasum,integrity}. Rather than pull in a
   JSON library and walk a tree, we scan for "tarball":"..." occurrences and
   take the nearest following "shasum" / "integrity". npm packuments are large
   and regular; this keeps the parser trivial. As above, a mistake here can
   only lose or mislabel a candidate. *)

let json_string_field json key pos =
  let pat = "\"" ^ key ^ "\":\"" in
  match find_from json pat pos with
  | None -> None
  | Some i ->
      let start = i + String.length pat in
      (match String.index_from_opt json start '"' with
       | None -> None
       | Some stop -> Some (String.sub json start (stop - start), stop + 1))

let npm_candidates json =
  let rec go pos acc =
    match json_string_field json "tarball" pos with
    | None -> List.rev acc
    | Some (url, next) ->
        let acc =
          if starts_with ~prefix:"https://" url then begin
            let filename = last_segment url in
            (* npm's "integrity" is "sha512-<base64>"; "shasum" is sha1. We
               record neither as sha256, because neither is one. The digest we
               report is computed over the bytes we actually fetched. *)
            { url; filename; version = version_of_filename filename;
              sha256 = None }
            :: acc
          end else acc
        in
        go next acc
  in
  (* Deduplicate: a packument repeats tarball URLs under dist-tags. *)
  let seen = Hashtbl.create 64 in
  go 0 []
  |> List.filter (fun c ->
         if Hashtbl.mem seen c.url then false
         else (Hashtbl.add seen c.url (); true))
