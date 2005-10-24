
;; This removes various sugar:
;;  *) soc-return
;;  *) elect-leader
;;  *) flood

;; ======================================================================

;; [2005.04.20]
;; Soc-return's are a strange beast.

;; [2005.10.02] I was just doing this in cleanup-tokmac, but I'm going to move it here.

;; [2005.10.12]
;; For now we're only allowing soc-returns from the base-station node,
;; there is no implicit "global tree" in TML.  (Regiment does generate
;; code for such a global tree, but TML makes no such assumption.)

(define desugar-macros
  (let ()

  (define (process-expr expr)
       (tml-generic-traverse
	;; Driver:
	(lambda (x autoloop)
	  (define (process-tok t)
	    (match t
	      [(tok ,name ,n) (guard (integer? n))
	       (vector `(tok ,name ,n) ())]
	      [(tok ,name ,e) 
	       (match (autoloop e)
		 [#(,v ,tbs) (vector `(tok ,name ,v) tbs)])]
	      [,other (error 'desugar-macros:process-tok "bad token: ~a" other)]))

	  (match x
	     ;; For now this is just syntactic sugar for routing on the global tree:   
	     ;; return-retry indi
	     [(soc-return ,[autoloop -> x])
	      (match x
		[#(,v ,tbs)
		 (vector
		  (let ([socretval (unique-name 'socretval)])
		    `(let ([,socretval ,v])
		       (if (= (my-id) ',BASE_ID)
			   (begin 
			     ,@(DEBUGMODE `(dbg '"Soc return on basenode, returning directly: %d" ,socretval))
			     (call (tok SOC-return-handler 0) ,socretval))
			   (dbg '"ERROR: soc-return called on node other than base station, node id: %d" (my-id))
			   ;; Disabling for now, don't want to assume global-tree
			   #;
			   (greturn ,socretval 
				   (to (tok SOC-return-handler 0)) 
				   (via (tok global-tree 0))
				   (seed '#f)
				   (aggr #f)
				   ))))
		  tbs)])]
	     ;; Sending to subtok 1 indicates that we're finished.
;	     [(soc-return-finished ,x)
;	      (loop `(return ,x (to (tok SOC-return-handler 1)) (via (tok global-tree 0))))]

	     [(flood ,[process-tok -> tok])
	      (let-match ([#(,t ,tbs) tok])
		 (let ((newtok (unique-name 'floodtok)))
		   (vector
		    `(gemit (tok ,newtok (my-id)))
		    `([,newtok subid () 
			       (grelay (tok ,newtok subid))
			       (call ,t)]
		      ,@tbs))))]
	    
	     ;; FIXME: doesn't work yet:
	     [(elect-leader ,t)
	      (let* ((compete (unique-name 'compete))
		     (storagename (unique-name 'leaderstorage))
		     (storage `(tok ,storagename 0))
		     (cur-leader (unique-name 'cur-leader))
		     (check-winner (unique-name 'am-i-winner))
		     (id (unique-name 'subtokid)))
		(vector
		 `(begin 
		    (gemit (tok ,compete (my-id)))
		    (timed-call 1000 ,check-winner)
		    )
		 `([,storagename () (stored [,cur-leader #f]) (set! ,cur-leader (my-id))]
		   [,compete ,id () 		 
		    (if (token-present? ,storage )
			(void)
			(subcall ,storage))
		    (if (< ,id (ext-ref ,storage ,cur-leader))
			(begin 
			  (printf '"(~a ~a) " id (ext-ref ,storage ,cur-leader)) 
			  (ext-set! ,storage ,cur-leader ,id)
			  (grelay (tok ,compete ,id)))
			(begin 
			  (printf '"~a "(ext-ref ,storage ,cur-leader))
			  ))]
		   [,check-winner ()
		      (if (= (ext-ref ,storage ,cur-leader) (my-id))
			  (call ,t)
			  (void))])
		 ))]
	     
	     [,other (autoloop other)]))
	;; Fuser:
	(lambda (subresults reconstruct)
	  (match subresults
	    [(#(,arg* ,newtbs*) ...)
	     (vector (apply reconstruct arg*)
		     (apply append newtbs*))]))
	;; Expression:
	expr))

  (define (process-tokbind tb)
    (mvlet ([(tok id args stored constbinds body) (destructure-tokbind tb)])
      (match (process-expr body)
	[#(,newbod ,tbs)
	 (cons `[,tok ,id ,args (stored ,@stored) ,newbod]
	       tbs)]
	[,other (error 'desugar-macros:process-tokbind "BUG: invalid returned val from process-expr: ~a")])))

  (lambda (prog)
    (match prog
      [(,lang '(program (bindings ,constbinds ...)
		 (nodepgm (tokens ,toks ...))))
       `(desugar-macros-lang
	 '(program (bindings ,constbinds ...)
	    (nodepgm (tokens 
			 ,@(apply append (map process-tokbind toks))))))]))
  ))




(define these-tests
  `(
    ,@(let ((randomprog
	     '(desugar-macros-lang
	      '(program
		(bindings)
		(nodepgm
		 (tokens
		  (node-start subtok_ind () (stored) (void))
		  (SOC-start subtok_ind () (stored)
		   (begin
		     (printf '"~a " (token-scheduled? (tok tok1 0)))
		     (timed-call 500 (tok tok1 0))
		     (timed-call 100 (tok check 0))
		     (timed-call 800 (tok check 0))))
		  (tok1 subtok_ind () (stored) (printf '"tok1 "))
		  (check subtok_ind () (stored)
		   (printf '"~a " (token-scheduled? (tok tok1 0))))))))))
       
      `(
	["Just make sure we get the same thing back for a prog without soc-return:"
	 (desugar-macros ',randomprog)
	 ,randomprog]
	))   

    ))

(define test-this (default-unit-tester
		    "22: Desugar-Macros: expand various macros"
		    these-tests))

(define test22 test-this)
(define tests22 these-tests)
