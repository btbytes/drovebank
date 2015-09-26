module Unix = struct
  include Unix

  let rec accept_non_intr s =
  try accept s
  with Unix_error (EINTR, _, _) -> accept_non_intr s

  let establish_server server_fun sockaddr =
    let sock =
      socket (domain_of_sockaddr sockaddr) SOCK_STREAM 0 in
    setsockopt sock SO_REUSEADDR true;
    bind sock sockaddr;
    listen sock 5;
    let thread_fun (s, caller) =
      set_close_on_exec s;
      let inchan = in_channel_of_descr s in
      let outchan = out_channel_of_descr s in
      server_fun inchan outchan;
      (* Do not close inchan nor outchan, as the server_fun could
         have done it already, and we are about to exit anyway
         (PR#3794) *)
      Thread.exit ()
    in
    while true do
      let (s, caller) = accept_non_intr sock in
      ignore(Thread.create thread_fun (s, caller))
    done
end

module Int64 = struct
  include Int64
  let ( + ) = add
  let ( - ) = sub
  let ( * ) = mul
  let ( / ) = div

  module Map = Map.Make(Int64)
end

let with_finalize ~f_final ~f =
  try
    let res = f () in
    f_final ();
    res
  with exn ->
    f_final ();
    raise exn

let with_ic ic f =
  let f () = f ic in
  let f_final () = close_in ic in
  with_finalize ~f_final ~f

let with_oc ic f =
  let f () = f ic in
  let f_final () = close_out ic in
  with_finalize ~f_final ~f

module Entry = struct
  type transaction = [`Cont | `Begin | `End | `Atomic]

  let string_of_transaction = function
    | `Cont -> "C"
    | `Begin -> "B"
    | `End -> "E"
    | `Atomic -> "A"

  type op = [`Deposit | `Withdraw]

  let string_of_op = function
    | `Deposit -> "D"
    | `Withdraw -> "W"

  type t = {
    tr: transaction;
    op: op;
    id: int64;
    qty: int64
  }

  let pp fmt t =
    Format.fprintf fmt "{ tr=%s; op=%s; id=%Ld; qty=%Ld; }"
      (string_of_transaction t.tr)
      (string_of_op t.op)
      t.id t.qty

  let show t =
    Printf.sprintf "{ tr=%s; op=%s; id=%Ld; qty=%Ld; }"
      (string_of_transaction t.tr)
      (string_of_op t.op)
      t.id t.qty

  let create ?(tr=`Atomic) ~op ~id ~qty () = { tr; op; id; qty; }

  let int64_of_transaction = function
    | `Cont -> 0L
    | `Begin -> 1L
    | `End -> 2L
    | `Atomic -> 3L

  let transaction_of_int64 = function
    | 0L -> `Cont
    | 1L -> `Begin
    | 2L -> `End
    | 3L -> `Atomic
    | _ -> invalid_arg "transaction_of_int64"

  let int64_of_op = function
    | `Deposit -> 0L
    | `Withdraw -> 4L

  let write buf pos t =
    let b1 =
      let open Int64 in
      logor
        (shift_left t.id 3)
        (logor (int64_of_transaction t.tr) (int64_of_op t.op))
    in
    EndianBytes.BigEndian.set_int64 buf pos b1;
    EndianBytes.BigEndian.set_int64 buf (pos+8) t.qty

  let write' ?(tr=`Atomic) ~op ~id ~qty buf pos =
    let b1 =
      let open Int64 in
      logor
        (shift_left id 3)
        (logor (int64_of_transaction tr) (int64_of_op op))
    in
    EndianBytes.BigEndian.set_int64 buf pos b1;
    EndianBytes.BigEndian.set_int64 buf (pos+8) qty

  let read buf pos =
    let b1 = EndianBytes.BigEndian.get_int64 buf pos in
    let qty = EndianBytes.BigEndian.get_int64 buf (pos+8) in
    let id = Int64.shift_right_logical b1 3 in
    let tr = transaction_of_int64 Int64.(logand b1 3L) in
    let op = if Int64.(logand b1 4L) = 0L then `Deposit else `Withdraw in
    { tr; op; id; qty; }

  let input ic =
    let buf = Bytes.create 16 in
    let rec inner pos len =
      let nb_read = input ic buf pos len in
      if nb_read = len then read buf 0
      else if nb_read = 0 then raise End_of_file
      else inner (pos+nb_read) (len-nb_read)
    in inner 0 16

  let output oc t =
    let buf = Bytes.create 16 in
    write buf 0 t;
    output oc buf 0 16

  let process db t = match t.op with
    | `Deposit ->
        (try
           Int64.(Map.add t.id (Map.find t.id db + t.qty) db)
         with Not_found ->
           Int64.Map.add t.id t.qty db)
    | `Withdraw ->
        try
          let cur_qty = Int64.Map.find t.id db in
          if cur_qty >= t.qty
          then Int64.Map.add t.id Int64.(cur_qty - t.qty) db
          else db
        with Not_found -> db
end
