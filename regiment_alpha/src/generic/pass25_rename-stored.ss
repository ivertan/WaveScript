
;; Renames all stored variables so that they are globally unique rather than per-handler unique.

(define rename-stored
  (let ()

;; The substitution is an association list binding token names to
;; association lists binding old-names to new-names.
(define process-expr 
  (lambda (subst this-tok expr)
  (define this-subst 
    (let ((entry (assq this-tok subst)))
      (if (not entry) (error 'rename-stored.process-expr "this-tok was not in subst list"))
      (cadr entry)))
  (match expr
;    [,x (guard (begin (disp "PEXP" x) #f)) 3]

    [(quote ,const) `(quote ,const)]
    ;; This is for recurring on tokens:
    [,num (guard (number? num)) num]
    [(tok ,t ,n) (guard (number? n)) `(tok ,t ,n)]
    [(tok ,t ,[e]) `(tok ,t ,e)]
    
    ;; Local stored var references and mutations.
    [,var (guard (symbol? var) (assq var this-subst))
      (cadr (assq var this-subst))]
    [(set! ,var ,[x])
     (guard (symbol? var) (assq var this-subst))
     `(set! ,(cadr (assq var this-subst)) ,x)]
        
    ;; External stored references:
    [(ext-ref ,t ,v)
     (let ((entry (assq (token->name t) subst)))
       (if (not entry)
	   (error 'rename-stored "got ext-ref to token that's not in subst: ~a" t))
       (let ((entry2 (assq v (cadr entry))))
	 (if (not entry2)
	     (error 'rename-stored "couldn't find binding for var ~a in token ~a" v t))
	 `(ext-ref ,t ,(cadr entry2))))]
    [(ext-set! ,t ,v ,[x])
     (let ((entry (assq (token->name t) subst)))
       (if (not entry)
	   (error 'rename-stored "got ext-set! to token that's not in subst: ~a" t))
       `(ext-set! ,t ,(cadr (assq v (cadr entry))) ,x))]
	 
    [,var (guard (symbol? var)) var]
    [(set! ,v ,[x]) 
					;	  (disp "Set! non local stored:" v)
     `(set! ,v ,x)]
    [(begin ,[xs] ...) `(begin ,xs ...)]
    ;; Shouldn't have to handle this:
    [(if ,[test] ,[conseq]) `(if ,test ,conseq)]
    [(if ,[test] ,[conseq] ,[altern])
     `(if ,test ,conseq ,altern)]
    [(let ([,lhs ,[rhs]]) ,[body])
     `(let ([,lhs ,rhs]) ,body)]
    ;; These are just primitives, they don't need their own form:
    ;[(return ,[x]) `(return ,x)]
    ;[(,call-style ,[args*] ...)
    ;(guard (memq call-style '(subcall call timed-call)))
    ; `(,call-style ,args* ...)]
    [(leds ,what ,which) `(leds ,what ,which)]
    [(,prim ,[rands] ...)
     (guard (or (token-machine-primitive? prim)
		(basic-primitive? prim)))
     `(,prim ,rands ...)]
	     ;;; TEMPORARY, We allow arbitrary other applications too!
    [(app ,[rator] ,[rands] ...)
     (warning 'rename-stored
	      "arbitrary application of rator: ~s" rator)	      
     `(app ,rator ,rands ...)]
    [,otherwise
     (error 'rename-stored:process-expr 
	    "bad expression: ~s" otherwise)]
    )))


(define (make-subst tbs)
  (map 
   (lambda (tb)
     (mvlet ([(tok id args stored constbinds body) (destructure-tokbind tb)])
	    (list tok (map (lambda (pr) (list (car pr) (unique-name (car pr))))
			   stored))))
   tbs))

(define (process-tokbind subst tb)
  (mvlet ([(tok id args stored constbinds body) (destructure-tokbind tb)])
	 `[,tok ,id ,args 
		(stored ,@(map list 
			       (map cadr (cadr (assq tok subst)))
			       (map cadr stored)))			    
		,(process-expr subst tok body)]))

(lambda (prog)
  (match prog
    [(,lang '(program (bindings ,constbinds ...)
		      (nodepgm (tokens ,toks ...))))          
     (let ([subst (make-subst toks)])
       ;(pretty-print subst)
       `(rename-stored-lang
	 '(program (bindings ,constbinds ...)
		   (nodepgm (tokens 
			     ,@(map (lambda (tb) (process-tokbind subst tb)) toks))))))])
)))
