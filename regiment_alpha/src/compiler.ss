;; This is the core.  Loaded by both the Chez and PLT versions.

;;======================================  
;(display "Loading main compiler module.  RegionStreams Demo.")
;(newline)

(define-regiment-parameter regiment-version 0.59)

;; This is a global variable mutated by the node-programs in the
;; simulator_nought...  Counts total communications received.
;;(define total-messages 0)
;; Moved this *again*.  Now the simulator just defines this (via
;; eval), when it starts running.

(define pass-names
  '(verify-regiment
    eta-primitives
    rename-var
    remove-unquoted-constant                        ;;  5
    
    static-elaborate
    
    reduce-primitives    
    remove-complex-constant                         ;;  7
    uncover-free                                    ;; 14
    ;    convert-closure                                 ;; 15
    lift-letrec                                     ;; 16
    lift-letrec-body                                ;; 22
    remove-complex-opera*
    verify-core
    classify-names
    add-heartbeats
    add-control-flow
    add-places
    ;    add-routing
    analyze-places
    deglobalize
    
    cleanup-token-machine    
    desugar-soc-return
    desugar-gradients
    cleanup-token-machine   ;; Rerun to expand out some stuff.
    
    ;    analyze-tokmac-recursion
    ;    inline-tokmac

;    desugar-let-stored
;    rename-stored

;; Temporarily I am disabling these ..
    cps-tokmac
    closure-convert

    cleanup-token-machine ;; Trying this.. [2005.09.27]

    ;; moving these after closure-convert.  WHY? Can't remember atm [2005.09.27]
;; [2005.09.27] OH.  I moved them because I didn't want cps to split references to 
;; a let-stored variable across two tokens.  (That gets messy, one has to use ext-ref.)
    desugar-let-stored
;    rename-stored

    ;    verify-token-machine
    ;    haskellize-tokmac 
    ))


;; ==================================================================
;; Functions for input/output to filesystem and for invoking compiler.

(define (dump-tokenmachine-to-file prog fn)
  (match prog
    [(haskellize-tokmac-language ,str)
     (with-output-to-file fn
       (lambda () (display str) (newline))
       'replace)]
    ;; If it's an earlier file, pretty print it:
    [(,lang ,prog)
     (with-output-to-file fn
       (lambda () (pretty-print `(,lang ,prog)))
       'replace)]
    [,other (error 'dump-tokenmachine-to-file "invalid input: ~S" prog)]))

;; This dumps to file only when provided the optional string filename argument:
;; The symbolic options are:  'barely-tokens 'almost-tokens 'almost-haskell 'haskell-tokens
(define (run-compiler p . args )
  (let ([filename #f]
	[passes pass-names]
	[verbose #f]
	;; If there are still values that need to be evaluated and filled in in the TM, do it.
	[p (match p
	     [(quasiquote ,_) (eval p)]
	     [,_ p])])
    (for-each (lambda (arg)
		(cond
                  [(string? arg) ;; It's an output filename.
                   (set! filename arg)]
		  [(eq? arg 'verbose) (set! verbose #t)]
		  ;; The pass-names may have already been restricted to be just the TML passes:
                  [(eq? arg 'barely-tokens)
                   (set! passes (list-remove-first 'cleanup-token-machine
				  (list-remove-after 'cleanup-token-machine pass-names)))]
                  [(eq? arg 'almost-tokens)
                   (set! passes (list-remove-first 'deglobalize ;; <- might fizzle
				  (list-remove-first 'cleanup-token-machine
                                     (list-remove-after 'cleanup-token-machine pass-names))))]
                  [(eq? arg 'almost-haskell)
                   (set! passes (remq 'haskellize-tokmac pass-names))]
                  [(eq? arg 'haskell-tokens) (void)]))
	      args)
    (when verbose
	  (printf "Running compiler with pass-names: \n")
	  (pretty-print passes))
    (let ((funs (map eval passes)))
      (let loop ([p p] [funs funs] [names passes])
        (if (null? funs) 
            (begin (if filename (dump-tokenmachine-to-file p filename)
                       p))
	    (begin 
	      (if verbose
		  (begin
		    (printf ";===============================================================================\n")
		    (printf "~a:\n\n" (car names))))
	      (let ((result ((car funs) p)))
		(if verbose
		    (pretty-print result) (newline))
		(loop result (cdr funs) (cdr names)))))))))

;; This one just stops after deglobalize:
(define (compile-to-tokens p . args)
  (apply run-compiler p 'barely-tokens args))
(define (compile-almost-to-tokens p . args)
  (apply run-compiler p 'almost-tokens args))

(define rc run-compiler) ;; shorthand
(define ct compile-to-tokens) ;; shorthand

;; This finishes off the compilation of scheme-format token machine.
;; It's just a front-end to run-compiler that restricts the passes we run over.
(define (assemble-tokmac tm . args)
  (printf "assem tokmac...\n" )
  (let ([starting-place 
	 (match tm 
	   [(,lang ,prog)
	    (case lang
	      [(add-places-language) 'analyze-places] ;; Not strictly correct.
	      [(deglobalize-lang) 'deglobalize]
	      [(cleanup-token-machine-lang) 'cleanup-token-machine]
	      [(cps-tokmac-lang) 'cps-tokmac]
	      
					;[(haskellize-tokmac-lang) (error...
	      [else 'deglobalize])])
	 ])
  (let ((passes (cdr (list-remove-before starting-place pass-names))))
    (disp "Assembling tokmac with passes: " passes)
;    (lambda (tm)
      (fluid-let ([pass-names passes])
	(apply run-compiler tm args)))))

(define at assemble-tokmac) ;; shorthand
(define assemble at) ;; shorthand

(define test
  (lambda (set)
    (fluid-let ([tests 
		 (map (lambda (p) 
			`(base-language '(program ,p)))
		      set)])
      (test-all))))

(define r  ;; shorthand
  (letrec ((loop
	    (case-lambda 
	     [(pass x)
	      (let ((prog  x))
		(fluid-let ((pass-names (list-remove-after pass pass-names)))
		  (parameterize ((tracer #t))
				(test-one prog #f #f))))]
	     [(x) (loop (rac pass-names) x)])))
    loop))

;; Token and later compiler:
(define (tr x)  ;; shorthand
  (let ((prog  x))
    (parameterize ((tracer #t)
		   (game-eval (lambda args 'unspecified))
		   (host-eval (lambda args 'unspecified)))
      (fluid-let ((pass-names (cdr (list-remove-before 'deglobalize pass-names))))
	(test-one prog)))))

;; Temp =============================================================

(newline)

(define (rr) (r '(circle 50 (anchor-at '(30 40))))) ;; shorthand

(define (doit x) ;; shorthand
  (cleanse-world)
  (run-simulation (build-simulation (compile-simulate-nought x))		  
		  20.0))

;; This is my big target program!!
'(define theprog
  '(let* ((R (circle-at 50 '(30 40)))
	 (f (lambda (tot next)
	      (cons (+ (car tot) (sense next))
		    (+ (cdr tot) 1))))
	 (g (lambda (tot) (/ (car tot) (cdr tot))))
	 (avg (smap g (rfold f (cons 0 0) R))))
    (until (pred (lambda (x) (> x 15.3)) avg)
	   R
	   (circle-at 100 '(0 0)))))

(define prog
  '(program
     (bindings (tmp_3 (cons '40 '())) (tmp_1 (cons '30 tmp_3)))
     (socpgm (bindings) (call f_token_result_2))
     (nodepgm
       (tokens
         (f_token_result_2 () (flood token_4))
         (token_4
           ()           
           (if (< (locdiff (loc) tmp_1) 10.0)
               (begin
                 (disp "PROG: blah blah calling elect leader")
                 (elect-leader m_token_result_2))
               '#f))
         (m_token_result_2 ()
                           (disp "PROG: Bang, election finished, got result..")
                           (soc-return (list 'anch this))))
       (startup))))


;; These are some temporary diagnostic functions:
(define (all-incoming) ;; shorthand
  (filter (lambda (ls) (not (null? ls)))
          (map simobject-incoming all-objs)))
(define (all-homepage) ;; shorthand
  (filter (lambda (ls) (not (null? ls)))
          (map simobject-homepage all-objs)))


(define (sim) (build-simulation  ;; shorthand
	     (compile-simulate-nought 
	      (cadadr (run-compiler '(anchor-at '(30 40)))))))

;; HOW TO RUN:
;; ----------------------------------------
;; Here I'll give some examples of how to run the system.  
;; This is for me -- because I forget how to invoke things over time.
;; (Though the unit tests give me something...)

;; simulator_nought.examples.ss -- has some example token machines.


;(define (t1) (init-world) (run-simulation        sim 2.0))
;(define (t2) (init-world) (run-simulation-stream sim 2.0))

;; Sigh, first class tokens:
;(r '(rmap (lambda (x) (rmap (lambda (y) y) world)) world)) 
  

(define theprog '(rfold + 0 (rmap sense world)))

;; I'm binding all these little random letter combinations!  Bah!
(define mp;;myprog ;; shorthand
;  '(rfold + 0 (rmap sense (circle-at '(30 40) 10))))
  '(rfold + 0 (rmap sense (khood-at '(30 40) 10))))

;; [2005.09.29] Moved run-simulator-alpha to simulator_alpha.ss
	    
(define ra run-simulator-alpha) ;; shorthand

;;======================================================================

[define tm-to-list ;; This is boilerplate, many of these tests just run the following:
	 (lambda (tm . extraparams)
	   `(parameterize ([unique-name-counter 0] 
			   [simalpha-dbg-on #f]
			   ,@extraparams
			   )
	       (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored         ; cps-tokmac
;		     closure-convert        ;cleanup-token-machine
		     )])
		 (let ([prog (run-compiler ',tm
					   ;'verbose
					   )])
		   (let ((prt (open-output-string)))
		     (display "(" prt)
		     (let ((result (run-simulator-alpha prog 
					'timeout 10000
					;'outport prt
							)
				   ))
		     (display ")" prt)
		     (read (open-input-string (get-output-string prt)))
		     result ;; Returns the soc-returned values rather than the output list.
		     )))))
	   )]

;; These are some of our system tests.  They test the compiler and the simulator as a whole.
;; The rest of the system tests are in the files named tests_*.ss
;; But some of the below tests may also be miscellaneous unit tests that require more than one module.
(define these-tests 
  (let ([tm-to-list ;; This is boilerplate, many of these tests just run the following:
	 (lambda (tm . extraparams)
	   `(parameterize ([unique-name-counter 0] 
			   [simalpha-dbg-on #f]
			   ,@extraparams
			   )
	       (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored         ; cps-tokmac
;		     closure-convert        ;cleanup-token-machine
		     )])
		 (let ([prog (run-compiler ',tm
					   'verbose
					   )])
		   (let ((prt (open-output-string)))
		     (display "(" prt)
		     (let ((result (run-simulator-alpha prog 
					;'timeout 10000
					'outport prt
							)
				   ))
		       (display ")" prt)
		       (read (open-input-string (get-output-string prt)))
		       ;result ;; Returns the soc-returned values rather than the output list.
		     )))))
	   )]
	)
  `( 
    ;; Urg, this is wrong:
    ;    [(deep-assq 'startup (run-compiler '(circle-at '(30 40) 50))) (startup)]
    
    ["Verify that the trivial program produces no token bindings but the defaults"
     (filter (lambda (tokbind)
	       (not (memq (car tokbind) '(spread-global global-tree))))
	     (cdr (deep-assq 'tokens (compile-to-tokens '3))))
     ()]

     
     ["Testing simple combinations of passes: generate a continuation." 
      (let ((toks (cdr (deep-assq 'tokens 
		 (closure-convert (cleanup-token-machine '(tokens (tok1 () (subcall tok2)))))))))
	(let ((x (remq 'SOC-start (remq 'node-start (remq 'actual-node-start (map car toks))))))
	  ;; This is the continuation that was added:
	  (length x)))
      1]


    ["Simalpha: Now we test running the Simulator Alpha on a very simple token machine."
     (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
     (let ((prt (open-output-string)))
       (display "(" prt)
       (run-simulator-alpha 
	(cleanup-token-machine '(tokens (node-start () (display " ") (display (my-id)))))
	'outport prt)
       (display ")" prt)
       (read (open-input-string (get-output-string prt)))))
     ,(lambda (ls) 	
	(set-equal? (list->set ls)
		    (list->set (cons BASE_ID (cdr (iota 30))))))]



     ["Respect call order."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () 
			      (call a)
			      (call b)
			      (call c))
		   (a (x) (printf "a "))
		   (b (x) (printf "b "))
		   (c (x) (printf "c "))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      (a b c)]


     ["Timed tokens: test the simulator with timed tokens."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () 
			      (timed-call 200 tok1)
			      (timed-call 100 tok2))
		   (tok1 (x) (printf "tok1 "))
		   (tok2 (x) (printf "tok2 ")
			     (timed-call 50 tok3))
		   (tok3 (x) (printf "tok3 "))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
     (tok2 tok3 tok1)]

     ["Timed tokens 2: test simultaneous timed/untimed calls to same token, then deschedule one timed"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () 
			      (call tok1) 
			      (timed-call 100 tok1)
			      (call tok2)
			      (timed-call 100 tok2))
		   (tok1 () (printf "tok1 ")
			     (token-deschedule tok1))
		   (tok2 () (printf "tok2 "))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
     (tok1 tok2 tok2)]

     ["Timed tokens 3: make two timed calls to the same token."
      (apply < ,(tm-to-list
	'(tokens
	  (SOC-start () (timed-call 100 tok1)
		        (timed-call 200 tok1))
	  (tok1 () (printf "~a \n" (my-clock))))))
      #t]


     [
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () 
			      (timed-call 200 a)
			      (timed-call 100 b)
			      (timed-call  50 c))
		   (a (x) (printf "a "))
		   (b (x) (printf "b "))
		   (c (x) (printf "c "))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      (c b a)]
     [
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () 
			      (timed-call 200 a)
			      (call b)
			      (timed-call  50 c))
		   (a (x) (printf "a "))
		   (b (x) (printf "b "))
		   (c (x) (printf "c "))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      (b c a)]


     ["Clocks"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () (call tok0))
		   (tok0 () (printf "~a " (my-clock))
			 (call tok1))
		   (tok1 () (printf "~a " (my-clock))
			 (timed-call 100 tok2))
		   (tok2 () (printf "~a " (my-clock))
			 (call tok3))
		   (tok3 () (printf "~a " (my-clock)))
		 ))))
	   (let ((result 
		  (let ((prt (open-output-string)))
		    (display "(" prt)       
		    (run-simulator-alpha prog 'outport prt)
		    (display ")" prt)
		    (read (open-input-string (get-output-string prt))))))
	     ;; RRN: modified this test to be indiffirent to how much time soc-start takes:
	     (map (lambda (x) (- x (car result))) result)))))
      (0 1 101 102)]

     ["Bcast:"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () (printf "~a" (my-clock)) (bcast tok1 3))
		   (tok1 (x) (printf "(~a ~a)" (my-id) (my-clock)))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      ,(lambda (results)
	 (let ((SOCSTRT (car results)) ;; This compensates for whatever time is consumed before soc-start runs.
	       (ls (cdr results)))
	   (printf "Testing ~a\n" (+ SOCSTRT RADIO_DELAY SCHEDULE_DELAY))
	 (and (< (length ls) 30) (> (length ls) 1) ;; There should be "some" responses
	      (andmap (lambda (x) (equal? (cadr x) 
					  (+ SOCSTRT RADIO_DELAY SCHEDULE_DELAY)))
		      ls)
	      (not (memq BASE_ID (map car ls))))))]

     ;; Before I had a simulator bug wherein call-tokens were going to neighbors. 
     ;; (but bcast tokens did not arrive locally)
     ["Test for interference between calls and bcasts. " 
      (filter (lambda (x) (eq? (car x) 'tok3))
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #t])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored         ; cps-tokmac
;		     closure-convert        ;cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (printf "(start ~a ~a)" (my-id) (my-clock)) (call (tok tok3 0)) (bcast tok1))
		  (tok1 () (printf " (tok1 ~a) " (my-id)))
		  (tok3 () (printf " (tok3 ~a) " (my-id)))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	    lst
	    )))))
      ((tok3 ,BASE_ID))]


     ["Token present?"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac )));closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 		   
		   (SOC-start () 
			      (printf "first: ~a" (token-present? (tok tok1 0)))
			      ;(call tok1)
			      (timed-call 200 tok2)
			      (timed-call 100 tok1)
			      )
		   (tok1 () (printf "tok1 "))
		   (tok2 () (printf "second: ~a" (token-present? (tok tok1 0))))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
     (first: #f tok1 second: #t)]
     [
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac )));closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 		   
		   (SOC-start () 
			      (printf "first: ~a" (token-present? (tok tok1 0)))
			      (timed-call 200 tok2)
			      (call tok1)
			      (timed-call 100 tok2)
			      )
		   (tok1 () (printf "tok1 "))
		   (tok2 () (printf "second: ~a" (token-present? (tok tok1 0))))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      (first: #f tok1 second: #t second: #t)]

     ["Token Evict"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac )));closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 		   
		   (SOC-start () 
			      (call check)
			      (call (tok tok1 0))
			      (call check)
			      (call kickout)
			      (call check))
		   (tok1 () (printf "tok1 "))
		   (check () (printf "~a" (token-present? (tok tok1 0))))
		   (kickout () (evict (tok tok1 0)))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      (#f tok1 #t #f)]

     ["token-scheduled? test"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
	(let ([prog
	       (cleanup-token-machine
		'(tokens
		  (SOC-start () 
			     (call tok1 '10)
			     (if (token-scheduled? tok1)
				 (display "yes ")
				 (display "no "))
			     (if (token-scheduled? tok2)
				 (display "yes ")
				 (display "no "))
			     (call tok2 11))
		  (tok1 (x) (void))
		  (tok2 (x) (void))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	    lst)))
      (yes no)]

     ["token-deschedule test"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
	(let ([prog
	       (cleanup-token-machine
		'(tokens
		  (SOC-start () 
			     (call tok1 '10)
			     (if (token-scheduled? tok1)
				 (display "yes ")
				 (display "no "))
			     (token-deschedule tok1)
			     (if (token-scheduled? tok1)
				 (display "yes ")
				 (display "no "))
			     (token-deschedule tok1)
			     (token-deschedule tok1)
			     (token-deschedule tok1)
			     (if (token-scheduled? tok1)
				 (display "yes ")
				 (display "no "))
			     (call tok1 '10)
			     (if (token-scheduled? tok1)
				 (display "yes ")
				 (display "no "))
			     (if (token-scheduled? tok1)
				 (display "yes ")
				 (display "no "))
			     )
		  (tok1 (x) (void))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	    lst)))
      (yes no no yes yes)]


     ["Token Timed-Schedule/Deschedule test"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
	(let ([prog
	       (cleanup-token-machine
		'(tokens
		  (SOC-start () 
			     (if (token-scheduled? (tok tok1 0)) (display "yes ") (display "no "))
			     (timed-call 100 tok1 '10)
			     (if (token-scheduled? (tok tok1 0)) (display "yes ") (display "no "))
			     (token-deschedule tok1)
			     (if (token-scheduled? (tok tok1 0)) (display "yes ") (display "no "))
			     (timed-call 100 tok1 '10)
			     (timed-call 200 tok1 '10)
			     (token-deschedule tok1)
			     (if (token-scheduled? (tok tok1 0)) (display "yes ") (display "no "))
			     (call tok1 '10)
			     (call tok1 '10)
			     (timed-call 200 tok1 '10)
			     (timed-call 100 tok1 '10)
			     (token-deschedule tok1)
			     (if (token-scheduled? (tok tok1 0)) (display "yes ") (display "no "))
			     )
		  (tok1 (x) (void))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	    lst)))
      (no yes no no no)]

     ["Another Token Scheduled?"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names (list-remove-before 'cleanup-token-machine pass-names)))
					;'(cleanup-token-machine cps-tokmac )));closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 		   
		   (SOC-start () 
			      (printf "~a " (token-scheduled? (tok tok1 0)))
			      (timed-call 500 (tok tok1 0))
			      (timed-call 100 check)
			      (timed-call 800 check))
		   (tok1 () (printf "tok1 "))
		   (check () (printf "~a " (token-scheduled? (tok tok1 0))))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      (#f #t tok1 #f)]

;; TODO FIXME: GOOD TEST:  GET THIS TO WORK!!!!
#;     ["Try token-scheduled? with some subcall trickery"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #t])
      (fluid-let ((pass-names (list-remove-before 'cleanup-token-machine pass-names)))
					;'(cleanup-token-machine cps-tokmac )));closure-convert)))
	 (let ((prog 
		(run-compiler
		 '(tokens 		   
		   (SOC-start ()
			      ;; Use subcall to call it immediately,befoe the rest proceeds.
			      (subcall check)
			      (timed-call 500 (tok tok1 0))
			      (timed-call 100 check)
			      (timed-call 800 check))
		   (tok1 () (printf "tok1 "))
		   (check () (printf "~a " (token-scheduled? (tok tok1 0))))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      (#f #t tok1 #f)]


     ["Make sure simulator can handle subcalls directly if need be."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #t])
	 (let ((prog 
		(cleanup-token-machine
		 '(tokens 		   
		   (SOC-start ()
			      (printf "a ")
			      (subcall tok1)
			      (printf "c ")
			      (call tok2)
			      (printf "d "))
		   (tok1 () (printf "b "))
		   (tok2 () (printf "e "))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt))))))
      (a b c d e)]

     ["Make sure simulator can handle subcalls directly if need be #2."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #t])
	 (let ((prog 
		(cleanup-token-machine
		 '(tokens 		   
		   (SOC-start () (printf "~a " (subcall tok1)))
		   (tok1 () (return 349))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt))))))
      (349)]

     
     ["Testing sim: 'manually' propogate a flood"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #t])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-let-stored
		     ;rename-stored          cps-tokmac
		     ;closure-convert        cleanup-token-machine
					    )])
	(let ([prog
	       (run-compiler
		(read (open-input-file "demos/manual_tree.tm"))
		)])
	  (run-simulator-alpha prog 'timeout 5000)
	  )))
      unspecified]



;      ["Testing sim: 'manually' propogate a flood"
;       (parameterize ([unique-name-counter 0] [simalpha-dbg-on #t])
; 	 (let ((prog 
; 		(run-compiler
; 		 `(tokens
; 		   [SOC-start () 
; 			      (printf "~a: Root spreading...\n" (my-clock))
; 			      (bcast down (my-id) 1)
; 			      (timed-call 1000 SOC-start)
; 			      ]
; 		   [down (p h)
; 			 (stored [parent -1] [hops 1000])
; 			 (if (< h hops)
; 			     (begin 
; 			       (printf "~a.~a: Down   p:~a  hops:~a\n" (my-clock) (my-id) p h)
; 			       (set! parent p)
; 			       (set! hops h)			
; 			       (bcast down (my-id) (+ hops 1))))
; 			 ]
; 		   [up (dest v)
; 					;(if (not (token-present? down))
; 					;  (printf "Not on tree!"))
; 		       (if (= dest (my-id))
; 			   (if (token-present? down)
; 			       (if (= (my-id) ,BASE_ID)
; 				   (printf "Got return: ~a\n" v)
; 				   (bcast up (ext-ref down parent) (+ v 1)))))
; 		       ])
		 
; 		 )



     
    ;; [2005.05.29] Note tok1 should be statically called and is currently called dynamically!
    ;; Oh duh, that's because all calls go through the dyndispatch table.
     ["Subcalls: Run simulator on simple subcall program." 
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	 (let ((prog 
		(cleanup-token-machine (run-compiler
	       '(tokens 
		 (SOC-start () (printf "result ~a" (subcall tok1 3)))
		 (tok1 (x) (return (+ x 300)))
		 )))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
     (result 303)]
     
     ,@(let ([commontest 
	      '(parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
		 (let ((prog 
		     (run-compiler
		      '(tokens 
			(SOC-start () (printf "result ~a" (+ (subcall tok1 4) (subcall tok1 3))))
			(tok1 (x) (return (+ x 1000)))
			))))
		(let ((prt (open-output-string)))
		  (display "(" prt)
		  (run-simulator-alpha prog 'outport prt)
		  (display ")" prt)
		  (read (open-input-string (get-output-string prt))))))])
	 `(["Add two subcalls (only through cps-tokmac)"
	    (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac )))
	      ,commontest)
	    (result 2007)]
	   ["Same test but now with closure-convert"
	    (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	      ,commontest)
	    (result 2007)]))

     ["Stored vars: Now use a stored var."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine 
				desugar-let-stored  rename-stored
				cps-tokmac closure-convert cleanup-token-machine)))
	(let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () 
			      (call tok1 99) 
			      (call tok1 100)
			      (call tok1 101)
			      (call tok1 999))
		   (tok1 (x) (stored (y 3))
			 (printf "~a " y)
			 (set! y x)))
		   )))
	   (let ((prt (open-output-string)))
	     (display "(" prt)
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      (3 99 100 101)]

     ["Stored vars: Now many stored vars."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ((pass-names '(cleanup-token-machine 
				desugar-let-stored  rename-stored
				cps-tokmac closure-convert cleanup-token-machine)))
	(let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () 			      
			      (call tok1 1 2 3)
			      (call tok2))
		   (tok1 (a b c) (stored (x 0) (y 0) (z 0))
			 (set! x a)
			 (set! y b)
			 (set! z c))
		   (tok2 () 
			 (printf "(~a ~a ~a)" (ext-ref tok1 x) (ext-ref tok1 y) (ext-ref tok1 z))
			 (ext-set! tok1 y 10)
			 (printf "(~a ~a ~a)" (ext-ref tok1 x) (ext-ref tok1 y) (ext-ref tok1 z))
			 (ext-set! tok1 z 10)
			 (printf "(~a ~a ~a)" (ext-ref tok1 x) (ext-ref tok1 y) (ext-ref tok1 z))
			 (ext-set! tok1 x 10)
			 (printf "(~a ~a ~a)" (ext-ref tok1 x) (ext-ref tok1 y) (ext-ref tok1 z))
			 )))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      ((1 2 3) (1 10 3) (1 10 10) (10 10 10))]

; FIXME: HAVEN'T FIXED THE SIM UP FOR THIS YET:
#;
     ["Stored vars: Check order of evaluation for stored vars."
      , (tm-to-list
	'(tokens 
	  (SOC-start () (call tok1) (call tok1) (call tok1))
	  (tok1 () 
		(stored [a (begin (printf "a ") 3)]
			[b (begin (printf "b ") (+ 1 a))])
		(printf "~a " (+ a b)))))
      ]
     

     ["Now keep stored vars on all 1-hop neighbors, make sure they don't change."  
      ,(tm-to-list
	'(tokens 
	  (SOC-start () 			      
		     (bcast tok1)
		     (timed-call 100 tok2)
		     (printf "\n")
		     (timed-call 200 tok2)
		     )
	  (tok2 () (bcast tok1))
	  (tok1 () (stored [count 0])
		(let-stored ([id (my-id)])
		(if (= count 0)
		    (begin
		      (printf "fst ~a ~a \n" (my-id) id)
		      (set! count 1))
		    (printf "snd ~a ~a \n" (my-id) id))))))
      unspecified]
	


     ;; Ok before I was having problems with how I do the counters for
     ;; subtok indices of the continuations.  This double invocation tests that:
     ["Test double invocation of a continuation-bearing token." 
      (fluid-let ([pass-names '(cleanup-token-machine  desugar-let-stored rename-stored  cps-tokmac closure-convert)])
       (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
         (let ((prog
		(run-compiler
		 '(tokens
		   (SOC-start () (printf "SOCSTART~n")
			      (call tok1 55)
			      (call tok1 66))
		   (tok1 (x) (printf " ~a " (+ x (subcall tok2))))
		   (tok2 () (return 3))))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt)))))))
      (SOCSTART 58 69)]


     ;; This doesn't work after closure-convert because while it does
     ;; maintain orderings of local invocations, that does not include
     ;; subsequent continuation invocations of those local
     ;; invocations...
     ;;   Ok, now it works because I changed the CPS algorithm not to
     ;;   introduce a continuation in this case.
     ,@(let ((common 
	     '(parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
	      (let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () 
			      (call tok1 1)
			      (call tok1 0)
			      (call tok1 1)
			      (call tok1 0)
			      )
		   (tok1 (x) 
;			 (printf "_ ")
			 (if (= x 0)
			     (let-stored ((y (begin (printf "a") 3))) (printf "b ") y)
			     (printf "c "))))
		   )))
		(let ((prt (open-output-string)))
		  (display "(" prt)
		  (run-simulator-alpha prog 'outport prt)
		  (display ")" prt)
		  (read (open-input-string (get-output-string prt))))))))	
	 `(["Now use let-stored:"
	    (fluid-let ((pass-names '(cleanup-token-machine 
				      desugar-let-stored  rename-stored
				      cps-tokmac      )))
	      ,common)	   
	    (c ab c b)]
	   ["Same test but with closure-convert."
	    (fluid-let ((pass-names '(cleanup-token-machine 
				      desugar-let-stored  rename-stored
				      cps-tokmac closure-convert   )))
	      ,common)
	    (c ab c b)]))


     ,@(let ((common 
	      '(parameterize ((unique-name-counter 0)
			      (simalpha-dbg-on #f))
	      (let ((prog 
		(run-compiler
		 '(tokens 
		   (SOC-start () 
			      (call tok1 1)
			      (call tok1 0)
			      (call tok1 1)
			      (call tok1 0)
			      )
		   (tok1 (x) 
			 (if (= x 0)
			     (let-stored ((y (begin (printf "a") 3))) (printf "b ") y)
			     (begin (subcall tok2) (printf "c "))))
		   (tok2 () (return 3)))
		   )))
		(let ((prt (open-output-string)))
		  (display "(" prt)
		  (run-simulator-alpha prog 'outport prt)
		  (display ")" prt)
		  (read (open-input-string (get-output-string prt))))))))
	 `(["This time I force a continutaion by using subcall.  Thus the c's are delayed."
	   (fluid-let ((pass-names '(cleanup-token-machine 
				     desugar-let-stored  rename-stored
				     cps-tokmac )))
	     ,common)
	   (ab b c c)]
	   ["And one last time using subcall and closure convert."
	    (fluid-let ((pass-names '(cleanup-token-machine 
				      desugar-let-stored  rename-stored
				      cps-tokmac closure-convert)))
	      ,common)
	    (ab b c c)
	    ;(c ab c b)
	    ]))

     ["Test gradient ghopcount, gversion, gparent, gorigin."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored         ; cps-tokmac
;		     closure-convert        ;cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (gemit tok1))
		  (tok1 () (printf "(~a : ~a ~a ~a ~a : ~a)" (my-id) (gparent) (gorigin) (ghopcount) (gversion) (my-clock)))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	    (let ((base (cdr (assq BASE_ID lst)))
		  (others (map cdr (alist-remove BASE_ID lst))))
	      (if (all-equal? others)
		  ;; Return something that won't vary based on sim parameters:
		  (list (assq BASE_ID lst) (car others))
		  `(ERROR: ,others)))
	    ))))
      ;; This timing stuff is a bit fragile
      ((10000 : atroot 10000 0 1 : 2) (: 10000 10000 1 1 : ,(+ RADIO_DELAY SCHEDULE_DELAY 1)))
      ]


     ;; TODO: need to explicitely control tho network parameters for this one:
     ["Gradients: just a gemit and unconditional grelay. (NONDETERMINISTIC)" 
      retry ;; Retry this test if it fails... it's nondeterministic.
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine  desugar-let-stored
		     rename-stored          cps-tokmac
		     closure-convert        cleanup-token-machine)])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (gemit tok1))
		  (tok1 (x) (printf "~a " (gdist)) (grelay))))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))	    
	    (list (length lst) 
		  (car lst)
		  (cadr lst)
		  (> (car (reverse lst)) 1)
		  (equal? lst (sort < lst)))
	    )))) ;; Only true with VERY restricted simulation model.
	(30 0 1 #t #t)]


     ["Gradients: make a two hop neighborhood. (NONDETERMINISTIC)"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine  desugar-let-stored
		     rename-stored          cps-tokmac
		     closure-convert        cleanup-token-machine)])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (gemit tok1))
		  (tok1 (x) (printf "~a " (gdist)) (if (< (gdist) 2) (grelay)))))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	    (list (< (length lst) 30)
		  (sort < (list->set lst))
		  (equal? lst (sort < lst))) ;; Only true with VERY restricted simulation model.
	    ))))
	(#t (0 1 2) #t)]

;; This case was too fragile and dependent on the ordering.  I could make it better and bring it back.
;; Problem is that it depends on the aggregator being turned on, because without aggregation we no longer use the timer.
     ["Gradients: Make sure the timer gets set right. "
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     ;rename-stored         ; cps-tokmac
;		     closure-convert        cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (gemit tok1))
		  (catcher (x) (void))
		  (tok1 () (greturn (my-id) 
				    (to (tok catcher 0))
				    (via (tok tok1 0))
				    (aggr #f)))
		  ))])
	  ;; Dig out the name of the timeout:
	  (let ((timeout-name
		 (car (rac (rdc (deep-assq 'tokens prog))))))
	    (let ((newprog
		   ;; Insert some more functionality for tok1:
		   (append (deep-assq 'tokens prog)
			   `([tok1 (g_parent g_origin g_hopcount g_version)
				   (printf "~a.~a: tok1: Is time-out set? ~a\n" 
					      (my-clock) (my-id) (token-present? (tok ,timeout-name 0)))]))))
	      (run-simulator-alpha
	       (cleanup-token-machine newprog)
	       'timeout 5000)
	      )))))
      unspecified]


     ["Gradients: execute a return from 1-hop neighbors. Manual timeout.  (NONDETERMINISTIC)"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored         ; cps-tokmac
;		     closure-convert        cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () ;(printf "SOCSTART ") 
			     (gemit tok1)
			     ;; Manual timeout:
			     ;(timed-call 1000 tok1)
			     )
		  (catcher (v) (printf " ~a " v))
		  (tok1 () (printf "_ ")
			(greturn (my-id) (to catcher)))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt 
					'timeout 10000)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	    lst
	    ))))
      ,(lambda (lst)
	 (let ((lst (filter number? lst)))
	   (and
	    (eq? BASE_ID (car lst))
	    (not (memq BASE_ID (cdr lst)))
	    (> (length lst) 1)
	    (eq? (length lst) (length (list->set lst))))))]

     ;; [2005.10.06] After doing my refactoring to make multiple return-handler tokens
     ;; this isn't working.  We're only getting a return from one of our neighbors.
     ["Gradients: execute a repeated return from 1-hop neighbors. (NONDETERMINISTIC)"
      (parameterize ([unique-name-counter 0] 
		     [simalpha-dbg-on #f]
		     [simalpha-channel-model 'lossless]
		     [simalpha-failure-mode 'none])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     ;rename-stored          
		     cps-tokmac
		     closure-convert        cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (printf "(")
			     (call tok1 '10))
		  (catcher (v) (printf "~a " v))
		  (tok1 (reps) 
			(printf ") (")
			(gemit tok2)
			(if (> reps 0)
			    (timed-call 1000 tok1 (- reps 1))))
		  (tok2 () ;(printf "_ ") 
			(greturn (my-id) 
				 (to catcher)))
		  ) 'verbose
		)])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt) ;'timeout 5000 );
		   (display "))" prt)
		   (read (open-input-string (get-output-string prt))))))
	    lst
	    ))))
      ,(lambda (x)
	 ;; ASSUMES LOSSLESS CHANNELS AND DETERMINISTIC TIMING:
	 ;; Makes sure we hear from the same neighbors every time:
	 ;(printf "Checking : ~a\n" x)
	 ;(set! x (map (lambda (l) (filter number? l)) x))
	 (and (eq? (car x) ())
	      ;(equal? (cadr x) (list BASE_ID)) ;; No longer true.  Not staggering epochs for non-aggregated greturn.
	      (all-equal? (map (lambda (l) (sort < (filter number? l))) 
			       (rdc (cddr x))))))]

     ["Gradients: execute a repeated return from whole network. (NONDETERMINISTIC)"
      retry
      (parameterize ([unique-name-counter 0] 
		     [simalpha-dbg-on #f]
		     [simalpha-consec-ids #t]
		     [simalpha-channel-model 'lossless]
		     [simalpha-failure-module 'none])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored          
					;cps-tokmac ;closure-convert        
		     cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (call tok1 '5))
		  (catcher (v) (printf " ~a " v))
		  (tok1 (reps) 
			(printf ") (")
			(gemit tok2)
			(if (> reps 0)
			    (timed-call 1000 tok1 (- reps 1))))
		  (tok2 () (grelay) (greturn (my-id) (to catcher)))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "((" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display "))" prt)
		   (read (open-input-string (get-output-string prt))))))

;	    (for-each (lambda (x) (display x) (newline)) lst)
;	    (let ((lens (map length lst)))
	    lst
	    ))))

      ;; You will see a staggered reception of results.
      ;; First from the one-hop neighbors, then also the two-hops, and so on.
      ,(lambda (x) 
	 (and
	 ;; Let's make sure the list increases in distance at first:
; 	 ;; Check the first three.
; 	  (let ([one   (length (car x))]
; 	       [two   (length (cadr x))]
; 	       [three (length (caddr x))])
; 	   (< one two three))
	 ;; Also check to make sure whe heard from everyone.
	 (= (simalpha-num-nodes)
	    (length (list->set (apply append x))))
	 ))]

     ["Gradients: execute a repeated return from 2-hop neighbors. (NONDETERMINISTIC)"
      retry
      (parameterize ([unique-name-counter 0] 
		     [simalpha-dbg-on #f])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored          
					;cps-tokmac ;closure-convert        
		     cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (call tok1 '5))
		  (catcher (v) (printf "~a " v))
		  (tok1 (reps)  
			(printf ") (")
			(gemit tok2)
			(if (> reps 1)
			    (timed-call 1500 tok1 (- reps 1))))
		  (tok2 () (grelay) 
			(if (= (gdist) 1)
			    (greturn (gversion) (to catcher))
			(if (= (gdist) 2)
			    (greturn (+ 100 (gversion)) (to catcher)))
			))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "((" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display "))" prt)
		   (read (open-input-string (get-output-string prt))))))
	    ;(for-each (lambda (x) (display x) (newline)) lst)


	    (list 
	     lst
	    (map (lambda (ls)
		   (let ((small (filter (lambda (n) (< n 100)) ls))
			 (big   (filter (lambda (n) (> n 100)) ls)))
		     (list (length big) (length small))))

		 ;; Don't count first or last batch:
		 (cddr (rdc lst))))

	    ))))

      ,(lambda (result) 
	 (and 
	  ;; This asserts that there are more two-hop than one-hop neighbors:
	  (andmap (lambda (x) (apply > x))
		  (cadr result))
	 ))]

     ["Gradients: Now try aggregated greturn."
      (filter (lambda (x) (not (zero? x)))
	      ,(tm-to-list
		'(tokens 
		  (SOC-start () (gemit tok1))
		  (catcher (x) (printf "~a " x))
		  (tok1 () 
			(greturn (gdist)
				 (to catcher)
				 (seed 0)
				 (aggr sum)))
		  (sum (x y) (+ x y)))))
      ,(lambda (ls)
	 (and (= (length ls) 1)
	      (> (car ls) 0)))]

     ["Gradients: Now try cons-aggregated greturn from one-hops"
      retry  ;; It's possibly we have no neighbors at all!
      (map list->set
	   (filter (lambda (x) (not (null? x)))
		   , (tm-to-list
		     '(tokens 
		       (SOC-start () (call tok1 '5))
		       (tok1 (reps)
			     (gemit tok2)
			     (if (> reps 1)
				 (timed-call 1000 tok1 (- reps 1))))
		       (catcher (x) (printf "~a " x))
		       (tok2 () 
			     (greturn (list (gdist))
				      (to catcher)
				      (seed ())
				      (aggr f)))
		       (f (x y) (append x y))))))
      ;; Epoch staggered aggregation
      ((0) (0 1) (0 1) (0 1) (0 1) (1))
      ]

     ["Gradients: Same thing but to whole network."
      , (tm-to-list
	'(tokens 
	  (SOC-start () (call tok1 '10))
	  (tok1 (reps)
		(gemit tok2)
		(if (> reps 1)
		    (timed-call 1000 tok1 (- reps 1))))
	  (catcher (x) (printf "~a " x))
	  (tok2 () 
		(grelay)
		(greturn (list (gdist))
			 (to catcher)
			 (seed ())
			 (aggr f)))
	  (f (x y) (append x y))))
      ;; Epoch staggered aggregation
	,(lambda (x) 
	;; Let's make sure the list increases in distance at first:
	;; Check the first three.

	(let ([one   (/ (apply + (car x)) (length (car x)))]
	      [two   (/ (apply + (cadr x)) (length (cadr x)))]
	      [three (/ (apply + (caddr x)) (length (caddr x)))])
	  (< one two three)))]

     ["Gradients: Now look at clock-skew."
      (map (lambda (ls) (and (not (null? ls))
			     (- (apply max ls) (apply min ls))))
      , (tm-to-list
	'(tokens 
	  (SOC-start () (call tok1 '10))
	  (tok1 (reps)
		(gemit tok2)
		(if (> reps 1)
		    (timed-call 1000 tok1 (- reps 1))))
	  (catcher (x) (printf "~a " x))
	  (tok2 () 
		(grelay)
		(greturn (list (my-clock)) ; (my-id)))
			 (to catcher)
			 (seed ())
			 (aggr f)))
	  (f (x y) (append x y)))))
      ;; Epoch staggered aggregation
      ,(lambda (x) 
	;; Let's make sure the list increases in distance at first:
	;; Check the first three.
	 (apply <= (list-head (filter number? x) 5)))]

     ["Gradients: now launch three nested gradients. (NONDETERMINISTIC)"
      retry ;; Must retry, network might not be connected
      (parameterize ([unique-name-counter 0] 
		     [simalpha-dbg-on #f]
		     [simalpha-failure-mode 'none]
		     [simalpha-channel-model 'lossless]
		     [simalpha-consec-ids #t]
		     [simalpha-num-nodes 30])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored          
					;cps-tokmac ;closure-convert        
		     cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () 
			     (printf "(~a ~a \"A launching\")\n" (my-clock) (my-id))
			     (gemit a)
			     (timed-call 1000 print-dists))
		  (print-dists ()
			     (printf "(\"After a period of time, dists at base are:\" ~a ~a ~a)"
				     (gdist a) (gdist b) (gdist c)))
		  (a () (grelay)
		        (if (= (my-id) 15)
			    (begin 
			      (printf "(~a ~a ~a \"B launching\")\n" (my-clock) (my-id) (gdist a))
			      (gemit b))))
		  (b () (grelay)
		        (if (= (my-id) 20)
			    (begin
			      (printf "(~a ~a ~a ~a \"C launching\")\n" (my-clock) (my-id) (gdist a) (gdist b))
			      (gemit c))))
		  (c () (grelay)
		        (if (= (my-id) BASE_ID)
			    (begin 
			      (printf "(~a ~a ~a ~a ~a \"C hit home!\")\n" (my-clock) (my-id) (gdist a) (gdist b) (gdist c))
			      ;(printf "home")
			      )))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	     lst
	     ))))
      ,(lambda (ls)
	 ;; Received all messages:
	 (= (length ls) 5))]

     ["Gradients: return value through three nested gradients. (NONDETERMINISTIC)"
      retry ;; Must retry, network might not be connected
      (parameterize ([unique-name-counter 0] 
		     [simalpha-dbg-on #f]
		     [simalpha-failure-mode 'none]
		     [simalpha-channel-model 'lossless]
		     [simalpha-consec-ids #t]
		     [simalpha-num-nodes 30])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored          
					;cps-tokmac ;closure-convert        
		     cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () 
			     (gemit a)
			     (timed-call 1000 return-up))
		  (return-up ()
			     (greturn 8967
				      (to catcher1)
				      (via c)))
		  (catcher1 (v) (greturn v 
					 (to catcher2)
					 (via b)))
		  (catcher2 (v) (greturn v
					 (to catcher3)
					 (via a)))
		  (catcher3 (v) (printf "~a ~a ~a ~a" (my-id) 
					(> (my-clock) 1000)
					(< (my-clock) 2000)
					v))

		  (a () (grelay)
		        (if (= (my-id) 15)
			      (gemit b)))
		  (b () (grelay)
		        (if (= (my-id) 20)
			      (gemit c)))
		  (c () (grelay))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	     lst
	     ))))
      (,BASE_ID #t #t 8967)]


     ["Gradients: let a thousand flowers bloom (gradient from everywhere)."
      retry ;; Must retry, network might not be connected
      (parameterize ([unique-name-counter 0] 
		     [simalpha-dbg-on #f]
		     [simalpha-failure-mode 'none]
		     [simalpha-channel-model 'lossless]
		     [simalpha-consec-ids #t]
		     [simalpha-num-nodes 30])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored          
					;cps-tokmac ;closure-convert        
		     cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () 
			     (gemit spark)
			     ;(timed-call 1000 return-up)
			     )
		  (spark () (grelay)
			    (printf "(Spark ~a)\n" (my-id))
			    (gemit secondary))
		  (secondary () (grelay)
			     (printf "(~a ~a ~a ~a)\n" (gorigin) (gparent) (my-id) (gdist)))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog) ;'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	     lst
	     ))))
      ;; FIXME : Finish
      unspecified]


     ["Run complex buffered-gradient TM from file"
      , (tm-to-list (car (file->slist "demos/buffered_gradients.tm")) 
		    '[simalpha-timeout 5000])
      unspecified]

     ["Test soc-return (#1).  Try it w/out desugar-soc-return."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ([pass-names (rdc (list-remove-after 'desugar-soc-return pass-names))])
	(let ([prog (run-compiler 399)])
	  (run-simulator-alpha prog))))
      (399)]

     ["Test soc-return (#2).  Try it WITH desugar-soc-return, but still on base station."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      ;; Go all the way through desugar-gradients and the subsequent cleanup-token-machine
      (fluid-let ([pass-names (rdc (list-remove-after 'cps-tokmac pass-names))])
	(let ([prog (run-compiler 399)])
	  (run-simulator-alpha prog))))
      (399)]

    ["Test soc-return (#3). soc-returns from one hop neighbors, without desugar gradients."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
	(let ([prog (cleanup-token-machine
		     '(tokens
		       (SOC-start () (soc-return (my-id)) (bcast tok1))
		       (tok1 () 
			     (printf " recvd ")
			     (soc-return (my-id))
			     )
		       ))])
	  (run-simulator-alpha prog)))
      ;; Result should be base_id followed by some number of non-base-ids.
      ,(lambda (ls)
	 (and (> (length ls) 1)
	      (eq? (car ls) BASE_ID)
	      (andmap (lambda (n) (not (eq? n BASE_ID))) (cdr ls))))
      ]

#; ; FIXME: Not there yet:
    ["Test soc-return (#4). soc-returns from one hop neighbors, WITH desugar gradients."
     (parameterize ([unique-name-counter 0] 
		    [simalpha-dbg-on #t] ;; (dbg ...) statements
		    )
      (fluid-let ([pass-names '(cleanup-token-machine 
				desugar-soc-return 
				desugar-gradients cleanup-token-machine
				desugar-let-stored
				;rename-stored
				)])
	(let ([prog (run-compiler
		     '(tokens
		       (SOC-start () 
				  (call spread-global)
				  (soc-return (my-id)) 
				  ;; Wait till the gradient has spread to do our soc-return:
				  (timed-call 1000 sendit))
		       (sendit () (bcast tok1))
		       (tok1 ()
			     (printf " recvd ")
			     (greturn (my-id) (to SOC-return-handler) (via global-tree))
			     ;(soc-return (my-id))
			     ;(soc-return (gdist))
			     )
		       ;; The global tree is required for soc-return to work.
		       (spread-global () (printf "Spreading global (~a, clock ~a)...\n" (my-id) (my-clock))
				      (gemit global-tree) (timed-call 1000 spread-global))
		       (global-tree () (printf "~a." (my-id)) (grelay))
		       ))])
	  (run-simulator-alpha prog 'timeout 5000))))
      395]

#;
     ["Gradients: execute a return from 1-hop neighbors. Manual timeout.  (NONDETERMINISTIC)"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #t])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored         ; cps-tokmac
;		     closure-convert        ;cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (printf "SOCSTART ") 
			     (gemit tok1)
;			     (timed-call 1000 timeout)
			     )
		  (catcher (v) (printf "Got: ~a" v))
		  (tok1 () (printf "~a_ " (my-id))) ;(greturn (my-id) (to catcher)))
;		  (timeout () (printf "! ")
;			   (greturn (my-id) (to catcher) (via tok1)))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (display "(" prt)
		   (run-simulator-alpha prog 'outport prt)
		   (display ")" prt)
		   (read (open-input-string (get-output-string prt))))))
	    lst
	    ))))
	(#t 1 2 #t)]      


     ;; TODO FIXME: finish:
#;     ["Now simulate gradients and subcalls in one program."
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
        ;; Respect the actual ordering of passes used by the compiler:
        (fluid-let ([pass-names (list-remove-before 'cleanup-token-machine pass-names)])
	  (let ([prog
		 (run-compiler
		  '(tokens
		    (SOC-start () (call spread-global))
		    (node-start () (void))
		    (spread-global ()
		       (gemit global-tree)
		       (timed-call 100 spread-global))
		    (global-tree ()
				 (printf "Tree spreading... ~a\n" (my-id))
				 (grelay))
		    ))])
	    (let ((lst 
		   (let ([prt (open-output-string)])
		     (display "(" prt)
		     (run-simulator-alpha prog );'outport prt)
		     (display ")" prt)
		     (read (open-input-string (get-output-string prt))))))
	      lst
	      ))))
      ,(lambda (x) #t)]

     ;; TODO FIXME: This causes a system freeze when you attempt to simulate.
#;     ["Finish assembly of a simple rfold over a rmap"
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #t])
      (fluid-let ([pass-names (list-remove-before 'deglobalize pass-names)])
	(let ((prog
	       (run-compiler
		'(add-places-language
		  '(program
		    (props (result_4 local) (a_1 local)
			   (tmpworld_7 leaf region area distributed)
			   (tmpfunc_8 function local) (result_5 local) (b_2 local)
			   (a_3 local) (tmprmap_9 area distributed)
			   (tmpfunc_10 function local)
			   (result_6 signal distributed final))
		    (control-flow (SOC tmpworld_7 tmprmap_9 result_6))
		    (lazy-letrec
		     ((result_6 100 (X_12) SOC (rfold tmpfunc_10 '0 tmprmap_9))
		      (tmpfunc_10
		       #f
		       _
		       _
		       (lambda (a_3 b_2)
			 (lazy-letrec ((result_5 #f _ _ (+ a_3 b_2))) result_5)))
		      (tmprmap_9 100 (X_11) (X_11) (rmap tmpfunc_8 tmpworld_7))
		      (tmpfunc_8
		       #f
		       _
		       _
		       (lambda (a_1)
			 (lazy-letrec ((result_4 #f _ _ (nodeid a_1))) result_4)))
		      (tmpworld_7 1000 _ _ world))
		     result_6))))))
	      (let ((lst 
		     (let ([prt (open-output-string)])
		       (display "(" prt)
		       (run-simulator-alpha prog 'outport prt)
		       (display ")" prt)
		       (read (open-input-string (get-output-string prt))))))
		lst))))
      foo]
	





#;
			  (printf "~ntok1 at ~a: input ~a stored ~a~n" 
				  (node-id (simobject-node this))
				  (list g_parent g_origin g_hopcount g_version)
				  tokobj)


#;      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine  desugar-let-stored  rename-stored          
		     cps-tokmac  closure-convert  )])
	(run-compiler
	 '(tokens
	   (SOC-start () (gemit tok1))
	   (catcher (v) (printf "Got return: ~a" v))
	   (tok1 () (greturn (my-id) (to catcher)))
	   )))





;; [2005.09.25] I forgot what this did, so it's hard to work on it right now:
#;     ["Temporary: Write a troublesome simulator program to disk and try to execute it."
      (let ((prt (open-output-string)))
	(display "(" prt)
	(run-simulator-alpha
	 '(define (node-code this) (let ((local-sense (lambda () ((current-sense-function) (node-pos (simobject-node this)))))) (let* () (letrec ((SOC-return-handler (lambda #0=(current-vtime subtokind . vals) (let ((x #1=(quote sim-alpha-uninitialized))) (let #2=((numvals (length vals))) (if (< numvals 1) (warning #3=(quote simulator-alpha) #4="executing ~a padding args ~a with zero." (quote SOC-return-handler) (list-tail (quote #5=(x)) . #6=(numvals)))) (if (> numvals 1) (error #7=(quote simulator-alpha) #8="executing ~a, got excess vals ~a for args ~a" (quote SOC-return-handler) vals (quote #5#))) (if #9=(null? vals) (set! x . #10=(0)) (begin (set! x . #11=((car vals))) . #12=((set! vals (cdr vals))))) #13="Done initializing arguments." (let* (#14=(the-store (simobject-token-store this)) (simtok-obj (make-simtok (quote SOC-return-handler) . #15=(subtokind))) . #16=((old-outgoing (simobject-outgoing-msg-buf this)) (old-local (simobject-local-msg-buf this)))) #17=(DEBUGMODE (check-store the-store)) #18="Is there already an allocated token object?:" (let #19=((tokobj (hashtab-get the-store simtok-obj))) (if #20=(not tokobj) (begin #21="If not, then we allocate that token object..." #22=" setting the invoke counter to zero." (set! tokobj (vector 0)) . #23=((hashtab-set! the-store simtok-obj tokobj)))) #24=(set-simobject-outgoing-msg-buf! this (quote ())) #25=(set-simobject-local-msg-buf! this (quote ())) (if (= (quote 10000) #26=(node-id (simobject-node this))) (simulator-soc-return x) (error (quote SOC-return-handler) "ran on non-base node! id: ~a" #26#)) . #27=((set-simobject-outgoing-msg-buf! this (append (reverse (simobject-outgoing-msg-buf this)) old-outgoing)) (set-simobject-local-msg-buf! this (append (reverse (simobject-local-msg-buf this)) old-local)) (void)))))))) (node-start (lambda #0# (let () (let #2# (if (< numvals 0) (warning #3# #4# (quote node-start) (list-tail (quote ()) . #6#))) (if (> numvals 0) (error #7# #8# (quote node-start) vals (quote ()))) #13# (let* (#14# (simtok-obj (make-simtok (quote node-start) . #15#)) . #16#) #17# #18# (let #19# (if #20# (begin #21# #22# (set! tokobj (vector 0)) . #23#)) #24# #25# (void) . #27#)))))) (SOC-start (lambda #0# (let () (let #2# (if (< numvals 0) (warning #3# #4# (quote SOC-start) (list-tail (quote ()) . #6#))) (if (> numvals 0) (error #7# #8# (quote SOC-start) vals (quote ()))) #13# (let* (#14# (simtok-obj (make-simtok (quote SOC-start) . #15#)) . #16#) #17# #18# (let #19# (if #20# (begin #21# #22# (set! tokobj (vector 0)) . #23#)) #24# #25# (set-simobject-local-msg-buf! this (cons (make-simevt #f (bare-msg-object (make-simtok (quote tok1) 0) (list (begin #28="This whole block represents the allocation of a continuation closure:" (let ((kind_4 (if (hashtab-get the-store (make-simtok (quote K_3) 0)) (let ((new (+ (quote 1) (let ((exttokobj (hashtab-get the-store (make-simtok (quote K_3) 0)))) (if exttokobj (vector-ref exttokobj 1) . #29=(#f)))))) (begin (let ((exttokobj (hashtab-get the-store (make-simtok (quote K_3) 0)))) (if exttokobj (vector-set! exttokobj 1 new) (warning #30=(quote ext-set!) #31="token not present: ~a" (quasiquote (K_3 . subtok))))) new)) (begin #32="Allocate this zeroeth token object just to hold a counter MEMORY WASTEFUL!:" (set-simobject-local-msg-buf! this (cons (make-simevt #f (bare-msg-object (make-simtok (quote K_3) 0) (list (quote 11) (void)) . #33=(current-vtime))) . #34=((simobject-local-msg-buf this)))) (quote 1))))) (begin #35="Do the actual token object (closure) allocation.  Capture freevars:" (set-simobject-local-msg-buf! this (cons (make-simevt #f (bare-msg-object (make-simtok (quote K_3) kind_4) (list (quote 11)) . #33#)) . #34#)) #36="Return the name of this continuation object:" (make-simtok (quote K_3) kind_4)))) (quote 4)) . #33#)) . #34#)) . #27#)))))) (K_3 (lambda #0# (let ((flag #1#) (fv0 #1#)) (let #2# (if (< numvals 2) (warning #3# #4# (quote K_3) (list-tail (quote #37=(flag fv0)) . #6#))) (if (> numvals 2) (error #7# #8# (quote K_3) vals (quote #37#))) (if #9# (set! flag . #10#) (begin (set! flag . #11#) . #12#)) (if #9# (set! fv0 . #10#) (begin (set! fv0 . #11#) . #12#)) #13# (let* (#14# (simtok-obj (make-simtok (quote K_3) . #15#)) . #16#) #17# #18# (let #19# (if #20# (begin #21# #22# (set! tokobj (vector 0 0)) . #23#)) #24# #25# (if (= flag (quote 11)) (if (= subtokind (quote 0)) (void) (void)) (begin (set-simobject-local-msg-buf! this (cons (make-simevt #f (bare-msg-object (make-simtok (quote tok1) 0) (list (begin #28# (let ((kind_2 (if (hashtab-get the-store (make-simtok (quote K_1) 0)) (let ((new (+ (quote 1) (let ((exttokobj (hashtab-get the-store (make-simtok (quote K_1) 0)))) (if exttokobj (vector-ref exttokobj 1) . #29#))))) (begin (let ((exttokobj (hashtab-get the-store (make-simtok (quote K_1) 0)))) (if exttokobj (vector-set! exttokobj 1 new) (warning #30# #31# (quasiquote (K_1 . subtok))))) new)) (begin #32# (set-simobject-local-msg-buf! this (cons (make-simevt #f (bare-msg-object (make-simtok (quote K_1) 0) (list (quote 11) (void)) . #33#)) . #34#)) (quote 1))))) (begin #35# (set-simobject-local-msg-buf! this (cons (make-simevt #f (bare-msg-object (make-simtok (quote K_1) kind_2) (list (quote 11) fv0) . #33#)) . #34#)) #36# (make-simtok (quote K_1) kind_2)))) (quote 3)) . #33#)) . #34#)) (hashtab-remove! the-store (make-simtok (quote K_3) subtokind)))) . #27#)))))) (K_1 (lambda #0# (let ((flag #1#) (fv0 #1#)) (let #2# (if (< numvals 2) (warning #3# #4# (quote K_1) (list-tail (quote #38=(flag fv0)) . #6#))) (if (> numvals 2) (error #7# #8# (quote K_1) vals (quote #38#))) (if #9# (set! flag . #10#) (begin (set! flag . #11#) . #12#)) (if #9# (set! fv0 . #10#) (begin (set! fv0 . #11#) . #12#)) #13# (let* (#14# (simtok-obj (make-simtok (quote K_1) . #15#)) . #16#) #17# #18# (let #19# (if #20# (begin #21# #22# (set! tokobj (vector 0 0 (quote 0))) . #23#)) #24# #25# (if (= flag (quote 11)) (if (= subtokind (quote 0)) (void) (begin (vector-set! tokobj 2 fv0))) (begin (printf (quote "result ~a") (+ (vector-ref tokobj 2) fv0)) (hashtab-remove! the-store (make-simtok (quote K_1) subtokind)))) . #27#)))))) (tok1 (lambda #0# (let ((k_58 #1#) (x #1#)) (let #2# (if (< numvals 2) (warning #3# #4# (quote tok1) (list-tail (quote #39=(k_58 x)) . #6#))) (if (> numvals 2) (error #7# #8# (quote tok1) vals (quote #39#))) (if #9# (set! k_58 . #10#) (begin (set! k_58 . #11#) . #12#)) (if #9# (set! x . #10#) (begin (set! x . #11#) . #12#)) #13# (let* (#14# (simtok-obj (make-simtok (quote tok1) . #15#)) . #16#) #17# #18# (let #19# (if #20# (begin #21# #22# (set! tokobj (vector 0)) . #23#)) #24# #25# (set-simobject-local-msg-buf! this (cons (make-simevt #f (bare-msg-object k_58 (list (quote 99) (+ x (quote 1000))) . #33#)) . #34#)) . #27#))))))) (let ((dyndispatch_table (make-default-hash-table))) (begin (void) (hashtab-set! dyndispatch_table (quote SOC-return-handler) SOC-return-handler) (hashtab-set! dyndispatch_table (quote node-start) node-start) (hashtab-set! dyndispatch_table (quote SOC-start) SOC-start) (hashtab-set! dyndispatch_table (quote K_3) K_3) (hashtab-set! dyndispatch_table (quote K_1) K_1) (hashtab-set! dyndispatch_table (quote tok1) tok1)) (lambda (msgob current-vtime) (mvlet (((name subtok) (let ((tok (msg-object-token msgob))) (values (simtok-name tok) (simtok-subid tok))))) (let ((handler (hashtab-get dyndispatch_table name))) (if (not handler) (error (quote node-code) "dyndispatch: no handler for token name: ~a in table: ~n~a" name dyndispatch_table)) (apply handler current-vtime subtok (msg-object-args msgob)))))))))


)
	 'outport prt)
	(display ")" prt)
	(read (open-input-string (get-output-string prt))))
      (result 2007)]

)))


(define test-this (default-unit-tester "Main compiler unit." these-tests))
(define maintests these-tests)
(define maintest test-this)


'
     (fluid-let ((pass-names
		  (list-remove-after desugar-gradients ;'cps-tokmac
				     (list-remove-before 'cleanup-token-machine pass-names))))
       (disp "PASS NAMES" pass-names)
       (game-eval (lambda args (void)))
       (let ((prog 
	      (r
	       '(tokens 
		 (SOC-start () (gemit gradient))
		 (gradient () 
			   (greturn x (to handler))
			   (grelay))
		 (handler (x) (display " ") (display x))
		 ))))
	 (disp "PROG")
	 (pp prog)
;	 (run-simulator-alpha prog)
	 ))



#;
    (fluid-let ((pass-names '(cleanup-token-machine cps-tokmac closure-convert)))
	 (let ((prog 
		(run-compiler
	       '(tokens 
		 (SOC-start () (printf "result ~a" (subcall tok1 3)))
		 (tok1 (x) (return (* x (+ (subcall tok2) (subcall tok3)))))
		 (tok2 () (return 55))
		 (tok3 () (return 45))
		 ))))
	   (let ((prt (open-output-string)))
	     (display "(" prt)       
	     (run-simulator-alpha prog 'outport prt)
	     (display ")" prt)
	     (read (open-input-string (get-output-string prt))))))



	       '(tokens 
		 (SOC-start () (printf "result ~a" (subcall tok1 3)))
		 (tok1 (x) (return (* x (+ (subcall tok2) (subcall tok3)))))
		 (tok2 () (return 55))
		 (tok3 () (return 45))
		 )


#;    [
     '(fluid-let ((pass-names
		  (list-remove-after desugar-gradients ;'cps-tokmac
				     (list-remove-before 'cleanup-token-machine pass-names))))
       (disp "PASS NAMES" pass-names)
       (let ((prog 
	      (run-compiler
	       '(tokens 
		 (SOC-start () (gemit gradient))
		 (gradient () 
			   (greturn x (to handler))
			   (grelay))
		 (handler (x) (display " ") (display x))
		 ))))
	 (disp "PROG")
	 (pp prog)
;	 (run-simulator-alpha prog)
	 ))
     
     ,(lambda a #t)
     ]





'

(fluid-let ([pass-names
             '(cleanup-token-machine
                desugar-gradients
                cleanup-token-machine
                desugar-let-stored
                rename-stored
                cps-tokmac
                closure-convert
                cleanup-token-machine)])
  (let ([prog
         (run-compiler
           '(tokens
              (SOC-start () (gemit tok1))
              (tok1 (x) (printf "_ ") (grelay))))])
    (let ([prt (open-output-string)])
      (display "(" prt)
      (run-simulator-alpha prog 'outport prt)
      (display ")" prt)
      (read (open-input-string (get-output-string prt))))))




'
      (parameterize ([unique-name-counter 0] [simalpha-dbg-on #f])
      (fluid-let ([pass-names
		   '(cleanup-token-machine  desugar-gradients
		     cleanup-token-machine desugar-let-stored
		     rename-stored          cps-tokmac
		     closure-convert        cleanup-token-machine
		     )])
	(let ([prog
	       (run-compiler
		'(tokens
		  (SOC-start () (call tok1 '1))
		  (catcher (v) (printf "~a" v))
		  (tok1 (reps) 
			(gemit tok2)
			(if (> reps 0)
			    (timed-call 500 tok1 (- reps 1))))
		  (tok2 () (greturn 34 ;(my-id) 
				    (to catcher)))
		  ))])
	  (let ((lst 
		 (let ([prt (open-output-string)])
		   (run-simulator-alpha prog)
		   (read (open-input-string (get-output-string prt))))))
	    lst
	    ))))