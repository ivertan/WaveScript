;(require (lib "trace.ss") (lib "iu-match.ss") "../plt/helpers.ss")

;;; Pass 10: deglobalize
;;; April 2004
;===============================================================================

;;; This pass represents the biggest jump in the compiler.  It
;;; transforms my simplified global language into a local program to
;;; be run in each node in the sensor network.


;;; Input grammar:

;;; <Pgm>  ::= <Let>
;;; <Let>  ::= (lazy-letrec (<Decl>*) <var>)
;;; <Decl> ::= (<var> <Exp>)
;;; <Exp>  ::= <Simple>
;;;          | (if <Simple> <Simple> <Simple>)
;;;          | (lambda <Formalexp> <Let>)
;;;          | (<primitive> <Simple>*)
;;; <Formalexp> ::= (<var>*)
;;; <Simple> ::= (quote <Lit>) | <Var>

;;; Output grammar:

;;; RRN: Should we introduce a simple imperative language here???

;;;  <Pgm> ::= (program (bindings <Decl>*) <SOCPgm> <NodePgm>)
;;;  <SOCPgm> ::= <Statement*>
;;;  <NodePgm> ::= (nodepgm <Entry> (bindings <Decl>*) (tokens <TokBinding>*))
;;;  <Entry>  ::= <Token>
;;;  <Decl> ::= (<var> <Exp>)
;;;  <TokBinding> ::= (<Token>  <Code>*)
;;; <TODO> DECIDE ON LOCAL BINDINGS:
;;;  <TokBinding> ::= (<Token> (bindings <Decl>*) <Code>*)

;;;  <Code> ::= <Statement>*
;;;  <Statement>  ::= <BasicStuff?>
;;;                | (emit <Token> <Simple>*)
;;;                | (relay <Token>)
;;;                | (dist <Token>)
;;;                | (return <Token> <Simple>)
;;;                | <Macro> 
;;;  <Macro> ::= (flood <Token>)
;;;            | (elect-leader <Token> [<Token>])  ;; <TODO> optional second argument.. decider
;;;  <Simple> ::= (quote <Lit>) | <Var>

;;;  <Token> ::= <Symbol> | ...???
;;;  <Exp>  ::= ???

;;========================================
;; EXAMPLE:

;; This program just returns 3.  It has a generic binding defining a
;; single constant, it has no startup tokens (startups must be
;; *tokens* not other bindings.)  It has no socpgm-exclusive bindings,
;; and the socprogram merely returns the single value, then finishes.
'(program
  (bindings (result '3))
  (socpgm (bindings ) (soc-return result) (soc-finished))
  (nodepgm (tokens ) (startup )))

;===============================================================================
;; Some CHANGES (not keeping a complete log):

;;[2004.06.09] RRN: Adding a 'soc-return' form.  Anything

;;[2004.06.09] RRN: Adding implicit 'I-am-SOC' boolean variable for
;; use by node programs.. This is only for generated code, or my
;; handwritten test cases.

;; [2004.06.13] RRN: Moved functions for dealing with token names into helpers.ss

;===============================================================================

(define proptable 'not-defined-yet)

(define (check-prop p s)
  (let ((entry (assq s proptable)))
    (if entry (memq p (cdr entry))
	(error 'pass10_deglobalize:check-prop
	       "This should not happen!  ~nName ~s has no entry in ~s."
	       s proptable))))

    (define (simple? x) 
      (match x
          [(quote ,imm) #t]
          [,var (guard (symbol? var)) #t]
	  [,otherwise #f]))

    (define symbol-append
      (lambda args
	(string->symbol (apply string-append (map symbol->string args)))))


;; (Name, DistributedPrim, Args) -> TokenBinds
;; This produces a list of token bindings.
(define explode-primitive
  (lambda (form memb prim args)
;	(disp "Explode primitive" name prim args)
	  (case prim
	    [(sparsify) (void)]

	    [(anchor-at)
	     (let ([consider (new-token-name)]
		   [leader (new-token-name)]
		   [target (car args)])
	       `([,form () (flood ,consider)]
		 [,consider () (if (< (locdiff (loc) ,target) 10.0)
				   (elect-leader ,memb)
				   '#f)]))]

	    [(circle)
	     (let ([rad (car args)]
		   [anch (cadr args)])
;		   (arg (unique-name 'arg)))
	       `(
		 [,(get-membership-name anch) () (call ,form)]
		 [,form () (emit ,memb)]
		 [,memb () (if (< (dist ,form) ,rad) (relay))]
		 )
	       )]

#;	    [(circle-at)
	     (let ([rad (cadr args)]
		   [loc (car args)])
	       `(
		 [,form () (emit ,memb)]
		 [,memb () (if (< (dist ,form) ,rad) (relay))]
		 ))]	   
		 
	    [(union)
	     `([,form () (begin
			(iftok (and ,(get-membership-name (car args)) 
				    ,(get-membership-name (cadr args)))
			       (add ,memb)))]
	       ;; These may be duplicate token entries:
	       [,(get-membership-name (car args))  () (begin (call ,form))]
	       [,(get-membership-name (cadr args)) () (begin (call ,form))]		       	     
    ;	       [,memb ... Don't know what yet... that depends on varrefs ]
	       )]

	    [else `([UNHANDLED-EXPLODE-PRIM (,prim) (void)])])))


    ;; LetrecExpr -> (Entry, Cbinds, TokenBinds)
    ;; This produces a list of constant bindings, token bindings, and
    ;; a token entry point of zero arguments.  The entrypoint is the
    ;; root, or finally returned edge of the data flow graph...
    (define process-letrec
      (lambda (expr)
        (match expr
	       [(lazy-letrec ([,lhs* ,rhs*] ...) ,body)
		(if (symbol? body)
		    (let loop ((lhs* lhs*) 
			       (rhs* rhs*)
			       (cacc '())
			       (tacc '()))
		      (if (null? lhs*)
			  (values (if (check-prop 'distributed body)
				      (mvlet (((form memb) (token-names body)))
					     form)
				      body)
				  cacc tacc)
			  ;; UHH TODO: membership or formation?
					;(map get-formation-name lhs*) 
			  (mvlet ([(cbinds tbinds) (process-expr (car lhs*) (car rhs*) )])
;				 (disp "GOT CBINDS TBINDS:" cbinds tbinds)
				 (loop (cdr lhs*) (cdr rhs*)
				       (append cbinds cacc) 
				       (append tbinds tacc)))))
		    (error 'deglobalize "Body of letrec should be just a symbol at this point."))]
	  )))


   ;; This produces code for returning the value from a particular
   ;; primitive application to the SOC.
(define primitive-return
  (lambda (prim tokname)
    (case prim
      [(anchor-at)
       `([,tokname ()
	  ;; At each formation click, we output this node.
	  (soc-return (list 'ANCH this))])]

      [(circle-at)     
       `([,tokname 
	  ()
	  ;; At each formation click, we output this circle: 
	  ;;   For now this just lists the tokname, this should be the
	  ;; membership tokname for the circle.  Later we'll put some
	  ;; other hack in.
	  (soc-return '(CIRC ,tokname))])]

      [(circle)
       `([,tokname 
	  ()
	  ;; At each formation click, we output this circle: 
	  ;;   For now this just lists the tokname, this should be the
	  ;; membership tokname for the circle.  Later we'll put some
	  ;; other hack in.
	  (soc-return '(CIRC ,tokname))])]
      
      [(smap)
       `([,tokname (v) (soc-return v)])]
      
      [else (error 'primitive-return 
		   "This function incomplete; doesn't cover: ~s. Ryan, finish it! "
		   prim)]
      )))

   ;; (Name, Expr) -> (Cbinds, TokenBinds)
   ;; This processes an expression and returns both its constant
   ;; bindings, and it's token bindings.
    (define process-expr
      (lambda (name expr)	
	(let ((finalname (check-prop 'final name)))
        (match expr
          ;; The possibility that the final value is local is
	  ;; handled in 'deglobalize' so we don't worry about it here:
	  [,x (guard (simple? x))      
	      (values `([,name ,expr]) ;`([,name (begin (return ,x))])
		      '())  ]
	  
          ;; All args are simple:
          [(if ,test ,conseq  ,altern)
	   (values `([,name ,expr]) '())]
;               ,[test-binds   test-toks] 
;	       ,[conseq-binds conseq-toks] 
;	       ,[altern-binds altern-toks])
;	   (values (append test-binds conseq-binds altern-binds)
;		   (append test-toks conseq-toks altern-toks))]


  	 ;; Don't need to make a new token name, the name of this
  	 ;; function is already unique:
	  [(lambda ,formalexp ,[process-letrec -> entry constbinds tokenbinds])
;	   (if (not (null? tokenbinds))
;	       (error 'deglobalize 
;		      "Should not get any tokens from internal letrec right now!: ~s"
;		      tokenbinds))
	   (values '() 
		   (cons `[,name ,formalexp (lazy-letrec ,constbinds (call ,entry))]
			 tokenbinds))]

	  ;; TODO:
          [(,prim ,rand* ...) (guard (basic-primitive? prim))
	   (values `([,name ,expr]) '())]

          [(,prim ,rand* ...) (guard (distributed-primitive? prim))   
	   (mvlet ([(form memb) (token-names name)])
		  (values '() 
			  (append 
			   (explode-primitive form memb prim rand*)
			   (if finalname
			       (primitive-return prim memb)
			       '()))
			  ))]
	  
          [,unmatched
            (error 'deglobalize "invalid expression: ~s"
                   unmatched)]))))

(define deglobalize
  (let ()

    (lambda (prog)
;      (pretty-print prog) (newline)
      (match prog
        [(,input-language (quote (program (props ,table ...) (lazy-letrec ,binds ,fin))))
	 ;; This is essentially a global constant for the duration of compilation:
	 (set! proptable table)
	 	 
	 ;; Make sure the final value is tagged simple:
;	 (if (memq 'local (assq fin proctable))
;	 (let ((temp (filter (lambda (ls) (memq 'final ls)

	 (mvlet ([(entry constbinds tokenbinds) (process-letrec `(lazy-letrec ,binds ,fin))])
		
   ;	       (disp "Got the stuff " entry constbinds tokenbinds (assq entry constbinds))
		;; This pass uses the same language as the prior pass, lift-letrec
					;`(,input-language '(program ,body))
		`(deglobalize-lang '(program 
				     (bindings ,@constbinds)
				     ,(if (assq entry constbinds)
					  ;; Socpgm bindings are null for now:
					  `(socpgm (bindings ) (soc-return ,entry) (soc-finished))
					  `(socpgm (bindings ) (call ,entry)))
			      (nodepgm (tokens ,@tokenbinds)
				       				       
				       ;; <TODO> It's the LEAVES that need priming:
				       ,(if (assq entry constbinds)
					    `(startup )
					    ;; How did this make sense:
					;`(startup ,entry)
					    `(startup )
					    )
				       ))))
	 ]))))

;;;  <Pgm> ::= (program <SOCPgm> <NodePgm>)
;;;  <SOCPgm> ::= <Statement*>
;;;  <NodePgm> ::= (nodepgm <Entry> (bindings <Decl>*) (tokens <TokBinding>*))



;========================================

(define these-tests 
  `(
;    [(lazy-letrec () '3) unspecified]

    [(mvlet ([(a b) (get-names 'x)]) (list a b))
     (f_token_x m_token_x)]

    [(deglobalize '(lang '(program 
			   (props [result_1 final local])
			   (lazy-letrec ((result_1 '3)) result_1))))
     unspecified]

    [(deglobalize '(lang '(program 
			   (props [b local]
				  [a local]
				  [anch distributed anchor]
				  [circ distributed final region]
				  )
			   (lazy-letrec
			    ((b (cons '2 '()))
			     (a (cons '1 b))
			     (anch (anchor-at a))
			     (circ (circle '50 anch)))
			    circ))))
     unspecified]
  ))


(define test-this (default-unit-tester
		    "Pass10: Pass to convert global to local program."
		    these-tests))

#;(define test-this
  (let ((these-tests these-tests))
    (lambda args 
      (let ((verbose (memq 'verbose args)))	
	(let ((tests (map car these-tests))
	      (intended (map cadr these-tests)))
	  (let ((results (map eval tests)))
	    (if verbose 
		(begin
		  (display "Testing pass to convert global to local program.")
		  (newline)
		  (newline) (display "Here are intended results:") (newline)
		  (write intended) (newline) (newline)
		  (newline) (display "Here are actual results:") (newline)
		  (write results) (newline) (newline)))
	   
	    (equal? intended results)))))))  

(define test10 test-this)
(define tests10 these-tests)

;==============================================================================




'(t '(letrec ((a (anchor-at '(30 40)))
		(r (circle-at 50 a))
		(f (lambda (tot next)
		     (cons (+ (car tot) (sense next))
			   (+ (cdr tot) 1))))
		(g (lambda (tot) (/ (car tot) (cdr tot))))
		(avg (smap g (rfold f (cons 0 0) r)))
		)
	 3))

'(deglobalize-lang
  '(program
     (socpgm (call result_12))
     (nodepgm
       result_12
       (bindings
         ((tmp_13 (cons '40 '()))
          (tmp_14 (cons '0 '0))
          (result_12 '3)
          (tmp_9 (cons '30 tmp_13))))
       (tokens
         ((g_2 (lazy-letrec
                 ((tmp_16 (cdr tot_6))
                  (tmp_17 (car tot_6))
                  (result_10 (/ tmp_17 tmp_16)))
                 (call result_10)))
          (f_4 (lazy-letrec
                 ((tmp_18 (cdr tot_8))
                  (tmp_19 (+ tmp_18 '1))
                  (tmp_21 (car tot_8))
                  (tmp_22 (+ tmp_21 tmp_20))
                  (result_11 (cons tmp_22 tmp_19)))
                 (call result_11)))
          (f_token_a_5 () (flood token_24))
          (token_24
            ()
            (if (< (locdiff (loc) tmp_9) 10.0)
                (elect-leader m_token_a_5))))))))






'(program ;;result???
	 (binds [target '(30 40)])
	 (tokens [form_a () (flood consider)] 
		 [consider () (if (< (locdiff (loc) (target)) 10.0)
			       (elect-leader memb_a)
			       '#f)]
		 [memb_a () (call form_r)]
		 [form_r () (emit memb_r)]
		 [memb_r () (begin (if (< (dist) 50) 
				       (relay))
				   (call fold_it))]
		 [memb_r:ret (v) (call map_it v)]
		 [fold_it () (return memb_r (aggregator f) (sense))]
		 [f (x y) (+ x y)]
		 
		 [map_it (v) (call g v)]
		 [g (v) (begin (...) (output __))]
		 )
	 )

'(f_token_result_2
  ((m_token_tmp_3 () (call f_token_result_2))
   (f_token_result_2 () (emit m_token_result_2))
   (m_token_result_2
    ()
    (if (< (dist f_token_result_2) '50) (relay)))
   (f_token_tmp_3 () (flood token_6))
   (token_6
    ()
    (if (< (locdiff (loc) tmp_1) 10.0)
	(elect-leader m_token_tmp_3)))))