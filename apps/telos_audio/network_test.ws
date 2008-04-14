



/* 
 * This simply reports the node IDs of every node.
 *
 * .author Ryan Newton
 *
 */

/* 
 * [2008.04.11]
 * Jeez, it seems like every time I turn around everything stops working on TinyOS. *

 * It's not working well in non-WSRADIOMODE atm.  And perhaps the
 * RADIOMODE ver is getting hosed by stray packets from other nodes
 * programmed some time ago.
 *

Run this with wstiny -split 


 */

using TOS;
using Array;
using Mutable;

//Node:strm = iterate arr in read_telos_audio(200, 100) {


// The CTP knocks out 8 bytes...
//toparr :: Array Int16 = Array:build((20 / 2) - 1, fun(i) i.gint)
toparr :: Array Int16 = Array:build(9, fun(i) i.gint + 300)

zeroarr :: Array Int16 = Array:make(0, 0)
//zeroarr :: Array Int16 = Array:null

// Hardware timer rate:
maxrate = 512
step = 5 // Step period down by
// Epoch in seconds 
epoch = 60 * maxrate // One minute

//steps = (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 75 100 200)

Node:src = TOS:timer$ maxrate;
//Node:src = read_telos_audio(14, 100)
//Node:src = read_telos_audio(100, 200)

Node:strm = iterate arr in Node:src  {
  state { nextlvl :: Int16 = 0;
          cur :: Int16 = 0;
          cap :: Int16 = maxrate; // Start off w/ one msg/sec
	  epochnum :: Int16 = 0;
	  msgcounter :: Int16 = 0;

	  // NEW SYSTEM:
	  // Increment the rate (in msgs per second), and then map that onto period:
	  rate = 1
	  }

  // Just die at the end:
  if cap < 1 then wserror("alldone");

  //led0Toggle();
  led1Toggle();
  //led2Toggle();
  id = getID();
  //payload = maxPayloadLength(); // 28 by default.
  dropped = getDroppedInputCount();
  
  //arr[0] := cnt;
  //toparr[0] := (cast_num(id) :: Int16);
  toparr[0] := Int16! id;
  toparr[1] := cur;
  toparr[2] := cap;
  toparr[3] := nextlvl;
  toparr[4] := epochnum;
  toparr[5] := msgcounter;

  foo = ref(false);

  if cur == cap then {
    cur := 0;
    //if id != 1 then print(".");
    //if id != 1 then emit toparr;
    msgcounter += 1;
    foo := true;
  };

  toparr[6] := maxrate;
  toparr[7] := Int16! dropped;
  toparr[8] := if foo then 2222 else 1111;

  if id != 1 && foo then emit toparr;
  //if id != 1 then emit toparr else emit zeroarr;
  //if id != 1 then emit toparr;
  //emit zeroarr;
  //if foo then emit toparr;

  if nextlvl == epoch then {
    nextlvl := 0;
    msgcounter := 0;

    // HACK: two different steps:
/*     if cap < 20  */
/*     then cap := cap - 1 */
/*     else cap := cap - step; */
    rate := rate + 1;
    cap := maxrate / rate;

    epochnum += 1;
    //if id != 1 then print("New epoch "++epochnum++" cap is "++cap++"\n");
  };

  nextlvl += 1;
  cur += 1;
  
  //if id > 1 then emit toparr;

  //if id != 1 then print("Running on "++id++" cnt "++cnt++"\n");
  //if id != 1 then print("arr "++toparr++"\n");

  //emit arr;
  //emit arr;
  //emit (payload, 234, id, cnt, dropped);

  //x :: Int32 = 99;
  //emit ((cast_num(id)::Int32), cnt, x,x,x,x,x);
  //emit(x,x,x,x,x)
  //emit 8587;
  //emit (id, toparr.length);  
  
}

main = Node:strm;
