


(define haskellize-tokmac-language
  (lambda (str) 
    
    (printf "~nDumping token machine into directory: ~s~n" (current-directory))
    (let ([out (force-open-output-file "test_tokmac_comp.tm")])
      (display str out)
      (close-output-port out))
    (printf "~nBinding top-level function (run_tm) to compile&assemble this token machine.~n")
    (define-top-level-value 'run_tm
      (lambda ()
	(parameterize ([current-directory "haskell"])
	  (printf "Running token machine in directory: ~s~n~n from str: ~n~s~n~n" 
		  (current-directory) str)

	  (if (not (file-exists? "assembler"))
	      (error 'run_tm "Missing assembler.")
	      (let ([file (or (and (file-exists? "test_tokmac_comp.tm") "test_tokmac_comp.tm")
			      (and (file-exists? "../test_tokmac_comp.tm") "../test_tokmac_comp.tm")
			      (error 'run_tm "Missing test_tokmac_comp.tm") )])	    		
		;; First use the assembler:
		(if (zero? (system (string-append "./assembler " file)))
		    ;; Then use the NesC compiler:
		    (system "make pc")
		    (error 'haskellized-tokmac "did not parse or assemble.")
		 ))))))
    (run_tm)))

