(**************************************************************************)
(*                                                                        *)
(*                              OCamlFormat                               *)
(*                                                                        *)
(*            Copyright (c) Facebook, Inc. and its affiliates.            *)
(*                                                                        *)
(*      This source code is licensed under the MIT license found in       *)
(*      the LICENSE file in the root directory of this source tree.       *)
(*                                                                        *)
(**************************************************************************)

(** OCamlformat RPC API.

    This module defines the commands exchanged between the server and the
    client, and the way to build RPC clients.

    The whole API is functorized over an [IO] module defining the blocking
    interface for reading and writing the data.

    After you decided on the {!module-type-IO} implementation, the
    {!Ocamlformat_rpc_lib.Make} API can then be instantiated:

    {[
      module RPC = Ocamlformat_rpc_lib.Make (IO)
    ]} *)

type format_args =
  { path: string option
        (** Path used for the current formatting request, this allows
            ocamlformat to determine which .ocamlformat files must be
            applied. *)
  ; config: (string * string) list option
        (** Additional options used for the current formatting request. *) }

val empty_args : format_args

module Version : sig
  type t = V1 | V2

  val to_string : t -> string

  val of_string : string -> t option
end

module type IO = IO.S

module Make (IO : IO) : sig
  module type Command_S = sig
    type t

    val read_input : IO.ic -> t IO.t

    val to_sexp : t -> Csexp.t

    val output : IO.oc -> t -> unit IO.t
  end

  module type Client_S = sig
    type t

    type cmd

    val pid : t -> int

    val mk : pid:int -> IO.ic -> IO.oc -> t

    val query : cmd -> t -> cmd IO.t

    val halt : t -> (unit, [> `Msg of string]) result IO.t
    (** The caller must close the input and output channels after calling
        [halt]. *)
  end

  (** Version used to set the protocol version *)
  module Init :
    Command_S with type t = [`Halt | `Unknown | `Version of string]

  module V1 : sig
    module Command :
      Command_S
        with type t =
          [ `Halt
          | `Unknown
          | `Error of string
          | `Config of (string * string) list
          | `Format of string ]

    module Client : sig
      include Client_S with type cmd = Command.t

      val config :
        (string * string) list -> t -> (unit, [> `Msg of string]) result IO.t

      val format : string -> t -> (string, [> `Msg of string]) result IO.t
    end
  end

  module V2 : sig
    module Command :
      Command_S
        with type t =
          [ `Halt
          | `Unknown
          | `Error of string
          | `Format of string * format_args ]

    module Client : sig
      include Client_S with type cmd = Command.t

      val format :
           format_args:format_args
        -> string
        -> t
        -> (string, [> `Msg of string]) result IO.t
      (** [format_args] modifies the server's configuration temporarily, for
          the current request. *)
    end
  end

  type client = [`V1 of V1.Client.t | `V2 of V2.Client.t]

  val pick_client :
       pid:int
    -> IO.ic
    -> IO.oc
    -> string list
    -> (client, [`Msg of string]) result IO.t
  (** The RPC offers multiple versions of the API.
      [pick_client ~pid in out versions] handles the interaction with the
      server to agree with a common version of the RPC to use. Trying
      successively each version of the provided list [versions] until the
      server agrees, for this reason you might want to list newer versions
      before older versions. The given {!module-IO.ic} and {!module-IO.oc}
      values are referenced by the {!client} value and must be kept open
      until {!halt} is called. *)

  val pid : client -> int

  val halt : client -> (unit, [> `Msg of string]) result IO.t
  (** Tell the server to close the connection. No more commands can be sent
      using the same {!client} value. *)

  val config :
       (string * string) list
    -> client
    -> (unit, [> `Msg of string]) result IO.t
  (** @before v2 *)

  val format :
       ?format_args:format_args
    -> string
    -> client
    -> (string, [> `Msg of string]) result IO.t
  (** [format_args] modifies the server's configuration temporarily, for the
      current request.

      @before v2 When using v1, [format_args] will be ignored. *)

  (** A basic interaction could be:

      {[
        RPC.config [("profile", "ocamlformat")] client >>= fun () ->
        RPC.format "let x = 4 in x" client >>= fun formatted ->
        ...
        RPC.halt client >>= fun () ->
        ...
      ]} *)
end

(** For a basic working example, see:
    {{:https://github.com/ocaml-ppx/ocamlformat/blob/93a6b2f46cf31237c413c1d0ac604a8d69676297/test/rpc/rpc_test.ml}
    test/rpc/rpc_test.ml}. *)

(** Disclaimer:

    The [ocamlformat-rpc-lib] API is versioned to offer some basic backwards
    compatibility. Note that this guarantee is "best effort", meaning the
    authors will try to minimize the changes over time and preserve the
    original behavior or versioned clients as much as possible. However
    structural changes may happen. *)
