// Got 8.27 seconds for 5 million tuples. (with FIFO)
// Got 7.359 on justice w/depthfirst

// Weird 4.6s on faith after changing vector to plain array... and the machine's under load!
// 5.4s on justice...

// Removed the tuple copy and got down to 3.87 on faith (fifo). (still one processor loaded)
// With -O3 this is back up to 4.25
// Got it down to 3.6 by manually "interning" the string.

// I also changed the output of the box to just a float (not another
// tuple) and that still didn't help at all.

// Note: it takes .3 seconds to spool the data out if we just run the datasource.

//----------------------------------------

// These are the headers & #defines that occur at the beginning of all
// wavescript-generated header files.
#include <WaveScope.h>
#include <Heartbeat.hpp>
#include <PrintBox.hpp>
#include <RawFileSource.hpp>
#include <AsciiFileSink.hpp>
#include <Boxes.hpp>

/* for boost smart pointers */
#include <boost/shared_ptr.hpp>
#include <boost/enable_shared_from_this.hpp>

#include <boost/functional/hash.hpp>

#include <stdio.h>
#include <list>
#include <vector>
#include <string>
#include <ext/hash_map>

using boost::enable_shared_from_this;
using namespace std;
using namespace __gnu_cxx;

#define TRUE 1
#define FALSE 0

#define WSNULL 0
#define WSNULLSEG (RawSeg::NullRef)

typedef int wsint_t;
typedef double wsfloat_t;
typedef bool wsbool_t;
typedef string wsstring_t;

#define WS_DEFINE_OUTPUT_TYPE(type)                \
  inline void emit(const type &tuple) {         \
    uint i;                                     \
    for (i=0; i<m_outputs.size(); i++) {        \
      m_outputs[i]->enqueue(new type (tuple), this);  \
    } \
    totalEmits++; \
  }

/*
#define WS_DEFINE_OUTPUT_TYPE(type)                \
  inline void emit(const type &tuple) {         \
    uint i;                                     \
    for (i=0; i<m_outputs.size(); i++) {        \
      m_outputs[i]->enqueue(new type (tuple), this);  \
    } \
    totalEmits++; \
  } \
  void freeTuple(void *tuple) { \
  type *tuplePtr = (type *)tuple; \
  delete tuplePtr; \
  } 
*/


/******** LISTS ********/
template <class T>
class cons {
public: 
  typedef boost::shared_ptr< cons<T> > ptr;
  cons(T a, ptr b) {
    car = a;
    cdr = b;
  }
  T car;
  ptr cdr;

  //  static ptr null;  //    = ptr((cons<T>*)0);
};

// We construct a single null object which we cast to what we need.
cons<int>::ptr NULL_LIST = cons<int>::ptr((cons<int>*)0);



// This defines the WaveScript primitives that the code generated by
// the WaveScript compiler depends upon.
 class WSPrim {

   public:

   inline static wsbool_t wsnot(wsbool_t b) {
     return (wsbool_t)!b;
   }

   static wsint_t width(const RawSeg& w) {
     return (wsint_t)w.length();
   }
   static wsint_t start(const RawSeg& w) {
     return (wsint_t)w.start();
   }
   static wsint_t end(const RawSeg& w) {
     return (wsint_t)w.end();
   }

   static RawSeg joinsegs(const RawSeg& a, const RawSeg& b) {
     return RawSeg::append(a,b);
   }
   // Currently takes start sample number (inclusive) and length.
   // TODO: Need to take SeqNo for start!
   static RawSeg subseg(const RawSeg& ss, wsint_t start, wsint_t len) {
     uint32_t offset = (uint32_t)((SeqNo)start - ss.start());
     //return ss.subseg(offset, offset+len);
     return RawSeg::subseg(ss, offset, len); // INCONSISTENT DOCUMENTATION! FIXME!
   }
      
   static wsstring_t stringappend(const wsstring_t& A, const wsstring_t& B) {
     return A+B;
   }

   // Simple hash function, treat everything as a block of bits.
   static size_t generic_hash(unsigned char* ptr, int size) {
     size_t hash = 5381;
     int c;
     for(int i=0; i<size; i++) 
       hash = ((hash << 5) + hash) + ptr[i]; /* hash * 33 + c */	 	 
     return hash;
   }   
   
   // Optimized version, unfinished.
   /*
   static unsigned long hash(unsigned char* ptr, int size) {
     int stride = sizeof(unsigned long);
     unsigned long hash = 5381;
     unsigned long* chunked = (unsigned long*)ptr;
     int rem = size % stride;
     for (int i=0; i < size/stride; i++) {
       hash = ((hash << 5) + hash) + chunked[i];
     }
     for (int i=0; i < rem; i++) {
       //FINISH
     }
     return hash;
   }
   */

};



// These are built-in WSBoxes. 
// Most of these are intended to go away at some point.
class WSBuiltins {
   
   /* Zip2 operator: takes 2 input streams of types T1 and T2 and emits zipped
      tuples, each containing exactly one element from each input stream. */
   template <class T1, class T2> class Zip2: public WSBox {
   public:
     Zip2< T1, T2 >() : WSBox("zip2") {}
  
     /* Zip2 output type */
     struct Output
     {
       T1 _first;
       T2 _second;
    
       Output(T1 first, T2 second) : _first(first), _second(second) {}
       friend ostream& operator << (ostream& o, const Output& output) { 
	 cout << "< " << output._first << ", " << output._second << " >"; return o; 
       }
     };

   private:
     DEFINE_OUTPUT_TYPE(Output);
  
     bool iterate(uint32_t port, void *item)
     {
       m_inputs[port]->requeue(item);

       bool _e1, _e2; /* indicates if elements available on input streams */
       _e1 = (m_inputs[0]->peek() != NULL); _e2 = (m_inputs[1]->peek() != NULL);
    
       while(_e1 && _e2) {
	 T1* _t1 = (T1*)(m_inputs[0]->dequeue()); 
	 T2* _t2 = (T2*)(m_inputs[1]->dequeue()); 
	 emit(Output(*_t1, *_t2)); /* emit zipped tuple */
	 delete _t1; delete _t2;
	 _e1 = (m_inputs[0]->peek() != NULL); _e2 = (m_inputs[1]->peek() != NULL);
       }
       return true;
     }
   };


};
/* These structs represent tuples in the WS program. */
struct tuptyp_12 {
  tuptyp_12() {}
} 
;

struct tuptyp_10 {
  wsstring_t fld1;
  wsfloat_t fld2;
  wsint_t fld3;
  wsfloat_t fld4;
  tuptyp_10() {}
  tuptyp_10(wsstring_t tmp_17, wsfloat_t tmp_16, wsint_t tmp_15, wsfloat_t tmp_14) :
    fld1(tmp_17), 
    fld2(tmp_16), 
    fld3(tmp_15), 
    fld4(tmp_14) {}
} 
;


class WSDataFileSource_13 : public WSSource {
  public:
  WSDataFileSource_13(wsstring_t path, wsstring_t mode, wsint_t repeats) {
    _f = fopen(path.c_str(), "r");
    if (_f == NULL) {
      chatter(LOG_CRIT, "Unable to open data file %s: %m", path.c_str());
      abort();
    }
    Launch();
  }
  
    DEFINE_SOURCE_TYPE(struct tuptyp_10);
  
  private:
    FILE* _f;

    //vector<struct tuptyp_10> acc;
    tuptyp_10 acc[3000];
    unsigned int totalread;
    int count;

  void *run_thread() {
    while (!Shutdown()) {
      struct tuptyp_10 tup;
      
      // Cap of a 100 on length of read strings:
      char str1[100];
      int status = fscanf(_f, "%s %lf %d %lf", str1, &(tup.fld2), &(tup.fld3), &(tup.fld4));
      tup.fld1 = str1;
      if (status != 4) {
        chatter(LOG_WARNING, "dataFile EOF encountered (status=%d).", status);
	//printf("\n\nACCUMULATED SIZE: %d\n\n", acc.size());
	printf("\n\nACCUMULATED SIZE: %d\n\n", totalread);
	for(int j=0; j<2499; j++) {
	  for(unsigned int i=0; i < totalread; i++) {
	    source_emit(acc[i]);
	    count++;
	  }
	}
	printf("Finished repeating... total output %d\n", count);
        WSSched::stop();
        return NULL;
      }
      source_emit(tup);
      //      acc[i] = tup;
      //acc.push_back(tup);      
      acc[totalread] = tup;
      totalread++;
      count++;
    } 
    return NULL;} 
} 
;
class Iter_s_2 : public WSBox {
  public:
  //WS_DEFINE_OUTPUT_TYPE(tuptyp_10);
  WS_DEFINE_OUTPUT_TYPE(wsfloat_t);
  
  Iter_s_2() {
    //ht_3 = hash_map< wsstring_t, wsfloat_t, boost::hash<string> >(300);
    ht_3 = hash_map< size_t, wsfloat_t >(300);
  }
  
  private:
  hash_map< size_t, wsfloat_t > ht_3;
  //hash_map< wsstring_t, wsfloat_t, boost::hash<string> > ht_3;
  
  /* WaveScript input type: (Struct tuptyp_10) */
  bool iterate(uint32_t portnum, void* datum) {
    /* Naturalize input type to meet expectations of the iterate-body. */
    //tuptyp_10 pattmp_5 = *((tuptyp_10*) datum);
    tuptyp_10* casted = ((tuptyp_10*) datum);
    wsstring_t sym_6 = (casted->fld1);
    
    // EXPERIMENT: assume the hash *IS* the key (no collisions): (interned)
    //boost::hash< wsstring_t > hshfun;
    //size_t hsh = hshfun(sym_6);
    // Super DEGENERATE hash!
    size_t hsh = (size_t)sym_6[0];

    wsfloat_t entry = (ht_3)[hsh];
    wsint_t vol_8 = (casted->fld3);
    wsfloat_t price_9 = (casted->fld4);

    if (!(entry)) {
      (ht_3)[hsh] = 1.0;
      entry = 1.0;
    }
    if (vol_8 == -1) {
      (ht_3)[hsh] = (entry * price_9);
    } else {
      wsfloat_t t_7 = (casted->fld2);
      //emit((tuptyp_10)tuptyp_10(sym_6, t_7, vol_8, (price_9 * entry)));
      emit(price_9 * entry);
    }
    return FALSE;
  }
} 
;


class PrintQueryOutput : public WSBox {
  public:
  PrintQueryOutput(const char *name) : WSBox("PrintQueryOutput") {}
  
  private:
  DEFINE_NO_OUTPUT_TYPE;
  
  bool iterate(uint32_t port, void *input) {
    tuptyp_10 *element = (tuptyp_10 *)input;
    printf("WSOUT: ");
    { tuptyp_10 tmp_18 = (*element);
      cout << "{";
    printf(tmp_18.fld1.c_str());
      cout << "; ";
    printf("%f", tmp_18.fld2);
      cout << "; ";
    printf("%d", tmp_18.fld3);
      cout << "; ";
    printf("%f", tmp_18.fld4);
      cout << "}"; }
    ;
    printf("\n");
    delete element;
    return false;
  } 
} 
;



int main(int argc, char ** argv)
{
  /* initialize subsystems */ 
  WSInit(&argc, argv);

  /* declare variable to hold final result */
  //WSBox* toplevel;

  /* begin constructing operator graph */
  WSSource* merged_1 = new WSDataFileSource_13("ticks_splits.input", "text", -1);

  WSBox* s_2 = new Iter_s_2();
  s_2->connect(merged_1); 

  /* dump output of query -- WaveScript type = (Signal (Struct tuptyp_10)) */
  //PrintQueryOutput out = PrintQueryOutput("WSOUT");
  //  out.connect(toplevel);

  /* now, run */
  WSRun();

  return 0;
}

