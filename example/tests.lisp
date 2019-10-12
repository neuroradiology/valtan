(ffi:require js:fs "fs")

(defun test (filename)
  (with-open-file (in filename)
    (let ((eof-value '#:eof))
      (do ((form (read in nil eof-value) (read in nil eof-value)))
          ((eq form eof-value))
        (prin1 form)
        (terpri)
        (assert (eval form))))))

(test "example/sacla-tests/must-cons.lisp")
(test "example/sacla-tests/must-character.lisp")
(test "example/sacla-tests/must-string.lisp")
