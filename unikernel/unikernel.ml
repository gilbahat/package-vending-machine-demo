(** The package vending machine.

    Boot: read the signed manifest, verify its Ed25519 signature, validate it
    with the EverParse-generated parser, and build the allowlist.

    Serve: four GET routes, no URL ever accepted from a client.

      GET /v1/{pypi,npm}/<name>   resolve a package to a list of artifact ids
      GET /v1/a/<id>              fetch one artifact by id
      GET /v1/allowlist           what this machine will vend at all
      GET /v1/status              build info and counters

    The security-critical step is that every candidate URL -- including those
    scraped out of an upstream response body -- must pass
    {!Vend_verified.validate_url} before it is dialled.

    Copyright (c) 2026. SPDX-License-Identifier: ISC *)

open Lwt.Infix

let src = Logs.Src.create "vend" ~doc:"package vending machine"
module Log = (val Logs.src_log src : Logs.LOG)

module Make
    (S : Tcpip.Stack.V4V6)
    (KV : Mirage_kv.RO)
    (HTTP : Http_mirage_client.S) =
struct
  (* Server.Flow, not Server.Make: the latter wants a Conduit_mirage.S, while
     the stack's TCP module is a plain Mirage_flow.S. *)
  module Server = Cohttp_mirage.Server.Flow (S.TCP)

  (* The functor parameter supplies the ALPN client's type; requests go through
     the top-level Http_mirage_client.request. *)
  let _ = (module HTTP : Http_mirage_client.S)

  (* ---------------------------------------------------------------- *)
  (* State                                                             *)
  (* ---------------------------------------------------------------- *)

  type artifact = {
    url : string;              (* validated at resolve time, never from a client *)
    upstream : Vend_verified.upstream;
    filename : string;
    version : string;
    declared_sha256 : string option;
  }

  type state = {
    allow : (int * string, unit) Hashtbl.t;   (* (ecosystem, name) *)
    artifacts : (string, artifact) Hashtbl.t; (* id -> artifact *)
    mutable resolved : int;
    mutable served : int;
    mutable rejected_urls : int;
  }

  let state () = {
    allow = Hashtbl.create 512;
    artifacts = Hashtbl.create 1024;
    resolved = 0;
    served = 0;
    rejected_urls = 0;
  }

  (* ---------------------------------------------------------------- *)
  (* Manifest                                                          *)
  (* ---------------------------------------------------------------- *)

  let sha256_hex s = Digestif.SHA256.(to_hex (digest_string s))

  (* Walk a manifest body that has ALREADY been validated by the
     EverParse-generated parser. Because validation succeeded we know every
     length is in range and the entry list is exactly consumed, so this walk
     cannot run off the end -- and OCaml would raise rather than read out of
     bounds even if it could. *)
  let entries_of_body body =
    let n = String.length body in
    let rec go off acc =
      if off >= n then List.rev acc
      else
        let eco = Char.code body.[off] in
        let name_len = Char.code body.[off + 1] in
        let name = String.sub body (off + 2) name_len in
        go (off + 2 + name_len) ((eco, name) :: acc)
    in
    go 12 []

  (* [key_raw] is the 32-byte Ed25519 public key, baked into the image. *)
  let load_manifest st kv key_raw =
    let ( let* ) = Lwt.bind in
    let* r = KV.get kv (Mirage_kv.Key.v "manifest.bin") in
    match r with
    | Error e ->
        Log.err (fun m -> m "manifest.bin unreadable: %a" KV.pp_error e);
        Lwt.return_error "manifest unreadable"
    | Ok blob ->
        if String.length blob < 64 then
          Lwt.return_error "manifest shorter than a signature"
        else begin
          let signature = String.sub blob 0 64 in
          let body = String.sub blob 64 (String.length blob - 64) in
          (* 1. authenticity, before the parser sees anything *)
          match Mirage_crypto_ec.Ed25519.pub_of_octets key_raw with
          | Error _ -> Lwt.return_error "manifest public key is malformed"
          | Ok key ->
              if not (Mirage_crypto_ec.Ed25519.verify ~key signature ~msg:body)
              then Lwt.return_error "manifest signature is INVALID"
              else if
                (* 2. shape, by the generated validator, exact consumption *)
                not (Vend_verified.manifest_check body)
              then
                Lwt.return_error
                  ("manifest malformed: " ^ Vend_verified.manifest_last_error ())
              else begin
                List.iter
                  (fun (eco, name) -> Hashtbl.replace st.allow (eco, name) ())
                  (entries_of_body body);
                Log.info (fun m ->
                    m "manifest OK: %d entries, sha256=%s"
                      (Hashtbl.length st.allow) (sha256_hex body));
                Lwt.return_ok ()
              end
        end

  (* ---------------------------------------------------------------- *)
  (* Upstream fetching                                                 *)
  (* ---------------------------------------------------------------- *)

  (* Fetch a URL that has ALREADY passed the verified validator.

     follow_redirect is false. A followed 302 would let the upstream choose
     our next destination, reintroducing exactly the SSRF primitive the
     validator removes. *)
  let get_validated http url =
    Http_mirage_client.request http ~follow_redirect:false url
      (fun _resp acc chunk -> Lwt.return (acc ^ chunk))
      ""
    >|= function
    | Ok (resp, body) -> (
        match resp.Http_mirage_client.status with
        | `OK -> Ok (resp, body)
        | s ->
            Error
              (Fmt.str "upstream returned %a" H2.Status.pp_hum s))
    | Error err -> Error (Fmt.str "%a" Mimic.pp_error err)

  (* The gate. Nothing else in this file dials anything. *)
  let fetch st http upstream url =
    if not (Vend_verified.validate_url upstream url) then begin
      st.rejected_urls <- st.rejected_urls + 1;
      Log.warn (fun m -> m "REJECTED by verified validator: %S" url);
      Lwt.return_error "url rejected by the verified validator"
    end else get_validated http url

  (* ---------------------------------------------------------------- *)
  (* Resolve                                                           *)
  (* ---------------------------------------------------------------- *)

  let ecosystem_of_string = function
    | "pypi" -> Some (0, Vend_verified.Pypi_index, Vend_verified.Pypi_files)
    | "npm" -> Some (1, Vend_verified.Npm_registry, Vend_verified.Npm_registry)
    | _ -> None

  (* A package name is one path segment. Reject anything that is not, before
     it is ever concatenated into a URL. This is belt and braces: a name that
     slipped through would still have to pass the verified validator. *)
  let name_ok name =
    name <> ""
    && String.length name <= 128
    && String.for_all
         (fun c ->
           (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
           || (c >= '0' && c <= '9')
           || c = '-' || c = '.' || c = '_' || c = '~')
         name

  let id_of_url url = String.sub (sha256_hex url) 0 32

  let json_escape s =
    let b = Buffer.create (String.length s + 8) in
    String.iter
      (fun c ->
        match c with
        | '"' -> Buffer.add_string b "\\\""
        | '\\' -> Buffer.add_string b "\\\\"
        | '\n' -> Buffer.add_string b "\\n"
        | '\r' -> Buffer.add_string b "\\r"
        | '\t' -> Buffer.add_string b "\\t"
        | c when Char.code c < 0x20 ->
            Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
        | c -> Buffer.add_char b c)
      s;
    Buffer.contents b

  let resolve st http eco_str name =
    match ecosystem_of_string eco_str with
    | None -> Lwt.return_error "unknown ecosystem"
    | Some (eco_tag, index_upstream, files_upstream) ->
        if not (name_ok name) then Lwt.return_error "invalid package name"
        else if not (Hashtbl.mem st.allow (eco_tag, name)) then
          Lwt.return_error "package is not on this machine's allowlist"
        else begin
          (* Build the index URL. Construction is unverified; the gate is. *)
          let index_url =
            match eco_str with
            | "pypi" -> Vend_verified.upstream_prefix index_upstream ^ name ^ "/"
            | _ -> Vend_verified.upstream_prefix index_upstream ^ name
          in
          fetch st http index_upstream index_url >>= function
          | Error e -> Lwt.return_error ("upstream index: " ^ e)
          | Ok (_resp, body) ->
              let candidates =
                if eco_str = "pypi" then Resolve.pypi_candidates body
                else Resolve.npm_candidates body
              in
              (* ★ Every candidate URL came out of an upstream response body.
                 This is the CVE-2026-65923 dataflow. Validate, or discard. *)
              let kept =
                List.filter_map
                  (fun (c : Resolve.candidate) ->
                    if Vend_verified.validate_url files_upstream c.url then
                      Some c
                    else begin
                      st.rejected_urls <- st.rejected_urls + 1;
                      Log.warn (fun m ->
                          m "upstream offered a URL the validator refused: %S"
                            c.url);
                      None
                    end)
                  candidates
              in
              List.iter
                (fun (c : Resolve.candidate) ->
                  Hashtbl.replace st.artifacts (id_of_url c.url)
                    { url = c.url; upstream = files_upstream;
                      filename = c.filename; version = c.version;
                      declared_sha256 = c.sha256 })
                kept;
              st.resolved <- st.resolved + 1;
              let items =
                List.map
                  (fun (c : Resolve.candidate) ->
                    Printf.sprintf
                      {|{"id":"%s","filename":"%s","version":"%s","sha256":%s}|}
                      (id_of_url c.url) (json_escape c.filename)
                      (json_escape c.version)
                      (match c.sha256 with
                       | Some d -> "\"" ^ json_escape d ^ "\""
                       | None -> "null"))
                  kept
              in
              Lwt.return_ok
                (Printf.sprintf
                   {|{"ecosystem":"%s","name":"%s","count":%d,"artifacts":[%s]}|}
                   (json_escape eco_str) (json_escape name) (List.length kept)
                   (String.concat "," items))
        end

  (* ---------------------------------------------------------------- *)
  (* Serve one artifact                                                *)
  (* ---------------------------------------------------------------- *)

  let serve_artifact st http id =
    match Hashtbl.find_opt st.artifacts id with
    | None -> Lwt.return_error "unknown artifact id"
    | Some a -> (
        (* The URL comes from our own table, already validated at resolve
           time. It is re-validated here anyway: the check is a few hundred
           nanoseconds and it means no code path reaches the network without
           passing the gate immediately beforehand. *)
        fetch st http a.upstream a.url >>= function
        | Error e -> Lwt.return_error e
        | Ok (_resp, body) ->
            let got = sha256_hex body in
            match a.declared_sha256 with
            | Some want when not (String.equal want got) ->
                Log.err (fun m ->
                    m "digest mismatch for %s: index said %s, got %s"
                      a.filename want got);
                Lwt.return_error "artifact digest does not match the index"
            | _ ->
                st.served <- st.served + 1;
                Lwt.return_ok (body, got, a.filename))

  (* ---------------------------------------------------------------- *)
  (* HTTP surface                                                      *)
  (* ---------------------------------------------------------------- *)

  let split_path p =
    String.split_on_char '/' p |> List.filter (fun s -> s <> "")

  let respond ?(status = `OK) ?(ctype = "application/json") ?(extra = []) body =
    let headers =
      Cohttp.Header.of_list
        ([ ("content-type", ctype);
           (* content-length is deliberately NOT set here: cohttp computes the
              framing itself, and a second copy risks a request-smuggling
              style disagreement between us and any intermediary. *)
           (* This service never returns HTML and never wants to be framed,
              sniffed, or cached by anything in between. *)
           ("x-content-type-options", "nosniff");
           ("cache-control", "no-store") ]
        @ extra)
    in
    Server.respond_string ~headers ~status ~body ()

  let error_json msg =
    Printf.sprintf {|{"error":"%s"}|} (json_escape msg)

  let allowlist_json st =
    let items =
      Hashtbl.fold
        (fun (eco, name) () acc ->
          Printf.sprintf {|{"ecosystem":"%s","name":"%s"}|}
            (if eco = 0 then "pypi" else "npm")
            (json_escape name)
          :: acc)
        st.allow []
      |> List.sort compare
    in
    Printf.sprintf {|{"count":%d,"packages":[%s]}|} (List.length items)
      (String.concat "," items)

  let status_json st =
    Printf.sprintf
      {|{"resolved":%d,"served":%d,"urls_rejected_by_validator":%d,"allowlist":%d,"upstreams":["%s","%s","%s"],"follow_redirects":false}|}
      st.resolved st.served st.rejected_urls (Hashtbl.length st.allow)
      (Vend_verified.upstream_prefix Vend_verified.Pypi_index)
      (Vend_verified.upstream_prefix Vend_verified.Pypi_files)
      (Vend_verified.upstream_prefix Vend_verified.Npm_registry)

  let dispatch st http _conn req _body =
    let uri = Cohttp.Request.uri req in
    let meth = Cohttp.Request.meth req in
    let path = Uri.path uri in
    match (meth, split_path path) with
    | `GET, [ "v1"; "status" ] -> respond (status_json st)
    | `GET, [ "v1"; "allowlist" ] -> respond (allowlist_json st)
    | `GET, [ "v1"; ("pypi" | "npm") as eco; name ] -> (
        resolve st http eco name >>= function
        | Ok json -> respond json
        | Error e -> respond ~status:`Bad_request (error_json e))
    | `GET, [ "v1"; "a"; id ] -> (
        serve_artifact st http id >>= function
        | Ok (body, digest, filename) ->
            respond ~ctype:"application/octet-stream"
              ~extra:
                [ ("x-vend-digest", "sha256:" ^ digest);
                  ( "content-disposition",
                    Printf.sprintf "attachment; filename=\"%s\""
                      (json_escape filename) ) ]
              body
        | Error e -> respond ~status:`Bad_request (error_json e))
    | `GET, _ -> respond ~status:`Not_found (error_json "no such route")
    | _, _ ->
        respond ~status:`Method_not_allowed
          (error_json "this machine only answers GET")

  (* ---------------------------------------------------------------- *)

  (* Port is fixed rather than a boot argument: this machine has exactly one
     job, and a smaller boot-argument surface is one less thing to get wrong. *)
  let port = 8080

  let start stack kv http =
    let st = state () in
    let ( let* ) = Lwt.bind in
    (* Pin the OCaml-side prefix strings against the constants compiled into
       the verified C. A drift here would otherwise fail silently as "every
       URL is rejected"; this makes it fail loudly instead. *)
    if not (Vend_verified.self_check ()) then begin
      Log.err (fun m ->
          m "REFUSING TO START: prefix strings disagree with the verified C");
      Lwt.return_unit
    end
    else
    let* pub = KV.get kv (Mirage_kv.Key.v "manifest.pub") in
    match pub with
    | Error e ->
        Log.err (fun m ->
            m "REFUSING TO START: manifest.pub unreadable: %a" KV.pp_error e);
        Lwt.return_unit
    | Ok raw ->
    load_manifest st kv raw >>= function
    | Error e ->
        Log.err (fun m -> m "REFUSING TO START: %s" e);
        (* A machine that cannot establish its allowlist must not serve. *)
        Lwt.return_unit
    | Ok () ->
        Log.info (fun m ->
            m "vending machine listening on %d; upstreams pinned at compile \
               time; redirects disabled" port);
        let http = Server.make ~callback:(dispatch st http) () in
        S.TCP.listen (S.tcp stack) ~port (fun flow -> Server.callback http flow);
        S.listen stack
end
