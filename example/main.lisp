(ffi:console.log "hello world")
(ffi:console.log (list 1 2 3))

(dotimes (i 10)
  (ffi:console.log i))

(dolist (i (list 1 2 3))
  (ffi:console.log i))

(dolist (x (list 'foo 'bar 'baz))
  (ffi:console.log "case" x
                   (case x
                     (foo 100)
                     (bar 200)
                     (otherwise 300))))

(dolist (k '(1 2 3 :four v () t 'other))
  (ffi:console.log
   (case k ((1 2) 'clause1)
         (3 'clause2)
         (nil 'no-keys-so-never-seen)
         ((nil) 'nilslot)
         ((:four v) 'clause4)
         ((t) 'tslot)
         (otherwise 'others))))

(defun fact (n)
  (cond ((= n 0) 1)
        (t (* n (fact (- n 1))))))

(ffi:console.log (fact 5))

(ffi:console.log "==================== Character ====================")
(ffi:console.log (ffi:typeof #\a)
                 (ffi:ref #\a "length")
                 #\a (characterp #\a))
(assert (characterp #\a))
(assert (not (characterp "a")))
(assert (eql #\a (code-char 97)))
(assert (= 97 (char-code #\a)))

(ffi:console.log "==================== Array ====================")
(ffi:console.log (make-array 3))
(ffi:console.log (make-array 3 :initial-element 100))
(ffi:console.log (arrayp (make-array 3)))
(let ((a (make-array 3 :fill-pointer t)))
  (assert (array-has-fill-pointer-p a))
  (assert (= 1 (array-rank a)))
  (assert (vectorp a))
  (assert (not (vectorp 1)))
  (assert (vectorp "test"))
  (dotimes (i 3)
    (setf (aref a i) i))
  (dotimes (i 3)
    (assert (= (aref a i) i))))

(let ((array "abcd"))
  (ffi:console.log array)
  (assert (eql (aref array 0) #\a))
  (assert (eql (aref array 1) #\b))
  (assert (eql (aref array 2) #\c))
  (assert (eql (aref array 3) #\d)))

(let ((x (make-array 10 :initial-element #\a :element-type 'character)))
  (assert (eq (array-element-type x) 'character))
  (assert (stringp x))
  (assert (string= x "aaaaaaaaaa")))

(ffi:console.log "==================== ffi ====================")
(let ((x (ffi:new (ffi:ref "Array") 10)))
  (ffi:console.log x)
  (ffi:set (ffi:index x 0) "a")
  (ffi:console.log (ffi:index x 0)))

(ffi:console.log "==================== cons ====================")
(ffi:console.log (cons 1 2))
(assert (eql 1 (car (cons 1 2))))
(assert (eql 2 (cdr (cons 1 2))))
(assert (consp (cons 1 2)))
(let ((x (cons 1 2)))
  (assert (eql 100 (rplaca x 100)))
  (assert (eql 200 (rplacd x 200)))
  (assert (eql 100 (car x)))
  (assert (eql 200 (cdr x))))
(let ((x (cons 1 2)))
  (setf (car x) 849213482)
  (assert (eql (car x) 849213482)))
(ffi:console.log (list* 1))
(ffi:console.log (list* 1 2))
(ffi:console.log (list* 1 2 3))
(ffi:console.log "member" (member 2 (list 1 2 3)))

(ffi:console.log "==================== lambda-list ====================")
(defun f1 (&rest args)
  (ffi:console.log args))

(f1 1 2 3)

(defun f2 (x y &rest z)
  (ffi:console.log x y z))

(f2 1 2)
(f2 1 2 3)
(f2 1 2 3 4)

(defun f3 (&key (foo 100))
  foo)

(ffi:console.log (f3))
(ffi:console.log (f3 :foo 0))

(ffi:console.log "==================== defstruct ====================")
(defstruct foo
  x y z)
(ffi:console.log (make-foo))
(ffi:console.log (make-foo :x 10 :y 20 :z 30))
(ffi:console.log (make-foo :z 10 :x 20))
(ffi:console.log (make-foo :y 100))
(let ((foo (make-foo :x 12345 :y 200 :z 'foo)))
  (ffi:console.log (foo-x foo))
  (ffi:console.log (foo-y foo))
  (ffi:console.log (foo-z foo)))

(defstruct bar
  (x 100))
(ffi:console.log (make-bar))
(ffi:console.log (make-bar :x 0))

(defstruct (hoge (:constructor %make-hoge))
  x
  y
  z)
(ffi:console.log (%make-hoge :x 1 :y 2 :z 3))

(defstruct (piyo (:constructor %make-piyo (x y z)))
  x
  y
  z)
(let ((piyo (%make-piyo 100 200 300)))
  (ffi:console.log piyo)
  (setf (piyo-x piyo) 'test)
  (ffi:console.log piyo (piyo-x piyo)))

(let ((piyo (%make-piyo 1 2 3)))
  (ffi:console.log (eq piyo piyo))
  (ffi:console.log (eq piyo (copy-structure piyo)))
  (ffi:console.log (eq piyo (copy-piyo piyo)))
  (ffi:console.log (piyo-p piyo)))

(ffi:console.log "==================== Symbol ====================")
(assert (equal (symbol-plist 'foo) '()))
(setf (symbol-plist 'foo) (list 'a 1 'b 2))
(assert (equal (symbol-plist 'foo) '(a 1 b 2)))
(setf (get 'aaa 'key1) 100)
(assert (= (get 'aaa 'key1) 100))

(assert (keywordp :foo))
(assert (not (keywordp 'foo)))
(assert (not (keywordp 1)))

(let ((name (symbol-name 'abc)))
  (assert (stringp name))
  (assert (string= name "ABC")))

(ffi:console.log "==================== Hash Table ====================")
(let ((x (make-hash-table)))
  (ffi:console.log x)
  (ffi:console.log (hash-table-p x))
  (ffi:console.log "hash-table-count" (hash-table-count x))
  (ffi:console.log (gethash "key1" x))
  (ffi:console.log (setf (gethash "key1" x) "value"))
  (ffi:console.log  "hash-table-count" 1 (hash-table-count x))
  (gethash "key1" x)
  (ffi:console.log (remhash "key1" x))
  (ffi:console.log "hash-table-count" 0 (hash-table-count x))
  (ffi:console.log (remhash "key1" x))
  )

(let ((ht (make-hash-table)))
  (setf (gethash "key1" ht) 100)
  (setf (gethash "key2" ht) 200)
  (setf (gethash "key3" ht) 300)
  (maphash (lambda (k v)
             (ffi:console.log k v))
           ht))

(ffi:console.log "==================== destructuring-bind ====================")

(destructuring-bind (a) (list 1)
  (ffi:console.log a))

(destructuring-bind ((a)) (list (list 2))
  (ffi:console.log a))

(destructuring-bind ((a &optional (b "default"))) (list (list 2))
  (ffi:console.log a b))

(destructuring-bind ((a &optional (b "default")) x y)
    (list (list 2) 10 20)
  (ffi:console.log a b x y))

(destructuring-bind ((a &optional (b 'bee)) one two three)
    `((alpha) ,@(list 1 2 3))
  (ffi:console.log a b three two one))

(destructuring-bind (a . b) (cons 1 2)
  (ffi:console.log a b))

(ffi:console.log "==================== apply ====================")
(ffi:console.log (apply '+ '()))
(ffi:console.log (apply '+ '(1 2 3)))
(ffi:console.log (apply '+ 1 2 3 '(4 5 6)))

(ffi:console.log "(numberp 1)" (numberp 1))
(ffi:console.log "(numberp 1.2)" (numberp 1.2))
(ffi:console.log "(numberp 'a)" (numberp 'a))
(ffi:console.log "(integerp 1)" (integerp 1))
(ffi:console.log "(integerp 1.0)" (integerp 1.0))
(ffi:console.log "(integerp 'a)" (integerp 'a))

(ffi:console.log "==================== stream ====================")
(ffi:console.log
 (with-output-to-string (out)
   (write-string "string" out)
   (write-char #\! out)))

(ffi:console.log "==================== package ====================")
(ffi:console.log (package-name :cl))
(ffi:console.log (package-name 'common-lisp))
(ffi:console.log (find-package :keyword))
(ffi:console.log (package-name (find-package :keyword)))

(defun foo ()
  (ffi:console.log "a")
  (return-from foo)
  (ffi:console.log "b"))

(foo)

(ffi:console.log (find-if #'(lambda (x) (= x 2)) '(1 2 3)))



(ffi:console.log (make-symbol "adlfjasldfkjksj"))

(let ((x 0))
  (defun f ()
    (setq x (+ x 1))))

(ffi:console.log (f))
(ffi:console.log (f))

(ffi:console.log #\a)
(ffi:console.log (characterp #\a))
(ffi:console.log (code-char 70))
(ffi:console.log (char-code #\a))

(ffi:console.log (funcall #'+ 1 2))
(ffi:console.log (apply #'+ '(1 2 3)))
(ffi:console.log (apply #'+ 100 200 '(1 2 3)))

(defun return-values ()
  (values 100 200))

(assert (= 100 (multiple-value-call #'+ 100)))
(assert (= 300 (multiple-value-call #'+ (return-values))))
(assert (= 6 (multiple-value-call #'+ (values 1 2 3))))

(assert (= 300 (multiple-value-call '+ 100 200)))
(assert (= 600 (multiple-value-call '+ 100 200 300)))
(assert (= 106 (multiple-value-call '+ 100 (values 1 2 3))))
(assert (= 400 (multiple-value-call '+ 100 (return-values))))

(assert (equal 1 1))
(assert (not (equal 1 2)))
(assert (equal 'a 'a))
(assert (not (equal 'a 'b)))
(assert (equal (cons 1 2) (cons 1 2)))
(assert (equal '(1 ((a b) 3)) '(1 ((a b) 3))))
(assert (not (equal '(2 ((a b) 3)) '(1 ((a b) 3)))))
(assert (not (equal (list 1 2) (list 1 2 3))))

((lambda (&rest x) (assert (equal x (list 1 2 3)))) 1 2 3)
((lambda (x &rest y)
   (assert (eql x 1))
   (assert (equal y (list 2 3))))
 1 2 3)

((lambda (x)
   (declare (special x))
   (assert (eql x 0)))
 0)

(defun e18153e3-f341-4e18-8114-c98ca80b6835 ()
  (declare (special x))
  (assert (eql x 123)))

(let ((x 123))
  (declare (special x))
  (e18153e3-f341-4e18-8114-c98ca80b6835))
