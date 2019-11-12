(in-package :common-lisp)

(macrolet ((def (name op initial-value)
             `(defun ,name (&rest numbers)
                (let ((acc ,initial-value))
                  (dolist (n numbers)
                    (unless (numberp n)
                      (type-error n 'number))
                    (setq acc (,op acc n)))
                  acc))))
  (def + *:%add 0)
  (def * *:%mul 1))

(defun - (number &rest numbers)
  (unless (numberp number)
    (type-error number 'number))
  (if (null numbers)
      (*:%negate number)
      (dolist (n numbers number)
        (unless (numberp n)
          (type-error n 'number))
        (setq number (*:%sub number n)))))

(defun / (number &rest numbers)
  (unless (numberp number)
    (type-error number 'number))
  (if (null numbers)
      (/ 1 number)
      (dolist (n numbers number)
        (unless (numberp n)
          (type-error n 'number))
        (setq number (*:%floor number n)))))

(defun logand (&rest integers)
  (let ((result -1))
    (dolist (i integers)
      (unless (integerp i)
        (type-error i 'integer))
      (setq result (*:%logand result i)))
    result))

(macrolet ((def (name cmp)
             `(defun ,name (number &rest numbers)
                (unless (numberp number)
                  (type-error number 'number))
                (dolist (n numbers t)
                  (unless (numberp n)
                    (type-error n 'number))
                  (unless (,cmp number n)
                    (return nil))
                  (setq number n)))))
  (def = *:%=)
  (def /= *:%/=)
  (def > *:%>)
  (def < *:%<)
  (def >= *:%>=)
  (def <= *:%<=))

(defun rem (number divisor)
  (unless (numberp number)
    (type-error number 'number))
  (unless (numberp divisor)
    (type-error divisor 'number))
  (*:%rem number divisor))

(defun mod (number divisor)
  (rem number divisor))

(defun floor (number &optional (divisor 1))
  (unless (numberp number)
    (type-error number 'number))
  (unless (numberp divisor)
    (type-error divisor 'number))
  (*:%floor number divisor))

(defun floatp (x)
  (and (not (integerp x))
       (numberp x)))

(defun plusp (x)
  (< 0 x))

(defun minusp (x)
  (< x 0))

(defun 1+ (x)
  (+ x 1))

(defun 1- (x)
  (- x 1))

(defun zerop (x)
  (= x 0))

(defun evenp (x)
  (= 0 (rem x 2)))

(defun oddp (x)
  (= 1 (rem x 2)))

(defun min (number &rest more-numbers)
  (dolist (n more-numbers number)
    (when (< n number)
      (setq number n))))

(defun max (number &rest more-numbers)
  (dolist (n more-numbers number)
    (when (< number n)
      (setq number n))))

(defun expt (base power)
  (let ((acc 1))
    (dotimes (i power)
      (setq acc (* acc base)))
    acc))
