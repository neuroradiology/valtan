(in-package :compiler)

(defparameter *temp-counter* 0)

(defvar *compilation-vars* '())
(defvar *compilation-functions* '())
(defvar *compilation-body* '())

(defstruct compilation
  vars
  functions
  body)

(defun make-lir (op &rest args)
  (cons op args))

(defun gen-temp (prefix)
  (prog1 (format nil "~A~A" prefix *temp-counter*)
    (incf *temp-counter*)))

(defun gen-label ()
  (gen-temp "L"))

(defun gen-var ()
  (let ((var (gen-temp "V")))
    (push var *compilation-vars*)
    var))

(defun emit (lir)
  (push lir *compilation-body*))

(defun hir-to-lir (hir)
  (ecase (hir-op hir)
    ((const)
     (let ((lir (make-lir 'const (hir-arg1 hir))))
       lir))
    ((lref)
     (binding-id (hir-arg1 hir)))
    ((gref)
     (hir-arg1 hir))
    ((lset)
     (let ((var (binding-id (hir-arg1 hir))))
       (emit (make-lir 'lset var (hir-arg2 hir)))
       var))
    ((gset)
     (emit (make-lir 'gset (hir-arg1 hir) (hir-arg2 hir)))
     (hir-arg1 hir))
    ((if)
     (let ((test (hir-to-lir (hir-arg1 hir)))
           (flabel (gen-label))
           (tlabel (gen-label))
           (result (gen-var)))
       ;; then
       (emit (make-lir 'fjump test flabel))
       (let ((then (hir-to-lir (hir-arg2 hir))))
         (emit (make-lir 'move result then)))
       (emit (make-lir 'jump tlabel))
       ;; else
       (emit (make-lir 'label flabel))
       (let ((else (hir-to-lir (hir-arg3 hir))))
         (emit (make-lir 'move result else)))
       ;; merge branch
       (emit (make-lir 'label tlabel))
       result))
    ((progn)
     (let (r)
       (dolist (arg (hir-arg1 hir))
         (setq r (hir-to-lir arg)))
       r))
    ((lambda)
     )
    ((let)
     (let ((bindings (hir-arg1 hir)))
       (dolist (binding bindings)
         (push (binding-id binding) *compilation-vars*)
         (let ((r (hir-to-lir (binding-init-value binding))))
           (emit (make-lir 'move (binding-id binding) r))))
       (let (r)
         (dolist (arg (hir-arg2 hir))
           (setq r (hir-to-lir arg)))
         r)))
    ((lcall call)
     (let ((args (mapcar (lambda (arg)
                           (let ((r (hir-to-lir arg))
                                 (a (gen-var)))
                             (emit (make-lir 'move a r))
                             a))
                         (hir-arg2 hir)))
           (result (gen-var)))
       (emit (make-lir 'move result (make-lir (hir-op hir) (hir-arg1 hir) args)))
       result))
    ((unwind-protect)
     )
    ((block)
     )
    ((return-from)
     )
    ((tagbody)
     )
    ((go)
     )
    ((catch)
     )
    ((throw)
     )
    ((*:%defun)
     )
    ((*:%defpackage) hir)
    ((*:%in-package) hir)
    ((ffi:ref) hir)
    ((ffi:set) hir)
    ((ffi:var) hir)
    ((ffi:typeof) hir)
    ((ffi:new) hir)
    ((ffi:aget) hir)
    ((js-call) hir)
    ((module) hir)))

(defun convert-to-lir (hir)
  (let ((*temp-counter* 0)
        (*compilation-vars* '())
        (*compilation-functions* '())
        (*compilation-body* '()))
    (hir-to-lir hir)
    (make-compilation :vars *compilation-vars*
                      :functions *compilation-functions*
                      :body (coerce (nreverse *compilation-body*) 'vector))))


#|
(LET (("X_1" #(CONST 0)))
  (CALL + (LREF "X_1") #(CONST 1)))

(prog (X_1)
  (move X_1 (const 0))
  (call + X_1 (const 1)))

(let ((x 0))
  (defun counter ()
    (setq x (+ x 1))))

(let (("x_1" #(const 0)))
  (call system:fset #(const counter)
        (named-lambda nil #s(parsed-lambda-list :vars nil :rest-var nil :optionals nil :keys nil :min 0 :max 0 :allow-other-keys nil)
          (progn (progn (lset "x_1" (call + (lref "x_1") #(const 1))))))))

(compiland :vars (x tmp0 tmp1 tmp2 tmp3 tmp4)
           :functions #((named-lambda nil #s(parsed-lambda-list :vars nil :rest-var nil :optionals nil :keys nil :min 0 :max 0 :allow-other-keys nil)
                          (lset tmp2 x)
                          (lset tmp3 (const 1))
                          (lset tmp4 (call + tmp2 tmp3))
                          (return tmp4)))
           :body #((lset x 0)
                   (lset tmp0 (const counter))
                   (lset tmp1 (fn 0))
                   (call fset tmp0 tmp1)))

|#