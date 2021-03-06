
include "stdlib.ws";
include "gnuplot.ws";
include "types.ws";

// When we're not live we just print log messages to the stream.
fun log(l,s) println(s)
fun log_file(l,s) print(s++"\n")
fun timer_source(_,t) timer(1000.0 / intToFloat(t))

// Also need a dummy for this:
fun vxp_buffer_time_remaining() 0.0

// ================================================================================

// NOTE: THESE OLD FILES ARE 24KHZ!!

marmotfile =
  if FILE_EXISTS("15min_marmot_sample.raw") then "15min_marmot_sample.raw" else
  if FILE_EXISTS("3min_marmot_sample.raw") then "3min_marmot_sample.raw" else
  if FILE_EXISTS("6sec_marmot_sample.raw") then "6sec_marmot_sample.raw" else
  //  if FILE_EXISTS("~/archive/4/marmots/brief.raw") then "~/archive/4/marmots/brief.raw" else
  wserror("Couldn't find sample marmot data, run the download scripts to get some.\n");

// How many samples a second do we want to process on each input audio channel?
//accelerator = 1;                   // For testing purposes.
//accelerator = 20;          // 60 saturates honor on one thread, actually 30 does, 20 almost does but not quite
accelerator = 4

// With multiple threads on honor we don't saturate CPU, but we do end
// up with an extra 5 million elements in the queue after running 10
// tuples through run_3phases



// HACK: making the timer integer for emit-c2:
samp_rate = 49152 * accelerator; // HACK - we should get this from the stream/timebase/sigseg

winsize = 16384;

fun amplify(n,s)
  iterate x in s {
    for i = 1 to n {
      emit x;
    }
  }

// Old data files are 24 khz...
driver = 
   if GETENV("COREFITBENCH") == ""
   // Our simulation of a "realtime" Ensbox:
   then timer(samp_rate * 4.0 / winsize`i2f)
   // Just run really fast to benchmark WSC.
   else amplify(100, timer(10.0));

debugdriver = iterate x in driver {
  println("GETENV <"++GETENV("WSCBENCH")++">");
  print("DRIVER FIRED: "++ realtime() ++" timerrate "++ (samp_rate * 4.0 / winsize`i2f) ++"\n");
  emit x;
}

chans = (readFile(marmotfile, "mode: binary window: "++winsize, driver) 
     :: Stream Sigseg (Int16));

// TODO: Try oversampling this input stream to 48 khz to make the detector match the live data:
// Quite inefficient.
chans48 = window(iterate samp in dewindow(chans) { emit samp; emit samp }, winsize*2);

fun onechan(offset)
  iterate w in chans48 {
    size = w`width / 4;
    assert_eq("source stream multiple of 4", w`width, size * 4);
    arr = Array:build(size, fun (i) (w[[(i*4) + offset]]));
    emit toSigseg(arr, w`start / 4`intToInt64 , w`timebase)
  }


// Testing, trying this instead:
ch1i = onechan(0); 
ch2i = onechan(1); 
ch3i = onechan(2); 
ch4i = onechan(3);

//BASE <- debugdriver
