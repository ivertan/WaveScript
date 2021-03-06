

    
open Bigarray;;


(*let rec insert_between x ls =
  match ls with
    | []   -> []
    | [h]  -> [h]
    | h::t -> h:: x:: insert_between x ls*)
let arrayToList bigarr =
  let acc = ref [] in
  for i = 0 to Bigarray.Array1.dim bigarr - 1 do
    acc := Bigarray.Array1.get bigarr i :: !acc
  done;
  List.rev !acc

let autofft = 
  let size = ref 1024 in
  let plan = ref (Fftw2.create Fftw2.forward !size) in 
    fun (arr : (Complex.t, complex64_elt, c_layout) Array1.t) ->
      if Array1.dim arr == !size
      then !plan arr
      else (size := Array1.dim arr;
	    plan := Fftw2.create Fftw2.forward !size;
	    !plan arr)
;;	      


(* let autofft arr = arr *)


(* Need to halve the size of the output!! *)
(*
let fftR2C (sigseg : (float, Bigarray.float64_elt) sigseg) : (Complex.t, Bigarray.complex64_elt) sigseg = 
  let flarr = toArray sigseg in
  let newsize = (Array1.dim flarr / 2) + 1 in 
  let bigarr = Array1.create complex64 c_layout (Bigarray.Array1.dim flarr) in
  for i = 0 to Bigarray.Array1.dim flarr - 1 do
    Array1.set bigarr i { Complex.re= Array1.get flarr i; Complex.im = 0.0 };
  done;
    let result = autofft bigarr in
    (* Really lame to still need to copy out only the bottom half.*)
    let complexarr = Array1.create complex64 c_layout newsize in
      for i = 0 to newsize-1 do
	Array1.set complexarr i  (Array1.get result i);
      done;
      (* Start is zero for this frequency domain array: *)
      toSigseg complexarr 0 3333
*)


(*let fftR2C (flarr : (float, Bigarray.float64_elt) BigArray.Array1.t) : (Complex.t, Bigarray.complex64_elt) BigArray.Array1.t = *)
let fftR2C flarr = 
  let newsize = (Array1.dim flarr / 2) + 1 in 
  let bigarr = Array1.create complex64 c_layout (Bigarray.Array1.dim flarr) in
  for i = 0 to Bigarray.Array1.dim flarr - 1 do
    Array1.set bigarr i { Complex.re= Array1.get flarr i; Complex.im = 0.0 };
  done;
    let result = autofft bigarr in
    (* Really lame to still need to copy out only the bottom half.*)
    let complexarr = Array1.create complex64 c_layout newsize in
      for i = 0 to newsize-1 do
	Array1.set complexarr i  (Array1.get result i);
      done;
      (* Start is zero for this frequency domain array: *)
      complexarr


(* If our arrays were already bigarrays... well the we'd still need to
   copy to get the half of the output that we want. 
   Wouldn't have to copy on input...*)


let powInt n x = 
  let rec loop acc i =
    if i == 0
    then acc
    else loop (n * acc) (i - 1)
  in loop 1 x

let element_limit = 
  let args = List.tl (Array.to_list Sys.argv )
  in begin 
(*      Printf.printf "Argv head %s\n" (List.hd args); *)
     if not (args == []) && (List.hd args = "-n")
     then begin 
(*           Printf.printf "Setting element limit %d\n" (int_of_string (List.hd (List.tl args))); *)
          int_of_string (List.hd (List.tl args))
	  end
     else -1
     end

