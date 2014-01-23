(in-package "CCL")

;;; Large parts of Cocoa are not thread safe.  Many calls must be made
;;; only on the "main" (i.e., the initial) thread.
;;;
;;; For historical reasons CCL calls thread "processes".  So, instead
;;; of speaking of the "main thread" or the "event thread", we will
;;; use the term "event process".


(defstatic *interrupt-id-map* (make-id-map))

(objc:defmethod (#/lispInterrupt: :void) ((self ns:ns-application) id)
  (funcall (id-map-free-object *interrupt-id-map* (#/intValue id)))
  (#/release id))

(defun %interrupt-event-process (f wait)
  (#/performSelectorOnMainThread:withObject:waitUntilDone:
   *nsapp*
   (objc:@selector #/lispInterrupt:)
   ;; The NSNumber instance is released in #/lispInterrupt: above
   (#/initWithInt: (#/alloc ns:ns-number)
		   (assign-id-map-id *interrupt-id-map* f))
   wait))
  
(defun queue-for-event-process (f)
  "Queue the zero-argument function F for asynchronous execution in
the event process."
  (if (eq *current-process* *initial-process*)
    (funcall f)
    (%interrupt-event-process f nil)))

(defun call-in-event-process (f)
  "Invoke the zero-argument function F in the event process, wait for
it to finish, and return whatever values F returns."
  (if (eq *current-process* *initial-process*)
    (funcall f)
    (let ((return-values nil))
      (flet ((wrapper ()
               (setq return-values (multiple-value-list (funcall f)))))
        (declare (dynamic-extent #'wrapper))
	(%interrupt-event-process #'wrapper t)
        (apply #'values return-values)))))


(defclass cocoa-event-process (process)
  ())

(defmethod process-interrupt ((process cocoa-event-process) function
			      &rest args)
  (if (eq process *current-process*)
    (apply function args)
    (if (and *nsapp* (#/isRunning *nsapp*))
      (queue-for-event-process #'(lambda () (apply function args)))
      (call-next-method))))

(defmethod process-exit-application :before ((process cocoa-event-process)
                                             (thunk t))
  (when (eq process *initial-process*)
    (#/terminate: *nsapp* +null-ptr+)))