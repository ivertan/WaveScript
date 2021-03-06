

// This explicitely makes the state static.

// TODO: Enhance this version of rewindow so that it can handle gaps in the output stream.
fun rewindow(sig, newwidth, step) 
  if step > newwidth
  then wserror("rewindow won't allow the creation of non-contiguous output streams")
  else iterate w in sig {
    state { acc = nullseg; }
    acc := joinsegs(acc, w);
    for i = 1 to w.width {
      if acc.width > newwidth
      then {emit subseg(acc, acc.start, newwidth);
	    acc := subseg(acc, acc.start + step, acc.width - step)}
      else break;
    }
  };



main = rewindow(audioFile("./countup.raw", 4096, 0, 44000), 1024, 512);
