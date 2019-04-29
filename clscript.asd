(defsystem "clscript"
  :serial t
  :components ((:module "compiler"
                :components
                ((:file "packages")
                 (:file "util")
                 (:file "host")
                 (:file "error")
                 (:file "ir")
                 (:file "pass1")
                 (:file "pass2")
                 (:file "compiler")))))
