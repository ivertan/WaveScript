

// [2007.11.07] 
// Uh oh... testall_wsc just failed on this with the error below.
// But when I reran by hand it worked... scary.
// Ah, I think it crashes only in -dbg mode.
/*
generated C++ output to "./query.cpp".

Linking extra libraries requested by query file:
Compiling .cpp file using g++.
g++ -g -O0 -I/home/newton/v1.dbg//include -DSegList -DuseArray -Di386 -DTIMING_RDTSC -DTRAIN_SCHEDULER -o ./query.exe ./query.cpp /home/newton/v1.dbg//libws-SMSegList.a -lpthread
Time spent in g++: 4 seconds

Executable output to query.
Wed Nov  7 11:08:07.274 2007: WSSched: CPU Speed from /proc/cpuinfo = 2392541
Wed Nov  7 11:08:07.274 2007: TimebaseMgrInit: TimebaseMgr startup OK
Wed Nov  7 11:08:07.274 2007: start: Allocated 2 threads.
Wed Nov  7 11:08:07.274 2007: start: Started 2 threads... waiting for them to complete.
Wed Nov  7 11:08:07.274 2007: _start: created thread 8073d60 aka thread[1]:  (pid=17133, tid=17134)
Wed Nov  7 11:08:07.274 2007: _start: created thread 8074348 aka thread[2]:  (pid=17133, tid=17135)
Wed Nov  7 11:08:07.274 2007: run: Thread 0 starting
Wed Nov  7 11:08:07.274 2007: iterate: Tuple limit hit.  Stopping query.
Wed Nov  7 11:08:07.274 2007: _start: created thread 80743b0 aka thread[3]:  (pid=17133, tid=17136)
Wed Nov  7 11:08:07.274 2007: run: Thread 1 starting
Wed Nov  7 11:08:07.274 2007: lock: mutex lock failed
Wed Nov  7 11:08:07.275 2007: run: cond_wait returned error: Invalid argument                                                               
*/


// This does a rewindow manually.  That is, without defining a
// separate function and using the inliner.

// This serves as a test of sigseg operations.

include "common.ws";

//fun assert_eq(s,a,b) if not(a==b) then wserror("Assert failed in '"++s++"' : "++ a ++" not equal "++ b);

size = 40;

//s1 = (readFile("./countup.raw", "mode: binary  window: 4096", timer(10.0)) :: Stream (Sigseg Int16));

fun print_sigseg(ss) {
  if ss.width == 0 then print("[->]")  else 
  print("["++ ss`start ++" -> "++ ss`end ++"]")
}

s1 = iterate _ in timer(10.0) {
  state { pos = 0 }
  ss = toSigseg(Array:make(size, intToInt16(99)), pos, nulltimebase);
  println("Sending out " ++ ss`width);
  assert_eq_prnt("null arr width ", 0, (Array:null :: Array Int)`Array:length);
  println("null width " ++ (nullseg :: Sigseg Int)`width);
  //assert_eq_prnt("null width ", 0, (nullseg :: Sigseg Int)`width);
  assert_eq_prnt("make_null width ", 0, (make_nullseg() :: Sigseg Int)`width);
  emit ss;
  pos += gint(size);
}

newwidth = 1024;
step = gint(512);

s2 = iterate win in s1 {
   state { acc = make_nullseg() }

   print("\nIncoming width ");
   print(win`width);
   print(" Current ACC/width ");
   print(acc`width);
   print(": ");
   print_sigseg(acc);
   print("\n");


   newacc = joinsegs(acc, win);
   assert_eq("join", newacc`width, win`width + acc`width);
   acc := newacc;

   // We do this entirely with index numbers, no abstract Time objects are used.
   // win.width is an upper bound on how many windows we can produce.

   print("JOINED Current ACC/width ");
   print(acc.width);
   print(": ");
   print_sigseg(acc);
   print("\n");

   while acc.width > newwidth {
     print("Iterating, acc.width " ++ acc.width ++ "\n");
     chop = subseg(acc, acc`start, newwidth);
     emit chop;

     //     print("Cutting leftover: "++ acc++" "++acc.start++" "++step++"  "++acc.width-step++"  \n");
     leftover = subseg(acc, acc.start + step`intToInt64, acc.width - step);
     //     print("  Got leftover\n");
     assert_eq("split", acc`width, chop`width + leftover`width - step);
     acc := leftover;
   }
};

main = s2;
