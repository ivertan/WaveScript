
;;; NOTE: for the moment I AM ALLOWING USAGE OF ARBITRARY SCHEME FUNCTIONS HERE!

;;; [2004.06.28] Pass: Cleanup Token Machine
;===============================================================================

;; [2005.03.25] I'm making this pass pretty permissive so that I can
;; use it from multiple places.  It's permissive on its input grammar,
;; but strict with its output grammar.


;;; This pass has become a really big lowering pass.

;;;   (*) Regularizes the syntax of token machines.  Right now what it
;;;   does is include implicit begins,

;;;   (*) Collapses duplicate tokens with the same name into one token.

;;;   (*) Lift's the "socpgm" into a token handler called "SOC-start"
;;;   The grammar of the output has no socpgm.  We also insure that
;;;   the output has some SOC-start and node-start handler, even if
;;;   they are empty.

;;    (*) Throws away the "SOC bindings".  These become just the
;;    handler-local bindings for "SOC-start".
;; NOTE: [2005.03.25] Getting rid of node-local constant binds.
;; Whatever, let them all be global.


;;;   (*) Desugaring: It expands out some primitive applications
;;;   that are just shorthands.  (For example, (gdist) becomes
;;;   (gdist <this-token>)    ;;; TODO: not finished...
;;;   It also expands some syntaxes (and, or), and regularizes certain usages 
;;;   (greturn's arguments become ordered properly, defaults supplied).

;;;   (*) Should be IDEMPOTENT.  
;;;   Can run it multiple times or inbetween different passes.

;;;   (*) RENAME-VARS SHOULD RUN BEFORE THIS PASS.  It depends on
;;;   merging token handlers without collisions between stored vars
;;;   and constant bindings.



;;; INPUT GRAMMAR:

;; Extremely messy, ad-hoc, and lenient.


;;; OUTPUT GRAMMAR:

;;;  <Pgm> ::= (program (bindings <Cbind>*) <NodePgm>)
;;;  <NodePgm> ::= (nodepgm (tokens <TokBinding>*))
;       NOTE: tokens will inclide a binding for SOC-start and node-start
;;;  <Cbind> ::= (<var> <Exp>)
;       NOTE: These expressions will be statically calculable -- constants.
;;;  <TokBinding> ::= (<TokName> <SubtokId> (<Var> ...) (bindings <Cbind>*) (stored <Stored>) <Expr>)
;;;  <TokName>   ::= <Symbol> 
;;;  <SubtokId>  ::= <Integer>
;;;  <Token>     ::= (tok <Tokname> <Int>)
;;;  <DynToken>  ::= <Token>    | (tok <Tokname> <Expr>)
;;;     NOTE: Either the whole token reference or just the sub-index can be dynamic.
;;;  <Expr>      ::= (quote <Constant>)
;;;                | <Var>
;;;                | <DynToken>
;;;                | (set! <Var> <Expr>)
;;;                | (ext-ref <DynToken> <Var>)
;;;                | (ext-set! <DynToken> <Var> <Expr>)
;       NOTE: These are static token refs for now.
;;;                | (begin <Expr> ...)
;;;                | (let ((<Symbol> <Expr>)) <Expr>)
;;;                | (if <Expr> <Expr> <Expr>)
;;;                | (subcall <DynToken> <Expr>...)
;;;                | (return <Expr>)
;;;                | (<Prim> <Expr> ...)
;;;                | (<Expr> ...)
;;;                | (leds <Red|Yellow|Green> <On|Off|Toggle>)
;;;                | <GExpr>
;;;                | <Sugar> 
;;;  <GExpr>     ::= (gemit <DynToken> <Expr> ...)
;;;                | (greturn <Expr> (to <DynToken>) (via <DynToken>) (seed <Expr>) (aggr <Token>))
;;;                | (grelay <DynToken>) ;; NEED TO ADD RELAY ARGS!
;;;                | (gdist <DynToken>)
;;;                | (gparent <DynToken>)
;;;                | (gorigin <DynToken>)
;;;                | (ghopcount <DynToken>)
;;;                | (gversion <DynToken>)
;;;  <Sugar>     ::= (flood <Expr>)
;;;                | (elect-leader <Token> [<Token>])
                     ;; <TODO> optional second argument.. decider
;;;  <Prim> ::= <BasicPrim> 
;;;           | call | subcall | timed-call | bcast
;;;           | is_scheduled | deschedule | is_present | evict



;===============================================================================

;;; [2004.10.22]  Now this also will expand out flood/elect-leader.
;;; This pass is starting to do way too much work...

;; [2005.03.28]  Moving destructure-tokbind to helpers.ss

(define cleanup-token-machine
  (build-compiler-pass ;; This wraps the main function with extra debugging
   'cleanup-token-machine
   `(input)
   `(output (grammar ,full_but_clean_tml PassInput))
  (let ()

    ;; Uses constants DEFAULT_SUBTOK and DEFAULT_SUBTOK_VAR

    (define (handler->formals tb)
      (mvlet ([(tok id args stored bindings body) (destructure-tokbind tb)])
	     args))
    (define (handler->body tb)
      (mvlet ([(tok id args stored bindings body) (destructure-tokbind tb)])
	     body))
    (define (handler->subtokid tb)
      (mvlet ([(tok id args stored bindings body) (destructure-tokbind tb)])
	     id))
    (define (handler->stored tb)
      (mvlet ([(tok id args stored bindings body) (destructure-tokbind tb)])
	     stored))
  

    ;; [2005.03.27] Adding a somewhat unsafe hack (assumes all variables
    ;; renamed) that makes this do the right thing when it's given a begin
    ;; expression as opposed to a list.
    (define make-begin
      (lambda (expr*)
	(match (match `(begin ,@expr*)
		      ;; This means we messed up:
		      [(begin begin ,[expr*] ...) (apply append expr*)]
		      [(begin ,[expr*] ...) (apply append expr*)]
		      [,expr (list expr)])
	       [() '(void)]
	       [(,x) x]
	       [(,x ,x* ...) `(begin ,x ,x* ...)])))

    
    ;; This removes duplicates among the token bindings.
    ;; <TOOPTIMIZE> Would use a hash-table here for speed.
    ;; :: TokenBindings -> TokenBindings
    (define (remove-duplicate-tokbinds tbinds)
     ;  (disp "Removing token dups" tbinds)
      (let loop ((ls tbinds))
	(if (null? ls) '()
	    (let* ([tok (caar ls)]
		   [dups (filter (lambda (entry) (eq? tok (car entry))) (cdr ls))])
	      (if (null? dups)
		  (cons (car ls) (loop (cdr ls)))	    


		  ;(mvlet ([(tok id args stored bindings body) (destructure-tokbind all-handlers)])  	      
		  (let* ([all-handlers (cons (car ls) dups)]
			 [formals* (map handler->formals all-handlers)]
			 [body* (map handler->body all-handlers)]
			 [subid* (map handler->subtokid all-handlers)]
			 [stored* (map handler->stored all-handlers)]
			 [allstored (apply append stored*)]
			 ;; bindings ignored... no longer used.
			 )
		    (DEBUGMODE
		     (if (not (apply myequal? formals*))
		     (error 'remove-duplicate-tokbinds
			    "handlers for token ~s don't all take the same arguments: ~s" 
			    tok formals*))
		     (if (not (apply myequal? subid*))
		     (error 'remove-duplicate-tokbinds
			    "handlers for token ~s don't all take the same subtokids: ~s" 
			    tok subid*))
		     ;; Make sure there is no intersection between stored vars:
		     (let ((svars (map car allstored)))
		       (if (not (= (length svars) (length (list->set svars))))
			   (error 'remove-duplicate-tokbinds
			    "handlers for token ~s have overlapping stored vars: ~s" tok svars)))
		     )
		    (let ([mergedhandler
			   `[,tok ,(car subid*) ,(car formals*)
				  (stored ,@allstored)
				  ,(make-begin (snoc ''multiple-bindings-for-token
						     ;; FIXME: Is it really necessary to randomize??
						     ;(randomize-list body*)
						     body*
						     ))]
;		             (begin ,@body* 'multiple-bindings-for-token)
			     ])
;		  (disp "MERGED:" mergedhandler)
		      (cons mergedhandler
			    (loop (filter (lambda (entry) (not (eq? tok (car entry)))) (cdr ls)))))
		    ))))))

    (define process-expr 
      ;(trace-lambda cleanuptokmac:procexp 
      (lambda (env tokens this-token this-subtok)
	;; This just loops back with the same context:
	(define (loop x) ((process-expr env tokens this-token this-subtok) x))

	  (define-syntax check-tok
	    (syntax-rules ()
	      [(_ call tokexp)
	       (let ((name (match tokexp
				  [,s (guard (symbol? s)) s]
				  [(tok ,t) t]
				  [(tok ,t ,num) t]
				  [,other (error 'check-tok "(~s) invalid token: ~s" call other)])))
		 (if (not (memq name tokens))
		     (if (regiment-verbose)
			 (warning 'cleanup-token-machine
				  "~s to unknown token: ~s" call tokexp))))]))
	  (define (tokname? t) (memq t tokens))

	  (lambda (stmt)
	  (match stmt
;	     [,x (guard (begin (printf  "PEXPmatch ~s\n" x) #f)) 3]
		 
	     [,const (guard (constant? const))
		     `(quote ,const)]
	     [(quote ,const) `(quote ,const)]

	     [,t (guard (symbol? t) (memq t tokens))
		 `(tok ,t ,DEFAULT_SUBTOK)]

	     ;; Cleanup does not verify that this is a valid stored-reference.
	     ;; That's done elsewhere:
	     [(ext-ref ,t ,v) `(ext-ref ,(if (tokname? t) `(tok ,t ,DEFAULT_SUBTOK) t) ,v)]
	     [(ext-set! ,t ,v ,[x]) `(ext-set! ,(if (tokname? t) `(tok ,t ,DEFAULT_SUBTOK) t) ,v ,x)]

	     [(tok ,t) `(tok ,t ,DEFAULT_SUBTOK)]
	     ;; Static form
	     [(tok ,t ,n) (guard (number? n)) `(tok ,t ,n)]
	     ;; Dynamic form
	     [(tok ,t ,[e]) `(tok ,t ,e)]

	     [,var (guard (symbol? var))
		   (DEBUGMODE 
		    (cond 
		     [(memq var env) var]
		     [(memq var tokens)
		      
			(warning 'cleanup-token-machine
				 "reference to token name: ~s" var)]
		     [(token-machine-primitive? var) var]
		     [else (warning 'cleanup-token-machine
				    "unbound variable reference: ~s" var)]))
		   var]
	     [(set! ,var ,[x])
	      (DEBUGMODE 
	       (cond 
		[(memq var env) (void)]
		[(memq var tokens)		 
		 (warning 'cleanup-token-machine
			  "attempt to set! token name: ~s" var)]
		[else (warning 'cleanup-token-machine
			       "unbound variable reference in set!: ~s ~n  env ~s" 
			       var env)]))
	      `(set! ,var ,x)]

	     [(begin ,[x]) x]
	     [(begin ,[xs] ...)
	      (make-begin xs)]

	     [(and) ''#t]
	     [(and ,[a]) a]
	     [(and ,[a] ,b ...)
	      `(if ,a ,(loop `(and ,b ...))
		   '#f)]
	     [(or) ''#f]
	     [(or ,[a]) a]
	     [(or ,[a] ,b ...)
	      `(if ,a '#t
		   ,(loop `(or ,b ...)))]

	     [(if ,[test] ,[conseq] ,[altern])
	      `(if ,test ,conseq ,altern)]
	     [(if ,test ,conseq)
	      (loop `(if ,test ,conseq (void)))]

	     ;; Match lambdas because they might be used in inbetween stages. 
	     ;; (e.g. between cps and closure-convert)
	     [(lambda (,args ...) ,bodies ...)
	      ;; Be careful "this-token" might be lying if this lambda is really going to 
	      ;; be transformed into another token of its own.
	      `(lambda ,args (begin ,@(map (process-expr (append args env) tokens this-token this-subtok)
					  bodies)))]

	     [(let ([,lhs* ,[rhs*]] ...) ,bodies ...)
	      ;; Temporary, should rename vars:
	      (if (not (null? (intersection lhs* (apply append (map tml-free-vars rhs*)))))
		  (error 'cleanup-token-machine:process-expr "Temporarily not allowed to refer to let's lhss in rhss:"))
	      (let loop ((l lhs*) (r rhs*))
		(if (null? l)
		    (make-begin (map (process-expr (append lhs* env) tokens this-token this-subtok)
				     bodies))
		    `(let ([,(car l) ,(car r)])
		       ,(loop (cdr l) (cdr r)))))]

	     ;; Here we have letrec style binding.  Probably shouldn't.
	     [(let-stored ([,lhs* ,rhs*] ...) ,bodies ...)
	      (let ([newenv (append lhs* env)])
		(let ([loop (process-expr newenv tokens this-token this-subtok)])
		  `(let-stored ([,lhs* ,(map loop rhs*)] ...)
			       ,(make-begin (map loop bodies)))))]

	     ;; TODO: expand away let*
	     [(let* () ,[bodies] ...)  (make-begin bodies)]
	     [(let* ( [,l1 ,r1] ,rest ...) ,bodies ...)
	      (loop
	       `(let ([,l1 ,r1])
		  (let* ,rest ,bodies ...)))]


	     [(activate (tok ,t ,n) ,[args*] ...)
	      (guard (number? n))
	      `(if (not (token-scheduled? (tok ,t ,n)))
		   (call (tok ,t ,n) ,@args*)
		   (void))]

	     [(activate ,[e] ,[args*] ...)
	      (if (regiment-verbose) (printf "\nDesugaring activate call to: ~a args: ~a\n" e args*))
	      (match e
		[(tok ,t ,v) 
		 `(if (not (token-scheduled? ,e))
		      (call ,e ,@args*)
		      (void))]
		[,other
		 (let ([ind (unique-name 'ind)])       
		   `(let ((,ind ,e))
		      (if (token-scheduled? ,ind)
			  (call ,ind ,@args*)
			  (void))))])]

	     ;; TODO: check to see if the "tok" is a locally bound variable if it is not a tokname?
	     ;; Should give warning if not.
	     [(,call-style ,tok ,[args*] ...)
	      (guard (memq call-style '(gemit call bcast subcall)))
	      (check-tok call-style tok)	     
	      `(,call-style ,(if (tokname? tok)
				 `(tok ,tok ,DEFAULT_SUBTOK)
;				 `(tok ,tok)
				 tok)
			    ,args* ...)]
	     [(timed-call ,time ,tok ,[args*] ...)
	      (if (not (number? time))
		  (error 'cleanup-token-machine "first argument to timed-call must be a time!, not: ~a" time))
	      (check-tok 'timed-call tok)
	      `(timed-call ,time ,(if (tokname? tok)
				      `(tok ,tok ,DEFAULT_SUBTOK)
				      tok)
			   ,args* ...)]
	     [(return ,[x]) `(return ,x)] ;; A local return, not a gradient one.

	     [(grelay) `(grelay (tok ,this-token ,this-subtok))]
	     [(grelay ,tok) (guard (tokname? tok))
	      (check-tok 'grelay tok)
	      ;; There is some question here as to whether we should
	      ;; default to this-subtok or to Zero subtoken index.
	      `(grelay (tok ,tok ,this-subtok))]
	     [(grelay (tok ,t ,[e])) (check-tok 'grelay t)
	      `(grelay (tok ,t ,e))]
	     
	     ;; Expand this out to refer to the precise token...
	     ;; TODO FIXME TODO: change this to refer to the specific subtok_ind:
	     [(gdist)                         `(gdist (tok ,this-token subtok_ind))]
	     [(gdist (tok ,t ,[n]))           `(gdist (tok ,t ,n))]
	     [(gdist ,t) (guard (tokname? t)) `(gdist (tok ,t 0))]
	     [(gdist ,[e])                    `(gdist ,e)]

	     [(gparent)                         `(gparent (tok ,this-token subtok_ind))]
	     [(gparent (tok ,t ,[n]))           `(gparent (tok ,t ,n))]
	     [(gparent ,t) (guard (tokname? t)) `(gparent (tok ,t 0))]
	     [(gparent ,[e])                    `(gparent ,e)]

	     [(gorigin)                         `(gorigin (tok ,this-token subtok_ind))]
	     [(gorigin (tok ,t ,[n]))           `(gorigin (tok ,t ,n))]
	     [(gorigin ,t) (guard (tokname? t)) `(gorigin (tok ,t 0))]
	     [(gorigin ,[e])                    `(gorigin ,e)]

	     [(ghopcount)                         `(ghopcount (tok ,this-token subtok_ind))]
	     [(ghopcount (tok ,t ,[n]))           `(ghopcount (tok ,t ,n))]
	     [(ghopcount ,t) (guard (tokname? t)) `(ghopcount (tok ,t 0))]
	     [(ghopcount ,[e])                    `(ghopcount ,e)]

	     [(gversion)                          `(gversion (tok ,this-token subtok_ind))]
	     [(gversion (tok ,t ,[n]))            `(gversion (tok ,t ,n))]
	     [(gversion ,t) (guard (tokname? t))  `(gversion (tok ,t 0))]
	     [(gversion ,[e])                     `(gversion ,e)]
	     
	     [(greturn ,[expr]            ;; Value
		      (to ,memb)         ;; To
		      (via ,parent)      ;; Via
		      (seed ,[seed_vals] ...) ;; With seed
		      (aggr ,rator_toks ...)) ;; Aggregator 	      
	      (check-tok 'return-to memb)
	      (check-tok 'return-via parent)

	      (let ((seed (if (null? seed_vals) ''#f
			      (car seed_vals)))
		    (aggr (if (null? rator_toks) #f
			      (car rator_toks))))

		(define (fix-token t)
		  (match t
			 [,s (guard (symbol? s)) `(tok ,s 0)]
			 [(tok ,t) `(tok ,t 0)]
			 [(tok ,t ,n) `(tok ,t ,n)]))

		(if aggr (check-tok 'return-aggr aggr))
		`(greturn ,expr 
			 (to ,(fix-token memb)) 
			 (via ,(fix-token parent))
			 (seed ,seed) 
			 (aggr ,(if aggr (fix-token aggr) aggr))))]

	     ;; This fills in defaults for missing greturn parameters:
	     [(greturn ,thing ,stuff ...)
	      (if (or (not (andmap pair? stuff))
		      (not (set? (map car stuff)))
		      (not (subset? (map car stuff)
				    '(to via seed aggr))))
		  (error 'cleanup-token-machine
			 "process-expr: bad syntax for greturn: ~s" `(greturn ,stuff ...)))
	      (loop
	       `(greturn ,thing 
			,(assq 'to stuff)
			,(if (assq 'via stuff)
			     (assq 'via stuff)
			     `(via ,this-token))
			,(if (assq 'seed stuff)
			     (assq 'seed stuff)
			     '(seed '#f))
			,(if (assq 'aggr stuff)
			     (assq 'aggr stuff)
			     '(aggr #f))))]

	     [(leds ,what ,which) `(leds ,what ,which)]

	     [(,prim ,[rands] ...)
	      (guard (or (token-machine-primitive? prim)
			 (basic-primitive? prim)))
	      `(,prim ,rands ...)]

;	     [(,kwd ,stuff ...)
;	      (guard (base-keyword? kwd))
;	      (error 'cleanup-token-machine:process-expr 
;		     "keyword expression not allowed: ~s" stmt)]
	     
	     ;;; TEMPORARY, We allow arbitrary other applications too!

	     [(app ,[rator] ,[rands] ...)
	      (warning 'cleanup-token-machine
		       "free form app of rator: ~s" rator)
	      `(app ,rator ,rands ...)]

	     [(,[rator] ,[rands] ...)
	      (warning 'cleanup-token-machine
		       "arbitrary application of rator: ~s" rator)
	      (DEBUGMODE 
	       (if (or (not (symbol? rator)) (not (memq rator env)))
		   (warning 'cleanup-token-machine
			    "unbound rator: ~s" rator)))
	      `(app ,rator ,rands ...)]


	     [,otherwise
	      (error 'cleanup-token-machine:process-expr 
		     "bad expression: ~s" otherwise)]
	     ))))
    
    (define process-tokbind 
      (lambda (env tokens)
	(lambda (tokbind)
	  (mvlet ([(tok id args stored bindings body) (destructure-tokbind tokbind)])
		 (let ((baseenv (cons id (append args bindings env))))
		 (let ((newstored 
			(reverse
			 (cadr 
			  (foldl
			  (lambda (binding a)
			    (match a
				   [(,env ,stored)
				    (list 
				     (cons (car binding) env)
				     (cons (list (car binding) 
						 ((process-expr env tokens tok id) (cadr binding)))
					   stored))]))
			  (list baseenv '())
			  stored)))))
		 `(,tok ,id ,args (stored ,@newstored) ;(bindings ,@bindings)
			,((process-expr (append (map car stored) baseenv) tokens tok id)
			  body))))))))
	    
    (define decode 
      (lambda (lang stuff)
	(let ([bindings '()]
	      [socbindings '()]
	      [socpgm '()]
	      [nodetoks '()]
	      [node-startup '()])
	  (let loop ((ls stuff))
;	    (disp "Decoding:" (map car bindings) (map car socbindings)
;		  socpgm (map car nodetoks) node-startup)
;	    (disp "Decoding from" ls)
		 
	    (if (null? ls)
		(let ((result `(,lang
				'(program (bindings ,@bindings)
					  (socpgm (bindings ,@socbindings) ,@socpgm)
					  (nodepgm (tokens ,@nodetoks)
						   (startup ,@node-startup))))))
;		  (printf "cleanup-token-machine: Desugaring to: ~n")
;		  (pp result)
		  result)
		(begin 
		  (match (car ls)
			 [(bindings ,x ...) (set! bindings x)]
			 [(socbinds ,x ...) (set! socbindings x)]
			 [(socpgm (bindings ,b ...) ,x ...)  
			  (set! socbindings b)
			  (set! socpgm x)]
			 [(socpgm ,x ...)   (set! socpgm x)]
			 [(nodepgm (tokens ,x ...))
			  (set! nodetoks x)]
			 [(nodepgm (tokens ,x ...) (startup ,s ...))
			  (set! nodetoks x)
			  (set! node-startup s)]
			 [(nodetoks ,x ...) (set! nodetoks (append x nodetoks))]
			 [(tokens ,x ...) (set! nodetoks (append x nodetoks))]
			 [(startup ,x ...) (set! node-startup x)]
			 ;; TEMP: for my own convenience, I allow other expressions to 
			 ;; transform into node-startup code:
			 [,expr (set! nodetoks
				      (cons `[node-start () ,expr] nodetoks))]
			 [,other (error 
				  'cleanup-token-machine:decode
				  "this isn't part of a valid token machine program! ~n ~a"
				  other)])
		  (loop (cdr ls))))))))

    (define (cleanup lang socconsts nodeconsts socpgm tokens nodestartups)
      
      (let ((hasns (assq 'node-start tokens))
	    (hassts (not (null? nodestartups))))
	(if (not hasns)
	    (set! tokens
		  (cons `[node-start ()
			    (begin 
			      ,@(map (lambda (t) `(call ,t)) nodestartups)
			      (void)
			      )]
			tokens))
	    (if (and hasns hassts)
		(error 'cleanup-token-machine "TM has both a \"node-start\" token and designated \"startup\" tokens."))
	    ))

      (if (not (assq 'SOC-start tokens))
	  (set! tokens (cons `[SOC-start () (void)] tokens)))
      (if socpgm
	  (set! tokens (cons `[SOC-start () ,(make-begin socpgm)] tokens)))
      ;; This is a little weird.  It depends on the duplicate handler
      ;; merging below.  We push the constbinds into *one* SOC-start
      ;; handler, and if there are others, the bindings get to them
      ;; too during the merge.
; NEVERMIND, no more local const binds:
;      (if (not (null? socconsts))
;	  (set! tokens (cons `[SOC-start () (bindings ,@socconsts (void))] tokens)))
      ;; Instead, we merge together all binds:

      (let ([allconsts (append socconsts nodeconsts
			       (foldl (lambda (th acc)
					(mvlet ([(tok id args stored bindings body) 
						 (destructure-tokbind th)])
					       (append bindings acc)))
				      '() tokens))]
	    ;; Duplicate elimination happens before other processing of token handlers:
	    [nodup-toks (remove-duplicate-tokbinds tokens)])
	`(,lang
	     '(program (bindings ,@nodeconsts)
		       (nodepgm (tokens
				 ,@(map (process-tokbind (map car allconsts)
							 (map car nodup-toks))
					nodup-toks)))))
	))
  
     ;; Main body of cleanup-token-machine
     (lambda (prog)
       (let matchloop ((prog prog))
       (match prog
	;; If there is a specified input language, we don't change it.
	;; This pass is called from multiple places, so that would confuse things:
        [(,lang '(program (bindings ,constbinds ...)
			  (socpgm (bindings ,socbinds ...) 
				  ,socstmts ...)
			  (nodepgm (tokens ,nodetoks ...)
				   (startup ,starttoks ...))))
	 
; 	 (disp "Lang" lang
; 	       "constbinds" (map car constbinds)
; 	       "socbinds" (map car socbinds)
; 	       "socstmts" socstmts
; 	       "tokens" (map car nodetoks)
; 	       "starttoks" starttoks)

	 (cleanup lang socbinds constbinds 
                  (if (null? socstmts) #f `(begin ,@socstmts))
                  nodetoks 
		  starttoks)]
	[(,lang '(program ,stuff ...)) (matchloop (decode lang stuff))]
	;; Cleanup-token-machine is a real lenient pass.  
	;; It will take the token machines in other forms, such as
	;; without the language annotation:
	[(program (bindings ,constbinds ...)
		  (socpgm (bindings ,socbinds ...)
			  ,socstmts ...)
		  (nodepgm (tokens ,nodetoks ...)
			   (startup ,starttoks ...)))
	 (matchloop `(UNKNOWNLANG ',prog))]

	['(program ,stuff ...) (matchloop (decode 'cleanup-token-machine-lang stuff))]
	[(program ,stuff ...) (matchloop (decode 'cleanup-token-machine-lang stuff))]
	
	[,stuff (matchloop (decode 'cleanup-token-machine-lang (list stuff)))]
	))))))


;	 (let* ([initenv (map car bindings)]
;		[socenv (append (map car socbinds) initenv)]
;		[tokenv (map car nodetoks)]
;		[nodebinds (map (process-bind initenv) nodebinds)]
;		[socbinds  (map (process-bind socenv) socbinds)]
;		[socstmts (map (process-expr socenv)


;       	 `(,input-lang
;	   '(program (bindings ,nodebinds ...)
;		     (socpgm (bindings ,socbinds ...) ,(make-begin socstmts))
;		     (nodepgm (tokens ,nodetoks ...) 
;			      (startup ,starttoks ...))))
	   

(define these-tests
  `(
    
    ["Put an empty test through." 
     (cleanup-token-machine 
      '(deglobalize-lang 
	'(program
	  (bindings )
	  (socpgm (bindings ) )
	  (nodepgm (tokens) (startup ) ))))    
     (deglobalize-lang
      '(program
	(bindings)
	(nodepgm
	 (tokens
	  (SOC-start subtok_ind () (stored) (void))
	  (node-start subtok_ind () (stored) (void))))))]


    ["Now collapse two tokens of the same name"
     (cleanup-token-machine 
      '(deglobalize-lang 
	'(program
	  (bindings )
	  (socpgm (bindings ) (gemit tok1))
	  (nodepgm
	   (tokens
	    [tok1 () 'fun1]
	    [tok1 () 'fun2])
	   (startup )
	   ))))
     ,(lambda (p)
	(match p 
	  [(deglobalize-lang
	    '(program (bindings )
		      (nodepgm (tokens ,toks ...))))
           (let* ([tok1 (assq 'tok1 toks)]
                  [body (rac tok1)])
	   (and (deep-member? 'fun1 body)
		(deep-member? 'fun2 body)))]))]

    ["Test of greturn normalization #1"
     (deep-assq 'greturn
		(cleanup-token-machine 
		 '(deglobalize-lang 
		   '(program
		     (bindings ) (socpgm (bindings ) (gemit tok1))
		     (nodepgm
		      (tokens
		       [tok1 () (greturn 3 (to tok2) )]
		       [tok2 (x) 3])
		      (startup ))))))
     (greturn
      '3
      (to (tok tok2 0))
      (via (tok tok1 0))
      (seed '#f)
      (aggr #f))]
    
    ["Test of gdist normalization"
     (deep-assq 'gdist
		(cleanup-token-machine '(tokens (tok1 () (gdist)))))
     ,(lambda (x) (match x 
		   [(gdist (tok tok1 ,_)) #t]
		   [,_ #f]))]
	     
  
))



(define test-this (default-unit-tester
		    "21: Cleanup-Token-Machine: regularize syntax of token machine"
		    these-tests))


(define test21 test-this)
(define tests21 these-tests)
(define test-cleanup-token-machine test-this)
(define tests-cleanup-token-machine these-tests)


;; TODO RENAME
;; TODO USE IN THIS MODULE??  WHAT WAS LEFT UNDONE?
 (define find-emittoks_RENAME_ME
      (letrec ([tok-allowed-loop 
		(lambda (expr)
		  (match expr
			 [(tok ,t ,[main-loop -> e]) e]
			 [,e (main-loop e)]))]
	       [do-primitive
		(lambda (prim args)
		  (apply append
		  (map-prim-w-types 
		   (lambda (arg type)
		     (match (cons type arg)
		       [(Token . (tok ,tok ,[main-loop -> e])) e]
		       [(,other . ,[main-loop -> e]) e]))
		   prim args)))]
	       [main-loop
		(lambda (expr)
		  (match expr
	     ;[,x (guard (begin (printf "FindEmitToks matching: ~a~n" x) #f)) 3]
	     [(quote ,_) '()]
	     [,num (guard (number? num)) '()]
	     [,var (guard (symbol? var)) '()]
	     [(set! ,var ,[e]) e]
	     [(ext-ref (tok ,t ,[e]) ,v) e]
	     [(ext-set (tok ,t ,[e]) ,v ,[e2]) (append e e2)]
	     ;; If we ever have a first class reference to a token name, it is potentially tainted.
	     ;; This is a conservative estimate:
	     [(tok ,t ,n) (guard (number? n)) (list t)]
	     [(tok ,t ,[e]) (cons t e)]
	     [(begin ,[exprs] ...) (apply append exprs)]
	     [(if ,[exprs] ...) (apply append exprs)]
	     [(let ([,_ ,[rhs*]] ...) ,[body])	(apply append body rhs)]

	     ;; "Direct call":  Not allowing dynamic gemit's for now:
	     [(gemit (tok ,t ,[e]) ,[args*] ...)  (cons t (apply append e args*))]
	     ;; Indirect gemit call... could consider restricting these.
	     [(gemit ,[e] ,[args*] ...)
	      (error 'pass23_desugar-gradients "not allowing dynamically targetted gemits atm.")
	      ;(apply append e args*)
	      ]
	     ;; Also allowing dynamic relays and dists.  
	     ;; These don't matter as much because I'm basing 
	     [(grelay (tok ,t ,[e])) e]
	     [(gdist (tok ,t ,[e])) e]
	     [(parent (tok ,t ,[e])) e]
	     [(origin (tok ,t ,[e])) e]
	     [(hopcount (tok ,t ,[e])) e]
	     [(version (tok ,t ,[e])) e]

	     ;; The to's and the vias are static! Aggr has no subtok index!
	     [(greturn ,[expr] (to (tok ,t ,tn)) (via (tok ,v ,vn)) (seed ,[seed_val]) (aggr ,a))
	      (append expr seed_val)]

	     [(leds ,what ,which) '()]

	     ;; Static calls are allowed:
	     [(call (tok ,t ,[e]) ,[args*] ...) (apply append e args*)]
	     ;; Anything more dynamic makes us think the operand is potentially emitted.

	     [(return ,[e])  e]

#|	     [(call ,[args*] ...) (apply append args*)]
	     [(subcall (tok ,t ,[e]) ,[args*] ...) (apply append e args*)]
	     [(subcall ,[args*] ...) (apply append args*)]
	     [(bcast (tok ,t ,[e]) ,[args*] ...) (apply append e args*)]
	     [(bcast ,[args*] ...) (apply append args*)]
	     [(timed-call ,[time] (tok ,t ,[e]) ,[args*] ...) (apply append time e args*)]
	     [(timed-call ,[args*] ...) 
	      ;(disp "TIMED call to dynamic tokens...")
	      (apply append args*)]
|#	     
	     ;; All primitives that can take tokenss
	     [(,prim ,args* ...)
	      (guard (or (token-machine-primitive? prim)
			 (basic-primitive? prim)))
	      (do-primitive prim args*)
	      ]

	     [(app ,[rator] ,[rands] ...) (apply append rator rands)]
	     [,otherwise
	      (error 'desugar-gradient:find-emittoks
		     "bad expression: ~s" otherwise)]
	     ))])

	main-loop))