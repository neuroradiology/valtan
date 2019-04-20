(in-package :compiler)

(defvar *literal-symbols*)

(defparameter *character-map*
  '((#\! . "BANG")       
    (#\" . "QUOTATION")  
    (#\# . "HASH")       
    (#\$ . "DOLLAR")     
    (#\% . "PERCENT")    
    (#\& . "AMPERSAND")  
    (#\' . "QUOTE")      
    (#\( . "LPAREN")     
    (#\) . "RPAREN")     
    (#\* . "STAR")       
    (#\+ . "PLUS")       
    (#\, . "COMMA")      
    (#\- . "_")          
    (#\. . "DOT")        
    (#\/ . "SLASH")      
    (#\: . "COLON")      
    (#\; . "SEMICOLON")  
    (#\< . "LESS")       
    (#\= . "EQUAL")      
    (#\> . "GREATER")    
    (#\? . "QUESTION")   
    (#\space . "SPACE")  
    (#\@ . "AT")         
    (#\[ . "LBRACKET")   
    (#\\ . "BACKSLASH")  
    (#\] . "RBRACKET")   
    (#\^ . "CARET")      
    (#\_ . "__")         
    (#\` . "BACKQUOTE")  
    (#\{ . "LBRACE")     
    (#\| . "PIPE")       
    (#\} . "RBRACE")     
    (#\~ . "TILDE")
    (#\newline . "NEWLINE")
    (#\return . "RETURN")
    (#\backspace . "BACK")
    (#\page . "PAGE")
    (#\tab . "TAB")))

(defparameter *emitter-table* (make-hash-table))

(defun symbol-to-js-identier (symbol)
  (flet ((f (c)
           (or (cdr (assoc c *character-map*))
               (string c))))
    (with-output-to-string (out)
      (write-string "S_" out)
      (map nil (lambda (c)
                 (write-string (f c) out))
           (string symbol)))))

(defun binding-to-js-identier (binding)
  (symbol-to-js-identier (binding-value binding)))

(defun register-symbol-literal (symbol)
  (or (gethash symbol *literal-symbols*)
      (setf (gethash symbol *literal-symbols*)
            (symbol-to-js-identier symbol))))

(defun const-to-js-literal (value)
  (typecase value
    (null "lisp.nilValue")
    (symbol (register-symbol-literal value))
    (otherwise (princ-to-string value))))

(defun js-call (name &rest args)
  (format nil "~A(~{~A~^,~})" name args))

(defun pass2-form (form return-value-p)
  (when return-value-p
    (princ "return "))
  (pass2 form return-value-p)
  (format t ";~%"))

(defun pass2-forms (forms return-value-p)
  (do ((ir* forms (rest ir*)))
      ((null (rest ir*))
       (pass2-form (first ir*) return-value-p))
    (pass2 (first ir*) nil)
    (format t ";~%")))

(defmacro def-emit (op (ir return-value-p) &body body)
  (let ((name (gensym)))
    `(progn
       (defun ,name (,ir ,return-value-p)
         (declare (ignorable ir return-value-p))
         ,@body)
       ,@(mapcar (lambda (op)
                   `(setf (gethash ',op *emitter-table*) ',name))
                 (if (consp op) op (list op))))))

(def-emit const (ir return-value-p)
  (princ (const-to-js-literal (ir-arg1 ir))))

(def-emit lref (ir return-value-p)
  (princ (binding-to-js-identier (ir-arg1 ir))))

(def-emit gref (ir return-value-p)
  (let ((ident (register-symbol-literal (ir-arg1 ir))))
    (format t "lisp.symbol_value(~A)" ident)))

(def-emit (lset gset) (ir return-value-p)
  (when return-value-p
    (write-string "("))
  (cond ((eq 'lset (ir-op ir))
         (format t "~A = " (binding-to-js-identier (ir-arg1 ir)))
         (pass2 (ir-arg2 ir) t))
        (t
         (let ((ident (register-symbol-literal (ir-arg1 ir))))
           (format t "lisp.set_symbol_value(~A, " ident))
         (pass2 (ir-arg2 ir) t)
         (write-string ")")))
  (when return-value-p
    (write-string ")")))

(def-emit if (ir return-value-p)
  (when return-value-p
    (format t "(function() {~%"))
  (write-string "if (")
  (pass2 (ir-arg1 ir) t)
  (format t " !== lisp.nilValue) {~%")
  (pass2-form (ir-arg2 ir) return-value-p)
  (format t "} else {~%")
  (pass2-form (ir-arg3 ir) return-value-p)
  (format t "}")
  (if return-value-p
      (write-string "})()")
      (terpri)))

(def-emit progn (ir return-value-p)
  (when return-value-p
    (format t "(function() {~%"))
  (pass2-forms (ir-arg1 ir) return-value-p)
  (when return-value-p
    (format t "})()")))

(defun emit-check-arguments (parsed-lambda-list)
  (let ((min (parsed-lambda-list-min parsed-lambda-list))
        (max (parsed-lambda-list-max parsed-lambda-list)))
    (cond ((null max)
           (format t "if (arguments.length < ~D) {~%" min))
          ((= min max)
           (format t "if (arguments.length !== ~D) {~%" min))
          (t
           (format t "if (arguments.length < ~D || ~D < arguments.length) {~%" min max)))
    (write-line "throw new Error('invalid number of arguments');")
    (write-line "}")))

(defun emit-lambda-list (parsed-lambda-list)
  (let ((i 0))
    (dolist (var (parsed-lambda-list-vars parsed-lambda-list))
      (format t "let ~A = arguments[~D];~%" (binding-to-js-identier var) i)
      (incf i))
    (dolist (opt (parsed-lambda-list-optionals parsed-lambda-list))
      (let ((var (first opt))
            (value (second opt)))
        (format t "let ~A = arguments[~D] || "
                (binding-to-js-identier var)
                i)
        (write-string "(")
        (pass2 value t)
        (write-line ");")
        (when (third opt)
          (format t "let ~A = (arguments.length > ~D ? lisp.tValue : lisp.nilValue);~%"
                  (binding-to-js-identier (third opt)) i))
        (incf i)))
    (let ((rest-var (parsed-lambda-list-rest-var parsed-lambda-list)))
      (when rest-var
        (format t "let ~A = lisp.jsArrayToList(arguments.slice(~D));~%"
                (binding-to-js-identier rest-var) i)
        (binding-to-js-identier rest-var)))))

(def-emit lambda (ir return-value-p)
  (let ((parsed-lambda-list (ir-arg1 ir)))
    (write-line "(function() {")
    (emit-check-arguments parsed-lambda-list)
    (emit-lambda-list parsed-lambda-list)
    (pass2-forms (ir-arg2 ir) t)
    (format t "})")))

(def-emit let (ir return-value-p)
  (if return-value-p
      (format t "(function() {~%")
      (format t "{~%"))
  (dolist (binding (ir-arg1 ir))
    (format t "let ~A = " (symbol-to-js-identier (first binding)))
    (pass2 (second binding) t)
    (format t ";~%"))
  (pass2-forms (ir-arg2 ir) return-value-p)
  (if return-value-p
      (format t "})()")
      (format t "}~%")))

(def-emit call (ir return-value-p)
  (let ((ident (register-symbol-literal (ir-arg1 ir))))
    (format t "lisp.call_function(~A" ident))
  (dolist (arg (ir-arg2 ir))
    (write-string ", ")
    (pass2 arg t))
  (write-string ")"))

(defun pass2 (ir return-value-p)
  (funcall (gethash (ir-op ir) *emitter-table*)
           ir
           return-value-p))

(defun emit-initialize-symbols ()
  (maphash (lambda (symbol ident)
             (format t "let ~A = lisp.intern('~A', '~A');~%"
                     ident
                     symbol
                     (package-name (symbol-package symbol))))
           *literal-symbols*))

(defun pass2-toplevel (ir)
  (let ((*literal-symbols* (make-hash-table)))
    (let ((output (with-output-to-string (*standard-output*)
                    (pass2 ir nil))))
      (emit-initialize-symbols)
      (write-string output)))
  (values))

(defun pass2-toplevel-forms (ir-forms)
  (let ((*literal-symbols* (make-hash-table)))
    (let ((output (with-output-to-string (*standard-output*)
                    (dolist (ir ir-forms)
                      (pass2 ir nil)))))
      (emit-initialize-symbols)
      (write-string output))))