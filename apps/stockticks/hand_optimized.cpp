// Made the data source loop N times.

// Un-boosted the hash_map.
// Made the hash_map indexed by char* instead of string.


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
   
//   static SigSeg<complex> fft(SigSeg<float> input) {
//       /* Currently we just use the unitless timebase: */ 
//       Timebase _freq = Unitless;
//       SigSeg<float>* casted = &input;
      
//       /* alloc buffer for FFT */
//       Signal<complex> s = Signal<complex>(_freq);
//       complex *fft_buf = s.getBuffer(casted->length()/2);
//       float *fft_flt = (float *)fft_buf;

//       /* copy input over to output buffer */
//       float *cbuf = casted->getDirect();
//       memmove(fft_flt, cbuf, sizeof(float)*casted->length());
//       casted->release(cbuf);
      
//       /* do the fft */
//       FFT::realft(fft_flt-1, casted->length(), +1);

//       /* return the sigseg */
//       SigSeg<complex> output = s.commit(casted->length()/2);
//       delete casted;
//       return(output);
//   }


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

  
//   class WSDataFileSource : public WSSource {
//   public:
//     WSDataFileSource(wsstring_t path, wsstring_t mode, wsint_t repeats) {
//       _f = fopen(path.c_str(), "r");
//       if (_f == NULL) { chatter(LOG_CRIT, "Unable to open data file %s: %m", path); abort(); }
//       Launch();
//     }

//     DEFINE_SOURCE_TYPE(TimeTuple<struct tick>);

//   private:
//     FILE* _f;
//     void *run_thread() {
//       double time;
//       char symb[7];
//       float price;
//       int volume;

//       while (!Shutdown()) {
// 	int status = fscanf(_f, "%lf %s %f %d\n", &time, symb, &price, &volume);
// 	if (status != 4) {
// 	  chatter(LOG_WARNING, "Tick EOF encountered (status=%d).", status);
// 	  WSSched::stop();
// 	  return NULL;
// 	}

// 	TimeTuple <struct tick> t;
// 	t.time = (uint64_t)(time*1000000);
// 	strcpy(t.tuple.symb, symb);
// 	t.tuple.price = price;
// 	t.tuple.volume = volume;
// 	source_emit(t);
//       }
//       return NULL;
//     }
//   };
  
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

    vector<struct tuptyp_10> acc;
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
	printf("\n\nACCUMULATED SIZE: %d\n\n", acc.size());
	for(int j=0; j<249; j++) {
	  for(unsigned int i=0; i < acc.size(); i++) {
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
      acc.push_back(tup);
      count++;
    } 
    return NULL;} 
} 
;
class Iter_s_2 : public WSBox {
  public:
  WS_DEFINE_OUTPUT_TYPE(tuptyp_10);
  
  Iter_s_2() {
    ht_3 = hash_map< const char* , wsfloat_t >(300);
  }
  
  private:
  hash_map< const char* , wsfloat_t > ht_3; 
  
  /* WaveScript input type: (Struct tuptyp_10) */
  bool iterate(uint32_t portnum, void* datum) {
    /* Naturalize input type to meet expectations of the iterate-body. */
    tuptyp_10 pattmp_5 = *((tuptyp_10*) datum);
    wsstring_t sym_6 = (pattmp_5.fld1);

    const char* str = sym_6.c_str();

    wsfloat_t t_7 = (pattmp_5.fld2);
    wsint_t vol_8 = (pattmp_5.fld3);
    wsfloat_t price_9 = (pattmp_5.fld4);
    if (WSPrim::wsnot((ht_3)[str])) {
      (ht_3)[str] = 1.0;
    } else {
      tuptyp_12();
    }
    if (vol_8 == -1) {
      (ht_3)[str] = ((ht_3)[str] * price_9);
    } else {
      emit((tuptyp_10)tuptyp_10(sym_6, t_7, vol_8, (price_9 * (ht_3)[str])));
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
//     printf(".");
//     printf("WSOUT: ");
//     { tuptyp_10 tmp_18 = (*element);
//       cout << "{";
//     printf(tmp_18.fld1.c_str());
//       cout << "; ";
//     printf("%f", tmp_18.fld2);
//       cout << "; ";
//     printf("%d", tmp_18.fld3);
//       cout << "; ";
//     printf("%f", tmp_18.fld4);
//       cout << "}"; }
//     ;
//     printf("\n");

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
  WSBox* toplevel = s_2;

  /* dump output of query -- WaveScript type = (Signal (Struct tuptyp_10)) */
  PrintQueryOutput out = PrintQueryOutput("WSOUT");
  //out.connect(toplevel);

  /* now, run */
  WSRun();

  return 0;
}

