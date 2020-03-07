(cl:in-package :valtan-core)

(cl:defun system:make-raw-string ()
  (ffi:new (ffi:ref "String")))

(cl:defun system:expand-raw-string (raw-string n)
  ((ffi:ref raw-string "padEnd") n))

(cl:defun system:code-to-raw-string (code)
  ((ffi:ref "String" "fromCharCode") code))

(cl:defun system:sub-raw-string/2 (raw-string start)
  ((ffi:ref raw-string "substring") start))

(cl:defun system:sub-raw-string/3 (raw-string start end)
  ((ffi:ref raw-string "substring") start end))

(cl:defun system:concat-raw-string/2 (raw-string-1 raw-string-2)
  ((ffi:ref raw-string-1 "concat") raw-string-2))

(cl:defun system:concat-raw-string/3 (raw-string-1 raw-string-2 raw-string-3)
  ((ffi:ref raw-string-1 "concat") raw-string-2 raw-string-3))

(cl:defun system:raw-string-upcase (raw-string)
  ((ffi:ref raw-string "toUpperCase") raw-string))

(cl:defun system:raw-string-downcase (raw-string)
  ((ffi:ref raw-string "toLowerCase") raw-string))

(cl:defun system:make-raw-array (size)
  (ffi:new (ffi:ref "Array") size))

(cl:defun system:fill-raw-array (raw-array element)
  ((ffi:ref raw-array "fill") element))

(cl:defun system:make-map ()
  (ffi:new (ffi:ref "Map")))

(cl:defun system:map-get (map key)
  (let ((value ((ffi:ref map "get") key)))
    (values value
            (if (eq value (ffi:ref "undefined"))
                nil
                t))))

(cl:defun system:map-set (map key value)
  ((ffi:ref map "set") key value))

(cl:defun system:map-length (map)
  (ffi:ref map "size"))

(cl:defun system:map-clear (map)
  ((ffi:ref map "clear")))
