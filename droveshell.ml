(*---------------------------------------------------------------------------
   Copyright (c) 2015 Vincent Bernardoff. All rights reserved.
   Distributed under the MIT license, see license at the end of the file.
  ---------------------------------------------------------------------------*)

open Drovelib

let () =
  let op = ref None in
  let anon_args = ref [] in
  let speclist = Arg.[
      "-s", Unit (fun () -> op := Some `Show), " Show ledger";
      "-d", Unit (fun () -> op := Some `Deposit),
      "<id> <qty> Deposit cash into an account";
      "-w", Unit (fun () -> op := Some `Withdraw),
      "<id> <qty> Withdraw cash from an account";
      "-t", Unit (fun () -> op := Some `Transfer),
      "<id> <id'> <qty> Transfer cash from an account to another";
      "-c", Unit (fun () -> op := Some `Custom),
      "<id> <qty> <op> <tr> <len> Custom operation";
  ] in
  let usage_msg =
    Printf.sprintf "Usage: %s <options>\nOptions are:" Sys.argv.(0) in
  Arg.parse speclist (fun a ->
      let a = try `Int64 Int64.(of_string a) with _ -> `String a in
      anon_args := a::!anon_args) usage_msg;
  let tmp = Sys.readdir "/tmp" in
  let drovebanks =
    Array.fold_left
      (fun a v ->
         if String.length v > 10 && String.sub v 0 10 = "drovebank-"
         then v::a else a
      ) [] tmp in
  let drovebank = match drovebanks with
    | [] ->
        prerr_endline "Impossible to locate any running DroveBank daemon, exiting.";
        exit 1
    | h::_ -> Unix.ADDR_UNIX ("/tmp/" ^ h) in
  try
    match !op with
    | None -> Arg.usage speclist usage_msg
    | Some `Show ->
        Unix.with_connection drovebank (fun ic oc ->
            (match Operation.dump ic oc with
            | Result.Error () -> prerr_endline "NOK"
            | Result.Ok db ->
                if Int64.Map.is_empty db then
                  Printf.eprintf "<ledger empty>\n"
                else
                  Int64.Map.iter (fun id qty ->
                      Printf.printf "%Ld: %Ld\n%!" id qty
                    ) db
            )
          )

    | Some `Deposit ->
        (match !anon_args with
         | [`Int64 qty; `Int64 id] ->
             Unix.with_connection drovebank (fun ic oc ->
                 match Operation.atomic ~op:`Deposit ~id ~qty ic oc with
                 | Result.Ok () -> prerr_endline "OK"
                 | _ -> prerr_endline "NOK"
               )
         | _ -> raise Exit
        )
    | Some `Withdraw ->
        (match !anon_args with
         | [`Int64 qty; `Int64 id] ->
             Unix.with_connection drovebank (fun ic oc ->
                 match Operation.atomic ~op:`Withdraw ~id ~qty ic oc with
                 | Result.Ok () -> prerr_endline "OK"
                 | _ -> prerr_endline "NOK"
               )
         | _ -> raise Exit
        )
    | Some `Transfer ->
        (match !anon_args with
         | [`Int64 qty; `Int64 id'; `Int64 id] ->
             Unix.with_connection drovebank (fun ic oc ->
                 match Operation.transfer ~id ~id' ~qty ic oc with
                 | Result.Ok () -> prerr_endline "OK"
                 | _ -> prerr_endline "NOK"
               )
         | _ -> raise Exit
        )
    | Some `Custom ->
        (match !anon_args with
         | [`Int64 len; `String tr; `String op; `Int64 qty; `Int64 id] ->
             Unix.with_connection drovebank (fun ic oc ->
                 match Operation.custom ~id ~qty ~op ~tr ~len ic oc with
                 | Result.Ok () -> prerr_endline "OK"
                 | _ -> prerr_endline "NOK"
               )
         | _ -> raise Exit
        )
  with exn ->
    prerr_endline Printexc.(to_string exn)

(*---------------------------------------------------------------------------
  Copyright (c) 2015 Vincent Bernardoff

  Permission is hereby granted, free of charge, to any person
  obtaining a copy of this software and associated documentation files
  (the "Software"), to deal in the Software without restriction,
  including without limitation the rights to use, copy, modify, merge,
  publish, distribute, sublicense, and/or sell copies of the Software,
  and to permit persons to whom the Software is furnished to do so,
  subject to the following conditions:

  The above copyright notice and this permission notice shall be
  included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
  ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
  ---------------------------------------------------------------------------*)
