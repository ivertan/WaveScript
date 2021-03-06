

// [2007.11.13]
// Doing a little timing on faith.
//  ws.opt takes 12.8 seconds to go through my multinode48khz dataset and do one detection.
//  mlton O2 takes 1.25/1.2 real/user
//  wsc.new -t O2 takes 5.5/4.6 sec (and you know, that's without thread safety disabled)
//    In O3 it takes ~5.2/4.3... or 5.0/4.2
//    Btw... this spends serious time in DOA fuse.

// Running -n 2 on awd... 
//   with -j 1 I get 2.3s
//   with -j 2 I get 5.2s
// Trying with global driver.

LOG_TIMING = 255;
// from elog.h in emstar
LOG_EMERG = 0;       /**< system is unusable */
LOG_ALERT = 1;       /**< action must be taken immediately */
LOG_CRIT = 2;      /**< critical conditions */
LOG_ERR = 3;      /**< error conditions */
LOG_WARNING = 4;       /**< warning conditions */
LOG_NOTICE = 5;      /**< normal but significant condition */
LOG_INFO = 6;      /**< informational */
LOG_DEBUG_0 = 7;       /**< debug */
LOG_OFF =  -1;	/**< don't emit log messages */
LOG_UNDEFINED = -2;      /**< loglevel not specified */


// GLOBAL CONSTANTS:


// When we're not live we just print log messages to the stream.
fun log(l,s) print(s++"\n");
fun timer_source(_,t) timer(1000.0 / t`intToFloat)

// Also need a dummy for this:
fun vxp_buffer_time_remaining() 0.0

include "stdlib.ws";
include "gnuplot.ws";


samp_rate = 48000.0; // HACK - we should get this from the stream/timebase/sigseg
winsize = 4 * 4096;

include "nodelocs.ws";
//nodes = [node1, node2, node3, node4, node5, node6, node7, node8]
nodes = [node1, node2, node3, node4]
//nodes = [node1, node2]
//nodes = nodels

/*
nodes = 
  [
   (100, -0.700000, 14107.000732, 13.200000)
   ,(103, -4106.700134, 12947.200012, 20.299999)
   ,(104, 1420.499992, 10212.300110, -10.700000)
   ,(108, -3468.399811, 9284.500122, 4.500000)
   ,(109, 773.099995, 6791.600037, -161.100006)
   ,(113, 0.000000, 0.000000, -10.100000)
   ,(112, -5601.399994, 4740.200043, -9.200000)
    //(115, -4438.600159, -516.499996, 10.800000),
   ]
*/

// ================================================================================

// NOW LOAD MARMOT CODE:

include "marmot_first_phase.ws";
include "marmot2.ws";
include "marmot_heatmap.ws";

axes :: (Float * Float * Float * Float);
axes = auto_axes(nodes)

// AUTO GRID SIZE:
desired_min_pixel_dimm = if EVILHACKS then 100 else 300
grid_scale = {
  let (xmin, xmax, ymin, ymax) = axes;
  min(absF(xmax - xmin) / desired_min_pixel_dimm`i2f,
      absF(ymax - ymin) / desired_min_pixel_dimm`i2f)
}


//================================================================================

globaldriver = timer(samp_rate * 4.0 / winsize`i2f);

fun read_audio((id, _,_,_)) {
  fn = "multinode48khz/"++id++".raw";
  
  //driver = timer(samp_rate * 4.0 / winsize`i2f);
  driver = globaldriver;
  chans = (readFile(fn, "mode: binary window: "++winsize, driver) :: Stream Sigseg (Int16));

  fun onechan(offset)
    iterate w in chans {
      size = w`width / 4;
      assert_eq("source stream multiple of 4", w`width, size * 4);
      arr = Array:build(size, fun (i) (w[[(i*4) + offset]]));
      emit toSigseg(arr, w`start / 4`intToInt64 , w`timebase)
  };
  
  (onechan(0), onechan(1), onechan(2), onechan(3))  
  //[onechan(0), onechan(1), onechan(2), onechan(3)]
}

tag :: List (Stream t) -> List (Stream (NodeRecord * t));
fun tag(sls) 
  map(fun((node,strms))
      stream_map(fun(x) (node,x) ,strms),
      List:zip(nodes,sls))

//================================================================================

// Main query:

//alldata :: List (List (Stream (Sigseg t)));
alldata = map(read_audio, nodes)
// Synced data from each node
alldetections = map(detector, alldata)

//tagged = tag(detections);

fun assignCPU(ind) {
/*   if NUMTHREADS=1  */
/*   then 0 */
/*   else moduloI(ind, NUMTHREADS-1) + 1 */
  ind+1
}

// AML results from each node.
allamls :: List (Stream AML);
allamls = List:mapi(fun(ind, ((id,_,_,yaw),strm))
	      //                maybe_graph_aml(id, yaw, 
		    SETCPUDEEP(assignCPU(ind),
		     smap(normalize_aml, oneSourceAMLTD(strm, 4096))),
//	             oneSourceAMLTD(strm, 4096),
              List:zip(nodes,alldetections))

merged :: Stream (Tagged AML);
merged = List:fold1(fun (x,y) merge(x,y), tag(allamls))
clusters :: Stream (List (Tagged AML));
clusters = temporal_cluster_amls(3, merged);
heatmaps :: Stream LikelihoodMap;
heatmaps = stream_map(fun(x) doa_fuse(axes,grid_scale,x), clusters);

ignored = draw_multi_amls(nodes,allamls)
ignored2 = draw_multi_detections(nodes,alldetections)

BASE <- 
merged
////merge(merge(ignored,ignored2),
//      common_backend(heatmaps, axes, grid_scale)
////      )
