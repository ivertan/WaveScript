
include "stdlib.ws";

// This version is enhanced to allow large steps that result in gaps in the output streams.
//   GAP is the space *between* sampled strips, negative for overlap!
fun rewindowGeneral (mynullseg, mystart, mywidth, mysubseg, myjoinsegs)
 fun (sig, newwidth, gap) {
  feed = newwidth + gap;

  if (gap <= (0 - newwidth))
    then wserror("rewindow cannot step backwards: width "++ show(newwidth) ++" gap "++show(gap))
    else 
     
   iterate (win in sig) {
    state { 
      acc = mynullseg; 
      // This bool helps to handle an output streams with gaps.
      // We have to states, true means we're to "output" a gap next,
      // false means we're to output a sigseg next.
      need_feed = false;
      go = false; // Temp 
    }

    acc := myjoinsegs(acc, win);
    //print("Acc "++show(acc`mystart)++":"++show(acc`end)++" need_feed "++show(need_feed)++"\n");

    go := true;
    while go {
     if need_feed then {
       if acc`mywidth > gap // here we discard a segment:
       then {acc := mysubseg(acc, acc`mystart + gap, acc`mywidth - gap);
	     need_feed := false; }
       else go := false
      } else {
	if acc`mywidth > newwidth
	then {emit mysubseg(acc, acc`mystart, newwidth);
	      if gap > 0 
	      then { 
		acc := mysubseg(acc, acc`mystart + newwidth, acc`mywidth - newwidth);
		need_feed := true; 
	      } else acc := mysubseg(acc, acc`mystart + feed, acc`mywidth - feed);
	} else go := false
      }
   }
  }
};

//rewindow = rewindowGeneral(nullseg, start, width, subseg, joinsegs);


  null4S  = (nullseg, nullseg, nullseg, nullseg);
  // Should probably assert that the widths are the same here.
  fun start4S((s1,_,_,_)) start(s1);
  fun width4S((s1,_,_,_)) width(s1);
  fun subseg4S((s1,s2,s3,s4), p, l) 
    (subseg(s1,p,l), subseg(s2,p,l), subseg(s3,p,l), subseg(s4,p,l));
  fun joinsegs4S((a1,a2,a3,a4), (b1,b2,b3,b4))
    (joinsegs(a1,b1), joinsegs(a2,b2), joinsegs(a3,b3), joinsegs(a4,b4));

rewindowS4S :: (Stream (Sigseg a * Sigseg b * Sigseg c * Sigseg d), Int, Int)
            ->  Stream (Sigseg a * Sigseg b * Sigseg c * Sigseg d);
rewindowS4S = {
  rewindowGeneral(null4S, start4S, width4S, subseg4S, joinsegs4S)
}


  nullL  = [];
  fun startL(ls) ls`head`start;
  fun widthL(ls) ls`head`width;
  fun subsegL(ls, p, l) {
    List:map(fun(ss) subseg(ss,p,l), ls)
  }
  fun joinsegsL(ls1, ls2) {
    if ls1 == []
    then ls2
    else if ls2 == []
    then ls1 
    else List:map2(fun(a,b) joinsegs(a,b), ls1, ls2)
  }

rewindowS4S :: (Stream (List (Sigseg a)), Int, Int) -> Stream (List (Sigseg a));
rewindowSLS = {
  rewindowGeneral(nullL, startL, widthL, subsegL, joinsegsL)
}

/*** Sample Main program ***/
/*
ch1 = (readFile("stdlib.ws", "mode: binary window: 10") :: Stream (Sigseg Int))

dummydetections = iterate(w in ch1) {
  state { pos = 0 }
  emit(true, pos, pos + 10 - 1);
  pos := pos + 10;
};

synced = syncN(dummydetections, [ch1, ch1, ch1, ch1]);

// Mike's approach, this works now:
/*
_synced = iterate(din in synced) {
  emit (List:ref(din,0),List:ref(din,1),List:ref(din,2),List:ref(din,3)) 
}
BASE <- rewindowS4S(_synced, 4096, 0)
*/

BASE <- rewindowSLS(synced, 4096, 0)
*/
