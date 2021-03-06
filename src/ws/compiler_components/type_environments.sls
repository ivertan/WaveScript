#!r6rs

;;;; This file defines an ADT for type environments used by the type checker.
;;;; It also defines the represenation for types themselves.

;;;; .author Ryan Newton

(library  (ws compiler_components type_environments) 
  (export
           scalar-type?

	   type? 
	   instantiated-type?
	   distributed-type?
	   arrow-type? type-containing-arrow?
	   polymorphic-type?  type-replace-polymorphic 
	   type-containing-mutable?
	   constant-typeable-as? 
	   known-size?
	   type->width
           datum->width

	   tvar-quotation?
           make-tvar
	   reset-tvar-generator
	   get-tvar-generator-count
	   make-tcell
	   make-rowcell
	   make-numcell
	   tcell->name
	   tcell-set!
	   tcell-get
           
	   empty-tenv
	   tenv?
	   tenv-lookup
	   tenv-is-let-bound?
	   tenv-extend
	   tenv-extend-pattern
	   tenv-append
	   tenv-map
	   tenv-eq? 

	   TEMP:tenv-sizes
	   test-type_environments
	   )

  (import (except (rnrs (6)) error)
	  (rnrs mutable-pairs (6))
	  (ws compat compat)
	  (ws globals)
	  (ws util iu-match) ;; TEMPTOGGLE
	  ;(ws util rn-match)
	  (ws util hashtab)
	  (ws util helpers)
	  (ws util reg_macros)
	  (ws compiler_components prim_defs)	
           )

; ----------------------------------------
;;; Representation for Types.
;;;
;;; TODO: If I wanted an added degree of safety, I could make types
;;; and instantiated-types totally disjoint; at the cost of boxing
;;; them.  Currently I believe I'm being sloppy in places.

;;; NOTE: Record types:
;;; These have the form (Record ROW-kind (name type) ...)
;;; ROW-kind = (Record ...) | (ROW ,sym) | #() 
;;;
;;; Thus we've overloaded #() to mean empty-record (in row context),
;;; and empty tuple in a normal type context.  
;;;
;;; The other tricky part about this representation is that throughout
;;; the compiler we assume the fields are sorted by field name.  This
;;; invariant must be preserved.

(define (scalar-type? ty) 
  (or (memq ty num-types)
      (memq ty '(Bool Char))
      ;; Whatever num type it is, we know it's a scalar:
      (and (pair? ty) (eq? (car ty) 'NUM))
      ))

(define (valid-type-symbol? s)
  (let ([str (symbol->string s)])
    (and (> (string-length str) 0)
	 (char-upper-case? (string-ref str 0)))))
(define (valid-typevar-symbol? s)
  (let ([str (symbol->string s)])
    (and (> (string-length str) 0)
	 (char-lower-case? (string-ref str 0)))))

;; Our types aren't a very safe datatype, but this predicate tries to give some assurance.
;; extra-pred is a bit of a hack to allow us to extend the functionality
(define (instantiated-type? t . extra-pred)
  (define (id x) x)
  (IFCHEZ (import rn-match) (void))
  (let loop ((t t))
   (match t
    [,s (guard (symbol? s)) (valid-type-symbol? s)]
    ;[(,qt ,v)          (guard (memq qt '(quote NUM)) (symbol? v)) (valid-typevar-symbol? v)]
    [(,qt (,v . #f))   (guard (tvar-quotation? qt) (symbol? v)) (valid-typevar-symbol? v)]
    [(,qt (,v . ,[t])) (guard (tvar-quotation? qt) (symbol? v)) (and t (valid-typevar-symbol? v))]
    [#(,ty* ...) (andmap loop ty*)]
    [(,arg* ... -> ,[ret]) (and ret (andmap loop arg*))]
    [(Struct ,name) (symbol? name)] ;; Adding struct types for output of nominalize-types.
    [(LATEUNIFY #f ,[t]) t]
    [(LATEUNIFY ,[t1] ,[t2]) (and t1 t2)]
    [(List Annotation) #t] ; FIXME: a bit of a hack, but Annotations should not appear in any other form

    ;; Instantiated record types must have a mutable cell separating them and their row.
    [(Record ,row) (guard (match? row '(,var . ,ty))) (loop row)]

    ;; Including Ref, Row:
    [(,C ,[t] ...) (guard (symbol? C) (not (tvar-quotation? C)) (not (eq? C 'Record)))
     (andmap id t)]
    [,s (guard (string? s)) #t] ;; Allowing strings for uninterpreted C types.
    ;[(,ptr ,[name]) (guard (eq-any? ptr 'Pointer 'ExclusivePointer)) name]
    [,oth (if (null? extra-pred) #f 
	      ((car extra-pred) oth))])))
(define (type? t)
  (IFCHEZ (import rn-match) (void))
  (instantiated-type? t 
    (lambda (x) 
      (match x 
        [(,qt ,v) (guard (tvar-quotation? qt) (symbol? v))
	 (valid-typevar-symbol? v)]
	;; This is a valid uninstantiated type:
	[(Record ,row) 
	 (match row
	   [(Row ,nm ,ty ,[tail]) (and tail (type? ty))]
	   [',var (symbol? var)]
	   [#() #t])]
        [,other #f]))))

;; Does it contain the monad?
(define (distributed-type? t)
  (define (id x) x)
  (IFCHEZ (import rn-match) (void))
  (let loop ((t t))
   (match t
    ;; TODO: FIXME: Use the type alias table, don't check for Region/Anchor directly:
    [Region #t]
    [Anchor #t]
    [(Area ,_) #t]
    [(Stream ,_) #t]    
    [,s (guard (symbol? s)) #f]
    [#(,ty* ...) (ormap loop ty*)]
    [(,qt ,v) (guard (tvar-quotation? qt) (symbol? v)) #f]
    [(,qt (,v . #f))  (guard (tvar-quotation? qt) (symbol? v))
     (warning 'distributed-type? "got type var with no info: ~s" v)
     #t] ;; This COULD be.
    [(,qt (,v . ,[t])) (guard (tvar-quotation? qt) (symbol? v)) t]
    [(,[arg] ... -> ,[ret]) (or ret (ormap id  arg))]
    [(Struct ,name) #f] ;; Adding struct types for output of nominalize-types.
    [(LUB ,a ,b) (error 'distributed-type? "don't know how to answer this for LUB yet.")]
    ;; Handles Ref, Record, Row:
    [(,C ,[t] ...) (guard (symbol? C)) (ormap id t)]
    [,else #f])))

;; Does it contain any type-vars?
(define (polymorphic-type? t)
  (define (id x) x)
  (IFCHEZ (import rn-match) (void))
  (let loop ((t t))
   (match t
    ;; TODO: FIXME: Use the type alias table, don't check for Region/Anchor directly:
    [,s (guard (symbol? s)) #f]
    [(,qt ,v) (guard (tvar-quotation? qt) (symbol? v)) #t]
    [(,qt (,v . #f))  (guard (tvar-quotation? qt) (symbol? v))
     (warning 'polymorphic-type? "got type var with no info: ~s" v)
     #t] ;; This COULD be.
    [(,qt (,v . ,[t])) (guard (tvar-quotation? qt) (symbol? v)) t]
    [#() #f]
    [#(,ty* ...) (ormap loop ty*)]
    [(,[arg] ... -> ,[ret]) (or ret (ormap id  arg))]
    [(Struct ,name) #f] ;; Adding struct types for output of nominalize-types.
    [(LUB ,a ,b) (error 'polymorphic-type? "don't know how to answer this for LUB yet.")]
    ;; Including Ref, Record, Row
    [(,C ,[t] ...) (guard (symbol? C)) (ormap id t)]
    [,else #f])))

(define type-replace-polymorphic
  (case-lambda
    [(ty dummy)        (type-replace-polymorphic ty dummy dummy dummy)]
    [(ty dummy ty-num) (type-replace-polymorphic ty dummy ty-num dummy)]
    [(ty dummy ty-num ty-row)
     (let loop ([ty ty])
       (match ty
	 [',v (ASSERT symbol? v) dummy]
	 [(NUM ,v) (ASSERT symbol? v) ty-num]      
	 [(Record ,row)
	  `(Record ,(match row
		      [(Row ,name ,[loop -> ty] ,[tail])
		       `(Row ,name ,ty ,tail)]
		      [#() '#()]
		      [',v (ASSERT symbol? v) ty-row]))]	 
	 [,s (guard (symbol? s)) s]
	 [#(,[t*] ...)                    (list->vector t*)]
	 [(,[arg*] ... -> ,[ret])        `(,@arg* -> ,ret)]
	 ;; Including Ref, Record, Row
	 [(,C ,[t*] ...) (guard (symbol? C) (not (tvar-quotation? C)))    (cons C t*)]
	 [,s (guard (string? s)) s] 
	 [,oth (error 'strip-irrelevant-polymorphism "unhandled type: ~s" oth)]))]))

;; Does a value of this type have mutable subcomponents?
(define (type-containing-mutable? t)
  (IFCHEZ (import rn-match) (void))
  (let loop ((t t))
   (match t
    [(Array ,_) #t]
    [(HashTable ,_ ,__) #t]
    [,s (guard (symbol? s))                              #f]
    [(,qt ,v) (guard (tvar-quotation? qt) (symbol? v)) #f]
    [(,qt (,v . ,_)) (guard (tvar-quotation? qt) (symbol? v))
     (error 'type-containing-mutable? "got instantiated type!: ~s" t)]
    [#(,ty* ...) (ormap loop ty*)]
    ;; An arrow type is not itself mutable.
    [(,[arg] ... -> ,[ret]) #f]
    [(Pointer ,name) #t] ;; This could contain mutable... 
    [(ExclusivePointer ,name) #t]
    ;; Including Ref, Record, Row
    [(,C ,[t] ...) (guard (symbol? C)) (ormap id t)]
    ;[,else #f] ;; [2008.08.06]
    )))

;; This means *is* an arrow type, not *contains* an arrow type.
(define (arrow-type? t)
  (IFCHEZ (import rn-match) (void))
  (match t
    ;[(quote (,v . #f)) #f]
    [(quote (,v . ,[rhs])) rhs]
    ;[(NUM ,_) #f] ;; NUM types shouldnt be arrows!
    [(,t1 ... -> ,t2) #t]
    [(LUB ,a ,b) (error 'arrow-type? "don't know how to answer this for LUB yet.")]
    [,else #f]))

(define (type-containing-arrow? t)
  (let loop ((t t))
   (match t
    [(quote (,v . #f)) #f]
    [(quote ,v) #f]    
    [(quote (,v . ,[rhs])) rhs]
    [(NUM ,_) #f] ;; NUM types shouldnt be arrows!
    [(,t1 ... -> ,t2) #t]
    [(LUB ,a ,b) (error 'type-containing-arrow? "don't know how to answer this for LUB yet.")]
    [#(,ty* ...) (ormap loop ty*)]
    [(Pointer ,name) #f]
    [(ExclusivePointer ,name) #f]
    [(,C ,[t] ...) (guard (symbol? C)) (ormap id t)] ;; Including Ref, Record, Row
    [,s (guard (symbol? s)) #f]
    )))

;; Taken instantiated or uninstantiated type:
(define constant-typeable-as? 
  (lambda (c ty)
    (if (eq? c 'BOTTOM) #t
	(match ty
	  [Uint8  (guard (fixnum? c)) (uint8? c)]
	  [Uint16 (guard (fixnum? c)) (uint16? c)]
	  [Int   (guard (fixnum? c))  (int32? c)]
	  [Int16 (guard (fixnum? c))  (int16? c)]
	  [Int32 (guard (fixnum? c))  (int32? c)]
	  [Int64 (guard (fixnum? c))  (int64? c)]
	  [Float   (flonum? c)]
	  [Double  (double? c)]
	  [Complex (cflonum? c)]
	  [Bool  (boolean? c)]
	  [Char (char? c)]
	  [String (string? c)]
	  [(List ,t) (and (list? c) (andmap (lambda (x) (constant-typeable-as? x t)) c))]
	  [(Array ,t) (and (vector? c) (vector-andmap (lambda (x) (constant-typeable-as? x t)) c))]
	  [#()   (eq? c 'UNIT)]
	
	  [#(,t* ...)
	   (and (tuple? c) (andmap (lambda (x t) (constant-typeable-as? x t))
				   (tuple-fields c) t*))]
	 #;
	  [(Record ,row (,name* ,ty*) ...)
	   (and (wsrecord? c)
		(andmap (lambda (name ty) 
			  (constant-typeable-as? (wsrecord-select c name) ty))
			name* ty*))]

	  ;; Type variable, matches anything:
	  [(,qt ,v) (guard (tvar-quotation? qt)) #t]	  

	  [(Sigseg ,t) (and (sigseg? c) (vector-andmap (lambda (x) (constant-typeable-as? x t)) (sigseg-vec c)))]
	  [Timebase    (timebase? c)]
	   	 
	  ;[else #f]
	  ))
    ))


  ;; Does this type have a known size?
  ;; Matters for making tuples into structs.
  (define (known-size? t)
    (define (id x) x)
    (match t
      [,simple (guard (symbol? simple)) #t]
      ;; TODO: FIXME: Use the type alias table, don't check for Region/Anchor directly:
      [(,qt ,v) (guard (tvar-quotation? qt) (symbol? v)) #f]
      [(,qt (,v . ,[t])) (guard (tvar-quotation? qt) (symbol? v)) t]
      ;; This shouldn't be in a tuple anyway:
      [(,[arg] ... -> ,[ret]) #f]

      [(Struct ,name)         #t]
      ;; These are pointers, doesn't matter what the type inside is.
      [(Sigseg ,_)            #t]
      [(Array  ,_)            #t]
      [(List   ,_)            #t]
      [(Pointer   ,_)         #t]
      [(ExclusivePointer  ,_) #t]
      ;; The name is an arbitrary symbol:
      [(Row ,name ,[elt] ,tail) (and elt (known-size? tail))]
      ;; Including Ref, Record:
      [(,C ,[t] ...) (guard (symbol? C)) (andmap id t)]
      [#(,[t] ...) (andmap id t)]
      [,else #f]))

  ;; TODO, needs to handle sum types properly.
  ;;
  ;; NOTE: this is specific to the C++ backend... but it also holds
  ;; for the external representation in files.
  ;;
  ;; NOTE: This doesn't actually correspond to the sizeof the C struct used to represent the tuple.
  ;; The C compiler is at liberty to do things like word-align the struct.
  (define type->width
    (case-lambda
      [(t) (type->width t #f)]
      [(t sumdecls) 
       (match t
         [Uint8  1]
         [Uint16 2]
         [Int16 2]

         [Int   4] ;; INTS ARE 16 BIT ON TELOS!!! FIXME FIXME

         [Int32 4] 
         [Int64 8]
         ;; HACK:
         ;[(Sigseg #(,[w*] ...)) (apply + w*)]
         ;[(Sigseg ,t)         (type->width t)]
         [(Sigseg ,t) 16]
         [Float  4]
         [Double 8]
         [Complex 8]
         [Char 1]
         [Bool 1] ; FIXME: check this
         ;;[Complex ]    
	 
         ;[#() 1] ;????
         [#(,[t*] ...) (apply + t*)]
	 ;[(Record ...)]
	 [(Record ,row)
	  (error 'type->width "unimplemented case: (Record ~a)" row)]

         [(Sum ,TC)
          (ASSERT sumdecls)
          (let ((sumtypedef (assoc `(,TC) sumdecls)))
            (ASSERT sumtypedef)
            (apply max (map (lambda (m) (type->width (cadr m) sumdecls)) (cdr sumtypedef))))]
	 
         [,other (error 'type->width "do not know the size of this type: ~s" other)]
	 )]))

  ;; like type->width, but receives both the type and the datum in order to calculate
  ;; the total width (necessary for e.g. arrays)
  (define datum->width
    (case-lambda
      [(t d) (datum->width t d #f)]
      [(t d sumdecls)
       (if (scalar-type? t)
	   (type->width t sumdecls)
	   (match t ;; No match recursion
	     [(Array ,elt)
	      (+ (type->width 'Int sumdecls) ;; The length slot.
		 (if #f ;(scalar-type? elt)
		     (* (vector-length d) (type->width elt sumdecls)) ;; Optimization.
		     (vector-fold + 0 
				   (vector-map (lambda (e) (datum->width elt e sumdecls)) d))))]
	     ;; FIXME: This makes the assumption that an Int is the same size as a cdr pointer:
	     [(List ,elt)  (foldl (lambda (e acc) (+ acc (datum->width elt e sumdecls)))
			     (type->width 'Int sumdecls) d)]
	     [#() 1] ; FIXME FIXME: what to really do here?
	     [#(,t* ...) (apply +   (map (lambda (e ty) (datum->width ty e sumdecls)) (tuple-fields d) t*))]
	     [(Record ,row)
	      (error 'datum->width "unimplemented case: (Record ~a)" row)]
	     [String (string-length d)] ; FIXME: there may be some overhead?
	     [(Sigseg ,elt) 
	      (+ 
	       (+ (type->width 'Int64 sumdecls)  ;; The Start slot.
		  (datum->width 'Timebase (sigseg-timebase d) sumdecls)  ;; The Timebase
		  )
	       (datum->width `(Array ,elt) (sigseg-vec d))
	       ;;(vector-map (lambda (e) (datum->width elt e sumdecls)) (sigseg-vec d))
	       )]
	     [Timebase (type->width 'Int sumdecls)] ;; For now assume this is a scalar.
	     ;;[,other (type->width t sumdecls)]
	     ))]))

; ----------------------------------------
;;; Representation for type variables  

;; We have three different kinds of type variables, each use a different "quotation mark".
;; Maybe should make a macro to assure it's inlined:
(define (tvar-quotation? qt)
  (eq-any? qt 'quote 'NUM 'ROW))
  
(define tvar-generator-count 0)
;; Makes a unique type variable.  Returns a symbol.
(define make-tvar
  (let* ([vars (list->vector (map symbol->string 
			       '(a b c d e f g h i j k l m n o p q r s t u v w x y z)))]
	 [len (vector-length vars)]
	 )
    (lambda ()
      (let loop ([ind tvar-generator-count] [acc '()])
	(cond
	 [(< ind len)  
	  (set! tvar-generator-count (fx+ 1 tvar-generator-count))
	  (string->symbol (apply string-append (cons (vector-ref vars ind) acc)))]
	 [else (loop (fx- (fx/ ind len) 1)
		     (cons (vector-ref vars (fxmod ind len)) acc))]))
      )))

;; Resets the unique name counter.
(define reset-tvar-generator
  (case-lambda 
    [()  (set! tvar-generator-count 0)]
    [(n) (set! tvar-generator-count n)]))
(define (get-tvar-generator-count) tvar-generator-count)

;; A tcell is like a tvar (quoted, representing a variable).  Except
;; instead of just containing a symbolic name, it is a cons cell also
;; including constraints on that variables type.  It's a place for
;; accumulating information on a variable.
(define make-tcell
  (case-lambda
    [() `(quote (,(make-tvar) . #f))]
    [(x)`(quote (,(make-tvar) . ,x))]))

;; Same but for row variables rather than normal type variables
(define make-rowcell
  (case-lambda
    [() `(ROW (,(make-tvar) . #f))]
    [(x)`(ROW (,(make-tvar) . ,x))]))
(define make-numcell
  (case-lambda
    [() `(NUM (,(make-tvar) . #f))]
    [(x)`(NUM (,(make-tvar) . ,x))]))

(define (tcell->name x)
  (IFCHEZ (import rn-match) (void))
  (match x
    [(,qt (,n . ,t)) (guard (tvar-quotation? qt))
     (DEBUGASSERT (symbol? n))    n]
    [,else (error 'tcell->name "bad tvar cell: ~s" x)]))
(define (tcell-set! x ty)
  (if (and (pair? x) (tvar-quotation? (car x))
	   (pair? (cadr x)))
      (set-cdr! (cadr x) ty)
      (error 'tcell-set! "Bad tcell: ~a" x)))
(define (tcell-get x)
  (if (and (pair? x) (tvar-quotation? (car x))
	   (pair? (cadr x)))
      (cdr (cadr x))
      (error 'tcell-get "Bad tcell: ~a" x)))

  
; ----------------------------------------
;;; Type Environment ADT.
;;;
;;; Type environments bind variable names to types.
;;; Currently, these may be instantiated or uninstantiated types.
;;; <br><br>
;;;
;;; [2007.02.21] Changing the tenv representation.  Now we wish to
;;; ultimately use the least-upper-bound of all the reference-sites as
;;; the type of a let-bound variable.  I'm internally changing the
;;; "flag" field to store #f for non-let-bound variables, and to be a
;;; type for let-bound variables.  That type will be a backup copy of
;;; the most general type.  The normal type field will contain the LUB
;;; of the reference-sites.

;; Helper: return the expression and flag for an entry in the tenv.
(define (build-entry v t flag)
  (if flag
      (match t
        ;; Expects the type to be a type var:
        [(quote ,pr) (ASSERT pair? pr)
                     ;; CONSTRUCT A DELAYED UNIFY:
                     ;; This is the scratch-pad on which we'll record the info from the call-sites. 

	             ;; Make a new location and splice it in:
                     (let ([cell (make-tcell (cdr pr))])
                       (set-cdr! pr 
                                 (if (inferencer-enable-LUB) `(LATEUNIFY #f ,cell) cell)))
                     
                     (values `(quote ,pr) #t)
                     ])
      (values t #f)))

(define TEMP:tenv-sizes '())
  
;; List based tenvs:
(begin 

  ;; This is simply meant to document the fact that we're depending on eq? for tenvs.
  (define tenv-eq? eq?)

  ;; Constructs an empty type environment.
  (define empty-tenv 
    ;; Uses a unique identifier.
    (let ([ident (gensym "tenv")])
      (lambda () (list ident))))

  ;; Predicate testing for type environments.
  (define (tenv? x)
    (IFCHEZ (import rn-match) (void))
    (match x
      ;; Format: [VAR, TYPE, Is-Let-Bound?-FLAG]
      [(,tenvsym [,v* ,t* ,flag*] ...)
       (and (eq? tenvsym (car (empty-tenv)))
	    (andmap symbol? v*)	  
	    (andmap type? t*);(andmap instantiated-type? t*)
	    (andmap (lambda (x) (or (boolean? x) (type? x))) flag*)
	    )]
      [,else #f]))
  ;; Retrieves a type if a binding exists for sym, otherwise #f.
  (define (tenv-lookup tenv sym)
    (DEBUGASSERT (tenv? tenv))
;    (let ([s (length tenv)]) (printf "SIZE: ~s\n" s) (set! TEMP:tenv-sizes (cons s TEMP:tenv-sizes)))
    (let ([entry (assq sym (cdr tenv))])
      (if entry (cadr entry) #f)))
  ;; This returns #t if the let-bound flag for a given binding is set.
  ;; If sym is lambda-bound or is unbound in the type environment, #f is
  ;; returned.
  (define (tenv-is-let-bound? tenv sym)
    (DEBUGASSERT (tenv? tenv))
    (let ([entry (assq sym (cdr tenv))])
      (if entry (caddr entry) #f)))

  ;; Extends a type environment.
  ;; .param tenv The type env to extend.
  ;; .param syms The names to bind.
  ;; .param vals The types to bind (expects instantiated type vars).
  ;; .param flag Optional flag: #t for let-bound, #f (default) for lambda-bound.
  ;; .returns A new type environment.
  (define (tenv-extend tenv syms types . flag)
    (IFCHEZ (import rn-match) (void))
    (DEBUGASSERT (tenv? tenv))
    (DEBUGASSERT (andmap type? types))
    ;(DEBUGASSERT (andmap instantiated-type? types))
;    (let ([s (length tenv)]) (printf "SIZE: ~s\n" s) (set! TEMP:tenv-sizes (cons s TEMP:tenv-sizes)))
    (let ([flag (if (null? flag) #f (if (car flag) #t #f))])
      (cons (car tenv)
	    ;; This doesn't provide any speedup:
#;
	    (let loop ([v* syms] [t* types] [acc '()])
	      (if (null? v*)
		  (append! (reverse! acc) (cdr tenv))
		  (let-values ([(rhs flg) (build-entry (car v*) (car t*) flag)])
		    (loop (cdr v*) (cdr t*) (cons (list (car v*) rhs flg) acc)))
		  ))

	    (append! (map (lambda (v t)
                           (let-values ([(rhs flg) (build-entry v t flag)])
                             (list v rhs flg)
			     ))
		      
		      syms types)
		    (cdr tenv))
	    )))
  ;; This isn't used in WaveScope currently (it's legacy, from Regiment 1.0)
  (define (tenv-append . tenvs)
    (cons (car (empty-tenv)) 
	  (apply append (map cdr tenvs))))

  ;; Applies a function to all types in a type enviroment.
  (define (tenv-map f tenv)
    (IFCHEZ (import rn-match) (void))
    (DEBUGASSERT (tenv? tenv))
    (cons (car tenv)
	  (map 
	      (lambda (x) 
		(match x 
		  [(,v ,t ,flag) `(,v ,(f t) ,flag)]
		  [,other (error 'tenv-map "bad tenv entry: ~s" other)]))
	    (cdr tenv))))
) ;; End list-based TENV ADT.


;; Hash-table based tenvs:
;; RUNS SLOWER!
#;
(begin 

  (reg:define-struct (tenvrec types letbounds))

  (define (tenv-size tenv)
    (let ([count 0])
      (hashtab-for-each (lambda (k t) (set! count (fx+ 1 count)))
			(tenvrec-types tenv))
      count))

  (define default-tenv-size 100)

  (define (empty-tenv) 
    (make-tenvrec (make-default-hash-table default-tenv-size)
		  (make-default-hash-table default-tenv-size)))
  ;; TODO: this should be a deeper check:
  (define (tenv? x) (and (tenvrec? x) ))
  (define (tenv-lookup tenv v)        (hashtab-get (tenvrec-types     tenv) v))
  (define (tenv-is-let-bound? tenv v) (hashtab-get (tenvrec-letbounds tenv) v))
  
  ;; UNSAFE VERSION:
  ;; 
  ;; Here's the trick of the hash-table based version.  We assume that
  ;; variable names are unique, so we continue to use the old tenv,
  ;; and just add in new bindings.
  (define (tenv-extend tenv syms types . flag)
;    (let ([s (tenv-size tenv)]) (printf "SIZE: ~s\n" s) (set! TEMP:tenv-sizes (cons s TEMP:tenv-sizes)))
    (let ([flag (if (null? flag) #f (if (car flag) #t #f))]
	  [table1  (tenvrec-types     tenv)]
	  [table2  (tenvrec-letbounds tenv)])      
      (let tenv-extend-loop ([s* syms] [t* types])
	(when (not (null? s*))    
	  (DEBUGASSERT (lambda (s) (not (hashtab-get table1 s))) (car s*))
	  (let-values ([(rhs flg) (build-entry (car s*) (car t*) flag)])
	    (hashtab-set! table1  (car s*) rhs)
	    (hashtab-set! table2  (car s*) flg))
	  (tenv-extend-loop (cdr s*) (cdr t*)))))
    tenv)


  ;; This isn't used in WaveScope currently (it's legacy, from Regiment 1.0)
  (define (tenv-append . tenvs)
    (let ([table1 (make-default-hash-table default-tenv-size)]
	  [table2 (make-default-hash-table default-tenv-size)])
      (for-each (lambda (tenv)
		  (let ([letbounds (tenvrec-letbounds tenv)])
		    (hashtab-for-each 
		     (lambda (k t)
		       (hashtab-set! table1 k t)
		       (hashtab-set! table2 k (hashtab-get letbounds k)))
		     (tenvrec-types tenv))))
	tenvs)
      (make-tenvrec table1 table2)))
  
  ;; Applies a function to all types in a type enviroment.
  (define (tenv-map f tenv)
    (let ([new (make-default-hash-table default-tenv-size)])
      (hashtab-for-each
       (lambda (k ty) (hashtab-set! new k (f ty)))
       (tenvrec-types tenv))
      (make-tenvrec new (tenvrec-letbounds tenv))))
)


;; This extends a type environment, retrieving the variables to bind
;; by deconstructing a pattern.
;; Ultimately this will be a hotspot, so we should remove the use of map/append/etc below:
(define (tenv-extend-pattern tenv pat type)
  ;; This builds up a list of the vars & types:
  (define (extendpat-loop pat type)
    (match pat
      [,v (guard (symbol? v)) (list (vector v type))]
      [#(,p* ...) 
       (apply append (map extendpat-loop p* (vector->list type)))]      
      ))
  
  (match (extendpat-loop pat type)
    [(#(,v* ,t*) ...) (tenv-extend tenv v* t*)]))



; ======================================================================
;;; Unit tests.

;; Unit tester.
(define-testing test-type_environments 
  (default-unit-tester "Type Representations" 
    `(
      ["NUM must have vars attached" (type? '#((NUM Int) (NUM Float))) #f]
      [(type? '(NUM a)) #t]
      [(type? '(Int -> (NUM a))) #t]      
      
      [(type? '(Record 'i)) #t]
      [(type? '(Record #())) #t]
      [(instantiated-type? '(Record 'i)) #f]
      [(instantiated-type? '(Record (quote (awn . #f)))) #t]

      [(instantiated-type? '(HashTable Int (Record (Row LastLoc #(Uint8 Int Uint8) (Row Balance Int #()))))) #f]
      
      [(polymorphic-type? '#()) #f]
      [(polymorphic-type? '(-> Int)) #f]
  )))


) ;; End module
