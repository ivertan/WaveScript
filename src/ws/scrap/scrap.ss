

'(let loop ([foo 0] [e heuth])
  (map-expression e
   (lambda (expr)
     (match expr
	    [,const (guard (simple-constant? const))
		    (box `(quote ,const))]
	    [,_ #f]))))
	   
(define (map-expression e f)
  (let loop ((e e))
    (let ([user (f e)])
      (if user
	  (unbox user)	
    (match e
	 [,const (guard (simple-constant? const))  `(quote ,const)]
	 [(quote ,const) `(quote ,const)]
	 [,var (guard (symbol? var)) var]
	 [(begin ,exp* ...) `(begin ,@(map loop exp*
	  ]
	 [(if ,[(process-value env tokens this-token) -> test]
	      ,[conseq] ,[altern]) `(if ,test ,conseq ,altern)]
	 ;; IF VALUES ARE NOT USED THEN DON'T LABEL WORRY ABOUT THEM.
	 [(let* ( (,lhs ,[rhs]) ...) ,[bodies] ...)
	  `(let*  ([,lhs ,rhs] ...)	,(make-begin bodies))]
	 
	 ;; HERE NEED TO DO CPS:
	 [(,call-style ,tok ,[args*] ...)
	  (guard (memq call-style '(emit call activate)))
	  `(,call-style ,tok ,args* ...)]
	 [(timed-call ,time ,tok ,[args*] ...)
	  `(timed-call ,time ,tok ,args* ...)]
	 
	 [(relay) '(relay)]
	 [(relay ,tok) `(relay ,tok)]
	 [(dist ,tok) `(dist ,tok)]	     
	 [(return ,[expr]            ;; Value
		  (to ,memb)         ;; To
		  (via ,parent)      ;; Via
		  (seed ,[seed_vals] ...) ;; With seed
		  (aggr ,rator_toks ...)) ;; Aggregator 	      
	  `(return ,expr 
		   (to ,memb) 
		   (via ,parent) 
		   (seed ,seed) 
		   (aggr ,aggr))]
	 [(leds ,what ,which) `(leds ,what ,which)]
	 
	 [(,prim ,[rands] ...)
	  (guard (or (token-machine-primitive? prim)
		     (basic-primitive? prim)))
	  `(,prim ,rands ...)]
	     ;;; TEMPORARY, We allow arbitrary other applications too!
	 [(,rator ,[rands] ...)
	  (warning 'cleanup-token-machine
		   "arbitrary application of rator: ~s" rator)
	  `(,rator ,rands ...)]	     
	 
	 [,otherwise
	  (error 'cleanup-token-machine:process-expr 
		 "bad expression: ~s" otherwise)]
	 )



















    

;; Oops, cycles might wreck this???
(define (lift-graph g)
  (let ((collect '()))
    (letrec ([get-obj 
	      (lambda (node)
		(let ((entry (assq node collect)))
		  (if entry (cadar entry)
		      (add-obj node))))]
	     [add-obj 
	      (lambda (node)
		(let ((exists (get-obj node collect)))
		  (set! collect 
			(cons (make-sim-object 
			       node '() 
			       (map get-obj (node-neighbors node))))))))]
      
			     
		       
  (for-each (lambda (node) 
	      (if 

	      

(define world (lift-graph graph))

(define compile-simulate-nought
  (let ()

    (lambda (prog)
      (match prog
	     [(program (socpgm ,socbinds ,socstmts ...) 
		       (nodepgm ,nodebinds ,nodetoks))
	      (






(begin (let* () (begin (call result_2)))
       (let* ([tmp_4 (cons '40 '())] [tmp_1 (cons '30 tmp_4)])
         (letrec ([f_token_tmp_3 (lambda () (flood token_6))]
                  [token_6
                   (lambda ()
                     (if (< (locdiff (loc) tmp_1) 10.0)
                         (elect-leader m_token_tmp_3)))]
                  [m_token_tmp_3 (lambda () (call f_token_result_2))]
                  [f_token_result_2 (lambda () (emit m_token_result_2))]
                  [m_token_result_2
                   (lambda ()
                     (if (< (dist f_token_result_2) '50) (relay)))]
                  [handler
                   (lambda (msg args)
                     (case msg
                       [((f_token_tmp_3) (apply f_token_tmp_3 args))
                        ((token_6) (apply token_6 args))
                        ((m_token_tmp_3) (apply m_token_tmp_3 args))
                        ((f_token_result_2) (apply f_token_result_2 args))
                        ((m_token_result_2)
                         (apply m_token_result_2 args))]))])
           (f_token_tmp_3))
))







     (define amend-tainted
	(let ()
	  (define (kify e) `(call k ,e))
	  (define (put-k expr)
	    (match expr
		   [,const (guard (simple-constant? const)) (kify `(quote ,const))]
		   [(quote ,const) (kify `(quote ,const))]
		   [,var (guard (symbol? var)) (kify var)]
		   [(tok ,tok) (kify `(tok ,tok))]
		   [(tok ,tok ,[expr]) (kify `(tok ,tok ,expr))]
		   [(ext-ref ,tok ,var) (kify `(ext-ref ,tok ,var))]
		   [(ext-set! ,tok ,var ,[expr]) (kify `(ext-set! ,tok ,var ,expr))]
		   [(set! ,v ,[e]) `(begin `(set! ,v ,e) ,(kify '(void)))]
		   ;; This case shouldn't be used:
		   [(begin) '(begin)]
		   [(begin ,xs ...) 
		    `(begin ,@(rdc xs) ,(kify (rac xs)))]
		   [(if ,test ,[conseq] ,[altern])
		    `(if ,test ,conseq ,altern)]
		   [(let ( (,lhs ,[rhs]) ...) ,body)	 
		    `(let  ([,lhs ,rhs])
		       ,(kify body))]
		   [(leds ,what ,which) (kify `(leds ,what ,which))]
		   [(,prim ,rands ...)
		    (guard (or (token-machine-primitive? prim)
			       (basic-primitive? prim)))
		    (kify `(,prim ,rands ...))]
		   [(,[rator] ,[rands] ...) 
		    (kify `(,rator ,rands ...))]
		   [,otherwise
		    (error 'cps-tokmac:number-freevars 
			   "bad expression: ~s" otherwise)]))
	  (define do-amend
	    (lambda  (tokbind)	      
	      (mvlet ([(tok id args stored constbinds body) (destructure-tokbind tokbind)])
		     (if (not (null? constbinds)) (error 'cps-tokmac "Not expecting local constbinds!"))
		     `(,tok ,id (k ,@args) (stored ,@stored)
			     ,(put-k body)))))	  
	  (lambda (tokbinds)
	    (disp "AMEND TAINTED..." (length tokbinds))
	    (map do-amend tokbinds))))
