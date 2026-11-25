;;; 60-aster.el --- Make AsTeR available (Blinux)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Loaded by Blinux's site-start.el.  Puts AsTeR's UI on the load-path, as
;; Raman's instructions say; start it with M-x load-library RET aster, then
;; M-x aster.  Commands live on the C-; SPC and C-' a prefixes.

;;; Code:

(let ((ui "/opt/emacspeak/aster-math/ui"))
  (when (file-directory-p ui)
    (add-to-list 'load-path ui)))

;;; 60-aster.el ends here
