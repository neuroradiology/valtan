(in-package :compiler)

(defstruct (ir (:constructor %make-ir))
  op
  return-value-p
  multiple-values-p
  args)

(defun ir-arg1 (ir) (first (ir-args ir)))
(defun ir-arg2 (ir) (second (ir-args ir)))
(defun ir-arg3 (ir) (third (ir-args ir)))

(defgeneric reduce-ir (ir))

(defmethod reduce-ir (ir)
  (ecase (ir-op ir)
    ((const)
     `#(const ,(ir-arg1 ir)))
    ((lref)
     `(,(ir-op ir) ,(binding-name (ir-arg1 ir))))
    ((gref)
     `(,(ir-op ir) ,(ir-arg1 ir)))
    ((lset)
     `(,(ir-op ir)
       ,(binding-name (ir-arg1 ir))
       ,(reduce-ir (ir-arg2 ir))))
    ((gset)
     `(,(ir-op ir)
       ,(ir-arg1 ir)
       ,(reduce-ir (ir-arg2 ir))))
    ((if)
     `(if ,(reduce-ir (ir-arg1 ir)) ,(reduce-ir (ir-arg2 ir)) ,(reduce-ir (ir-arg3 ir))))
    ((progn)
     `(progn ,@(mapcar #'reduce-ir (ir-arg1 ir))))
    ((lambda)
     `(named-lambda ,(ir-arg1 ir) ,(ir-arg2 ir) ,@(mapcar #'reduce-ir (ir-arg3 ir))))
    ((let)
     `(let ,(mapcar (lambda (b)
                      (destructuring-bind (k v) b
                        `(,(binding-name k)
                          ,(reduce-ir v)
                          ,@(if (eq :special (binding-type k))
                                '(:special)))))
                    (ir-arg1 ir))
        ,@(mapcar #'reduce-ir (ir-arg2 ir))))
    ((lcall call)
     `(,(ir-op ir) ,(ir-arg1 ir) ,@(mapcar #'reduce-ir (ir-arg2 ir))))
    ((unwind-protect)
     `(unwind-protect ,(reduce-ir (ir-arg1 ir)) ,(reduce-ir (ir-arg2 ir))))
    ((block)
     `(block ,(binding-name (ir-arg1 ir))
        ,@(mapcar #'reduce-ir (ir-arg2 ir))))
    ((return-from)
     `(return-from ,(binding-name (ir-arg1 ir))
        ,(reduce-ir (ir-arg2 ir))))
    ((tagbody)
     `(tagbody ,(ir-arg1 ir)
        ,@(mapcar (lambda (x)
                    (destructuring-bind (tagbody-value . body) x
                      `(,(tagbody-value-index tagbody-value)
                        ,(reduce-ir body))))
            (ir-arg2 ir))))
    ((go)
     `(go ,(tagbody-value-index (ir-arg2 ir))))
    ((catch)
     `(catch ,(reduce-ir (ir-arg1 ir))
        ,(reduce-ir (ir-arg2 ir))))
    ((throw)
     `(throw ,(reduce-ir (ir-arg1 ir)) ,(reduce-ir (ir-arg2 ir))))
    ((system::%defun)
     `(system::%defun ,(ir-arg1 ir)
                      ,(reduce-ir (ir-arg2 ir))))
    ((system::%defpackage) ir)
    ((system::%in-package) ir)
    ((ffi:ref) ir)
    ((ffi:set) ir)
    ((ffi:var) ir)
    ((ffi:typeof) ir)
    ((ffi:new) ir)
    ((ffi:aget) ir)
    ((js-call) ir)))

(defun make-ir (op return-value-p multiple-values-p &rest args)
  (%make-ir :op op
            :return-value-p return-value-p
            :multiple-values-p multiple-values-p
            :args args))

(defstruct parsed-lambda-list
  vars
  rest-var
  optionals
  keys
  min
  max
  allow-other-keys)

(defun collect-variables (parsed-lambda-list)
  (append (parsed-lambda-list-vars parsed-lambda-list)
          (if (parsed-lambda-list-rest-var parsed-lambda-list)
              (list (parsed-lambda-list-rest-var parsed-lambda-list)))
          (mapcar #'first (parsed-lambda-list-optionals parsed-lambda-list))
          (remove nil (mapcar #'third (parsed-lambda-list-optionals parsed-lambda-list)))
          (mapcar #'first (parsed-lambda-list-keys parsed-lambda-list))
          (remove nil (mapcar #'third (parsed-lambda-list-keys parsed-lambda-list)))))

(defstruct binding
  name
  type
  value
  (used-count 0))

(defstruct tagbody-value
  index
  id)
