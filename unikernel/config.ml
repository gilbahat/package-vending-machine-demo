(* Mirage configuration for the package vending machine.

   Target is solo5-hvt only. There is no unix target on purpose: a demo whose
   security argument is "the TCB is eight hypercalls" should not ship a build
   that runs as an ordinary process with a filesystem and a shell one exec()
   away.

   Copyright (c) 2026. SPDX-License-Identifier: ISC *)

open Mirage

(* The verified library is NOT an opam package.

   Mirage builds the unikernel in a dune context using the solo5 findlib
   toolchain, with every dependency vendored as source into duniverse/ and
   recompiled there -- host-installed archives are the wrong target (this is
   not academic: mirage-solo5's C bindings archive is empty unless it is built
   inside that context). So the verified library is vendored into
   unikernel/vendor/ by scripts/build-unikernel.sh and picked up by dune as
   part of this project.

   That leaves one wrinkle: functoria derives dune's `libraries` field from
   opam packages, and declaring an opam package that does not exist would
   break `make lock`. Attaching the library name to a package we already
   depend on adds it to `libraries` without inventing a package. *)
let packages =
  [ package ~libs:[ "digestif"; "vend_verified" ] "digestif"
  ; package "cohttp-mirage"
  ; package "http-mirage-client"
  ; package "ca-certs-nss"
  ; package "mirage-crypto-ec"
  ; package "logs"
  ; package "fmt"
  ; package "h2"      (* Http_mirage_client's response status type *)
    (* lwt >= 6 references Stdlib.Runtime_events from lwt.core, which drags
       runtime_events_consumer.o into the link. That object calls fstat(), and
       Solo5's freestanding libc has no filesystem and therefore no fstat, so
       the unikernel fails to link. Nothing here uses runtime events. *)
  ; package "lwt" ~max:"6.0.0"
  ]

(* The signed allowlist and the public key that verifies it are baked into the
   image. Baking the key is the point -- it is the trust root, and it should
   not be settable at boot. Baking the manifest alongside it is a demo
   simplification: a deployment would take the manifest from a block device or
   fetch it at boot, which is why the signature check exists at all. Using
   crunch rather than a block device also keeps BLOCK_READ/BLOCK_WRITE out of
   the reachable hypercall set. *)
let assets = crunch "assets"

let stack = generic_stackv4v6 default_network

(* Outbound HTTPS. happy-eyeballs handles v4/v6 selection, and the ALPN client
   carries TLS with the NSS trust anchors compiled in. *)
let he = generic_happy_eyeballs stack
let dns = generic_dns_client stack he
let mimic = mimic_happy_eyeballs stack he dns
let alpn = paf_client (tcpv4v6_of_stackv4v6 stack) mimic

let main =
  main "Unikernel.Make" ~packages
    (stackv4v6 @-> kv_ro @-> alpn_client @-> job)

let () = register "vend" [ main $ stack $ assets $ alpn ]
