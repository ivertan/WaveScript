;;; fft.ss
;;; Copyright (C) 1996 R. Kent Dybvig
;;; from "The Scheme Programming Language, 2ed" by R. Kent Dybvig

(define (dft x)
  (define (w-powers n)
    (let ((pi (* (acos 0.0) 2)))
      (let ((delta (/ (* -2.0i pi) n)))
        (let f ((n n) (x 0.0))
          (if (= n 0)
              '()
              (cons (exp x) (f (- n 2) (+ x delta))))))))
  (define (evens w)
    (if (null? w)
        '()
        (cons (car w) (evens (cddr w)))))
  (define (interlace x y)
    (if (null? x)
        '()
        (cons (car x) (cons (car y) (interlace (cdr x) (cdr y))))))
  (define (split ls)
    (let split ((fast ls) (slow ls))
      (if (null? fast)
          (values '() slow)
          (call-with-values
            (lambda () (split (cddr fast) (cdr slow)))
            (lambda (front back)
              (values (cons (car slow) front) back))))))
  (define (butterfly x w)
    (call-with-values
      (lambda () (split x))
      (lambda (front back)
        (values
          (map + front back)
          (map * (map - front back) w)))))
  (define (rfft x w)
    (if (null? (cddr x))
      (let ((x0 (car x)) (x1 (cadr x)))
        (list (+ x0 x1) (- x0 x1)))
      (call-with-values
        (lambda () (butterfly x w))
        (lambda (front back)
          (let ((w (evens w)))
            (interlace (rfft front w) (rfft back w)))))))
  (rfft x (w-powers (length x))))