;;; RRN: this file needs some serious cleaning-out.  The .NET compiler doesn't;;
;;; use a lot of the stuff in here.                                           ;;
;==============================================================================;

;(define region-primitives)
;(define anchor-primitives)

(define regiment-basic-primitives 
  '(cons car cdr 
	 + - * / < > = 
	 ))

(define regiment-distributed-primitives 
  '(rmap rfold smap time-of
	 circle circle-at anchor anchor-at anchor-where k-neighborhood time
	 cluster sparsify border planarize treeize filter union intersect
	 until when when-any when-percentage
	 sense neighbors ))
  
;;; 2004.03.31 - I don't know what the system's going to be called so
;;; I'm using the placeholder "blanko" which I will replace later. 
;;; OK, replacing with "regiment"
(define regiment-primitives
  (append regiment-basic-primitives
	  regiment-distributed-primitives))

(define (regiment-primitive? x) (memq x regiment-primitives))


#;(define marshal
(lambda (x)
  (let ((str (format "~s" x)))
    (let ((in (open-input-string str)))
      (read in)))))
#;(define (marshaltest x) (eq? x (marshal x)))

#;(define load:dump-expansion
(lambda (file dumpfile)
  (parameterize ([current-output-port (open-output-file dumpfile 'replace)]
                 [print-graph #t]
                 [current-eval
                   (case-lambda
                     [(exp)
                      (unless (and (pair? exp) (equal? "noexpand" (car exp)))
                        (write (expand exp)) (newline)(newline))
                      (eval exp)]
                     [(exp envspec)
                      (error
                        'load:dump-expansion
                        "Proxy eval procedure not prepared~s~a"
                        " to receive env-spec:" envspec)])])
    (load file)
    (close-port (current-output-port)))))

;===============================================================================
;;; helpers.ss
;;; Kent Dybvig
;;; January 4, 2001

;;; This file contains some useful helpers, including some generally
;;; useful for everyday Scheme programming and some specific to the
;;; p423 compilers.

;;; 03/08/2002 clc added new object-related keywords, attributes,
;;;                and primitives

;;; 04/19/2001 rkd changed register-mapping to avoid use of %o6
;;; 04/15/2001 rkd added operand-constraints nad register-mapping
;;;                to the machine definition, and added new helper
;;;                with-output-to-string.
;;; 04/03/2001 rkd moved ap into the caller-save-registers list where
;;;                it should have been all along
;;; 03/25/2001 rkd added pick, rem, edge-maker, home-of, neighbors,
;;;                neighbor-homes, extended-neighbor-homes; added
;;;                align-shift to machine definition; added ap to
;;;                machine-definition list of all-registers; added
;;;                sll to list of uil primitives
;;; 03/04/2001 rkd added generalized-member?, generalized-union?, and
;;;                new-frame-var?
;;; 02/26/2001 rkd added caller-save-registers and all-registers to the
;;;                machine definition.  knocked number of parameter
;;;                registers down to two for now.  added frame-var,
;;;                new-frame-var, frame-var?, frame-var->index, and
;;;                register?  fixed a bug in code-name caused by the
;;;                change to extract-suffix.
;;; 02/25/2001 rkd added parameter-registers and return-value-register
;;;                to the machine definition.  modified extract-suffix
;;;                to return only the numeric part of the suffix.
;;;                eliminated fref from uil-primitives (for now).
;;; 02/11/2001 rkd added definitions of uil-primitives, uil-primitive?,
;;;                uil-effect-primitive?, uil-predicate-primitive?, and
;;;                uil-value-primitive?
;;; 01/31/2001 rkd added definitions of logand, sll, sra, hybrid->datum,
;;;                and ptr->datum
;;; 01/28/2001 rkd added definitions of internal-scheme-primitives,
;;;                extended-scheme-primitive?, value-primitive?,
;;;                predicate-primitive?, and effect-primitive?
;;; 01/21/2001 rkd changed implementation of code-name
;;; 01/14/2001 rkd changed datum? to permit improper lists.
;;; 01/14/2001 rkd added immediate?
;;; 2002.05.22 rrn added get-formals, cast-formals, and cast-args

;;; the subset of Scheme keywords we support
(define base-keyword?
  (lambda (x)
    (and (memq x '(quote set! if begin let letrec lambda)) #t)))

;;; CC
;;; new keywords added for object system
(define obj-keyword?
  (lambda (x)
    (and (memq x '(define-class let-class open-package open-instance
                    new program)) #t)))
(define keyword?
  (lambda (x)
    (or (base-keyword? x) (obj-keyword? x))))

;; These are the symbols I use for different types right now:
;;   Bool Char Float64 Int32 List Object
;;   Number Pair Port String Symbol Vector Void

;;; In the below primitive table, you will also see 'Tag, which indicatess
;;; that the specified position simply holds information for the compiler,
;;; these tags are always symbols, so the recursion on operands spills over
;;; them harmlessly.  It would be nice if the primitive application case in
;;; each pass would abstain from recurring on Tag operands, but that would
;;; require bloating the code unnecessarily.  The tags at this point have
;;; the limited purpose of storing class names and such; it should not be
;;; a problem to keep track of.

;;; constants  (which can all occur unquoted)
(define constant?
  (lambda (x)
    (or ;(fx-integer? x)
        ;(flonum? x)
        ;(bg-integer? x)
					;(ratnum? x)
        (number? x)  ;; replacing chez specific...
        (null? x) ;; This means you can type () without a quote.
        (boolean? x)
        (char? x)
        (string? x)  ;; This is semantically straying;
        ;;              these ARE not necessarily constant;
        ;;              they can be modified by string-set!
        )))

#;(define constant->type
  (lambda (imm)
    (cond
      [(fx-integer? imm) 'Int32]
      [(flonum? imm) 'Float64]
      [(bg-integer? imm) 'Number]
      [(ratnum? imm) 'Number]
      [(boolean? imm) 'Bool]
      [(char? imm) 'Char]
      [(string? imm) 'String]
      [(null? imm) 'List]
      [(symbol? imm) 'Symbol]
      [else (error 'constant->type
                   "unknown constant: ~s" imm)])))

;; Things that need boxing (sigh):
#;(define immediate?
  (lambda (x)
    (or ;(null? x)
      (char? x)
      (fx-integer? x) ;; Not bignums
      (flonum? x)
      ;(boolean? x)
      )))

#;(define boxed-type?
  (lambda (type)
    (case type
      [(Char Int32 Float64) #t]
      [(Bool List Object Number Pair Port String Symbol Vector Void)
       #f]
      [(Tag) (error 'boxed-type?
                    "it is not reasonable to ask whether tags are boxed: ~a"
                    rand-type)]
      [else (error 'boxed-type?
                   "unknown type name: ~s" type)])))

;;; structured data
(define datum?
  (lambda (x)
    (or (constant? x)
        (null? x)
        (symbol? x)
        ;(string? x)
        (if (pair? x)
            (and (datum? (car x)) (datum? (cdr x)))
            (and (vector? x) (andmap datum? (vector->list x)))))))

;;; These are the basic scheme primitives:
;;; Entries are of the format:
;;   (<prim> <arity> <context> <rand-type(s)> <return-type>)
;;  <rand-type(s)> follows the same shape as the corresponding formals:
;;     (Int32 Int32)       -- Two fixint arguments
;;      Int32              -- Any number of fixint arguments
;;     (Char Char . Int32) -- Two characters, followed by any # of fixints
;;; For the latter two cases, <arity> will be the symbol "variable"

(define base-scheme-primitives
  '(
     ;; Incompletely implemented:
     (console-output-port 0 value () Port)
     (console-input-port 0 value () Port)
     (make-vector 1 value (Int32) Vector) ;; needs case lambda
     (ash 2 value (Number Number) Number) ;; needs right shifting
     
     ; not is a special case
     (not 1 not)
     
     ; predicates
     (= variable test (Number . Number) Bool)
     (< variable test (Number . Number) Bool)
     (fx= variable test (Int32 . Int32) Bool)
     (fx< variable test (Int32 . Int32) Bool)
     (fx<= variable test (Int32 . Int32) Bool)
     (fx> variable test (Int32 . Int32) Bool)
     (fx>= variable test (Int32 . Int32) Bool)
     (fl= variable test (Float64 . Float64) Bool)
     (fl< variable test (Float64 . Float64) Bool)
     (fl<= variable test (Float64 . Float64) Bool)
     (fl> variable test (Float64 . Float64) Bool)
     (fl>= variable test (Float64 . Float64) Bool)
     (char=? 2 test (Char Char) Bool)
     (eq? 2 test (Object Object) Bool)
     (boolean? 1 test (Object) Bool)
     (null? 1 test (Object) Bool)
     (pair? 1 test (Object) Bool)
     (procedure? 1 test (Object) Bool)
     (vector? 1 test (Object) Bool)
     (zero? 1 test (Int32) Bool)
     (char? 1 test (Object) Bool)
     (port? 1 test (Object) Bool)
     (string? 1 test (Object) Bool)
     (fixnum? 1 test (Object) Bool)
     (flonum? 1 test (Object) Bool)
     (bignum? 1 test (Object) Bool)
     (ratnum? 1 test (Object) Bool)
     
     ; value-producing
     (* variable value Number Number)
     (fx+ variable value Int32 Int32)
     (fx- variable value (Int32 . Int32) Int32)
     (fx* variable value Int32 Int32)
     (fx/ variable value (Int32 . Int32) Int32)
     (fl+ variable value Float64 Float64)
     (fl- variable value (Float64 . Float64) Float64)
     (fl* variable value Float64 Float64)
     (fl/ variable value (Float64 . Float64) Float64)
     (+ variable value Number Number)
     (- variable value (Number . Number) Number)
     (add1 1 value (Int32) Int32)
     (sub1 1 value (Int32) Int32)
     (car 1 value (Pair) Object)
     (cdr 1 value (Pair) Object)
     (cons 2 value (Object Object) Pair)
     (vector-length 1 value (Vector) Int32)
     (vector-ref 2 value (Vector Int32) Object)
     (list-ref 2 value (List Int32) Object)
     (list-tail 2 value (List Int32) Object)
     (string-ref 2 value (String Int32) Char)
     (string-append variable value String String)
     (string-length 1 value (String) Int32)
     (string->list 1 value (String) List)
     (list->string 1 value (List) String)
     (void 0 value () Void)
     (eval 1 value (Object) Object)
     (apply variable value (Object Object . Object) Object)
     (current-directory 0 value () Object)
     (oblist 0 value () List)
     (real-time 0 value () Int32)
     (integer-length 1 value (Number) Number)
     (char->integer 1 value (Char) Int32)
     (integer->char 1 value (Int32) Char)
     (fixnum->flonum 1 value (Int32) Float64)
     (flonum->fixnum 1 value (Float64) Int32)
     ;(symbol->string 1 value (Symbol) String)
     ;(string->symbol 1 value (String) Symbol)
     
     ; side-effecting
     (exit 0 effect () Void)
     (load 1 effect (Object) Void)
     (display 1 effect (Object) Void)
     (newline 0 effect () Void)
     (set-car! 2 effect (Pair Object) Void)
     (set-cdr! 2 effect (Pair Object) Void)
     (vector-set! 3 effect (Vector Int32 Object) Void)
     (string-set! 3 effect (String Int32 Char) Void)
     ))

;; Internal primitives are ones the compiler introduces in the
;; compilation process.  These system-primitives are there present
;; from the start, but should not be used by users.
;; Many of these do not have closures associated with them--inline only.
(define system-scheme-primitives
  '( (\#system-ref 1 value (Symbol) Object)
     (\#system-set! 2 effect (Symbol Object) Void)
     (\#real-error 2 effect (Object String) Void)
     
     (\#bignum->flonum 1 value (Number) Float64)
     (\#bignum-digitcount 1 value (Number) Int32)
     (\#bignum-length 1 value (Number) Int32)
     (\#bignum-collapse 1 value (Number) Number)
     (\#bignum-printbanks 1 effect (Number) Void)
     (\#set-closure-name! 2 effect (Object String) Void)
     
     ;; This is temporary, just until we get operational ports:
     (\#write-to-string 1 value (Object) String)
     
     (\#flonum->integer 1 value (Float64) Number)
     (\#flexpt 2 value (Float64 Float64) Float64)
     (\#flsqrt 1 value (Float64) Float64)
     (\#flfloor 1 value (Float64) Float64)
     (\#flceiling 1 value (Float64) Float64)
     (\#flround 1 value (Float64) Float64)
     ))

;;; These are scheme primitives that we support, but which get
;;; reduced into base scheme primitives.
(define derived-scheme-primitives
  '(
     ;; These two are treated oddly, they are in here, but they
     ;; also have library definitions.  This is redundant but efficient.
     (vector variable value Object Object)
     (list variable value Object Object)
     (<= variable test (Number . Number) Bool)
     (> variable test (Number . Number) Bool)
     (>= variable test (Number . Number) Bool)))

;; These primitives are defined in terms of other primitives, and are
;; accessible only through closures (not in any "inline" form).
;; All of these parameter and return types need to be reference types:
;; (A scheme closure can only return an object presently.)
(define library-scheme-primitives
  '(
     (floor 1 value (Number) Number)
     (ceiling 1 value (Number) Number)
     (round 1 value (Number) Number)
     ;;(ash 1 test (Number) Object)
     (gcd variable value Number Number)
     ;(lcm variable value Number Number) -- this needs apply
     (max variable value (Number . Number) Number)
     (min variable value (Number . Number) Number)
     (remainder 2 value (Number Number) Number)
     (quotient 2 value (Number Number) Number)
     (|#quotient-remainder| 2 value (Number Number) Number)
     (exact->inexact 1 value (Number) Number)
     (inexact->exact 1 value (Number) Number)
     (expt 2 value (Number Number) Number)
     (sqrt 1 value (Number) Number)
     
     (map variable value (Object Object . Object) Object)
     (append variable value List List)
     (reverse 1 value (List) List)
     (memq 2 value (Object List) Object)
     (memv 2 value (Object List) Object)
     (member 2 value (Object List) Object)
     (assq 2 value (Object List) Pair)
     (assv 2 value (Object List) Pair)
     (assoc 2 value (Object List) Pair)
     (length 1 value (List) Number)
     (format variable value (String . Object) String)
     (caar 1 value (Pair) Object)
     (cadr 1 value (Pair) Object)
     (cdar 1 value (Pair) Object)
     (cddr 1 value (Pair) Object)
     (caaar 1 value (Pair) Object)
     (caadr 1 value (Pair) Object)
     (cadar 1 value (Pair) Object)
     (caddr 1 value (Pair) Object)
     (cdaar 1 value (Pair) Object)
     (cdadr 1 value (Pair) Object)
     (cddar 1 value (Pair) Object)
     (cdddr 1 value (Pair) Object)
     (caaaar 1 value (Pair) Object)
     (caaadr 1 value (Pair) Object)
     (caadar 1 value (Pair) Object)
     (caaddr 1 value (Pair) Object)
     (cadaar 1 value (Pair) Object)
     (cadadr 1 value (Pair) Object)
     (caddar 1 value (Pair) Object)
     (cadddr 1 value (Pair) Object)
     (cdaaar 1 value (Pair) Object)
     (cdaadr 1 value (Pair) Object)
     (cdadar 1 value (Pair) Object)
     (cdaddr 1 value (Pair) Object)
     (cddaar 1 value (Pair) Object)
     (cddadr 1 value (Pair) Object)
     (cddadr 1 value (Pair) Object)
     (cddddr 1 value (Pair) Object)
     
     (integer? 1 test (Object) Bool)
     (equal? 2 value (Object Object) Bool)
     (eqv? 2 value (Object Object) Bool)
     (number? 1 test (Object) Bool)
     (exact? 1 test (Object) Bool)
     (inexact? 1 test (Object) Bool)
     (positive? 1 test (Number) Bool)
     (negative? 1 test (Number) Bool)
     (even? 1 test (Number) Bool)
     (odd? 1 test (Number) Bool)
     (list? 1 test (Object) Bool)
     (string=? 2 test (String String) Bool)
     
     (error variable effect (object String . Object) Void)
     ))

(define continuation-scheme-primitives
  '(
     (call/cc 1 value (Object) Object)
     ;(letk x in e) (setk v e) (nullk 0)
     ;(newp 0) (pushpk 2) (composek 2)
     ;(kabove 2)
     ;(kbelow 2)
     ))

;;; the subset of Scheme primitives we support
(define scheme-primitives
  `(
     ,@base-scheme-primitives
     ,@system-scheme-primitives
     ,@derived-scheme-primitives
     ,@continuation-scheme-primitives
     ,@library-scheme-primitives
     ))

;;; new primitives added during compilation
(define internal-scheme-primitives
  '(
     ; value-producing
     (make-bignum 2 value (Bool Vector) Object)
     (closure-code 1 value (Object) Object)
     (closure-freevar 1 value (Tag) Object)
     
     ;(closure-code 1 value)
     ;(closure-ref 2 value)
     (make-closure 1 value (Tag) Object)
     
     ; side-effecting
     ;(closure-set! 3 effect)
     (closure-set! 3 effect (Tag Tag Object Object) Void)
     ))
    
(define scheme-primitive?
  (lambda (x)
    (assq x scheme-primitives)))

(define library-scheme-primitive?
  (lambda (x)
    (assq x library-scheme-primitives)))

(define internal-scheme-primitive?
  (lambda (x)
    (assq x internal-scheme-primitives)))

(define extended-scheme-primitive?
  (lambda (x)
    (and (or (assq x scheme-primitives)
             (assq x internal-scheme-primitives))
         #t)))

(define get-primitive-entry
  (lambda (prim)
    (or (assq prim scheme-primitives)
        (assq prim internal-scheme-primitives)
        (error 'get-primitive-entry
               "no entry for this primitive: ~a" prim))))

;; If the numargs is variable, this function returns a pair
;; such as (a . b) indicating the range of possible argument counts
;; (+inf.0 is a very likely candidate for b).
#;(define (get-primitive-numargs prim)
  (let ([entrynum (list-ref (get-primitive-entry prim) 1)])
    (if (eq? 'variable entrynum)
        (match (get-primitive-rand-types prim)
          [,v (guard (symbol? v)) '(0 . +inf.0)]
          [(,v ...) (cons (length v) (length v))]
          [(,v ... . ,l) (cons (length v) +inf.0)])
        entrynum)))

#;(define (get-primitive-context prim)
  (list-ref (get-primitive-entry prim) 2))
#;(define get-primitive-rand-types
  (case-lambda
    [(prim) (list-ref (get-primitive-entry prim) 3)]
    [(prim len)
     (match (list-ref (get-primitive-entry prim) 3)
       [,t (guard (symbol? t)) (make-list len t)]
       [(,t* ...)
        (if (= (length t*) len) t*
            (error 'get-primitive-rand-types
                   "primitive ~s is fixed arity at length ~s~a~s"
                   prim (length t*) " you can't warp it to length " len))]
       [(,t* ... . ,spill)
        (let ([minlen (length t*)])
          (if (>= len minlen)
              (append t* (make-list (- len minlen) spill))
              (error 'get-primitive-rand-types
                     "primitive ~s requires at least ~s operand(s),~a~s~a"
                     prim minlen " the request to type it for "
                     len " is incorrect.")))])]))
(define (get-primitive-return-type prim)
  (list-ref (get-primitive-entry prim) 4))


;;;============================================================================
;;;
;;; CC
;;;
;;; The following are new "primitive?"-esque things relating to the object
;;;  system.
;;;

(define access-attributes
  '(public protected private))
(define access-attribute?
  (lambda (x)
    (memv x access-attributes)))

(define storage-attributes
  '(static instance))
(define storage-attribute?
  (lambda (x)
    (memv x storage-attributes)))

(define attributes
  (append
    access-attributes
    storage-attributes))

(define attribute?
  (lambda (x)
    (memv x attributes)))

;;;
;;;============================================================================


;;; presently defined for either Scheme or internal Scheme primitives
(define predicate-primitive?
  (lambda (x)
    (cond
      [(or (assq x scheme-primitives)
           (assq x internal-scheme-primitives)) =>
       (lambda (a) (eq? (caddr a) 'test))]
      [else #f])))

(define value-primitive?
  (lambda (x)
    (cond
      [(or (assq x scheme-primitives)
           (assq x internal-scheme-primitives)) =>
       (lambda (a) (eq? (caddr a) 'value))]
      [else #f])))

(define effect-primitive?
  (lambda (x)
    (cond
      [(or (assq x scheme-primitives)
           (assq x internal-scheme-primitives)) =>
       (lambda (a) (eq? (caddr a) 'effect))]
      [else #f])))


;===============================================================================

(define formalexp?
  (lambda (formalexp)
    (match formalexp
      [(,v* ...) (set? v*)]
      [,v (guard (symbol? v)) #t]
      [(,v* ... . ,extra) (set? (cons extra v*))]
      [,else #f])))

(define get-formals
  (lambda (formalexp)
    (match formalexp
      [(,v* ...) v*]
      [,v (guard (symbol? v)) (list v)]
      [(,v* ... . ,extra) (append v* (list extra))]
      [,else (error 'get-formals "invalid formals expression: ~a"
                    formalexp)])))

(define get-normal-formals
  (lambda (formalexp)
    (match formalexp
      [(,v* ...) v*]
      [,v (guard (symbol? v)) '()]
      [(,v* ... . ,extra) v*]
      [,else (error 'get-normal-formals "invalid formals expression: ~a"
                    formalexp)])))

(define get-list-formals
  (lambda (formalexp)
    (match formalexp
      [(,v* ...) '()]
      [,v (guard (symbol? v)) (list v)]
      [(,v* ... . ,extra) (list extra)]
      [,else (error 'get-list-formals "invalid formals expression: ~a"
                    formalexp)])))

(define cast-formals
  (lambda (formals formalexp)
    (match formalexp
      [,v (guard (symbol? v)) (car formals)]
      [(,v* ...) formals]
      [(,v* ... . ,extra)
       (match formals
         [(,v* ... ,last) `(,v* ... . ,last)])]
      [,else (error 'cast-formals
                    "invalid formals expression: ~a" formalexp)])))

(define cast-args
  (lambda (argexps formalexp)
    (match formalexp
      [,v (guard (symbol? v)) (list (cons 'list argexps))]
      [(,v* ...) argexps]
      [(,v* ... . ,extra)
       (let ([len (length v*)])
         (append (list-head argexps len)
                 (list (cons 'list (list-tail argexps len)))))]
      [,else (error 'cast-args
                    "invalid formals expression: ~a" formalexp)])))

(define list-head
  (lambda (lst n)
    (cond
      [(zero? n) '()]
      [(null? lst) (error 'list-head "list is not long enough: ~s ~s"
                          lst n)]
      [else (cons (car lst) (list-head (cdr lst) (sub1 n)))])))

(define filter
  (lambda (pred lst)
    (cond
      [(null? lst) '()]
      [(pred (car lst)) (cons (car lst) (filter pred (cdr lst)))]
      [else (filter pred (cdr lst))])))

(define list-index
  (lambda (pred ls)
    (cond
      ((null? ls) #f)
      ((pred (car ls)) 0)
      (else (let ((list-index-r (list-index pred (cdr ls))))
              (if (number? list-index-r)
                  (+ list-index-r 1)
                  #f))))))

#;(define timeeval
  (lambda (x)
    (let ([start (real-time)])
      (eval x)
      (- (real-time) start))))

#;(define cpueval
  (lambda (x)
    (let ([start (cpu-time)])
      (eval x)
      (- (cpu-time) start))))

(define snoc
  (lambda (a ls)
    (append ls (list a)) ))

(define rac
  (lambda (ls)
    (if (null? ls)
        (error 'rac "cannot take the rac of the empty-list")
        (let rac-loop ([cur (car ls)] [lst (cdr ls)])
          (if (null? lst)
              cur
              (rac-loop (car lst) (cdr lst)))))))

(define rdc
  (lambda (ls)
    (if (null? ls)
        (error 'rdc "cannot take the rdc of the empty-list")
        (let rdc-loop ([lst ls])
          (if (null? (cdr lst))
              '()
              (cons (car lst) (rdc-loop (cdr lst))))))))

(define mapleft
  (lambda (f ls)
    (if (null? ls)
        '()
        (let ([rst (mapleft f (cdr ls))])
          (cons (f (car ls)) rst)))))

(define mapright
  (lambda (f ls)
    (if (null? ls)
        '()
        (cons (f (car ls))
              (mapright f (cdr ls))))))

(define list-set
  (lambda (origls origpos v)
    (let list-set-loop ([ls origls] [pos origpos])
      (cond
        [(null? ls)
         (error 'list-set
                "list ~a is not long enough to reference pos ~a"
                origls origpos)]
        [(zero? pos) (cons v (cdr ls))]
        [else (cons (car ls)
                    (list-set-loop (cdr ls) (sub1 pos)))]))))

;===============================================================================

;; Repeatedly execute an expression some number of times:
(define-syntax rep
  (syntax-rules ()
    [(_ reps exp ...)
     (let loop ([n reps])
       (if (< n 1)
           (void)
           (begin exp ...
                  (loop (sub1 n)))))]))

(define insert-between
  (lambda (x lst)
    (let loop ([lst lst])
      (cond
        [(null? lst) '()]
        [(null? (cdr lst)) lst]
        [else (cons (car lst)
                    (cons x (loop (cdr lst))))]))))

;;; multiple-value let
(define-syntax mvlet
  (lambda (x)
    (define domvlet
      (lambda (bindings ids tmps body)
        (if (null? bindings)
            `((,#'lambda ,ids ,@body) ,@tmps)
            (syntax-case (car bindings) ()
              [(*ids expr)
               (with-syntax ([*tmps (generate-temporaries #'*ids)])
                 (with-syntax ([body (domvlet (cdr bindings)
                                              (append #'*ids ids)
                                              (append #'*tmps tmps)
                                              body)])
                   #'(call-with-values
                       (lambda () expr)
                       (lambda *tmps body))))]))))
    (syntax-case x ()
      [(_ (((id ...) expr) ...) form ...)
       (andmap (lambda (ls) (andmap identifier? ls)) #'((id ...) ...))
       (domvlet #'(((id ...) expr) ...) '() '() #'(form ...))])))

;;; procedures for manipulating sets
(define set?
  (lambda (ls)
    (or (null? ls)
        (and (not (memq (car ls) (cdr ls)))
             (set? (cdr ls))))))

(define list->set
  (lambda (ls)
    (if (null? ls) '()
        (set-cons (car ls) (list->set (cdr ls))))))

(define set-cons
  (lambda (x set)
    (cond
      [(null? set) (list x)]
      [(eq? x (car set)) set]
      [else (cons (car set) (set-cons x (cdr set)))])))

(define union
  (case-lambda
    [(set1 set2)
     (let loop ([set1 set1])
       (cond
         [(null? set1) set2]
         [(memq (car set1) set2) (loop (cdr set1))]
         [else (cons (car set1) (loop (cdr set1)))]))]
    [() '()]
    [(set1 . sets)
     (let loop ([set1 set1] [sets sets])
       (if (null? sets)
           set1
           (loop (union set1 (car sets)) (cdr sets))))]))

(define intersection
  (case-lambda
    [(set1 set2)
     (let loop ([set1 set1])
       (cond
         [(null? set1) '()]
         [(memq (car set1) set2) (cons (car set1) (loop (cdr set1)))]
         [else (loop (cdr set1))]))]
    [(set1 . sets)
     (let loop ([set1 set1] [sets sets])
       (if (null? sets)
           set1
           (loop (intersection set1 (car sets)) (cdr sets))))]))

(define difference
  (lambda (set1 set2)
    (cond
      ((null? set1) '())
      ((memq (car set1) set2) (difference (cdr set1) set2))
      (else (cons (car set1) (difference (cdr set1) set2))))))

(define generalized-member?
  (lambda (pred?)
    (lambda (x ls)
      (let f ([ls ls])
        (and (not (null? ls))
             (or (pred? (car ls) x)
                 (f (cdr ls))))))))

(define generalized-union
  (lambda (pred?)
    (let ([member? (generalized-member? pred?)])
      (lambda args
        (let f ([args args])
          (if (null? args)
              '()
              (let ([set1 (car args)] [set2 (f (cdr args))])
                (let loop ([set1 set1])
                  (cond
                    [(null? set1) set2]
                    [(member? (car set1) set2) (loop (cdr set1))]
                    [else (cons (car set1) (loop (cdr set1)))])))))))))

;;; (iota n) => (0 1 ... n-1)
;;; (iota i n) => (i i+1 ... i+n-1)
(define iota
  (case-lambda
    [(n) (iota 0 n)]
    [(i n)
     (if (= n 0)
         '()
         (cons i (iota (+ i 1) (- n 1))))]))

;;; unique-name produces a unique name derived the input name by
;;; adding a unique suffix of the form .<digit>+.  creating a unique
;;; name from a unique name has the effect of replacing the old
;;; unique suffix with a new one.
;;;
;;; reset-name-count! resets the internal counter used to produce
;;; the unique suffix.
;;;
;;; code-name takes a unique name and replaces its suffix ".nnn"
;;; with "$nnn", e.g., f.3 => f$3.  It is used by convert-closure.
;;;
;;; extract-suffix returns the numeric portion of the unique suffix
;;; of a unique name or code-name, or #f if passed a non unique name.
;(module (unique-name reset-name-count! extract-suffix
;                     code-name label-name #;method-name)
        ;RRN [01.09.16] -- We need to phase out code-name...
        (define count 0)
        (define unique-suffix
          (lambda ()
            (set! count (+ count 1))
            (number->string count)))
        (define reset-name-count!
          (lambda ()
            (set! count 0)))
        (define extract-root
          (lambda (sym)
            (list->string
              (let ([chars (string->list (symbol->string sym))])
                (define (s0 ls)
                  (cond
                    [(null? ls) chars]
                    [(char-numeric? (car ls)) (s1 (cdr ls))]
                    [else chars]))
                (define (s1 ls)
                  (cond
                    [(null? ls) chars]
                    [(char-numeric? (car ls)) (s1 (cdr ls))]
                    [(memv (car ls) '(#\. #\$ #\_ ))
                     (reverse (cdr ls))]
                    [else chars]))
                (s0 (reverse chars))))))
        (define extract-suffix
          (lambda (sym)
            (let ([str (symbol->string sym)])
              (let ([n (string-length str)]
                    [m (string-length (extract-root sym))])
                (and (not (= n m))
                     (substring str (+ m 1) n))))))
        (define strip-illegal
          (lambda (str)
            (list->string
              (filter (lambda (c) (or (char-alphabetic? c)
                                      (char-numeric? c)))
                      (string->list str)))))
        #;(define illegal-chars
            '(#\! #\@ #\# #\$ #\% #\^ #\& #\* #\. #\-))
        #;(define strip-illegal
            (lambda (str)
              (let loop ([ls illegal-chars]
                         [chars (string->list str)])
                (if (null? ls) (list->string chars)
                    (loop (cdr ls) (remq (car ls) chars))))))
        ;;Ok, this is designed so that it can extract the root from
        ;;either a
        (define unique-name
          (lambda (sym)
            (string->symbol
              (string-append
                (strip-illegal ;;RRN - THIS IS STUPID, CHANGE ME
                  (extract-root sym))
                "_" (unique-suffix)))))
        (define code-name  ;; RENAME ME to METHOD-NAME
          (lambda (sym)
            ;(disp "Code name")
            (string->symbol
              (string-append
                "fun"
                (let ([suffix (or (extract-suffix sym) (unique-suffix))])
                  (substring suffix 0 (string-length suffix)))
                "_"
                (strip-illegal (extract-root sym))
                ))))
        (define label-name
          (lambda (sym)
            (string->symbol
              (string-append
                (strip-illegal (extract-root sym))
                "$"
                (let ([suffix (or (extract-suffix sym) (unique-suffix))])
                  (substring suffix 0 (string-length suffix)))))))
;;) ;; Module deactivated

;;; create a "flattened" begin from list of expressions
;;; e.g., (make-begin '(1 (begin 2) (begin 3 4) 5)) => (begin 1 2 3 4 5)
(define make-begin
  (lambda (expr*)
    (match (match `(begin ,@expr*)
             [(begin ,[expr*] ...) (apply append expr*)]
             [,expr (list expr)])
      [(,x) x]
      [(,x ,x* ...) `(begin ,x ,x* ...)])))
;;RRN [01.09.17] :
(define make-code
  (lambda (expr*)
    (match (match `(code ,@expr*)
             [(code ,[expr*] ...) (apply append expr*)]
             [,expr (list expr)])
      [(,x) x]
      [(,x ,x* ...) `(code ,x ,x* ...)])))

(define with-output-to-string
  (lambda (th)
    (parameterize ([current-output-port (open-output-string)])
      (th)
      (get-output-string (current-output-port)))))


;;; we can only handle exact integers in the fixnum range
(define fx-integer?
  (let ()
    ;;RRN: Unfortunately MSIL can't handle boxed immediates, so fixnums
    ;; are the full size of a word:
    (define fixnum-minimum (- (expt 2 31)))
    (define fixnum-maximum (- (expt 2 31) 1))
    (lambda (x)
      (and (integer? x)
           (exact? x)
           (<= fixnum-minimum x fixnum-maximum)))))

(define bg-integer?
  (lambda (x)
    (and (integer? x)
         (exact? x)
         (not (fx-integer? x)))))

(define disp
  (lambda args
    (let loop ((args args))
      (if (null? args)
          (begin (newline) (newline))
          (begin (display (car args))(display " ")
                 (loop (cdr args)))))))