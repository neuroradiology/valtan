(in-package :common-lisp)

(defun make-symbol (string)
  (system::%make-symbol (system::array-to-js-string string)))

(defun symbol-name (symbol)
  (system::js-string-to-array (system::%symbol-name symbol)))

(defun symbol-package (symbol)
  (if (eq (system::symbol-package-name symbol) (ffi:ref "null"))
      nil
      (find-package (system::js-string-to-array (system::symbol-package-name symbol)))))

(defun keywordp (x)
  (and (symbolp x)
       (eq (symbol-package x)
           (find-package :keyword))))

(defun get (symbol indicator &optional default)
  (getf (symbol-plist symbol) indicator default))

(defun (setf symbol-plist) (plist symbol)
  (system::put-symbol-plist symbol plist))

(defsetf get (symbol indicator &optional default)
    (value)
  (let ((g-value (gensym)))
    `(let ((,g-value ,value))
       (system::%put ,symbol ,indicator
                     (progn ,default ,g-value))
       ,g-value)))

(defun remprop (symbol indicator)
  (do ((plist (symbol-plist symbol) (cddr plist))
       (prev nil plist))
      ((null plist))
    (when (eq indicator (car plist))
      (if prev
          (setf (cddr prev) (cddr plist))
          (setf (symbol-plist symbol) (cddr plist)))
      (return plist))))

(defun (setf symbol-value) (value symbol)
  (set symbol value))

(defun (setf symbol-function) (function symbol)
  (system::fset symbol function))

(defvar *gensym-counter* 0)

(defun gensym (&optional (prefix "G"))
  (make-symbol (cond ((and (integerp prefix) (<= 0 prefix))
                      (format nil "G~D" prefix))
                     ((not (stringp prefix))
                      (type-error prefix '(or string unsigned-byte)))
                     (t
                      (prog1 (system::string-append prefix (princ-to-string *gensym-counter*))
                        (incf *gensym-counter*))))))

(defvar *gentemp-counter* 0)

(defun gentemp (&optional (prefix "T") (package *package*))
  (do ()
      (nil)
    (let ((name (system::string-append prefix (princ-to-string *gentemp-counter*))))
      (incf *gentemp-counter*)
      (unless (find-symbol name package)
        (return (intern name package))))))

(defun copy-symbol (symbol &optional copy-props)
  (unless (symbolp symbol) (type-error symbol 'symbol))
  (cond (copy-props
         (let ((new-symbol (make-symbol (string symbol))))
           (when (boundp symbol)
             (setf (symbol-value new-symbol) (symbol-value symbol)))
           (when (fboundp symbol)
             (setf (symbol-function new-symbol) (symbol-function symbol)))
           (setf (symbol-plist new-symbol) (symbol-plist symbol))
           new-symbol))
        (t
         (make-symbol (string symbol)))))
