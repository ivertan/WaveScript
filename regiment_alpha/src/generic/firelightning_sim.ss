;;;; .title A Simple Lightning/Forest-fire Sim.
;;;; .author Ryan Newton

;;;; [2006.02.01] <br> 
;;;; Matt and discussed a simple lightning/forest-fire simulation that
;;;; would stress Regiment and provide for some interesting programs.


;----------------------------------------------------------------------
;; This function maintains the global lightning state and also reads
;; off sensor values.  <br><br>
;; 
;; It's a curried function whose outer layer is called every time the
;; time changes so as to maintain the simulation state.  (However,
;; this is optional, it could very well only update when a sensor
;; reading is requested.)  The time-step must be
;; greater-than-or-equal-to the one inputted last.  However they
;; needn't be consecutive. <br><br>
;; 
;; The inner lambda is only called when the simulator needs to read
;; an actual sensor value.
(define firelightning-sense-function
  ;; This is the statically allocated state used by the lightning sim.
  ;; Could refactor this to encapsulate it later:
  (let ([last-time #f]
	;;; Other state....
	;; Current set of fire objects.
	[fires '()]

	;; Constants:
	;; Need to make this much more sophisticated.
	[lightning-prob .0001] ;; Probability per millisecond of lightning.
	[fire-spread-rate .1] ;; Again, per millisecond.
	[fire-width 2000] ;; The fire is a ring 500m thick.  It "burns out" in the center.
	[fire-age 30000] ;; Total life in milleseconds.
	)
    (reg:define-struct (fire x y t rad))    
    (lambda (t)
      (if (not last-time) (set! last-time t))
      (if (< t last-time)
	  (error 'firelightning-timestepper 
		 "can't go backwards in time from t=~a to t=~a." last-time t))
      (if (= t last-time)
	  (void)
	  (let ([delta (fx- t last-time)])
	    ;(printf " delt:~a\n" delta)
	    ;; Update State...
	    ;; Propogate existing fires.
	    (set! fires
		  (filter (lambda (f)
			(if (> (fire-t f) fire-age)
			    ;; This fires dead!
			    #f
			    (begin 
			      (set-fire-rad! f (+ (fire-rad f) (* delta fire-spread-rate)))
			      #t)))
		    fires))

	    (if (not (null? fires))
		(printf "    Fires: ~a\n" fires))

	    ;; See if there's a new lightning strike.
	    ;; TODO: Put in proper poisson process.
	    (when (< (random 1.0) (fl* lightning-prob (exact->inexact delta)))
	      (let ([strike-time (+ (random delta) last-time)]
		    [strike-x (random world-xbound)]
		    [strike-y (random world-ybound)])
		(printf "  LIGHTNING!! ~a\n" strike-time)
		(set! fires (cons (make-fire strike-x strike-y strike-time 0) ;; Initial radius zero
				  fires))
		
		))

	    (set! last-time t)
	    ))
      ;; Done updating state, now create a function for reading sensor values:
      (lambda (type id x y)
	
	(case type
	  [(temp)  
	   (let ((temp 0))
	     (for-each (lambda (f)
			 ;; Measure distance from us to the center of the fire.
			 (let ((dist (sqrt (+ (^ (- x (fire-x f)) 2)
					      (^ (- y (fire-y f)) 2)))))
			   (printf "Dist : ~a \n" dist)
			   (sim-setlabel dist)
			   ;; Are we within the circle:
			   (when (< dist (fire-rad f))
			     ;; Are we within the "eye", however.
			     (unless (> (- (fire-rad f) fire-width) dist)
			       (set! temp (+ temp fire-temp))))))
	       fires)
	     temp)]
	  [(light) 9999] ;; TODO
	  [else (error 'firelightning-sense-function 
		       "unsupported sensor type: ~a" type)])))))

;----------------------------------------------------------------------
;; Install the lightning sim as the default sim:
(define (install-firelightning)
  (simalpha-sense-function firelightning-sense-function)
  ;(simalpha-sense-timestepper firelightning-timestepper)

  ;; Set the world size, 10KM square:
  (set! world-xbound 10000)
  (set! world-ybound 10000)

  ;; Inner/Outer Radius for radios is 300/500 meters:
  (simalpha-inner-radius 300)
  (simalpha-inner-radius 500)

  (simalpha-channel-model 'linear-disc)
  (simalpha-placement-type 'gridlike)
  (simalpha-failure-model 'none)
  )
