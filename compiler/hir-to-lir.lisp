(in-package :compiler)

(defparameter *temp-counter* 0)

(defvar *compiland-vars* '())
(defvar *compiland-functions* '())
(defvar *compiland-body* '())

(defparameter +start-basic-block+ (make-basic-block :id (make-symbol "START")))

(defun check-basic-block-succ-pred (bb)
  (mapc (lambda (pred)
          (let ((count (count (basic-block-id bb)
                              (mapcar #'basic-block-id (basic-block-succ pred))
                              :test #'equal)))
            (assert (= 1 count))))
        (basic-block-pred bb))
  (mapc (lambda (succ)
          (let ((count (count (basic-block-id bb)
                              (mapcar #'basic-block-id (basic-block-pred succ))
                              :test #'equal)))
            (assert (= 1 count))))
          (basic-block-succ bb)))

(defun show-basic-block (bb)
  (format t "~A ~A~%" (basic-block-id bb) (mapcar #'basic-block-id (basic-block-pred bb)))
  (do-vector (lir (basic-block-code bb))
    (format t "  ~A~%" lir))
  (let ((succ (basic-block-succ bb)))
    (format t " ~A~%" (mapcar #'basic-block-id succ)))
  (handler-case (check-basic-block-succ-pred bb)
    (error ()
      (format t "ERROR~%"))))

(defun show-basic-blocks (basic-blocks)
  (mapc #'show-basic-block basic-blocks)
  (values))

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
                                         :succ nil)
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
            (case (lir-op last)
              ((jump fjump)
               (let* ((jump-label (lir-jump-label last))
                      (to (find-if (lambda (bb2)
                                     (let ((lir (vector-first (basic-block-code bb2))))
                                       (and (eq (lir-op lir) 'label)
                                            (eq (lir-arg1 lir) jump-label))))
                                   basic-blocks)))
                 (setf (basic-block-succ bb)
                       (let ((succ '()))
                         (when to
                           (push bb (basic-block-pred to))
                           (push to succ))
                         (when (and prev (eq (lir-op last) 'fjump))
                           (push bb (basic-block-pred prev))
                           (push prev succ))
                         succ))))
              (otherwise
               (when prev
                 (push bb (basic-block-pred prev))
                 (setf (basic-block-succ bb)
                       (list prev))))))
          (setf prev bb)))
      (let ((basic-blocks (nreverse basic-blocks)))
        (setf (basic-block-succ +start-basic-block+) (list (first basic-blocks)))
        (push +start-basic-block+ (basic-block-pred (first basic-blocks)))
        basic-blocks))))

(defun flatten-basic-blocks (basic-blocks)
  (coerce (mapcan (lambda (bb)
                    (coerce (basic-block-code bb) 'list))
                  basic-blocks)
          'vector))

(defun remove-basic-block (bb)
  (dolist (pred (basic-block-pred bb))
    (setf (basic-block-succ pred)
          (mapcan (lambda (succ)
                    (if (eq succ bb)
                        (basic-block-succ bb)
                        (list succ)))
                  (basic-block-succ pred))))
  (dolist (succ (basic-block-succ bb))
    (setf (basic-block-pred succ)
          (mapcan (lambda (pred)
                    (if (eq pred bb)
                        (basic-block-pred bb)
                        (list pred)))
                  (basic-block-pred succ))))
  (values))

(defun remove-unused-block (basic-blocks)
  (delete-if (lambda (bb)
               (when (null (basic-block-pred bb))
                 (remove-basic-block bb)
                 t))
             basic-blocks))

(defun remove-unused-label (basic-blocks)
  (let ((label-table '()))
    (dolist (bb basic-blocks)
      (let* ((code (basic-block-code bb))
             (lir (vector-last code)))
        (when (lir-jump-p lir)
          (pushnew (lir-jump-label lir) label-table))))
    (delete-if (lambda (bb)
                 (let* ((code (basic-block-code bb))
                        (lir (aref code 0)))
                   (when (and (eq (lir-op lir) 'label)
                              (not (member (lir-arg1 lir) label-table)))
                     (cond ((= 1 (length code))
                            (remove-basic-block bb)
                            t)
                           (t
                            (setf (basic-block-code bb)
                                  (subseq code 1))
                            nil)))))
               basic-blocks)))

(defun graphviz (compiland)
  (with-open-file (out "/tmp/valtan.dot"
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create)
    (let ((basic-blocks (compiland-body compiland)))
      (write-line "digraph graph_name {" out)
      (write-line "graph [ labeljust = l; ]" out)
      (write-line "node [ shape = box; ]" out)
      (dolist (bb basic-blocks)
        (format out "~A [label = \"" (basic-block-id bb))
        (do-vector (lir (basic-block-code bb))
          (write-string (princ-to-string (cons (lir-op lir) (lir-args lir))) out)
          (write-string "\\l" out))
        (format out "\"];~%")
        (dolist (succ (basic-block-succ bb))
          (format out "~A -> ~A~%" (basic-block-id bb) (basic-block-id succ))))
      (write-line "}" out)))
  #+sbcl
  (progn
    (uiop:run-program (format nil "dot -Tpng '/tmp/valtan.dot' > '/tmp/valtan.png'" ))
    #+linux (uiop:run-program (format nil "xdg-open '/tmp/valtan.png'"))
    #+os-macosx (uiop:run-program (format nil "open '/tmp/valtan.png'"))))

(defun test ()
  (let* ((compiland (hir-to-lir (pass1-toplevel '(dotimes (i 10) (f i)))))
         (basic-blocks (split-basic-blocks (compiland-body compiland))))
    (show-basic-blocks (setf (compiland-body compiland) basic-blocks))
    (write-line "1 ==================================================")
    (show-basic-blocks (setf (compiland-body compiland) (remove-unused-block basic-blocks)))
    (write-line "2 ==================================================")
    (show-basic-blocks (setf (compiland-body compiland) (remove-unused-label basic-blocks)))
    (graphviz compiland)
    ))
