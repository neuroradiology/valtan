(in-package :compiler)

(defvar *p2-emit-stream* *standard-output*)
(defvar *p2-literal-symbols* (make-hash-table))
(defvar *p2-context*)

(defmacro p2-emit-try-finally (try finally)
  `(progn
     (write-line "try{" *p2-emit-stream*)
     ,try
     (write-line "}finally{" *p2-emit-stream*)
     ,finally
     (write-line "}" *p2-emit-stream*)))

(defmacro p2-emit-try-catch (try-form ((error-var) &body catch-form))
  `(progn
     (write-line "try {" *p2-emit-stream*)
     ,try-form
     (format *p2-emit-stream* "}catch(~A){" ,error-var)
     ,@catch-form
     (write-line "}" *p2-emit-stream*)))

(defun p2-emit-for-aux (loop-var start end step function)
  (write-string "for (let " *p2-emit-stream*)
  (write-string loop-var *p2-emit-stream*)
  (write-string " = " *p2-emit-stream*)
  (princ start *p2-emit-stream*)
  (write-string "; " *p2-emit-stream*)
  (write-string loop-var *p2-emit-stream*)
  (write-string " < " *p2-emit-stream*)
  (write-string end *p2-emit-stream*)
  (write-string "; " *p2-emit-stream*)
  (write-string loop-var *p2-emit-stream*)
  (if (= step 1)
      (write-string " ++" *p2-emit-stream*)
      (progn
        (write-string " += " *p2-emit-stream*)
        (princ step *p2-emit-stream*)))
  (write-line ") {" *p2-emit-stream*)
  (funcall function)
  (write-line "}" *p2-emit-stream*))

(defmacro p2-emit-for ((loop-var start end step) &body body)
  `(p2-emit-for-aux ,loop-var ,start ,end ,step (lambda () ,@body)))

(defmacro p2-with-unwind-special-vars (form unwind-code)
  (let ((unwind-code-var (gensym)))
    `(let ((,unwind-code-var ,unwind-code))
       (if (string= ,unwind-code-var "")
           ,form
           (p2-emit-try-finally ,form (write-string ,unwind-code-var *p2-emit-stream*))))))

(defmacro define-p2-emit (op (hir) &body body)
  (let ((name (make-symbol (format nil "~A:~A" (package-name (symbol-package op)) (symbol-name op)))))
    `(progn
       (defun ,name (,hir)
         (declare (ignorable hir))
         ,@body)
       (setf (get ',op 'p2-emit)
             ',name))))

(defun p2 (hir *p2-context*)
  (assert (member *p2-context* '(:expr :stmt)))
  (assert (eq (if (hir-return-value-p hir) :expr :stmt) *p2-context*))
  (let ((fn (get (hir-op hir) 'p2-emit)))
    (assert fn)
    (funcall fn hir)))

(defun p2-genvar (&optional (prefix "TMP"))
  (genvar prefix))

(defun p2-escape-string (string &optional prefix)
  (setq string (string string))
  (flet ((f (c)
           (or (cdr (assoc c *character-map*))
               (string c))))
    (with-output-to-string (out)
      (when prefix (write-string prefix out))
      (map nil (lambda (c)
                 (write-string (f c) out))
           string))))

(defun p2-local-var (symbol &optional (prefix "L_"))
  (p2-escape-string symbol prefix))

(defun p2-local-function (symbol)
  (p2-escape-string symbol "F_"))

(defun p2-symbol-to-js-value (symbol)
  (or (gethash symbol *p2-literal-symbols*)
      (setf (gethash symbol *p2-literal-symbols*)
            (genvar "G"))))

(defun p2-encode-string (string)
  (with-output-to-string (s)
    (write-char #\[ s)
    (let ((len (length string)))
      (do ((i 0 (1+ i)))
          ((>= i len))
        (princ (char-code (aref string i)) s)
        (when (< (1+ i) len)
          (write-string ", " s))))
    (write-char #\] s)))

(defun p2-literal (x)
  (cond ((null x)
         "lisp.S_nil")
        ((symbolp x)
         (p2-symbol-to-js-value x))
        ((stringp x)
         (format nil "CL_SYSTEM_JS_STRING_TO_ARRAY(lisp.codeArrayToString(~A))" (p2-encode-string x)))
        ((numberp x)
         (princ-to-string x))
        ((characterp x)
         (format nil "lisp.makeCharacter(~D)" (char-code x)))
        ((consp x)
         (format nil "lisp.makeCons(~A, ~A)"
                 (p2-literal (car x))
                 (p2-literal (cdr x))))
        ((vectorp x)
         (with-output-to-string (out)
           (write-string "CL_COMMON_LISP_VECTOR" out)
           (if (zerop (length x))
               (write-string "(" out)
               (dotimes (i (length x))
                 (if (zerop i)
                     (write-string "(" out)
                     (write-string "," out))
                 (write-string (p2-literal (aref x i)) out)))
           (write-string ")" out)))
        (t
         (error "unexpected literal: ~S" x))))

(defun p2-form (form)
  (cond ((hir-multiple-values-p form)
         (p2 form :expr))
        (t
         (let ((result (p2 form (if (hir-return-value-p form) :expr :stmt))))
           (format nil "lisp.values1(~A)" result)))))

(defun p2-forms (forms)
  (do ((forms forms (cdr forms)))
      ((length=1 forms)
       (p2-form (car forms)))
    (p2 (car forms) :stmt)))

(define-p2-emit const (hir)
  (p2-literal (hir-arg1 hir)))

(define-p2-emit lref (hir)
  (let ((binding (hir-arg1 hir)))
    (ecase (binding-type binding)
      ((:function)
       (p2-local-function (binding-name binding)))
      ((:variable)
       (p2-local-var (binding-id (hir-arg1 hir)))))))

(define-p2-emit gref (hir)
  (let ((ident (p2-symbol-to-js-value (hir-arg1 hir))))
    (format nil "lisp.symbolValue(~A)" ident)))

(define-p2-emit lset (hir)
  (let ((lhs (hir-arg1 hir))
        (rhs (hir-arg2 hir)))
    (let ((result (p2-local-var (binding-id lhs)))
          (value (p2 rhs :expr)))
      (format *p2-emit-stream* "~A = ~A;~%" result value)
      result)))

(define-p2-emit gset (hir)
  (let ((lhs (hir-arg1 hir))
        (rhs (hir-arg2 hir)))
    (let ((ident (p2-symbol-to-js-value lhs))
          (value (p2 rhs :expr)))
      (format *p2-emit-stream* "lisp.setSymbolValue(~A, ~A);~%" ident value)
      ident)))

(define-p2-emit if (hir)
  (let ((test (hir-arg1 hir))
        (then (hir-arg2 hir))
        (else (hir-arg3 hir)))
    ;; TODO: elseが省略できる場合は省略する
    (if (hir-return-value-p hir)
        (let ((test-result (p2 test :expr))
              (if-result (p2-genvar)))
          (format *p2-emit-stream* "let ~A;~%" if-result)
          (format *p2-emit-stream* "if(~A !== lisp.S_nil){~%" test-result)
          (format *p2-emit-stream* "~A=~A;~%" if-result (p2-form then))
          (format *p2-emit-stream* "}else{~%")
          (format *p2-emit-stream* "~A=~A;~%" if-result (p2-form else))
          (format *p2-emit-stream* "}~%")
          if-result)
        (let ((test-result (p2 test :expr)))
          (format *p2-emit-stream* "if(~A !== lisp.S_nil){~%" test-result)
          (p2 then :stmt)
          (format *p2-emit-stream* "}else{~%")
          (p2 else :stmt)
          (format *p2-emit-stream* "}~%")
          (values)))))

(define-p2-emit progn (hir)
  (p2-forms (hir-arg1 hir)))

(defun p2-emit-check-arguments (name parsed-lambda-list)
  (let ((min (parsed-lambda-list-min parsed-lambda-list))
        (max (parsed-lambda-list-max parsed-lambda-list)))
    (cond ((null max)
           (format *p2-emit-stream* "if(arguments.length < ~D) {~%" min))
          ((= min max)
           (format *p2-emit-stream* "if(arguments.length !== ~D) {~%" min))
          (t
           (format *p2-emit-stream* "if(arguments.length < ~D || ~D < arguments.length) {~%" min max)))
    (if (null name)
        (format *p2-emit-stream* "lisp.argumentsError(lisp.S_nil, arguments.length);~%")
        (format *p2-emit-stream* "lisp.argumentsError(lisp.intern('~A'), arguments.length);~%" name))
    (write-line "}" *p2-emit-stream*)))

(defun p2-make-save-var (var)
  (p2-local-var (binding-id var) "save_"))

(defun p2-emit-unwind-var (var finally-stream)
  (when (eq (binding-type var) :special)
    (let ((js-var (p2-symbol-to-js-value (binding-name var)))
          (save-var (p2-make-save-var var)))
      (format finally-stream "~A.value=~A;~%" js-var save-var))))

(defun p2-emit-declvar (var finally-stream)
  (ecase (binding-type var)
    ((:special)
     (let ((js-var (p2-symbol-to-js-value (binding-name var)))
           (save-var (p2-make-save-var var)))
       (format *p2-emit-stream* "const ~A=~A.value;~%" save-var js-var)
       (format *p2-emit-stream* "~A.value=" js-var))
     (when finally-stream
       (p2-emit-unwind-var var finally-stream)))
    ((:variable)
     (format *p2-emit-stream*
             "let ~A="
             (p2-local-var (binding-id var))))
    ((:function)
     (format *p2-emit-stream*
             "let ~A="
             (p2-local-function (binding-name var))))))

(defun p2-emit-lambda-list (parsed-lambda-list finally-stream)
  (let ((i 0))
    (dolist (var (parsed-lambda-list-vars parsed-lambda-list))
      (p2-emit-declvar var finally-stream)
      (format *p2-emit-stream* "arguments[~D];~%" i)
      (incf i))
    (dolist (opt (parsed-lambda-list-optionals parsed-lambda-list))
      (let ((var (first opt))
            (value (second opt))
            (supplied-binding (third opt)))
        (let ((result (p2 value :expr)))
          (p2-emit-declvar var finally-stream)
          (format *p2-emit-stream* "arguments.length > ~D ? arguments[~D] : " i i)
          (format *p2-emit-stream* "(~A);~%" result))
        (when supplied-binding
          (p2-emit-declvar supplied-binding finally-stream))
        (incf i)))
    (when (parsed-lambda-list-keys parsed-lambda-list)
      (let ((keyword-vars '()))
        (dolist (opt (parsed-lambda-list-keys parsed-lambda-list))
          (let* ((var (first opt))
                 (value (second opt))
                 (supplied-binding (third opt))
                 (keyword-var (p2-symbol-to-js-value (fourth opt)))
                 (supplied-var (p2-local-var (binding-id var) "supplied_")))
            (push keyword-var keyword-vars)
            (format *p2-emit-stream* "let ~A;~%" supplied-var)
            (let ((loop-var (p2-genvar)))
              (p2-emit-for (loop-var i "arguments.length" 2)
                (format *p2-emit-stream* "if(arguments[~D] === ~A){~%" loop-var keyword-var)
                (format *p2-emit-stream* "~A=arguments[~D+1];~%" supplied-var loop-var)
                (write-line "break;" *p2-emit-stream*)
                (write-line "}" *p2-emit-stream*)))
            (let ((result (p2 value :expr)))
              (p2-emit-declvar var finally-stream)
              (format *p2-emit-stream*
                      "~A !== undefined ? ~A : (~A);~%"
                      supplied-var
                      supplied-var
                      result))
            (when supplied-binding
              (p2-emit-declvar supplied-binding finally-stream)
              (format *p2-emit-stream* "~A !== undefined ? lisp.S_t : lisp.S_nil);~%" supplied-var))))
        (format *p2-emit-stream* "if((arguments.length-~D)%2===1)" i)
        (write-line "{lisp.programError('odd number of &KEY arguments');}")
        (when (and keyword-vars
                   (null (parsed-lambda-list-allow-other-keys parsed-lambda-list)))
          (let ((loop-var (p2-genvar)))
            (p2-emit-for (loop-var i "arguments.length" 2)
              (write-string "if(" *p2-emit-stream*)
              (do ((keyword-vars keyword-vars (rest keyword-vars)))
                  ((null keyword-vars))
                (format *p2-emit-stream* "arguments[~D]!==~A" loop-var (first keyword-vars))
                (when (rest keyword-vars)
                  (write-string " && " *p2-emit-stream*)))
              (format *p2-emit-stream*
                      ") { lisp.programError('Unknown &KEY argument: ' + arguments[~A].name); }~%"
                      loop-var))))))
    (let ((rest-var (parsed-lambda-list-rest-var parsed-lambda-list)))
      (when rest-var
        (p2-emit-declvar rest-var finally-stream)
        (format *p2-emit-stream* "lisp.jsArrayToList(arguments, ~D);~%" i)))))

(define-p2-emit lambda (hir)
  (let ((name (hir-arg1 hir))
        (parsed-lambda-list (hir-arg2 hir))
        (body (hir-arg3 hir)))
    (write-line "(function(){" *p2-emit-stream*)
    (p2-emit-check-arguments name parsed-lambda-list)
    (let ((finally-code
            (with-output-to-string (finally-stream)
              (p2-emit-lambda-list parsed-lambda-list finally-stream))))
      (p2-with-unwind-special-vars (let ((result (p2-forms body)))
                                     (format *p2-emit-stream* "return ~A;~%" result))
                                   finally-code))
    (write-line "})" *p2-emit-stream*)))

(define-p2-emit let (hir)
  (let ((bindings (hir-arg1 hir))
        (body (hir-arg2 hir)))
    (dolist (binding bindings)
      (let ((value (p2 (binding-init-value binding) :expr)))
        (p2-emit-declvar binding nil)
        (format *p2-emit-stream* "~A;~%" value)))
    (let (result)
      (p2-with-unwind-special-vars
       (setq result (p2-forms body))
       (with-output-to-string (output)
         (dolist (binding (reverse bindings))
           (p2-emit-unwind-var binding output))))
      result)))

(defun p2-prepare-args (args)
  (mapcar (lambda (arg)
            (p2 arg :expr))
          args))

(defun p2-emit-args (args)
  (do ((args args (cdr args)))
      ((null args))
    (princ (car args) *p2-emit-stream*)
    (when (cdr args)
      (write-string "," *p2-emit-stream*)))
  (write-line ");" *p2-emit-stream*))

(define-p2-emit lcall (hir)
  (let ((args (p2-prepare-args (hir-arg2 hir)))
        (result nil))
    (when (hir-return-value-p hir)
      (setq result (p2-genvar))
      (format *p2-emit-stream* "let ~A=" result))
    (format *p2-emit-stream* "~A(" (p2-local-function (binding-name (hir-arg1 hir))))
    (p2-emit-args args)
    result))

(define-p2-emit call (hir)
  ;; TODO: 組み込み関数の場合は効率の良いコードを出力する
  (let ((symbol (hir-arg1 hir))
        (args (p2-prepare-args (hir-arg2 hir)))
        (result nil))
    (when (hir-return-value-p hir)
      (setq result (p2-genvar))
      (format *p2-emit-stream* "let ~A=" result))
    (format *p2-emit-stream* "lisp.callFunctionWithCallStack(~A" (p2-symbol-to-js-value symbol))
    (when args (write-string "," *p2-emit-stream*))
    (p2-emit-args args)
    result))

(define-p2-emit unwind-protect (hir)
  (let ((protected-form (hir-arg1 hir))
        (cleanup-form (hir-arg2 hir))
        (saved-return-var (when (hir-return-value-p hir) (p2-genvar "saved")))
        (result))
    (when saved-return-var
      (format *p2-emit-stream* "let ~A;~%" saved-return-var))
    (p2-emit-try-finally (setq result
                               (cond ((hir-return-value-p hir)
                                      (let ((protect-form-result (p2-form protected-form)))
                                        (format *p2-emit-stream* "~A=lisp.currentValues();~%" saved-return-var)
                                        protect-form-result))
                                     (t
                                      (p2 protected-form :stmt)
                                      nil)))
                         (progn
                           (p2 cleanup-form :stmt)
                           (when (hir-return-value-p hir)
                             (format *p2-emit-stream*
                                     "lisp.restoreValues(~A);~%"
                                     saved-return-var))))
    result))

(defvar *p2-block-result*)

(define-p2-emit block (hir)
  (let ((name (hir-arg1 hir))
        (body (hir-arg2 hir)))
    (cond ((eql 0 (binding-escape-count name))
           (let ((*p2-block-result* (p2-genvar)))
             (format *p2-emit-stream* "let ~A;~%" *p2-block-result*)
             (format *p2-emit-stream* "~A: for(;;){" (binding-id name))
             (let ((result (p2-forms body)))
               (format *p2-emit-stream* "~A=~A;~%" *p2-block-result* result))
             (write-line "break;" *p2-emit-stream*)
             (write-line "}" *p2-emit-stream*)
             *p2-block-result*))
          (t
           (let ((error-var (p2-genvar "E_"))
                 result)
             (p2-emit-try-catch
              (setq result (p2-forms body))
              ((error-var)
               (format *p2-emit-stream*
                       "if(~A instanceof lisp.BlockValue && ~A.name === ~A){return ~A.value;}~%"
                       error-var
                       error-var
                       (p2-symbol-to-js-value (binding-name name))
                       error-var)
               (format *p2-emit-stream*
                       "else{throw ~A;}~%" error-var)))
             result)))))

(define-p2-emit return-from (hir)
  (let ((name (hir-arg1 hir))
        (form (hir-arg2 hir)))
    (cond ((eql 0 (binding-escape-count name))
           (let ((result (p2-form form)))
             (format *p2-emit-stream* "~A=~A;~%" *p2-block-result* result))
           (format *p2-emit-stream* "break ~A;~%" (binding-id name)))
          (t
           (let ((result (p2-form form)))
             (format *p2-emit-stream*
                     "throw new lisp.BlockValue(~A,~A);"
                     (p2-symbol-to-js-value (binding-name name))
                     result))))))

(define-p2-emit tagbody (hir)
  )

(define-p2-emit go (hir)
  )

(define-p2-emit catch (hir)
  )

(define-p2-emit catch (hir)
  )

(define-p2-emit *:%defun (hir)
  )

(define-p2-emit *:%defpackage (hir)
  )

(define-p2-emit *:%in-package (hir)
  )

(define-p2-emit ffi:ref (hir)
  )

(define-p2-emit ffi:set (hir)
  )

(define-p2-emit ffi:var (hir)
  )

(define-p2-emit ffi:typeof (hir)
  )

(define-p2-emit ffi:aget (hir)
  )

(define-p2-emit js-call (hir)
  )

(define-p2-emit module (hir)
  )

(defun p2-toplevel (hir)
  (let ((*p2-literal-symbols* (make-hash-table)))
    (p2 hir (if (hir-return-value-p hir) :expr :stmt))))

(defun p2-test (hir)
  (let (result)
    (let ((text
            (with-output-to-string (*p2-emit-stream*)
              (setq result (p2-toplevel hir)))))
      (handler-case (js-beautify text)
        (error () (write-line text)))
      result)))