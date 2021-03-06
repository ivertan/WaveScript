
// In this version, we're exploring the concept of an "ExclusivePointer" type.

// Note: FIXME: I should either check the run-time tags on the matrices
// during all operations, or I should introduce distinct types for
// FloatMatrix ComplexMatrix, etc.  (Except the latter requires being
// *able* to introduce user defined data types... which I think I can
// right now.)

// Should use C++ preprocessor to generate all the variants.

include "stdlib.ws";
include "gsl.ws";

// Here's our lame enumeration... We need union types.
float_matrix  = 0;
double_matrix = 1;
complex_matrix = 2;
complexdouble_matrix = 3;

DEBUGMATRIX = true;

//uniontype FloatMatrix t = FM__ ();

/*
type MatrixContents = (Int * ExclusivePointer "void*" * ExclusivePointer "void*");
uniontype Matrix t = 
    FM_ MatrixContents | 
    DM_ MatrixContents |
    CM_ MatrixContents |
    CDM_ MatrixContents 
*/

//foo = FM__(());

// A pair containing a type tag, the struct pointer, and the array pointer.
type Matrix t = (Int * ExclusivePointer "void*" * ExclusivePointer "void*");
//type Matrix #n = (ExclusivePointer "void*" * ExclusivePointer "void*");

#define UNBOXBOTH(CTY, OP, OPNAME)            \
    fun OPNAME(mat1,mat2) {                    \
      /*assert(dims(mat1)==dims(mat2));*/       \
      let (tag1,m1,ar1) = mat1;                  \
      let (tag2,m2,ar2) = mat2;                   \
      /*assert(tag1==tag2);*/                      \
      gsl_matrix##CTY##_##OP(m1`getPtr, m2`getPtr); \
    }  

#define UNBOXFIRST(CTY, OP, OPNAME)         \
    fun OPNAME(mat1,arg2) {                  \
      let (tag1,m1,ar1) = mat1;               \
      gsl_matrix##CTY##_##OP(m1`getPtr, arg2); \
    }

#define MAKEPURE(WSTY, PURE, IMPURE) \
    fun PURE(x,y) {                   \
      cop = Matrix:WSTY:copy(x);       \
      Matrix:WSTY:IMPURE(cop,y);        \
      cop                                \
    }                                     

#define BASIC(CTY, WSTY, TAG)                             \
    /* Hmm... initialize how? */                           \
    create :: (Int,Int) -> Matrix WSTY;                     \
    fun create(n,m) {                                        \
      p   = exclusivePtr $ gsl_matrix##CTY##_alloc(n,m);      \
      arr = exclusivePtr $ gsl_matrix##CTY##_data(getPtr(p));  \
      gsl_matrix##CTY##_set_zero(p`getPtr);                     \
      (TAG, p, arr)                                              \
    }                                                             \
                                                                   \
    /* These could be implemented by directly using the array: */   \
    get  :: (Matrix WSTY, Int, Int)       -> WSTY;                   \
    set  :: (Matrix WSTY, Int, Int, WSTY) -> ();                      \
    dims :: (Matrix WSTY)                 -> (Int * Int);              \
                                                                        \
    fun set((_,mat,_),i,j,x)  gsl_matrix##CTY##_set(mat`getPtr, i,j, x); \
    fun dims((_,mat,_)) {                         \
      let y = gsl_matrix##CTY##_size1(mat`getPtr); \
      let x = gsl_matrix##CTY##_size2(mat`getPtr);  \
      { (y,x) } \
    };        \
               \
    fun get(m,i,j)  {                     \
      let (_,mat,_) = m;                   \
      if DEBUGMATRIX then {                 \
        let (r,c) = Matrix:WSTY:dims(m);     \
        assert("matrix get, inds "++ i ++","++ j ++" dims "++ (r,c), i<r && j<c); \
      };                                       \
      gsl_matrix##CTY##_get(mat`getPtr, i,j);   \
    }                                            \
                                         \
    fun copy(mat1) {                      \
      let (r,c) = Matrix:WSTY:dims(mat1);  \
      let mat2  = Matrix:WSTY:create(r,c);  \
      let (_,m1,_) = mat1;                   \
      let (_,m2,_) = mat2;                    \
      gsl_matrix_memcpy(m2`getPtr, m1`getPtr); \
      mat2     \
    }           \
                 \
    fun eq(m1,m2) \
    Matrix:WSTY:dims(m1) == Matrix:WSTY:dims(m2) && \
    { i = ref(0);                    \
      j = ref(0);                     \
      stilleq = ref(true);             \
      let (r,c) = Matrix:WSTY:dims(m1); \
      while i < r && stilleq {           \
        while j < c && stilleq {          \
	  if Matrix:WSTY:get(m1,i,j) !=    \
             Matrix:WSTY:get(m2,i,j)        \
	  then stilleq := false;             \
	  j += 1;  \
	};          \
	i += 1;      \
      };              \
      stilleq          \
    }                   \
                         \
                          \
    UNBOXBOTH(CTY, add, add_inplace)                 \
    UNBOXBOTH(CTY, sub, sub_inplace)                  \
    UNBOXBOTH(CTY, mul_elements, mul_elements_inplace) \
    UNBOXBOTH(CTY, div_elements, div_elements_inplace)  \
    UNBOXFIRST(CTY, scale, scale_inplace)                \
    UNBOXFIRST(CTY, add_constant, add_constant_inplace)   \
                                                           \
    MAKEPURE(WSTY, add, add_inplace)                 \
    MAKEPURE(WSTY, sub, sub_inplace)                  \
    MAKEPURE(WSTY, mul_elements, mul_elements_inplace) \
    MAKEPURE(WSTY, div_elements, div_elements_inplace)  \
    MAKEPURE(WSTY, scale, scale_inplace)                 \
    MAKEPURE(WSTY, add_constant, add_constant_inplace)    \


// These are operations built on top of the basic interface:
#define BUILTONTOP(WSTY)                    \
 fun build(r,c, f) {                         \
      /* Should be createUNSAFE */            \
      mat = Matrix:WSTY:create(r, c);          \
      for i = 0 to r-1 {                        \
        for j = 0 to c-1 {                       \
	  Matrix:WSTY:set(mat, i, j, f(i,j))      \
	}                                          \
      };                                            \
      mat                                            \
   }                                                  \
                                                       \
 /* This is temporary, we can't pass arrays yet, but we can do this */ \
 fun toArray(mat) {                           \
      let (rows,cols) = Matrix:WSTY:dims(mat); \
      arr = Array:makeUNSAFE(rows * cols);      \
      for i = 0 to rows-1 {                      \
      for j = 0 to cols-1 {                       \
	  Array:set(arr, j + i*cols, Matrix:WSTY:get(mat,i,j)) \
	} \
      };   \
      arr   \
 }           \
              \
 /* This is temporary, we can't pass arrays yet, but we can do this */ \
 fun row(mat, i) {                                \
      let (r,c) = Matrix:WSTY:dims(mat);           \
      arr = Array:makeUNSAFE(c);                    \
      for j = 0 to c-1 {                             \
	Array:set(arr, j, Matrix:WSTY:get(mat,i,j))   \
      };    \
      arr    \
 }            \
               \
 fun col(m,j) { \
   let (r,c) = Matrix:WSTY:dims(m); \
   arr = Array:makeUNSAFE(r);        \
   for i = 0 to r-1 {                 \
     arr[i] := Matrix:WSTY:get(m,i,j); \
   };                                   \
   arr      \
 }           \
              \
 fun fromArray(arr, rowlen) {     \
      len = Array:length(arr);     \
      rows = len / rowlen;          \
      if (len != rowlen * rows)      \
      then wserror("fromArray: array length "++ len ++" is not divisible by "++ rowlen ++". Cannot convert to matrix."); \
      mat = Matrix:WSTY:create(rowlen, rows);        \
      for j = 0 to rows-1 {                           \
        for i = 0 to rowlen-1 {                        \
	  Matrix:WSTY:set(mat, i, j, arr[i + j*rowlen]) \
	} \
      };   \
      mat   \
    }        \
              \
 fun fromList2d(ls) {           \
   r   = List:length(ls);        \
   c   = List:length(ls`head);    \
   mat = Matrix:WSTY:create(r, c); \
   for i = 0 to r-1 {      \
     for j = 0 to c-1 {     \
       /* Inefficient... */  \
       Matrix:WSTY:set(mat, i,j, List:ref(List:ref(ls,i), j)); \
     } \
   };   \
   mat   \
 }        \
           \
 fun fromArray2d(arr) {         \
   r   = Array:length(arr);      \
   c   = Array:length(arr[0]);    \
   mat = Matrix:WSTY:create(r, c); \
   for i = 0 to r-1 {      \
     for j = 0 to c-1 {     \
       Matrix:WSTY:set(mat, i,j, Array:ref(arr[i], j)); \
     } \
   };   \
   mat   \
 }        \
           \
 fun rowmap(f, m) {                                    \
  let (rows,_) = Matrix:WSTY:dims(m);                   \
  Array:build(rows, fun(i) f(Matrix:WSTY:row(m,i)))      \
 }                                                        \
 fun map(f, mat) {                                         \
   let (r,c) = Matrix:WSTY:dims(mat);                       \
   Matrix:WSTY:build(r,c, fun(i,j) Matrix:WSTY:get(mat,i,j)) \
 }                                                            \
 fun map2(f, mat1,mat2) {                                      \
   let (r,c) = Matrix:WSTY:dims(mat1);                         \
   Matrix:WSTY:build(r,c, fun(i,j) f(Matrix:WSTY:get(mat1,i,j), Matrix:WSTY:get(mat2,i,j))) \
 }  



// One day we could do this with type classes.
#define INVERT(CTY, WSTY)               \
    fun invert(mat) {                    \
      let (tag,m1,d1) = mat;              \
      let (x,y)   = Matrix:WSTY:dims(mat); \
      let mat2 = Matrix:WSTY:create(x,y);   \
      let (tag,m2,d2) = mat2;                \
      let perm = nullperm(x);                 \
        /* Do the work: */                     \
        gsl_linalg##CTY##_LU_invert(m1`getPtr, perm, m2`getPtr); \
	Cfree(perm);               \
	mat2 \
    }

#define MULT(BLASPREC, WSTY, CONST)   \
    fun mul(mat1,mat2) {               \
      let (_,m1,d1) = mat1;             \
      let (_,m2,d2) = mat2;              \
      let (r,c) = Matrix:WSTY:dims(mat1); \
      let mat3 = Matrix:WSTY:create(r,c);  \
      let (tg,m3,d3) = mat3;                \
      /* Check return value? */              \
      gsl_blas_##BLASPREC##gemm(Matrix:noTrans(), Matrix:noTrans(), CONST 1.0, m1`getPtr, m2`getPtr, CONST 0.0, m3`getPtr); \
      mat3                                     \
    }

namespace Matrix {

  noTrans = nulltranspose;

  namespace Float {
    BASIC(_float, Float, float_matrix)
   // inversion Apparently not implemented for single precision...
    MULT(s, Float, )
    BUILTONTOP(Float)
   }

  namespace Double {
    BASIC(, Double, double_matrix)
    INVERT(, Double)
    MULT(d, Double, floatToDouble$ )
    BUILTONTOP(Double)
  }

  // We don't support complex numbers in the FFI yet! 
  namespace Complex {
    BASIC(_complex_float, Complex, complex_matrix)
//    INVERT(_complex_float, Complex) // WHY IS THIS NOT DEFINED?
    BUILTONTOP(Complex)
  }

  //  namespace ComplexDouble {} 
  
  namespace Generic {

    // A generic inversion routine:
    fun invert(mat) {
      let (tag,_,_) = mat;
      //if tag == float_matrix
      //then Matrix:Float:invert(mat) else
      if tag == double_matrix
      then Matrix:Double:invert(mat) else
      //    if tag == complex_matrix
      //    then Matrix:Complex:invert(mat) else
      //    if tag == complexdouble_matrix
      //    then Matrix:ComplexDouble:invert(mat)
      wserror("Unrecognized matrix type tag: "++tag)
    }
    
#define ALLGENERIC2(OP) \
    fun OP(mat1, arg2) {      \
      let (tag,_,_) = mat1;      \
      if tag == float_matrix    \
      then Matrix:Float:OP(mat1,arg2) else   \
      if tag == double_matrix   \
      then Matrix:Double:OP(mat1,arg2) else  \
      if tag == complex_matrix  \
      then Matrix:Complex:OP(mat1,arg2) else \
/*      if tag == complexdouble_matrix */  \
/*      then Matrix:ComplexDouble:OP(mat) else */ \
      wserror("Unrecognized matrix type tag: "++tag) \
    }

ALLGENERIC2(add)
ALLGENERIC2(sub)
ALLGENERIC2(mul_elements)
ALLGENERIC2(div_elements)
  //ALLGENERIC2(scale)
  //ALLGENERIC2(add_constant)


    /*fun foo(mat) {
      let (tag,_,_) = mat;
      if tag == float_matrix
      then Float:foo(mat) else
      if tag == double_matrix
      then Double:foo(mat) else
      if tag == complex_matrix
      then Complex:foo(mat) else
      if tag == complexdouble_matrix
      then ComplexDouble:foo(mat)
      wserror("Unrecognized matrix type tag: "++tag)
    }*/

  }
}
