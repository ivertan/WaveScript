(module pass13_addplaces mzscheme

  (require (lib "include.ss"))
  (require "constants.ss")
  (require "iu-match.ss")
  (require "helpers.ss")

  (require (lib "trace.ss"))

  (include (build-path ".." "generic" "pass13_addplaces.ss"))
  
;  (provide deglobalize
;;	   test-this these-tests test13 tests13)

   (define (test13)
     (addplaces '(annotate-heartbeats-lang
                  '(program
                    (props
                     (tmpanch_3 leaf anchor distributed)
                     (tmpunknpr_4 local)
                     (tmp_1 local)
                     (result_2 region area distributed final))
                    (lazy-letrec
                     ((tmp_1 #f (cons '30 tmpunknpr_4))
                      (result_2 1.0 (circle tmpanch_3 '50))
                      (tmpunknpr_4 #f (cons '40 '()))
                      (tmpanch_3 1.0 (anchor-at tmp_1)))
                     result_2)))))
     
  (provide (all-defined))
  )

;(require pass13_addplaces)

