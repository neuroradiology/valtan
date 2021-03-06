#+valtan
(in-package :common-lisp)
#-valtan
(in-package :valtan-core)

(defun funcall (function &rest args)
  (let ((function (ensure-function function)))
    (*:apply function (*:list-to-raw-array args))))

(defun apply (function arg &rest args)
  (let ((function (ensure-function function)))
    (cond ((null args)
           (unless (listp arg)
             (type-error arg 'list))
           (*:apply function (*:list-to-raw-array arg)))
          (t
           (let* ((head (list arg))
                  (tail head))
             (do ((rest args (cdr rest)))
                 ((null (cdr rest))
                  (unless (listp (car rest))
                    (type-error (car rest) 'list))
                  (setf (cdr tail) (car rest)))
               (let ((a (car rest)))
                 (setf (cdr tail) (list a))
                 (setq tail (cdr tail))))
             (*:apply function (*:list-to-raw-array head)))))))

(defun fdefinition (x)
  (or (cond ((consp x)
             (when (eq 'setf (car x))
               (get (cadr x) '*:fdefinition-setf)))
            ((symbolp x)
             (symbol-function x)))
      (error "The function ~S is undefined." x)))

(defun (cl:setf fdefinition) (function x)
  (or (cond ((consp x)
             (when (eq 'setf (car x))
               ;; TODO: clプリフィクスを外しても動くようにする
               (cl:setf (cl:get (cadr x) '*:fdefinition-setf)
                        function)))
            ((symbolp x)
             (setf (symbol-function x) function)))
      (error "Invalid function name: ~S" x)))
