(in-package :compiler)

(defparameter *temp-counter* 0)

(defvar *compiland-vars* '())
(defvar *compiland-functions* '())
(defvar *compiland-body* '())

(defstruct compiland
  vars
  functions
  body)

(defstruct lir-fn
  name
  lambda-list
  body)

(defun make-lir (op &rest args)
  (cons op args))

(defun lir-op (lir)
  (first lir))

(defun lir-arg1 (lir)
  (second lir))

(defun lir-arg2 (lir)
  (third lir))

(defun lir-jump-label (lir)
  (ecase (lir-op lir)
    (jump
     (lir-arg1 lir))
    (fjump
     (lir-arg2 lir))))

(defun lir-jump-p (lir)
  (case (lir-op lir)
    ((jump fjump) t)
    (otherwise nil)))

(defstruct basic-block
  id
  code
  next
  use-p)

(defun show-basic-block (basic-block)
  (format t "~A~%" (basic-block-id basic-block))
  (do-vector (lir (basic-block-code basic-block))
    (format t "  ~A~%" lir))
  (let ((next (basic-block-next basic-block)))
    (when next
      (format t " ~A~%" `(next ,(basic-block-id next))))))

(defun show-basic-blocks (basic-blocks)
  (dolist (bb basic-blocks)
    (show-basic-block bb)))

(defun gen-temp (prefix)
  (prog1 (make-symbol (format nil "~A~A" prefix *temp-counter*))
    (incf *temp-counter*)))

(defun gen-label ()
  (gen-temp "L"))

(defun gen-var ()
  (let ((var (gen-temp "V")))
    (push var *compiland-vars*)
    var))

(defun emit-lir (lir)
  (push lir *compiland-body*))

(defun emit-lir-forms (hir-forms)
  (let (r)
    (dolist (hir hir-forms)
      (setq r (hir-to-lir-1 hir)))
    r))

(defun hir-to-lir-1 (hir)
  (ecase (hir-op hir)
    ((const)
     (let ((lir (make-lir 'const (hir-arg1 hir))))
       lir))
    ((lref)
     (binding-id (hir-arg1 hir)))
    ((gref)
     (hir-arg1 hir))
    ((lset)
     (let ((var (binding-id (hir-arg1 hir)))
           (result (hir-to-lir-1 (hir-arg2 hir))))
       (emit-lir (make-lir 'lset var result))
       var))
    ((gset)
     (emit-lir (make-lir 'gset (hir-arg1 hir) (hir-arg2 hir)))
     (hir-arg1 hir))
    ((if)
     (let ((test (hir-to-lir-1 (hir-arg1 hir)))
           (flabel (gen-label))
           (tlabel (gen-label))
           (result (gen-var)))
       ;; then
       (emit-lir (make-lir 'fjump test flabel))
       (let ((then (hir-to-lir-1 (hir-arg2 hir))))
         (emit-lir (make-lir 'move result then)))
       (emit-lir (make-lir 'jump tlabel))
       ;; else
       (emit-lir (make-lir 'label flabel))
       (let ((else (hir-to-lir-1 (hir-arg3 hir))))
         (emit-lir (make-lir 'move result else)))
       ;; merge branch
       (emit-lir (make-lir 'label tlabel))
       result))
    ((progn)
     (emit-lir-forms (hir-arg1 hir)))
    ((lambda)
     (let* ((name (hir-arg1 hir))
            (lambda-list (hir-arg2 hir))
            (body (hir-arg3 hir))
            (lir-body (let ((*compiland-body* '()))
                        (emit-lir-forms body)
                        *compiland-body*)))
       (let ((fn (make-lir-fn :name (or name (gensym)) :lambda-list lambda-list :body lir-body)))
         (push fn
               *compiland-functions*)
         (make-lir 'fn (lir-fn-name fn)))))
    ((let)
     (let ((bindings (hir-arg1 hir)))
       (dolist (binding bindings)
         (ecase (binding-type binding)
           (:variable
            (push (binding-id binding) *compiland-vars*)
            (let ((r (hir-to-lir-1 (binding-init-value binding))))
              (emit-lir (make-lir 'move (binding-id binding) r))))
           (:function
            (push (binding-id binding) *compiland-vars*)
            (let ((r (hir-to-lir-1 (binding-init-value binding))))
              (emit-lir (make-lir 'move (binding-id binding) r))))))
       (emit-lir-forms (hir-arg2 hir))))
    ((lcall call)
     (let ((args (mapcar (lambda (arg)
                           (let ((r (hir-to-lir-1 arg))
                                 (a (gen-var)))
                             (emit-lir (make-lir 'move a r))
                             a))
                         (hir-arg2 hir)))
           (result (gen-var)))
       (emit-lir (make-lir 'move
                           result
                           (make-lir (hir-op hir)
                                     (if (eq 'lcall (hir-op hir))
                                         (binding-id (hir-arg1 hir))
                                         (hir-arg1 hir))
                                     args)))
       result))
    ((unwind-protect)
     (let ((protected-form (hir-arg1 hir))
           (cleanup-form (hir-arg2 hir)))
       (emit-lir (make-lir 'unwind-protect))
       (let ((result (hir-to-lir-1 protected-form)))
         (emit-lir (make-lir 'cleanup-start))
         (hir-to-lir-1 cleanup-form)
         (emit-lir (make-lir 'cleanup-end))
         result)))
    ((block)
     (let ((name (hir-arg1 hir))
           (body (hir-arg2 hir)))
       (setf (binding-init-value name) (gen-var))
       (let ((result (emit-lir-forms body)))
         (emit-lir (make-lir 'label (binding-id name)))
         result)))
    ((return-from)
     (let ((name (hir-arg1 hir))
           (result (hir-to-lir-1 (hir-arg2 hir))))
       (emit-lir (make-lir 'move (binding-init-value name) result))
       (emit-lir (make-lir 'jump (binding-id name)))
       (binding-init-value name)))
    ((tagbody)
     (dolist (elt (hir-arg2 hir))
       (destructuring-bind (tag . form) elt
         (emit-lir (make-lir 'label (tagbody-value-index (binding-id tag))))
         (hir-to-lir-1 form)))
     (make-lir 'const nil))
    ((go)
     (emit-lir (make-lir 'jump (tagbody-value-index (hir-arg1 hir))))
     (make-lir 'const nil))
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

(defun hir-to-lir (hir)
  (let ((*temp-counter* 0)
        (*compiland-vars* '())
        (*compiland-functions* '())
        (*compiland-body* '()))
    (emit-lir (make-lir 'return (hir-to-lir-1 hir)))
    (make-compiland :vars *compiland-vars*
                    :functions *compiland-functions*
                    :body (coerce (nreverse *compiland-body*) 'vector))))

(defun split-basic-blocks (code)
  (let ((current-block '())
        (basic-blocks '()))
    (flet ((add-block ()
             (unless (null current-block)
               (let ((code (coerce (nreverse current-block) 'vector)))
                 (push (make-basic-block :id (gensym)
                                         :code code
                                         :next nil)
                       basic-blocks)))))
      (do-vector (lir code)
        (case (lir-op lir)
          ((label)
           (add-block)
           (setq current-block (list lir)))
          ((jump fjump)
           (push lir current-block)
           (add-block)
           (setf current-block '()))
          (otherwise
           (push lir current-block))))
      (add-block)
      (let (prev)
        (dolist (bb basic-blocks)
          (let ((last (vector-last (basic-block-code bb))))
            (if (lir-jump-p last)
                (let ((jump-label (lir-jump-label last)))
                  (setf (basic-block-next bb)
                        (let ((bb2
                                (find-if (lambda (bb2)
                                           (let ((lir (vector-first (basic-block-code bb2))))
                                             (and (eq (lir-op lir) 'label)
                                                  (eq (lir-arg1 lir) jump-label))))
                                         basic-blocks)))
                          bb2)))
                (setf (basic-block-next bb)
                      prev)))
          (setf prev bb)))
      (nreverse basic-blocks))))

(defun flatten-basic-blocks (basic-blocks)
  (coerce (mapcan (lambda (bb)
                    (coerce (basic-block-code bb) 'list))
                  basic-blocks)
          'vector))

(defun remove-unused-label (basic-blocks)
  (let ((used-blocks (list (basic-block-id (car basic-blocks)))))
    (dolist (bb basic-blocks)
      (let ((next (basic-block-next bb)))
        (when next
          (push next used-blocks))))
    (let ((removed nil))
      (values (delete-if (lambda (bb)
                           (and (not (member (basic-block-id bb) used-blocks))
                                (setq removed t)))
                         basic-blocks)
              removed))))

(defun lir-optimize (compiland)
  (let ((code (compiland-body compiland)))
    (print code)
    (let ((basic-blocks (split-basic-blocks code)))
      (setq basic-blocks (remove-unused-label basic-blocks))
      (print (flatten-basic-blocks basic-blocks))
      compiland)))
