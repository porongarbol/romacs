;;; romacs.el --- Interact with Roblox exploits -*- lexical-binding: t; -*-

;; Version: 1.0
;; Package-Requires: ((websocket "1.14"))

;;; Comentary:

;; Romacs is an Emacs package to communicate with Roblox exploits
;; It originally used the filesystem to communicate but
;; For extensbility purposes, it now uses a websocket
;;
;; It's made to work with Fennel by default.
;; <f1> - Run Fennel script in Roblox
;; <f2> - See compiled Fennel script
;;
;; Protocol:
;; - There is a websocket server created by Emacs which Roblox connects to
;; - When Emacs send a message to Roblox, it's a Lua script that must be compiled with loadstring()
;; - When Emacs receives a message from Roblox, it's a list that looks like '(MESSAGE-TYPE DATA) This is so you can extend Romacs functionality via romacs-received-message-hook. Each hook gives a meaning to MESSAGE-TYPE and DATA
;;
;; Example extension that when Roblox sends "(emacs-insert \"Hello, world\")" it inserts "Hello, world" in current buffer
;; (add-hook 'romacs-received-message-hook
;;	(lambda (msg)
;;		(when (eq (car msg) 'emacs-insert)
;;			(insert (cadr msg)))
;;	)
;; )

;;; Code:
(require 'websocket)

(defgroup romacs nil
	"Interaction with Roblox exploits"
	:group 'external)

(defcustom romacs-save-files-automatically t
	"If t, it will save the files before compiling or running them"
	:type 'boolean
	:group 'romacs)

(defvar *romacs-websocket-server* nil
	"Romacs' WebSocket server to communicate with Roblox")

;; List because working with anything that is not a list is annoying as [REDACTED] in Emacs
(defvar *romacs-websocket-connections* '()
	"List of current connections to the websocket server.")

(defvar romacs-received-message-hook '()
	"Hook for when the server receives a message.
Each hook receives the parsed message as first argument")

(defun romacs-run-script (script)
	(interactive "sScript: ")
	(dolist (websocket *romacs-websocket-connections*)
		(websocket-send-text websocket script))
	(message "Script ran succesfully"))

(defun fennel-compile-current-buffer (flags)
	(when romacs-save-files-automatically
		(save-buffer))

	(if (buffer-file-name)
		(shell-command-to-string (concat flags " " (buffer-file-name)))
		nil)
)

(defun romacs-when-receive-message(frame)
	(let ((text (websocket-frame-text frame)))
		(run-hook-with-args 'romacs-received-message-hook (car (read-from-string text))))
)

(defun initialize-romacs-mode ()
	(message "Creating websocket")
	(setq-default *romacs-websocket-connections* '())
	(setq-default *romacs-websocket-server*
		(websocket-server 1003
			:host 'local
			:on-open (lambda (websocket)
				(message "A Roblox connection started")
				(push websocket *romacs-websocket-connections*)
			)
			:on-message (lambda (_websocket frame)
				(romacs-when-receive-message frame)
			)
			:on-close (lambda (websocket)
				(let ((connections *romacs-websocket-connections*))
					(setq *romacs-websocket-connections* (remove (1+ (seq-position connections websocket)) connections))) ;; I will have to refactor this garbage
				(message "A Roblox connection stopped")
			)
		)
	)
	(message "Created websocket")
)

(defun stop-romacs-mode ()
	(message "Closing websocket")
	(when *romacs-websocket-server*
		(websocket-server-close *romacs-websocket-server*))
	(setq-default *romacs-websocket-server* nil)
	(message "Closed websocket")
)

;; <f1 functionality>
;;
(defcustom romacs-fennel-flags "fennel --require-as-include --no-compiler-sandbox --correlate --compile"
	"Flags to compile a Fennel script."
	:type 'string
	:group 'romacs)

(defun romacs-run-fennel-script ()
	(interactive)

	(let ((script (fennel-compile-current-buffer romacs-fennel-flags)))
		(if script
			(romacs-run-script script)
			(message "Please save it as file")))
)

;; <f2 functionality>
(defcustom romacs-view-fennel-flags "fennel --no-compiler-sandbox --compile"
	"Also check *romacs-fennel-flags*. This is the same but for <f2>"
	:type 'string
	:group 'romacs)

(defvar romacs-output-buffer nil
	"Local variable which contains the current buffer to which <f2> will output to.")

(defun romacs-view-compiled-fennel-script ()
	(interactive)

	;; check for the buffer which we'll show the compiled script
	(setq romacs-output-buffer
		(if (buffer-live-p romacs-output-buffer)
			romacs-output-buffer
			(get-buffer-create (concat "*compiled " (buffer-name) "*"))))

	(let (
		(original-window (selected-window))
		(compiled-script (fennel-compile-current-buffer romacs-view-fennel-flags))
		(buffer-modified (buffer-modified-p))
	)
		(switch-to-buffer-other-window romacs-output-buffer)
		(erase-buffer)
		(when buffer-modified
			(insert "-- warning: file unsaved")
			(newline))
		(if compiled-script
			(insert compiled-script)
			(insert "Please save the file"))
		(lua-mode)
		(select-window original-window)
	)
)

;; <f3 functionality>
;; It shows the internal Roblox console
;; The protocol works like so: Emacs receives a '(console (:message "Hello, World" :type MessageOutput)) like message when there is a new message in the console
;; The Lua part that sends the messages to Emacs is already implemented so don't worry. This works out of the box
(defun format-console-message (message message-type)
	(cond
		((eq message-type 'MessageOutput) message)
		((eq message-type 'MessageError) (propertize message 'face 'error))
		((eq message-type 'MessageWarning) (propertize message 'face 'warning))
		((eq message-type 'MessageInfo) (propertize message 'face 'success))
	)
)

(defun romacs-console-protocol (msg)
	(when (eq (car msg) 'console)
		(let* (
			(msg-value (cadr msg))
			(*message (plist-get msg-value :message))
			(*message-type (plist-get msg-value :type))
		)
			(save-current-buffer
			(set-buffer (get-buffer-create "*ROBLOX CONSOLE*"))
			(save-excursion
			(goto-char (point-max))
			(insert (format-console-message *message *message-type))
			(newline)
			))
		)
	)
)

(add-hook 'romacs-received-message-hook 'romacs-console-protocol)

(defun romacs-show-roblox-console ()
	(interactive)
	(let ((console-buffer (get-buffer-create "*ROBLOX CONSOLE*")))
		(if (eq (current-buffer) console-buffer)
			(delete-window)
			(switch-to-buffer-other-window console-buffer))
	)
)

(define-minor-mode romacs-mode
	"Emacs integration with exploits via WebSockets"
	:lighter " RBLX"
	:keymap '(
		([f1] . romacs-run-fennel-script)
		([f2] . romacs-view-compiled-fennel-script)
		([f3] . romacs-show-roblox-console))
	:global t
	(if romacs-mode
		(initialize-romacs-mode)
		(stop-romacs-mode))
)

(provide 'romacs)

;;; romacs.el ends here
