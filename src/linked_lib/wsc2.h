

// [2007.12.06] This is the header that goes with my new C backend. -Ryan

// Headers that we need for the generated code:
#include<stdio.h>
#include<stdlib.h>
#include<string.h>
#include<math.h>
#include <time.h>
#include <sys/time.h>
#include <sys/resource.h>
#include<getopt.h>

#define LOAD_COMPLEX
//#define ALLOC_STATS


#ifdef LOAD_COMPLEX
#include<complex.h>
#endif

#define TRUE  1
#define FALSE 0

//#define ws_unit_t char
//#define ws_char_t char
//#define ws_bool_t char
//#define uint8_t unsigned char

typedef char ws_char_t;
typedef char ws_bool_t;
typedef char ws_unit_t;

typedef unsigned char      uint8_t;
typedef unsigned short int uint16_t;
//typedef unsigned int16_t uint16_t;

#define ws_string_t char*

#define PTRSIZE sizeof(void*)
#define ARRLENSIZE sizeof(int)

#include <locale.h>
char* commaprint(unsigned long long n);

#ifdef USE_BOEHM
  #include <gc/gc.h>
  #define BASEMALLOC GC_MALLOC
  inline void* gc_calloc(size_t count, size_t size) {
    size_t bytes = count*size;
    void* ptr = GC_MALLOC(bytes);
    bzero(ptr, bytes);
    return ptr;
  }
  #define BASECALLOC gc_calloc
  #define BASEFREE   free
  // If we are using BOEHM we do not need refcounts:
  #define RCSIZE 0
  #define ARRLENOFFSET -1
#else
  #define BASEMALLOC malloc
  #define BASECALLOC calloc
  #define BASEFREE   free
  #define RCSIZE sizeof(int)
  #define ARRLENOFFSET -2
#endif


// These macros allow us to monitor allocation rates if we wish:
#ifdef ALLOC_STATS
unsigned long long alloc_total = 0;
unsigned long long alloc_counter = 0;
unsigned long long free_counter = 0;
inline void* malloc_measured(size_t size) {
  alloc_total   += size;
  alloc_counter += 1;
  return BASEMALLOC(size);
}
inline void* calloc_measured(size_t count, size_t size) {
  alloc_total += size * count;
  alloc_counter += 1;
  return BASECALLOC(count,size);
}
inline void free_measured(void* object) {
  free_counter += 1;
  BASEFREE(object);
}
#define WSMALLOC malloc_measured
#define WSCALLOC calloc_measured
#define WSFREE   free_measured
#else
#define WSMALLOC BASEMALLOC
#define WSCALLOC BASECALLOC
#define WSFREE   BASEFREE
#endif

// Handle RCs on BOTH Cons Cells and Arrays:
// A RC is the size of an int currently:
#define CLEAR_RC(ptr)                ((int*)ptr)[-1] = 0
#define INCR_RC(ptr)        if (ptr) ((int*)ptr)[-1]++
#define DECR_RC_PRED(ptr) (ptr && --(((int*)ptr)[-1]) == 0)
#define GET_RC(ptr)                  ((int*)ptr)[-1]

// Handle Cons Cell memory layout:
// Cell consists of [cdr] [RC] [car]
#define CONSCELL(ty)   (void*)((char*)WSMALLOC(PTRSIZE+RCSIZE + sizeof(ty)) + PTRSIZE+RCSIZE);
#define CAR(ptr)       (*ptr)
#define CDR(ptr)       (*(void**)(((char*)ptr) - (PTRSIZE+RCSIZE)))
#define SETCDR(ptr,tl) (((void**)(((char*)ptr) - (PTRSIZE+RCSIZE)))[0])=tl
#define SETCAR(ptr,hd) ptr[0]=hd
#define FREECONS(ptr)  WSFREE((char*)ptr - sizeof(void*) - sizeof(int))

// This was from when RC's where the same size as a void* pointer:
//#define CDR(ptr)       (((void**)ptr)[-2])
//#define SETCDR(ptr,tl) (((void**)ptr)[-2])=tl

// Handle Array memory layout:
// An array consists of [len] [RC] [elem*]
// Both len and RC are currently ints:
#define ARRLEN(ptr)        (ptr ? ((int*)ptr)[ARRLENOFFSET] : 0)
//#define ARRLEN(ptr)        ((int*)ptr)[-2]
// This should not be used on a null pointer:
#define SETARRLEN(ptr,len) ((int*)ptr)[ARRLENOFFSET]=len

#define ARRLEN(ptr)        (ptr ? ((int*)ptr)[ARRLENOFFSET] : 0)
// Get a pointer to the *start* of the thing (the pointer to free)
#define ARRPTR(ptr)        (((void**)ptr) + ARRLENOFFSET)
#define FREEARR(ptr)       WSFREE(ARRPTR(ptr))

// This is not currently used by the code generator [2008.07.02], but can be used by C code.
//#define WSARRAYALLOC(len,ty) ((void*)((char*)calloc(ARRLENSIZE+RCSIZE + (len * sizeof(ty)), 1) + ARRLENSIZE+RCSIZE))
#define WSARRAYALLOC(len,ty) (ws_array_alloc(len, sizeof(ty)))
#define WSSTRINGALLOC(len)   (ws_array_alloc(len, sizeof(ws_char_t)))

inline void* ws_array_alloc(int len, int eltsize) {
  char* ptr = ((char*)WSMALLOC(ARRLENSIZE + RCSIZE + len*eltsize)) + ARRLENSIZE+RCSIZE;
  SETARRLEN(ptr, len);
#ifndef USE_BOEHM
  CLEAR_RC(ptr);
#endif
  return ptr;
}

#define moduloI(a,b) (a % b)

int outputcount = 0;
int wsc2_tuplimit = 10;

#ifdef ALLOC_STATS
unsigned long long last_alloc_printed = 0;
void ws_alloc_stats() {
  printf("  Malloc calls: %s\n", commaprint(alloc_counter));
  printf("  Free   calls: %s", commaprint(free_counter));
  printf("\t\t Unfreed objs: %s\n", commaprint(alloc_counter-free_counter));
  printf("  Total bytes allocated: %s\n",  commaprint(alloc_total));
  printf("  Bytes since last stats: %s\n", commaprint(alloc_total - last_alloc_printed));
  last_alloc_printed = alloc_total;
}
#endif

void wsShutdown() {
  #ifdef ALLOC_STATS
    ws_alloc_stats();
  #endif
}

void BASE(char x) { 
  outputcount++;
  if (outputcount == wsc2_tuplimit) { wsShutdown(); exit(0); }
#ifdef ALLOC_STATS
  ws_alloc_stats();
#endif
  fflush(stdout);
}

void ws_parse_options(int argc, char** argv) {
  int i, c;
  while ((c = getopt(argc, argv, "n:")) != -1) {
    //printf("Parsing option character: %c\n", c);
	switch (c) {
	case 'n':
	        wsc2_tuplimit = atoi(optarg);
		break;
	// case 's': // Do not print main stream output tuples.
	default:
	  //		usage();
	  //		return 1;
		break;
	}
  }
}

// FIXME: When driven by foreign source we don't use this:
void wserror_fun(char* msg) {
  //error(msg);
  printf("Failed with error: %s\n", msg);
  exit(-1);
}
#define wserror_wsc2(str) wserror_fun(str);

/*
// TODO:
int Listlength(void* list) {
  int acc = 0;
  printf("List len... %p\n", list);
  while (list != 0) {
    list = CDR(list);
    acc++;
  }
  return acc; 
}
*/

/*
// TODO:
void* Listappend(void* ls1, void* ls2) {
  printf("List append... %p and %p\n", ls1, ls2);
  return ls1;
}

// TODO:
void* Listreverse(void* ls) {
  printf("List reverse... %p\n", ls);
  return ls;
}
*/


// This won't work:
/*
int Listref(void* list, int n) {
  return 0; 
}
*/


char *commaprint(unsigned long long n)
{
	static int comma = '\0';
	static char retbuf[30];
	char *p = &retbuf[sizeof(retbuf)-1];
	int i = 0;

	if(comma == '\0') {
		struct lconv *lcp = localeconv();
		if(lcp != NULL) {
			if(lcp->thousands_sep != NULL &&
				*lcp->thousands_sep != '\0')
				comma = *lcp->thousands_sep;
			else	comma = ',';
		}
	}

	*p = '\0';

	do {
		if(i%3 == 0 && i != 0)
			*--p = comma;
		*--p = '0' + n % 10;
		n /= 10;
		i++;
	} while(n != 0);

	return p;
}


#ifdef LOAD_COMPLEX
inline static float cNorm(complex c) {
   float re =  __real__ (c);
   float im =  __imag__ (c);
   return sqrt ((re*re) + (im*im));
}
#endif

