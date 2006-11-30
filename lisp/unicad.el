(provide 'eucad)
(eval-when-compile
  (require 'cl))


(defvar chardet-max-size 10000
  "The max size to scan.")

;;(setq chardet-max-size 5000)

(defvar chardet-max-count 100
  "If the counter of certain coding system arrive this number, then
use this coding system.")

(defvar chardet-min-char/count 2
  "The minimum top chars in this number of characters")

(defvar SHORTCUT_THRESHOLD 0.95)
(defvar MINIMUM_DATA_THRESHOLD 4)
(defvar ENOUGH_DATA_THRESHOLD 1024)
(defvar MINIMUM_FILE_SIZE 7)

(defvar EUCTW_TABLE_SIZE   nil)
(defvar EUCKR_TABLE_SIZE   nil)
(defvar GB2312_TABLE_SIZE  nil)
(defvar GB18030_TABLE_SIZE nil)
(defvar BIG5_TABLE_SIZE    nil)
(defvar JIS_TABLE_SIZE     nil)
(defvar EUCJP_TABLE_SIZE   nil)
;; ;; EUCJP = JIS

(defvar EUCTW_DIST_RATIO   nil)
(defvar EUCKR_DIST_RATIO   nil)
(defvar GB2312_DIST_RATIO  nil)
(defvar GB18030_DIST_RATIO nil)
(defvar BIG5_DIST_RATIO    nil)
(defvar JIS_DIST_RATIO     nil)
(defvar EUCJP_DIST_RATIO   nil)

(defvar EUCTWCharToFreqOrder   nil)
(defvar EUCKRCharToFreqOrder   nil)
(defvar GB2312CharToFreqOrder  nil)
(defvar GB18030CharToFreqOrder nil)
(defvar BIG5CharToFreqOrder    nil)
(defvar JISCharToFreqOrder     nil)
(defvar EUCJPCharToFreqOrder   nil)

(defsubst chardet-reset-vars ()
  (dolist (coding fenc-coding-list)
    (fenc-set-counter coding 0))
  (setq fenc-coding-system nil
        fenc-error-counter 0
        fenc-char-counter 0))


;; universal-charset-detect

(defvar debug-code nil)
(defvar debug-now nil)
(setq debug-now nil)

(defvar debug-uni nil)
(setq debug-uni nil)

(defvar quick-size nil)
(setq quick-size 100)


(defun universal-charset-detect (size)
  "detect charset"
  (make-variable-buffer-local 'buffer-file-coding-system)
  (setq debug-code buffer-file-coding-system)
  (when (not (or (eq buffer-file-coding-system 'utf-8-unix)
                 (eq buffer-file-coding-system 'utf-8-dos)))
    (save-excursion
      (let ((end (+ (point) (min size chardet-max-size)))
            (input-state 'ePureAscii)
            code1 code2 code0
            state
            prober-result
            start
            quick-start quick-end)
        ;;(chardet-reset)
        ;;         (if (chardet-BOM-p)
        ;;             ;; if the data starts with BOM, we know it is UTF
        ;;             (return-utf))
        (goto-char (point-min))
        (setq debug-code 'mStart)
        (while (and (not (eq state 'mDone))
                    (eq input-state 'ePureAscii)
                    (< (point) end))
          (setq code1 (char-after))
          (forward-char 1)
          (setq debug-code 'mDoing) ;; for debug purpose
          (if debug-uni
              (message "#x%X: %s: point: %d" code1 (string code1) (point)))
          (if (and (>= code1 #x80)
                   (/= code1 #xA0)) ;; since many Ascii only page contains NBSP
              ;; we got a non-ascii byte (high-byte)
              (unless (eq input-state 'eHighbyte)
                (setq input-state 'eHighbyte)
                (setq start (max (point-min) (1- (point))))
;;                 (message "Non-ascii point: %d, current: %d" start (point))
                ;;                 (kill-esc-charset-prob)
                ;;                 (multibyte-utf-8-prober end)
                ;;                 (start-multi-byte-group-prober)
                ;;                 (start-single-byte-group-prober)
                ;;                 (start-latin1-prober)
                )
            (progn
              ;; OK, just pure ascii so far
              (if (and (eq input-state 'ePureAscii)
                       (or (= code1 #x1B) ;; ESC char
                           (and (= code1 ?{ ) (= code0 ?~ )))) ;; HZ "~{"
                  ;; found escape character or HZ "~{"
                  (setq input-state 'eEscAscii))
              (setq code0 code1))
            ))
        (setq debug-code input-state)
        (cond
         ((eq input-state 'eEscAscii)
          ;;           (start-esc-charset-prober)
          )
         ((eq input-state 'eHighbyte)
          ;;          (do-charset-prober)
          (if (> (- end start) quick-size)
              (setq quick-start start
                    quick-end (+ quick-size start))
            (setq quick-start start
                  quick-end end))
          (let ((maxConfidence 0.0))
            (cond
             ((eq (multibyte-group-prober quick-start quick-end) 'eFoundIt)
              (setq prober-result (car multibyte-bestguess))
              (setq maxConfidence 0.99))
             ((and (/= quick-end end)
                   (eq (multibyte-group-prober start end) 'eFoundIt))
              (setq prober-result (car multibyte-bestguess))
              (setq maxConfidence 0.99))
             (t
              (setq maxConfidence (latin1-prober start end))
              (setq debug-code maxConfidence)
              (if (> maxConfidence (car (cdr multibyte-bestguess)))
                  (setq prober-result 'latin-1)
                (setq prober-result (car multibyte-bestguess)
                      maxConfidence (car (cdr multibyte-bestguess))))))
            (setq debug-code (list prober-result maxConfidence)))
;;             (if (> (utf-8-prober end) (latin1-prober start end))
;;                 (setq prober-result 'utf-8)
;;               (setq prober-result 'latin-1))
;;             (setq debug-code start))          
;;           (setq prober-result (multibyte-utf-8-prober end))
;;           (setq debug-code prober-result)
          )
         ((eq input-state 'ePureAscii)
          (setq prober-result 'utf-8)
          (setq debug-code 'pure-ascii))
         (t
          nil))
        prober-result
        ))))

(add-to-list 'auto-coding-functions 'universal-charset-detect)



;; multi-byte-group-prober
;; includes:
;;  - utf-8
;;  - sjis
;;  - eucjp
;;  - gb18030
;;  - euckr
;;  - big5
;;  - euctw

(defvar multibyte-group-list nil)
(setq multibyte-group-list
      (list multibyte-utf8-list))
;;(setq multibyte-group-list (list multibyte-gb18030-list multibyte-big5-list multibyte-utf8-list))

;; (setq multibyte-group-list (list multibyte-utf8-list))
;; (length multibyte-group-list)
(setq multibyte-group-list (append multibyte-group-list (list multibyte-gb18030-list)))
(setq multibyte-group-list (append multibyte-group-list (list multibyte-big5-list)))
(setq multibyte-group-list (append multibyte-group-list (list multibyte-sjis-list)))
(setq multibyte-group-list (append multibyte-group-list (list multibyte-eucjp-list)))
(setq multibyte-group-list (append multibyte-group-list (list multibyte-euckr-list)))
(setq multibyte-group-list (append multibyte-group-list (list multibyte-euctw-list)))
;; (pop multibyte-group-list)
;; (setq multibyte-gb-list
;;       '(gb 0.0 test-func))
;; (add-to-list 'multibyte-group-list multibyte-gb-list)
;; (setq multibyte-utf8-list
;;       '(utf-8 0.0 mult))
;; (push 'utf-8 multibyte-utf8-list)
;; (setq test multibyte-group-list)
;; (setq test2 (pop test))
;; (multibyte-chardec-get-prober test2)
;; (symbolp test2)

;; (car (car multibyte-group-list))

(defvar multibyte-bestguess nil)

(setq multibyte-bestguess '(nil 0.0))

(defun multibyte-group-prober (start end)
  (let ((lists multibyte-group-list)
        (mState 'eDetecting)
        st
        current-chardec
        mBestGuess
        (bestConf 0.0)
        cf)
    (setq debug-code 'mb-group-start)
    (setq multibyte-bestguess '(nil 0.0))
    (while (and lists (eq mState 'eDetecting))
      ;;(setq lists multibyte-group-list)
      (setq current-chardec (pop lists))
      ;;(setq debug-code current-chardec)
      ;;(setq st (funcall (multibyte-chardec-get-prober current-chardec) start end))
      (setq st (condition-case e
                   (save-excursion
                     (funcall (multibyte-chardec-get-prober current-chardec) start end))))
      (setq debug-code (list current-chardec mState lists))
      (cond
       ((eq st 'eFoundIt)
        (setq mBestGuess (multibyte-chardec-get-name current-chardec))
        (setq bestConf 0.99)
        (setq mState 'eFoundIt))
       ((eq st 'eNotMe)
        nil)
       (t
        (setq cf (multibyte-chardec-get-confidence current-chardec))
        (if (> cf bestConf)
            (progn
              (setq mBestGuess (multibyte-chardec-get-name current-chardec))
              (setq bestConf cf))))))
    (if (or (= bestConf 0.0) (null mBestGuess))
        (setq mState 'eNotMe)
      (setq multibyte-bestguess (list mBestGuess bestConf)))
    mState))

;; distribution table

(defmacro dist-table-reset (dist-table)
  `(progn
     (setcdr (assoc 'mTotalChars ,dist-table) 0)
     (setcdr (assoc 'mFreqChars ,dist-table) 0)))

;; (dist-table-reset GB18030-dist-table)

(defmacro dist-table-total-chars (dist-table)
  `(cdr (assoc 'mTotalChars ,dist-table)))

(defmacro mTotalChars (dist-table)
  `(cdr (assoc 'mTotalChars ,dist-table)))

(defmacro dist-table-freq-chars (dist-table)
  `(cdr (assoc 'mFreqChars ,dist-table)))

(defmacro mFreqChars (dist-table)
  `(cdr (assoc 'mFreqChars ,dist-table)))

(defmacro dist-table-total-chars++ (dist-table)
  `(setcdr (assoc 'mTotalChars ,dist-table) (1+ (dist-table-total-chars ,dist-table))))

(defmacro mTotalChars++ (dist-table)
  `(setcdr (assoc 'mTotalChars ,dist-table) (1+ (dist-table-total-chars ,dist-table))))

;;(mTotalChars++ GB18030-dist-table)

(defmacro dist-table-freq-chars++ (dist-table)
  `(setcdr (assoc 'mFreqChars ,dist-table) (1+ (dist-table-freq-chars ,dist-table))))

(defmacro mFreqChars++ (dist-table)
  `(setcdr (assoc 'mFreqChars ,dist-table) (1+ (dist-table-freq-chars ,dist-table))))

;; (dist-table-freq-chars++ GB18030-dist-table)


;; utf-8-prober


(defvar multibyte-utf8-list nil)
(setq multibyte-utf8-list  
      '(utf-8 0.0 multibyte-utf8-prober))


(defmacro multibyte-chardec-get-name (chardec-list)
  (if (symbolp chardec-list)
      (list 'car chardec-list)
    (car chardec-list)))

(defmacro multibyte-chardec-get-confidence (chardec-list)
  (if (symbolp chardec-list)
      (list 'car (list 'cdr chardec-list))
    (car (cdr chardec-list))))

(defmacro multibyte-chardec-get-prober (chardec-list)
  (if (symbolp chardec-list)
      (list 'car (list 'cdr (list 'cdr chardec-list)))
    (car (cdr (cdr chardec-list)))))

;;(multibyte-chardec-get-name multibyte-utf8-list)
;;(multibyte-chardec-get-confidence multibyte-utf8-list)
;;(multibyte-chardec-get-prober multibyte-utf8-list)
;;(car (cdr (cdr multibyte-utf8-list)))

(defun multibyte-utf8-prober (start end)
  (setq debug-code 'start-multibyte-utf8)
  (let ((mState 'eDetecting)
        (mNumOfMBChar 0)
        codingState
        charlen
        (mConfidence 0.0)
        )
    (SM-reset)
    (save-excursion
      (goto-char start)
;;       (message "utf8 start: %s Point: %d" (string (char-after)) (point))
      (while (and (< (point) end)
                  (eq mState 'eDetecting))
        (setq codingState (NextState (char-after) UTF8SMModel))
        (setq charlen (SM-get-charlen))
        (forward-char 1)
        (cond
         ((= codingState eError)
          (setq mState 'eNotMe)
          (setcar (cdr multibyte-utf8-list) 0.01))
         ((= codingState eItsMe)
          (setq mState 'eFoundIt)
          (setcar (cdr multibyte-utf8-list) 0.99))
         ((= codingState eStart)
          (if (>= charlen 2)
              (setq mNumOfMBChar (1+ mNumOfMBChar))))
         (t nil))
;;         (if debug-utf8
;;             (message "UTF Code: #x%X, state: %d, charlen: %d, NumMB: %d" (char-after) codingState charlen mNumOfMBChar))
        (setq debug-code (list 'utf8-doing codingState mState mNumOfMBChar))
        )
      (setq debug-code 'utf-8-getting-confidence)
      (if (eq mState 'eDetecting)
          (if (> (setq mConfidence (multibyte-utf8-GetConfidence mNumOfMBChar)) SHORTCUT_THRESHOLD)
              (progn
                (setq mState 'eFoundIt)
                (setcar (cdr multibyte-utf8-list) 0.99))
            (setcar (cdr multibyte-utf8-list) mConfidence)))
      (setq debug-code (list 'utf8-done mState))
      mState)))

(defun multibyte-utf8-GetConfidence (mNumOfMBChar)
  (let ((unlike 0.99)
        (one-char-prob 0.5))
    (if (< mNumOfMBChar 6)
        (loop for i from 1 to mNumOfMBChar
              do (setq unlike (* unlike one-char-prob)))
      (setq unlike 0.01))
    (- 1 unlike)))

;;(multibyte-utf8-GetConfidence 2)


;; MultiByte GB18030 Prober

(defvar multibyte-gb18030-list nil)
(setq multibyte-gb18030-list
      '(gb18030 0.0 multibyte-gb18030-prober))

;;GB18030-dist-table

(defun multibyte-gb18030-prober (start end)
  (setq debug-code 'start-multibyte-gb18030)
  (let ((mState 'eDetecting)
        codingState
        charlen
        (mConfidence 0.0)
        (code0 0)
        (code1 0)
        (total (/ (- end start) 2))
        )
    (SM-reset)
;;     (message "Total: %d" total)
    (dist-table-reset GB18030-dist-table)
;;     (message "TotalChars: %d, FreqChars: %d"
;;              (mTotalChars GB18030-dist-table)
;;              (mFreqChars GB18030-dist-table))
    (save-excursion
      (goto-char start)
      (setq code1 (char-after))
      (while (and (< (point) end)
                  (eq mState 'eDetecting))
        (setq code1 (char-after))
        (setq codingState (NextState code1 GB18030SMModel))
        (forward-char 1)
        (setq debug-code (list 'gb-doing codingState mState))
        (cond
         ((= codingState eError)
          (setq mState 'eNotMe)
          (setcar (cdr multibyte-gb18030-list) 0.01))
         ((= codingState eItsMe)
          (setq mState 'eFoundIt)
          (setcar (cdr multibyte-gb18030-list) 0.99))
         ((= codingState eStart)
          (setq charlen (SM-get-charlen))
          (DistAnalyse-GB18030 code0 code1) ;; we are interested only in 2-byte
;;           (message "Code0: #x%X, Code1: #x%X" code0 code1)
          )
         (t nil))
        (setq code0 code1)
        )
      (setq debug-code 'gb18030-getting-confidence)
      (if (eq mState 'eDetecting)
          (if (and (> (setq mConfidence (DistAnalyse-GB18030-GetConfidence total)) SHORTCUT_THRESHOLD)
                   (> (mTotalChars GB18030-dist-table) ENOUGH_DATA_THRESHOLD))
              (progn
                (setq mState 'eFoundIt)
                (setcar (cdr multibyte-gb18030-list) 0.99))
            (if (= (setcar (cdr multibyte-gb18030-list) mConfidence) 0.99)
                (setq mState 'eFoundIt)
              )))
      (setq debug-code 'gb18030-done)
      mState)))

(defvar GB18030-dist-table nil)

(setq GB18030-dist-table
      '((mTotalChars . 0)
        (mFreqChars . 0)))

;;for GB2312 encoding, we are interested 
;;  first  byte range: 0xb0 -- 0xfe
;;  second byte range: 0xa1 -- 0xfe
;;no validation needed here. State machine has done that
(defun DistAnalyse-GB18030 (ch0 ch1)
  (let ((order -1))
    (if (and (>= ch0 #xb0) (>= ch1 #xa1))
        (setq order (- (+ (* 94 (- ch0 #xb0)) ch1) #xa1)))
    (when (>= order 0)
      (mTotalChars++ GB18030-dist-table)
      (if (and (< order GB18030_TABLE_SIZE) (> 512 (elt GB2312CharToFreqOrder order)))
          (mFreqChars++ GB18030-dist-table)))))

(defun DistAnalyse-GB18030-GetConfidence (total)
  (let ((Confidence 0.0))
  (cond
   ((and (> total MINIMUM_FILE_SIZE)
         (or (<= (mTotalChars GB18030-dist-table) 0) (<= (mFreqChars GB18030-dist-table) MINIMUM_DATA_THRESHOLD)))
      (setq Confidence 0.1))
   ((/= (mTotalChars GB18030-dist-table) (mFreqChars GB18030-dist-table))
    (setq Confidence (min (/ (float (mFreqChars GB18030-dist-table))
                              (* (float (- (mTotalChars GB18030-dist-table) (mFreqChars GB18030-dist-table)))
                                 GB18030_DIST_RATIO))
                          0.99)))
   (t
    (setq Confidence 0.99)))
  ))



;; MultiByte Big5 Prober

(defvar debug-big5 nil)

(defvar multibyte-big5-list nil)
(setq multibyte-big5-list
      '(big5 0.0 multibyte-big5-prober))

;;BIG5-dist-table
(defvar Big5-dist-table nil)

(setq Big5-dist-table
      '((mTotalChars . 0)
        (mFreqChars . 0)))


(defun multibyte-big5-prober (start end)
  (setq debug-code 'start-multibyte-big5)
  (let ((mState 'eDetecting)
        codingState
        charlen
        (mConfidence 0.0)
        (code0 0)
        (code1 0)
        (total (/ (- end start) 2))
        )
    (SM-reset)
    (dist-table-reset Big5-dist-table)
    (setq debug-big5 'starting-big5)
    (save-excursion
      (goto-char start)
      (setq code1 (char-after))
      (while (and (< (point) end)
                  (eq mState 'eDetecting))
        (setq code1 (char-after))
        (setq codingState (NextState code1 Big5SMModel))
        (forward-char 1)
        (setq debug-code (list 'gb-doing codingState mState))
        (cond
         ((= codingState eError)
          (setq mState 'eNotMe)
          (setcar (cdr multibyte-big5-list) 0.01))
         ((= codingState eItsMe)
          (setq mState 'eFoundIt)
          (setcar (cdr multibyte-big5-list) 0.99))
         ((= codingState eStart)
          (setq charlen (SM-get-charlen))
          (DistAnalyse-Big5 code0 code1) ;; we are interested only in 2-byte
;;           (message "Code0: #x%X, Code1: #x%X" code0 code1)
          )
         (t nil))
        (setq code0 code1)
        )
      (setq debug-code 'big5-getting-confidence)
      (if (eq mState 'eDetecting)
          (if (and (> (setq mConfidence (DistAnalyse-Big5-GetConfidence total)) SHORTCUT_THRESHOLD)
                  (> (mTotalChars Big5-dist-table) ENOUGH_DATA_THRESHOLD))
              (progn
                (setq mState 'eFoundIt)
                (setcar (cdr multibyte-big5-list) 0.99))
            (if (= (setcar (cdr multibyte-big5-list) mConfidence) 0.99)
                (setq mState 'eFoundIt))))
      (setq debug-code 'big5-done)
      mState)))

;;for big5 encoding, we are interested 
;;  first  byte range: 0xa4 -- 0xfe
;;  second byte range: 0x40 -- 0x7e , 0xa1 -- 0xfe
;;no validation needed here. State machine has done that
(defun DistAnalyse-Big5 (ch0 ch1)
  (let ((order -1))
    (if (>= ch0 #xa4)
        (if (>= ch1 #xa1)
            (setq order (- (+ (* 157 (- ch0 #xa4)) ch1 63) #xa1))
          (setq order (- (+ (* 157 (- ch0 #xa4)) ch1) #x40))))
    (when (>= order 0)
      (mTotalChars++ Big5-dist-table)
      (if (and (< order BIG5_TABLE_SIZE) (> 512 (elt Big5CharToFreqOrder order)))
          (mFreqChars++ Big5-dist-table)))))

(defun DistAnalyse-Big5-GetConfidence (total)
  (let ((Confidence 0.0))
  (cond
   ((and (> total MINIMUM_FILE_SIZE)
         (or (<= (mTotalChars Big5-dist-table) 0) (<= (mFreqChars Big5-dist-table) MINIMUM_DATA_THRESHOLD)))
      (setq Confidence 0.1))
   ((/= (mTotalChars Big5-dist-table) (mFreqChars Big5-dist-table))
    (setq Confidence (min (/ (float (mFreqChars Big5-dist-table))
                              (* (float (- (mTotalChars Big5-dist-table) (mFreqChars Big5-dist-table)))
                                 BIG5_DIST_RATIO))
                          0.99)))
   (t
    (setq Confidence 0.99)))
  ))




;; MultiByte S-JIS Prober

;; for S-JIS encoding, obeserve characteristic:
;; 1, kana character (or hankaku?) often have hight frequency of appereance
;; 2, kana character often exist in group
;; 3, certain combination of kana is never used in japanese language

(defvar debug-sjis nil)

(defvar multibyte-sjis-list nil)
(setq multibyte-sjis-list
      '(sjis 0.0 multibyte-sjis-prober))

;;SJIS-dist-table
(defvar SJIS-dist-table nil)

(setq SJIS-dist-table
      '((mTotalChars . 0)
        (mFreqChars . 0)))


(defun multibyte-sjis-prober (start end)
  (setq debug-code 'start-multibyte-sjis)
  (let ((mState 'eDetecting)
        codingState
        charlen
        (mConfidence 0.0)
        (code0 0)
        (code1 0)
        (total (/ (- end start) 2))
        )
    (SM-reset)
    (dist-table-reset SJIS-dist-table)
    (setq debug-sjis 'starting-sjis)
    (save-excursion
      (goto-char start)
      (setq code1 (char-after))
      (while (and (< (point) end)
                  (eq mState 'eDetecting))
        (setq code1 (char-after))
        (setq codingState (NextState code1 SJISSMModel))
        (forward-char 1)
        (setq debug-code (list 'gb-doing codingState mState))
        (cond
         ((= codingState eError)
          (setq mState 'eNotMe)
          (setcar (cdr multibyte-sjis-list) 0.01))
         ((= codingState eItsMe)
          (setq mState 'eFoundIt)
          (setcar (cdr multibyte-sjis-list) 0.99))
         ((= codingState eStart)
          (setq charlen (SM-get-charlen))
          (DistAnalyse-SJIS code0 code1) ;; we are interested only in 2-byte
;;           (message "Code0: #x%X, Code1: #x%X" code0 code1)
          )
         (t nil))
        (setq code0 code1)
        )
      (setq debug-code 'sjis-getting-confidence)
      (if (eq mState 'eDetecting)
          (if (and (> (setq mConfidence (DistAnalyse-SJIS-GetConfidence total)) SHORTCUT_THRESHOLD)
                   (> (mTotalChars SJIS-dist-table) ENOUGH_DATA_THRESHOLD))
              (progn
                (setq mState 'eFoundIt)
                (setcar (cdr multibyte-sjis-list) 0.99))
            (if (= (setcar (cdr multibyte-sjis-list) mConfidence) 0.99)
                (setq mState 'eFoundIt))))
      (setq debug-code 'sjis-done)
      mState)))

;;for sjis encoding, we are interested 
;;  first  byte range: 0x81 -- 0x9f , 0xe0 -- 0xfe
;;  second byte range: 0x40 -- 0x7e,  0x81 -- 0xfe
;;no validation needed here. State machine has done that
(defun DistAnalyse-SJIS (ch0 ch1)
  (let ((order -1))
    (cond
     ((and (>= ch0 #x81) (<= ch0 #x9f))
      (setq order (* 188 (- ch0 #x81))))
     ((and (>= ch0 #xe0) (<= ch0 #xef))
      (setq order (* 188 (+ (- ch0 #xe0) 31)))))
    (when (>= order 0)
      (setq order (+ order (- ch1 #x40)))
      (if (> ch0 #x7f)
          (setq order (1- order))))
    (when (>= order 0)
      (mTotalChars++ SJIS-dist-table)
      (if (and (< order JIS_TABLE_SIZE) (> 512 (elt JISCharToFreqOrder order)))
          (mFreqChars++ SJIS-dist-table)))))

(defun DistAnalyse-SJIS-GetConfidence (total)
  (let ((Confidence 0.0))
  (cond
   ((and (> total MINIMUM_FILE_SIZE)
         (or (<= (mTotalChars SJIS-dist-table) 0) (<= (mFreqChars SJIS-dist-table) MINIMUM_DATA_THRESHOLD)))
      (setq Confidence 0.1))
   ((/= (mTotalChars SJIS-dist-table) (mFreqChars SJIS-dist-table))
    (setq Confidence (min (/ (float (mFreqChars SJIS-dist-table))
                              (* (float (- (mTotalChars SJIS-dist-table) (mFreqChars SJIS-dist-table)))
                                 JIS_DIST_RATIO))
                          0.99)))
   (t
    (setq Confidence 0.99)))
  ))



;; MultiByte EUC-JP Prober

;; for japanese encoding, obeserve characteristic:
;; 1, kana character (or hankaku?) often have hight frequency of appereance
;; 2, kana character often exist in group
;; 3, certain combination of kana is never used in japanese language

(defvar debug-eucjp nil)

(defvar multibyte-eucjp-list nil)
(setq multibyte-eucjp-list
      '(euc-jp 0.0 multibyte-eucjp-prober))

;;EUCJP-dist-table
(defvar EUCJP-dist-table nil)

(setq EUCJP-dist-table
      '((mTotalChars . 0)
        (mFreqChars . 0)))


(defun multibyte-eucjp-prober (start end)
  (setq debug-code 'start-multibyte-eucjp)
  (let ((mState 'eDetecting)
        codingState
        charlen
        (mConfidence 0.0)
        (code0 0)
        (code1 0)
        (total (/ (- end start) 2))
        )
    (SM-reset)
    (dist-table-reset EUCJP-dist-table)
    (setq debug-eucjp 'starting-eucjp)
    (save-excursion
      (goto-char start)
      (setq code1 (char-after))
      (while (and (< (point) end)
                  (eq mState 'eDetecting))
        (setq code1 (char-after))
        (setq codingState (NextState code1 EUCJPSMModel))
        (forward-char 1)
        (setq debug-code (list 'gb-doing codingState mState))
        (cond
         ((= codingState eError)
          (setq mState 'eNotMe)
          (setcar (cdr multibyte-eucjp-list) 0.01))
         ((= codingState eItsMe)
          (setq mState 'eFoundIt)
          (setcar (cdr multibyte-eucjp-list) 0.99))
         ((= codingState eStart)
          (setq charlen (SM-get-charlen))
          (DistAnalyse-EUCJP code0 code1) ;; we are interested only in 2-byte
;;           (message "Code0: #x%X, Code1: #x%X" code0 code1)
          )
         (t nil))
        (setq code0 code1)
        )
      (setq debug-code 'eucjp-getting-confidence)
      (if (eq mState 'eDetecting)
          (if (and (> (setq mConfidence (DistAnalyse-EUCJP-GetConfidence total)) SHORTCUT_THRESHOLD)
                   (> (mTotalChars EUCJP-dist-table) ENOUGH_DATA_THRESHOLD))
              (progn
                (setq mState 'eFoundIt)
                (setcar (cdr multibyte-eucjp-list) 0.99))
            (if (= (setcar (cdr multibyte-eucjp-list) mConfidence) 0.99)
                (setq mState 'eFoundIt))))
      (setq debug-code 'eucjp-done)
      mState)))

;;for EUCJP encoding, we are interested 
;;  first  byte range: 0xa0 -- 0xfe
;;  second byte range: 0xa1 -- 0xfe
;;no validation needed here. State machine has done that
(defun DistAnalyse-EUCJP (ch0 ch1)
  (let ((order -1))
    (if (>= ch0 #xa0)
        (setq order (- (+ (* 94 (- ch0 #xa1)) ch1) #xa1)))
    (when (>= order 0)
      (mTotalChars++ EUCJP-dist-table)
      (if (and (< order JIS_TABLE_SIZE) (> 512 (elt JISCharToFreqOrder order)))
          (mFreqChars++ EUCJP-dist-table)))))

(defun DistAnalyse-EUCJP-GetConfidence (total)
  (let ((Confidence 0.0))
  (cond
   ((and (> total MINIMUM_FILE_SIZE)
         (or (<= (mTotalChars EUCJP-dist-table) 0) (<= (mFreqChars EUCJP-dist-table) MINIMUM_DATA_THRESHOLD)))
      (setq Confidence 0.1))
   ((/= (mTotalChars EUCJP-dist-table) (mFreqChars EUCJP-dist-table))
    (setq Confidence (min (/ (float (mFreqChars EUCJP-dist-table))
                              (* (float (- (mTotalChars EUCJP-dist-table) (mFreqChars EUCJP-dist-table)))
                                 JIS_DIST_RATIO))
                          0.99)))
   (t
    (setq Confidence 0.99)))
  ))



;; MultiByte EUC-KR Prober
;; Korean

(defvar debug-euckr nil)

(defvar multibyte-euckr-list nil)
(setq multibyte-euckr-list
      '(euc-kr 0.0 multibyte-euckr-prober))

;;EUCKR-dist-table
(defvar EUCKR-dist-table nil)

(setq EUCKR-dist-table
      '((mTotalChars . 0)
        (mFreqChars . 0)))


(defun multibyte-euckr-prober (start end)
  (setq debug-code 'start-multibyte-euckr)
  (let ((mState 'eDetecting)
        codingState
        charlen
        (mConfidence 0.0)
        (code0 0)
        (code1 0)
        (total (/ (- end start) 2))
        )
    (SM-reset)
    (dist-table-reset EUCKR-dist-table)
    (setq debug-euckr 'starting-euckr)
    (save-excursion
      (goto-char start)
      (setq code1 (char-after))
      (while (and (< (point) end)
                  (eq mState 'eDetecting))
        (setq code1 (char-after))
        (setq codingState (NextState code1 EUCKRSMModel))
        (forward-char 1)
        (setq debug-code (list 'gb-doing codingState mState))
        (cond
         ((= codingState eError)
          (setq mState 'eNotMe)
          (setcar (cdr multibyte-euckr-list) 0.01))
         ((= codingState eItsMe)
          (setq mState 'eFoundIt)
          (setcar (cdr multibyte-euckr-list) 0.99))
         ((= codingState eStart)
          (setq charlen (SM-get-charlen))
          (DistAnalyse-EUCKR code0 code1) ;; we are interested only in 2-byte
;;           (message "Code0: #x%X, Code1: #x%X" code0 code1)
          )
         (t nil))
        (setq code0 code1)
        )
      (setq debug-code 'euckr-getting-confidence)
      (if (eq mState 'eDetecting)
          (if (and (> (setq mConfidence (DistAnalyse-EUCKR-GetConfidence total)) SHORTCUT_THRESHOLD)
                   (> (mTotalChars EUCKR-dist-table) ENOUGH_DATA_THRESHOLD))
              (progn
                (setq mState 'eFoundIt)
                (setcar (cdr multibyte-euckr-list) 0.99))
            (if (= (setcar (cdr multibyte-euckr-list) mConfidence) 0.99)
                (setq mState 'eFoundIt))))
      (setq debug-code 'euckr-done)
      mState)))

;;for euc-KR encoding, we are interested 
;;  first  byte range: 0xb0 -- 0xfe
;;  second byte range: 0xa1 -- 0xfe
;;no validation needed here. State machine has done that
(defun DistAnalyse-EUCKR (ch0 ch1)
  (let ((order -1))
    (if (>= ch0 #xb0)
        (setq order (- (+ (* 94 (- ch0 #xb0)) ch1) #xa1)))
    (when (>= order 0)
      (mTotalChars++ EUCKR-dist-table)
      (if (and (< order EUCKR_TABLE_SIZE) (> 512 (elt EUCKRCharToFreqOrder order)))
          (mFreqChars++ EUCKR-dist-table)))))

(defun DistAnalyse-EUCKR-GetConfidence (total)
  (let ((Confidence 0.0))
  (cond
   ((and (> total MINIMUM_FILE_SIZE)
         (or (<= (mTotalChars EUCKR-dist-table) 0) (<= (mFreqChars EUCKR-dist-table) MINIMUM_DATA_THRESHOLD)))
      (setq Confidence 0.1))
   ((/= (mTotalChars EUCKR-dist-table) (mFreqChars EUCKR-dist-table))
    (setq Confidence (min (/ (float (mFreqChars EUCKR-dist-table))
                              (* (float (- (mTotalChars EUCKR-dist-table) (mFreqChars EUCKR-dist-table)))
                                 EUCKR_DIST_RATIO))
                          0.99)))
   (t
    (setq Confidence 0.99)))
  ))


;; MultiByte EUC-TW Prober
;;

(defvar debug-euctw nil)

(defvar multibyte-euctw-list nil)
(setq multibyte-euctw-list
      '(euc-tw 0.0 multibyte-euctw-prober))

;;EUCTW-dist-table
(defvar EUCTW-dist-table nil)

(setq EUCTW-dist-table
      '((mTotalChars . 0)
        (mFreqChars . 0)))


(defun multibyte-euctw-prober (start end)
  (setq debug-code 'start-multibyte-euctw)
  (let ((mState 'eDetecting)
        codingState
        charlen
        (mConfidence 0.0)
        (code0 0)
        (code1 0)
        (total (/ (- end start) 2))
        )
    (SM-reset)
    (dist-table-reset EUCTW-dist-table)
    (setq debug-euctw 'starting-euctw)
    (save-excursion
      (goto-char start)
      (setq code1 (char-after))
      (while (and (< (point) end)
                  (eq mState 'eDetecting))
        (setq code1 (char-after))
        (setq codingState (NextState code1 EUCTWSMModel))
        (forward-char 1)
        (setq debug-code (list 'gb-doing codingState mState))
        (cond
         ((= codingState eError)
          (setq mState 'eNotMe)
          (setcar (cdr multibyte-euctw-list) 0.01))
         ((= codingState eItsMe)
          (setq mState 'eFoundIt)
          (setcar (cdr multibyte-euctw-list) 0.99))
         ((= codingState eStart)
          (setq charlen (SM-get-charlen))
          (DistAnalyse-EUCTW code0 code1) ;; we are interested only in 2-byte
;;           (message "Code0: #x%X, Code1: #x%X" code0 code1)
          )
         (t nil))
        (setq code0 code1)
        )
      (setq debug-code 'euctw-getting-confidence)
      (if (eq mState 'eDetecting)
          (if (and (> (setq mConfidence (DistAnalyse-EUCTW-GetConfidence total)) SHORTCUT_THRESHOLD)
                   (> (mTotalChars EUCTW-dist-table) ENOUGH_DATA_THRESHOLD))
              (progn
                (setq mState 'eFoundIt)
                (setcar (cdr multibyte-euctw-list) 0.99))
            (if (= (setcar (cdr multibyte-euctw-list) mConfidence) 0.99)
                (setq mState 'eFoundIt))))
      (setq debug-code 'euctw-done)
      mState)))

;;for euc-TW encoding, we are interested 
;;  first  byte range: 0xc4 -- 0xfe
;;  second byte range: 0xa1 -- 0xfe
;;no validation needed here. State machine has done that
(defun DistAnalyse-EUCTW (ch0 ch1)
  (let ((order -1))
    (if (>= ch0 #xc4)
        (setq order (- (+ (* 94 (- ch0 #xc4)) ch1) #xa1)))
    (when (>= order 0)
      (mTotalChars++ EUCTW-dist-table)
      (if (and (< order EUCTW_TABLE_SIZE) (> 512 (elt EUCTWCharToFreqOrder order)))
          (mFreqChars++ EUCTW-dist-table)))))

(defun DistAnalyse-EUCTW-GetConfidence (total)
  (let ((Confidence 0.0))
  (cond
   ((and (> total MINIMUM_FILE_SIZE)
         (or (<= (mTotalChars EUCTW-dist-table) 0) (<= (mFreqChars EUCTW-dist-table) MINIMUM_DATA_THRESHOLD)))
      (setq Confidence 0.1))
   ((/= (mTotalChars EUCTW-dist-table) (mFreqChars EUCTW-dist-table))
    (setq Confidence (min (/ (float (mFreqChars EUCTW-dist-table))
                              (* (float (- (mTotalChars EUCTW-dist-table) (mFreqChars EUCTW-dist-table)))
                                 EUCTW_DIST_RATIO))
                          0.99)))
   (t
    (setq Confidence 0.99)))
  ))


;; Latin-1 prober

(setq 
 UDF    0        ;; undefined
 OTH    1        ;; other
 ASC    2        ;; ascii capital letter
 ASS    3        ;; ascii small letter
 ACV    4        ;; accent capital vowel
 ACO    5        ;; accent capital other
 ASV    6        ;; accent small vowel
 ASO    7        ;; accent small other
 CLASS_NUM  8)   ;; total classes


(setq Latin1_CharToClass 
`[
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 00 - 07
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 08 - 0F
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 10 - 17
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 18 - 1F
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 20 - 27
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 28 - 2F
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 30 - 37
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 38 - 3F
  ,OTH  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC    ;; 40 - 47
  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC    ;; 48 - 4F
  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC  ,ASC    ;; 50 - 57
  ,ASC  ,ASC  ,ASC  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 58 - 5F
  ,OTH  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS    ;; 60 - 67
  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS    ;; 68 - 6F
  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS  ,ASS    ;; 70 - 77
  ,ASS  ,ASS  ,ASS  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 78 - 7F
  ,OTH  ,UDF  ,OTH  ,ASO  ,OTH  ,OTH  ,OTH  ,OTH    ;; 80 - 87
  ,OTH  ,OTH  ,ACO  ,OTH  ,ACO  ,UDF  ,ACO  ,UDF    ;; 88 - 8F
  ,UDF  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; 90 - 97
  ,OTH  ,OTH  ,ASO  ,OTH  ,ASO  ,UDF  ,ASO  ,ACO    ;; 98 - 9F
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; A0 - A7
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; A8 - AF
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; B0 - B7
  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH  ,OTH    ;; B8 - BF
  ,ACV  ,ACV  ,ACV  ,ACV  ,ACV  ,ACV  ,ACO  ,ACO    ;; C0 - C7
  ,ACV  ,ACV  ,ACV  ,ACV  ,ACV  ,ACV  ,ACV  ,ACV    ;; C8 - CF
  ,ACO  ,ACO  ,ACV  ,ACV  ,ACV  ,ACV  ,ACV  ,OTH    ;; D0 - D7
  ,ACV  ,ACV  ,ACV  ,ACV  ,ACV  ,ACO  ,ACO  ,ACO    ;; D8 - DF
  ,ASV  ,ASV  ,ASV  ,ASV  ,ASV  ,ASV  ,ASO  ,ASO    ;; E0 - E7
  ,ASV  ,ASV  ,ASV  ,ASV  ,ASV  ,ASV  ,ASV  ,ASV    ;; E8 - EF
  ,ASO  ,ASO  ,ASV  ,ASV  ,ASV  ,ASV  ,ASV  ,OTH    ;; F0 - F7
  ,ASV  ,ASV  ,ASV  ,ASV  ,ASV  ,ASO  ,ASO  ,ASO    ;; F8 - FF
])

;;    0 : illegal 
;;    1 : very unlikely 
;;    2 : normal 
;;    3 : very likely

(setq Latin1ClassModel
[
;; UDF OTH ASC ASS ACV ACO ASV ASO  
    0   0   0   0   0   0   0   0   ;; UDF
    0   3   3   3   3   3   3   3   ;; OTH
    0   3   3   3   3   3   3   3   ;; ASC
    0   3   3   3   1   1   3   3   ;; ASS
    0   3   3   3   1   2   1   2   ;; ACV
    0   3   3   3   3   3   3   3   ;; ACO
    0   3   1   3   1   1   1   3   ;; ASV
    0   3   1   3   1   1   3   3   ;; ASO
])

(setq charClass (aref Latin1_CharToClass #x45))
(setq freq (aref Latin1ClassModel (+ (* ASS CLASS_NUM) charClass)))

(defvar debug-latin1 nil)

(defun latin1-prober (start end)
  (setq debug-code 'start-latin1)
  (let ((mState 'eDetecting)
        (code0-class OTH)
        code1-class
        code0
        code1
        freq
        (mFreqCounter [0 0 0 0]))
    (fillarray mFreqCounter 0)
    (setq debug-latin1 mFreqCounter)
    (save-excursion
      (goto-char start)
      (while (and (< (point) end)
                  (not (eq mState 'eNotMe)))
        (setq debug-code 'latin1-doing)
        (setq code1 (char-after))
        (forward-char 1)
        (setq code1-class (aref Latin1_CharToClass code1))
        (setq freq (aref Latin1ClassModel (+ (* code0-class CLASS_NUM) code1-class)))
        (if (= freq 0)
            (setq mState 'eNotMe)
          (progn
            ;; mFreqCounter[freq]++
            (aset mFreqCounter freq (1+ (aref mFreqCounter freq)))
            (setq code0-class code1-class)))
        )
      (setq debug-code 'latin-getting-confidence)
      (latin1-GetConfidence mState mFreqCounter))))

(defun latin1-GetConfidence (mState mFreqCounter)
  (let ((confidence 0.0)
        (total 0))
    (if (eq mState 'eNotMe)
        (setq confidence 0.01)
      (progn
        (loop for i from 0 to (1- (length mFreqCounter))
              do (setq total (+ (elt mFreqCounter i) total)))
        (if (= total 0)
            (setq confidence 0.0)
          (progn
            (setq confidence (/ (* (elt mFreqCounter 3) 1.0) total))
            (setq confidence (- confidence (/ (* (elt mFreqCounter 1) 20.0) total)))
            ))
        (if (< confidence 0.0)
            (setq confidence 0.0))
        (setq confidence (* confidence 0.5))
        ))
    (message "Confidence of Latin-1: %f" confidence)
    confidence
    ))



;; MultiByte State Machine

;; (defun pck16bits (a b)
;;   (logior (lsh b 16) a))

;; since elisp supports only 29-bit integer,
;; the result is seperated to high 16-bit and low 16-bit array

(defun PCK16BITS (a b)
  `[,b ,a]
  )

(defun PCK8BITS (a b c d)
  (PCK16BITS (logior (lsh b 8) a)
             (logior (lsh d 8) c)))

(defun PCK4BITS (a b c d e f g h)
  (PCK8BITS (logior (lsh b 4) a)
            (logior (lsh d 4) c)
            (logior (lsh f 4) e)
            (logior (lsh h 4) g)))

(defun GETFROMPCK (i c)
  (let (result                          ;result0 is high 16-bits, result1 is low 16-bits
        shift
        re-low16)
    (setq result
          (elt (elt c 4) (lsh i (* -1 (elt c 0)))))
    (setq shift
          (lsh (logand i (elt c 1)) (elt c 2)))
    (if (<= shift 16)
        (setq re-low16
              (logior (lsh (elt result 1) (* -1 shift))
                      (logand #xFFFF (lsh (elt result 0) (- 16 shift)))))
      (setq re-low16 (lsh (elt result 0) (- 16 shift))))
    (setq re-low16
          (logand re-low16 (elt c 3)))
    re-low16
    ))

;; (setq c (cdr (assoc 'stateTable UTF8SMModel)))
;; (setq i 149)
;; (GETFROMPCK i c)
;; (GETCLASS #xBF UTF8SMModel)

(defun GETCLASS (ch Model)
  (GETFROMPCK ch (cdr (assoc 'classTable Model))))

;; (GETCLASS #xAC Big5SMModel)
(defun model-elt (Model key)
  (cdr (assoc key Model)))

;; (setq test (model-elt Big5SMModel 'charLenTable))

;; (elt (cdr (assoc 'charLenTable Big5SMModel)) 3)

(defvar eStart 0)
(defvar eError 1)
(defvar eItsMe 2)

(setq coding-state-machine
      `((mState . ,eStart)
        (mCharLen . 0)
        (mBytePos . 0)))

;; (setq test '(1 2))
;; (setq (car test) 3)

(defun SM-reset ()
  (setcdr (assoc 'mState coding-state-machine) eStart)
  (setcdr (assoc 'mCharLen coding-state-machine) 0)
  (setcdr (assoc 'mBytePos coding-state-machine) 0))

(defun SM-get-charlen ()
  (cdr (assoc 'mCharLen coding-state-machine)))

(defun NextState (ch Model)
  (let (byteCls
        (current-state (cdr (assoc 'mState coding-state-machine)))
        (current-bytepos (cdr (assoc 'mBytePos coding-state-machine)))
        next-state next-bytepos next-charlen)
    (setq byteCls (GETCLASS ch Model))
    (setq next-charlen (SM-get-charlen))
    (when (= current-state eStart)
      (setq next-bytepos 0)
;;       (setq debug-code 'read-charlen-table)
;;       (setq charlen-table (model-elt Model 'charLenTable))
      (setq next-charlen (elt (model-elt Model 'charLenTable) byteCls))
      ;;(setq debug-code (list 'charlen next-charlen))
      ;;(elt (model-elt UTF8SMModel 'charLenTable) 6)
      )
    (setq next-state
          (GETFROMPCK (+ (* current-state (model-elt Model 'classFactor)) byteCls)
                      (model-elt Model 'stateTable)))
    (setq next-bytepos (1+ current-bytepos))
;;     (if debug-sm
;;         (message "char: #x%X : %s, byteClass: %d charlen:%d" ch (string ch) byteCls next-charlen))
    (setq coding-state-machine `((mState . ,next-state)
                                 (mCharLen . ,next-charlen)
                                 (mBytePos . ,next-bytepos)
                                 ))
;;    (setq debug-code (list 'next-state current-state byteCls))
    (cdr (assoc 'mState coding-state-machine))
    ))

;; (setq charlen 2)
;; (setq pos 0)
;; (setq state eStart)
;; coding-state-machine
;; (SM-reset)
;; (NextState #x91 UTF8SMModel)

;; was defined as enum nsSMState
;; in nsCodingStateMachine.h
(setq eStart 0
      eError 1
      eItsMe 2)

(setq 
 eIdxSft4bits    3
 eIdxSft8bits    2
 eIdxSft16bits   1
 )

(setq 
 eSftMsk4bits    7
 eSftMsk8bits    3
 eSftMsk16bits   1
 )

(setq 
 eBitSft4bits    2
 eBitSft8bits    3
 eBitSft16bits   4
 )

(setq 
 eUnitMsk4bits    #x0000000F
 eUnitMsk8bits    #x000000FF
 eUnitMsk16bits   #x0000FFFF
 )

  ;; (setq struct nsPkgInt {
  ;;   nsIdxSft  idxsft
  ;;   nsSftMsk  sftmsk
  ;;   nsBitSft  bitsft
  ;;   nsUnitMsk unitmsk
  ;;   PRUint32  *data}
  ;; )

  ;; Big5 

(setq BIG5_cls 
      `[
        ;;(PCK4BITS 0 1 1 1 1 1 1 1)   ;; 00 - 07 
        ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 00 - 07    ;;allow #x00 as legal value
        ,(PCK4BITS 1 1 1 1 1 1 0 0) ;; 08 - 0f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 10 - 17 
        ,(PCK4BITS 1 1 1 0 1 1 1 1) ;; 18 - 1f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 20 - 27 
        ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 28 - 2f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 30 - 37 
        ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 38 - 3f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2) ;; 40 - 47 
        ,(PCK4BITS 2 2 2 2 2 2 2 2) ;; 48 - 4f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2) ;; 50 - 57 
        ,(PCK4BITS 2 2 2 2 2 2 2 2) ;; 58 - 5f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2) ;; 60 - 67 
        ,(PCK4BITS 2 2 2 2 2 2 2 2) ;; 68 - 6f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2) ;; 70 - 77 
        ,(PCK4BITS 2 2 2 2 2 2 2 1) ;; 78 - 7f 
        ,(PCK4BITS 4 4 4 4 4 4 4 4) ;; 80 - 87 
        ,(PCK4BITS 4 4 4 4 4 4 4 4) ;; 88 - 8f 
        ,(PCK4BITS 4 4 4 4 4 4 4 4) ;; 90 - 97 
        ,(PCK4BITS 4 4 4 4 4 4 4 4) ;; 98 - 9f 
        ,(PCK4BITS 4 3 3 3 3 3 3 3) ;; a0 - a7 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; a8 - af 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; b0 - b7 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; b8 - bf 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; c0 - c7 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; c8 - cf 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; d0 - d7 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; d8 - df 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; e0 - e7 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; e8 - ef 
        ,(PCK4BITS 3 3 3 3 3 3 3 3) ;; f0 - f7 
        ,(PCK4BITS 3 3 3 3 3 3 3 0) ;; f8 - ff 
        ])



(setq BIG5_st 
      `[
        ,(PCK4BITS eError eStart eStart      3 eError eError eError eError) ;;00-07 
        ,(PCK4BITS eError eError eItsMe eItsMe eItsMe eItsMe eItsMe eError) ;;08-0f 
        ,(PCK4BITS eError eStart eStart eStart eStart eStart eStart eStart) ;;10-17 
        ])

(setq Big5CharLenTable
      [0  1  1  2  0])

  ;; (setq Big5SMModel   `[
  ;;                      [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,BIG5_cls ] 
  ;;                      5 
  ;;                      [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,BIG5_st ] 
  ;;                      ,Big5CharLenTable 
  ;;                      "Big5" 
  ;;                      ])

(setq Big5SMModel   `(
                      (classTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,BIG5_cls])
                      (classFactor . 5)
                      (stateTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,BIG5_st])
                      (charLenTable . ,Big5CharLenTable)
                      (name . "Big5")
                      ))

(setq EUCJP_cls 
      `[
        ;;,(PCK4BITS 5 4 4 4 4 4 4 4)   ;; 00 - 07 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 00 - 07 
        ,(PCK4BITS 4 4 4 4 4 4 5 5)   ;; 08 - 0f 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 10 - 17 
        ,(PCK4BITS 4 4 4 5 4 4 4 4)   ;; 18 - 1f 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 20 - 27 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 28 - 2f 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 30 - 37 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 38 - 3f 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 40 - 47 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 48 - 4f 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 50 - 57 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 58 - 5f 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 60 - 67 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 68 - 6f 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 70 - 77 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; 78 - 7f 
        ,(PCK4BITS 5 5 5 5 5 5 5 5)   ;; 80 - 87 
        ,(PCK4BITS 5 5 5 5 5 5 1 3)   ;; 88 - 8f 
        ,(PCK4BITS 5 5 5 5 5 5 5 5)   ;; 90 - 97 
        ,(PCK4BITS 5 5 5 5 5 5 5 5)   ;; 98 - 9f 
        ,(PCK4BITS 5 2 2 2 2 2 2 2)   ;; a0 - a7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; a8 - af 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; b0 - b7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; b8 - bf 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; c0 - c7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; c8 - cf 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; d0 - d7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; d8 - df 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; e0 - e7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; e8 - ef 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; f0 - f7 
        ,(PCK4BITS 0 0 0 0 0 0 0 5)   ;; f8 - ff 
        ])


(setq EUCJP_st 
      `[
        ,(PCK4BITS      3      4      3      5 eStart eError eError eError) ;;00-07 
        ,(PCK4BITS eError eError eError eError eItsMe eItsMe eItsMe eItsMe) ;;08-0f 
        ,(PCK4BITS eItsMe eItsMe eStart eError eStart eError eError eError) ;;10-17 
        ,(PCK4BITS eError eError eStart eError eError eError      3 eError) ;;18-1f 
        ,(PCK4BITS      3 eError eError eError eStart eStart eStart eStart) ;;20-27 
        ])

(setq EUCJPCharLenTable
      [2  2  2  3  1  0])

(setq EUCJPSMModel `(
                     (classTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,EUCJP_cls])
                     (classFactor . 6 )
                     (stateTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,EUCJP_st ] )
                     (charLenTable . ,EUCJPCharLenTable )
                     (name . "EUC-JP" )
                     ))

(setq EUCKR_cls 
      `[
        ;;,(PCK4BITS 0 1 1 1 1 1 1 1)   ;; 00 - 07 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 00 - 07 
        ,(PCK4BITS 1 1 1 1 1 1 0 0)   ;; 08 - 0f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 10 - 17 
        ,(PCK4BITS 1 1 1 0 1 1 1 1)   ;; 18 - 1f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 20 - 27 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 28 - 2f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 30 - 37 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 38 - 3f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 40 - 47 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 48 - 4f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 50 - 57 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 58 - 5f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 60 - 67 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 68 - 6f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 70 - 77 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 78 - 7f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 80 - 87 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 88 - 8f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 90 - 97 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 98 - 9f 
        ,(PCK4BITS 0 2 2 2 2 2 2 2)   ;; a0 - a7 
        ,(PCK4BITS 2 2 2 2 2 3 3 3)   ;; a8 - af 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; b0 - b7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; b8 - bf 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; c0 - c7 
        ,(PCK4BITS 2 3 2 2 2 2 2 2)   ;; c8 - cf 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; d0 - d7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; d8 - df 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; e0 - e7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; e8 - ef 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; f0 - f7 
        ,(PCK4BITS 2 2 2 2 2 2 2 0)   ;; f8 - ff 
        ])


(setq EUCKR_st 
      `[
        ,(PCK4BITS eError eStart      3 eError eError eError eError eError) ;;00-07 
        ,(PCK4BITS eItsMe eItsMe eItsMe eItsMe eError eError eStart eStart) ;;08-0f 
        ])

(setq EUCKRCharLenTable
      [0  1  2  0])

(setq  EUCKRSMModel   `(
                        (classTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,EUCKR_cls ] )
                        (classFactor . 4 )
                        (stateTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,EUCKR_st ] )
                        (charLenTable . ,EUCKRCharLenTable )
                        (name . "EUC-KR" )
                        ))

(setq EUCTW_cls 
      `[
        ;;,(PCK4BITS 0 2 2 2 2 2 2 2)   ;; 00 - 07 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 00 - 07 
        ,(PCK4BITS 2 2 2 2 2 2 0 0)   ;; 08 - 0f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 10 - 17 
        ,(PCK4BITS 2 2 2 0 2 2 2 2)   ;; 18 - 1f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 20 - 27 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 28 - 2f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 30 - 37 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 38 - 3f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 40 - 47 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 48 - 4f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 50 - 57 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 58 - 5f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 60 - 67 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 68 - 6f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 70 - 77 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 78 - 7f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 80 - 87 
        ,(PCK4BITS 0 0 0 0 0 0 6 0)   ;; 88 - 8f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 90 - 97 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 98 - 9f 
        ,(PCK4BITS 0 3 4 4 4 4 4 4)   ;; a0 - a7 
        ,(PCK4BITS 5 5 1 1 1 1 1 1)   ;; a8 - af 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; b0 - b7 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; b8 - bf 
        ,(PCK4BITS 1 1 3 1 3 3 3 3)   ;; c0 - c7 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; c8 - cf 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; d0 - d7 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; d8 - df 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; e0 - e7 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; e8 - ef 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; f0 - f7 
        ,(PCK4BITS 3 3 3 3 3 3 3 0)   ;; f8 - ff 
        ])


(setq EUCTW_st 
      `[
        ,(PCK4BITS eError eError eStart      3      3      3      4 eError) ;;00-07 
        ,(PCK4BITS eError eError eError eError eError eError eItsMe eItsMe) ;;08-0f 
        ,(PCK4BITS eItsMe eItsMe eItsMe eItsMe eItsMe eError eStart eError) ;;10-17 
        ,(PCK4BITS eStart eStart eStart eError eError eError eError eError) ;;18-1f 
        ,(PCK4BITS      5 eError eError eError eStart eError eStart eStart) ;;20-27 
        ,(PCK4BITS eStart eError eStart eStart eStart eStart eStart eStart) ;;28-2f 
        ])

(setq EUCTWCharLenTable
      [0  0  1  2  2  2  3])

(setq  EUCTWSMModel   `(
                        (classTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,EUCTW_cls])
                        (classFactor . 7 )
                        (stateTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,EUCTW_st])
                        (charLenTable . ,EUCTWCharLenTable )
                        (name . "x-euc-tw" )
                        ))


  ;; the following state machine data was created by perl script in 
  ;; intl/chardet/tools. It should be the same as in PSM detector.
(setq GB18030_cls 
      `[
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 00 - 07 
        ,(PCK4BITS 1 1 1 1 1 1 0 0)   ;; 08 - 0f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 10 - 17 
        ,(PCK4BITS 1 1 1 0 1 1 1 1)   ;; 18 - 1f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 20 - 27 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 28 - 2f 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; 30 - 37 
        ,(PCK4BITS 3 3 1 1 1 1 1 1)   ;; 38 - 3f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 40 - 47 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 48 - 4f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 50 - 57 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 58 - 5f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 60 - 67 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 68 - 6f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 70 - 77 
        ,(PCK4BITS 2 2 2 2 2 2 2 4)   ;; 78 - 7f 
        ,(PCK4BITS 5 6 6 6 6 6 6 6)   ;; 80 - 87 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; 88 - 8f 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; 90 - 97 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; 98 - 9f 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; a0 - a7 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; a8 - af 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; b0 - b7 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; b8 - bf 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; c0 - c7 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; c8 - cf 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; d0 - d7 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; d8 - df 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; e0 - e7 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; e8 - ef 
        ,(PCK4BITS 6 6 6 6 6 6 6 6)   ;; f0 - f7 
        ,(PCK4BITS 6 6 6 6 6 6 6 0)   ;; f8 - ff 
        ])


(setq GB18030_st 
      `[
        ,(PCK4BITS eError eStart eStart eStart eStart eStart      3 eError) ;;00-07 
        ,(PCK4BITS eError eError eError eError eError eError eItsMe eItsMe) ;;08-0f 
        ,(PCK4BITS eItsMe eItsMe eItsMe eItsMe eItsMe eError eError eStart) ;;10-17 
        ,(PCK4BITS      4 eError eStart eStart eError eError eError eError) ;;18-1f 
        ,(PCK4BITS eError eError      5 eError eError eError eItsMe eError) ;;20-27 
        ,(PCK4BITS eError eError eStart eStart eStart eStart eStart eStart) ;;28-2f 
        ])

  ;; To be accurate  the length of class 6 can be either 2 or 4. 
  ;; But it is not necessary to discriminate between the two since 
  ;; it is used for frequency analysis only  and we are validing 
  ;; each code range there as well. So it is safe to set it to be 
  ;; 2 here. 
(setq GB18030CharLenTable
      [0  1  1  1  1  1  2])

(setq  GB18030SMModel   `(
                          (classTable . [,eIdxSft4bits ,eSftMsk4bits ,eBitSft4bits ,eUnitMsk4bits ,GB18030_cls])
                          (classFactor . 7 )
                          (stateTable . [,eIdxSft4bits ,eSftMsk4bits ,eBitSft4bits ,eUnitMsk4bits ,GB18030_st])
                          (charLenTable . ,GB18030CharLenTable )
                          (name . "GB18030" )
                          ))

  ;; sjis

(setq SJIS_cls 
      `[
        ;;,(PCK4BITS 0 1 1 1 1 1 1 1)   ;; 00 - 07 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 00 - 07 
        ,(PCK4BITS 1 1 1 1 1 1 0 0)   ;; 08 - 0f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 10 - 17 
        ,(PCK4BITS 1 1 1 0 1 1 1 1)   ;; 18 - 1f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 20 - 27 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 28 - 2f 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 30 - 37 
        ,(PCK4BITS 1 1 1 1 1 1 1 1)   ;; 38 - 3f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 40 - 47 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 48 - 4f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 50 - 57 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 58 - 5f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 60 - 67 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 68 - 6f 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; 70 - 77 
        ,(PCK4BITS 2 2 2 2 2 2 2 1)   ;; 78 - 7f 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; 80 - 87 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; 88 - 8f 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; 90 - 97 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; 98 - 9f 
        ;;#xa0 is illegal in sjis encoding  but some pages does 
        ;;contain such byte. We need to be more error forgiven.
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; a0 - a7     
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; a8 - af 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; b0 - b7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; b8 - bf 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; c0 - c7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; c8 - cf 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; d0 - d7 
        ,(PCK4BITS 2 2 2 2 2 2 2 2)   ;; d8 - df 
        ,(PCK4BITS 3 3 3 3 3 3 3 3)   ;; e0 - e7 
        ,(PCK4BITS 3 3 3 3 3 4 4 4)   ;; e8 - ef 
        ,(PCK4BITS 4 4 4 4 4 4 4 4)   ;; f0 - f7 
        ,(PCK4BITS 4 4 4 4 4 0 0 0)   ;; f8 - ff 
        ])


(setq SJIS_st 
      `[
        ,(PCK4BITS eError eStart eStart      3 eError eError eError eError) ;;00-07 
        ,(PCK4BITS eError eError eError eError eItsMe eItsMe eItsMe eItsMe) ;;08-0f 
        ,(PCK4BITS eItsMe eItsMe eError eError eStart eStart eStart eStart) ;;10-17 
        ])

(setq SJISCharLenTable
      [0  1  1  2  0  0])

(setq SJISSMModel   `(
                      (classTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,SJIS_cls ] )
                      (classFactor . 6 )
                      (stateTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,SJIS_st ] )
                      (charLenTable . ,SJISCharLenTable )
                      (name . "Shift_JIS" )
                      ))


(setq UCS2BE_cls 
      `[
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 00 - 07 
        ,(PCK4BITS 0 0 1 0 0 2 0 0)   ;; 08 - 0f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 10 - 17 
        ,(PCK4BITS 0 0 0 3 0 0 0 0)   ;; 18 - 1f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 20 - 27 
        ,(PCK4BITS 0 3 3 3 3 3 0 0)   ;; 28 - 2f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 30 - 37 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 38 - 3f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 40 - 47 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 48 - 4f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 50 - 57 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 58 - 5f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 60 - 67 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 68 - 6f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 70 - 77 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 78 - 7f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 80 - 87 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 88 - 8f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 90 - 97 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 98 - 9f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; a0 - a7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; a8 - af 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; b0 - b7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; b8 - bf 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; c0 - c7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; c8 - cf 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; d0 - d7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; d8 - df 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; e0 - e7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; e8 - ef 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; f0 - f7 
        ,(PCK4BITS 0 0 0 0 0 0 4 5)   ;; f8 - ff 
        ])


(setq UCS2BE_st 
      `[
        ,(PCK4BITS      5      7      7 eError      4      3 eError eError) ;;00-07 
        ,(PCK4BITS eError eError eError eError eItsMe eItsMe eItsMe eItsMe) ;;08-0f 
        ,(PCK4BITS eItsMe eItsMe      6      6      6      6 eError eError) ;;10-17 
        ,(PCK4BITS      6      6      6      6      6 eItsMe      6      6) ;;18-1f 
        ,(PCK4BITS      6      6      6      6      5      7      7 eError) ;;20-27 
        ,(PCK4BITS      5      8      6      6 eError      6      6      6) ;;28-2f 
        ,(PCK4BITS      6      6      6      6 eError eError eStart eStart) ;;30-37 
        ])

(setq UCS2BECharLenTable
      [2  2  2  0  2  2])

(setq UCS2BESMModel   `(
                        (classTable . [,eIdxSft4bits ,eSftMsk4bits ,eBitSft4bits ,eUnitMsk4bits ,UCS2BE_cls])
                        (classFactor . 6 )
                        (stateTable . [,eIdxSft4bits ,eSftMsk4bits ,eBitSft4bits ,eUnitMsk4bits ,UCS2BE_st])
                        (charLenTable . UCS2BECharLenTable )
                        (name . "UTF-16BE" )
                        ))

(setq UCS2LE_cls 
      `[
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 00 - 07 
        ,(PCK4BITS 0 0 1 0 0 2 0 0)   ;; 08 - 0f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 10 - 17 
        ,(PCK4BITS 0 0 0 3 0 0 0 0)   ;; 18 - 1f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 20 - 27 
        ,(PCK4BITS 0 3 3 3 3 3 0 0)   ;; 28 - 2f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 30 - 37 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 38 - 3f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 40 - 47 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 48 - 4f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 50 - 57 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 58 - 5f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 60 - 67 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 68 - 6f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 70 - 77 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 78 - 7f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 80 - 87 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 88 - 8f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 90 - 97 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; 98 - 9f 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; a0 - a7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; a8 - af 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; b0 - b7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; b8 - bf 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; c0 - c7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; c8 - cf 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; d0 - d7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; d8 - df 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; e0 - e7 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; e8 - ef 
        ,(PCK4BITS 0 0 0 0 0 0 0 0)   ;; f0 - f7 
        ,(PCK4BITS 0 0 0 0 0 0 4 5)   ;; f8 - ff 
        ])


(setq UCS2LE_st 
      `[
        ,(PCK4BITS      6      6      7      6      4      3 eError eError) ;;00-07 
        ,(PCK4BITS eError eError eError eError eItsMe eItsMe eItsMe eItsMe) ;;08-0f 
        ,(PCK4BITS eItsMe eItsMe      5      5      5 eError eItsMe eError) ;;10-17 
        ,(PCK4BITS      5      5      5 eError      5 eError      6      6) ;;18-1f 
        ,(PCK4BITS      7      6      8      8      5      5      5 eError) ;;20-27 
        ,(PCK4BITS      5      5      5 eError eError eError      5      5) ;;28-2f 
        ,(PCK4BITS      5      5      5 eError      5 eError eStart eStart) ;;30-37 
        ])

(setq UCS2LECharLenTable
      [2  2  2  2  2  2])

(setq UCS2LESMModel   `(
                        (classTable . [,eIdxSft4bits ,eSftMsk4bits ,eBitSft4bits ,eUnitMsk4bits ,UCS2LE_cls])
                        (classFactor . 6 )
                        (stateTable . [,eIdxSft4bits ,eSftMsk4bits ,eBitSft4bits ,eUnitMsk4bits ,UCS2LE_st])
                        (charLenTable . UCS2LECharLenTable )
                        (name . "UTF-16LE" )
                        ))


(setq UTF8_cls 
        `[
          ;; BitSft  0 1 2 3 4 5 6 7
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 00 - 07  ;;allow #x00 as a legal value
          ,(PCK4BITS 1 1 1 1 1 1 0 0) ;; 08 - 0f 1
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 10 - 17 2
          ,(PCK4BITS 1 1 1 0 1 1 1 1) ;; 18 - 1f 3
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 20 - 27 4
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 28 - 2f 5
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 30 - 37 6
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 38 - 3f 7
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 40 - 47 8
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 48 - 4f 9
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 50 - 57 10
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 58 - 5f 11
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 60 - 67 12
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 68 - 6f 13
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 70 - 77 14
          ,(PCK4BITS 1 1 1 1 1 1 1 1) ;; 78 - 7f 15
          ,(PCK4BITS 2 2 2 2 3 3 3 3) ;; 80 - 87 16
          ,(PCK4BITS 4 4 4 4 4 4 4 4) ;; 88 - 8f 17
          ,(PCK4BITS 4 4 4 4 4 4 4 4) ;; 90 - 97 18
          ,(PCK4BITS 4 4 4 4 4 4 4 4) ;; 98 - 9f 19
          ,(PCK4BITS 5 5 5 5 5 5 5 5) ;; a0 - a7 20
          ,(PCK4BITS 5 5 5 5 5 5 5 5) ;; a8 - af 21
          ,(PCK4BITS 5 5 5 5 5 5 5 5) ;; b0 - b7 22
          ,(PCK4BITS 5 5 5 5 5 5 5 5) ;; b8 - bf 23
          ,(PCK4BITS 0 0 6 6 6 6 6 6) ;; c0 - c7 24
          ,(PCK4BITS 6 6 6 6 6 6 6 6) ;; c8 - cf 25
          ,(PCK4BITS 6 6 6 6 6 6 6 6) ;; d0 - d7 26
          ,(PCK4BITS 6 6 6 6 6 6 6 6) ;; d8 - df 27
          ,(PCK4BITS 7 8 8 8 8 8 8 8) ;; e0 - e7 28
          ,(PCK4BITS 8 8 8 8 8 9 8 8) ;; e8 - ef 29
          ,(PCK4BITS 10 11 11 11 11 11 11 11) ;; f0 - f7 
          ,(PCK4BITS 12 13 13 13 14 15 0 0)   ;; f8 - ff 
          ])


(setq UTF8_st 
      `[
        ,(PCK4BITS eError eStart eError eError eError eError      12      10) ;;00-07  0
        ,(PCK4BITS      9      11      8      7      6      5      4      3) ;;08-0f  1
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;10-17  2
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;18-1f  3
        ,(PCK4BITS eItsMe eItsMe eItsMe eItsMe eItsMe eItsMe eItsMe eItsMe) ;;20-27  4
        ,(PCK4BITS eItsMe eItsMe eItsMe eItsMe eItsMe eItsMe eItsMe eItsMe) ;;28-2f  5
        ,(PCK4BITS eError eError      5      5      5      5 eError eError) ;;30-37  6
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;38-3f  7
        ,(PCK4BITS eError eError eError      5      5      5 eError eError) ;;40-47  8
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;48-4f  9
        ,(PCK4BITS eError eError      7      7      7      7 eError eError) ;;50-57  10
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;58-5f  11
        ,(PCK4BITS eError eError eError eError      7      7 eError eError) ;;60-67  12
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;68-6f  13
        ,(PCK4BITS eError eError      9      9      9      9 eError eError) ;;70-77  14
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;78-7f  15
        ,(PCK4BITS eError eError eError eError eError      9 eError eError) ;;80-87  16
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;88-8f  17
        ,(PCK4BITS eError eError      12      12      12      12 eError eError) ;;90-97  18
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;98-9f  19
        ,(PCK4BITS eError eError eError eError eError      12 eError eError) ;;a0-a7  20
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;a8-af  21
        ,(PCK4BITS eError eError      12      12      12 eError eError eError) ;;b0-b7  22
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;b8-bf  23
        ,(PCK4BITS eError eError eStart eStart eStart eStart eError eError) ;;c0-c7  24
        ,(PCK4BITS eError eError eError eError eError eError eError eError) ;;c8-cf  25
        ])

(setq UTF8CharLenTable
      ;0  1  2  3  4  5  6  7
      [0  1  0  0  0  0  2  3  
       3  3  4  4  5  5  6  6 ])

(setq UTF8SMModel   `(
                      (classTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,UTF8_cls ] )
                      (classFactor . 16 )
                      (stateTable . [,eIdxSft4bits  ,eSftMsk4bits  ,eBitSft4bits  ,eUnitMsk4bits  ,UTF8_st ] )
                      (charLenTable . ,UTF8CharLenTable )
                      (name . "UTF-8" )
                      ))



;; just for backup

(setq utf-8-dec '((bit1 #x7F #x80 1)
                  (bit2 #xDF #xE0 2)
                  (bit3 #xEF #xF0 3)
                  (bit4 #xF7 #xF8 4)
                  (bit5 #xFB #xFC 5)
                  (bit6 #xFD #xFE 6)
                  (bit7 #xFE #xFF 7)
                  (bitx #xBF #xC0 0)))

(defmacro get-utf-8-mask (name)
  `(car (cdr (assoc ,name utf-8-dec))))

(defmacro get-utf-8-mask2 (name)
  `(car (cdr (cdr (assoc ,name utf-8-dec)))))

(defmacro get-utf-8-bitnum (name)
  `(car (cdr (cdr (cdr (assoc ,name utf-8-dec))))))

(defmacro utf-8-mark-p (name ch)
  `(if (>= (setq masked (- ,(get-utf-8-mask name) ,ch)) 0)
      (= 0 (logand masked ,(get-utf-8-mask2 name)))))

(defun utf-8-prober (size)
  "This is not from unicode charset detector"
  (setq debug-code buffer-file-coding-system-explicit)
  (unless buffer-file-coding-system-explicit
    (let (code1
          code2
          follow-num
          (state nil)
          (confidence 0.0))
      (setq debug-code 'utf-8-start)
      (save-excursion
        (goto-char (point-min))
        (while (or (> confidence 10)
                   (and (not (eq state 'not-me))
                        (< (point) size)))
          (setq debug-code 'utf-8-doing)
          (setq code1 (char-after))
          (forward-char 1)
          (if debug-now
              (message "Code1: #x%X" code1))
          (cond
           ( ;;(utf-8-mark-p bit1 code1)
            (<= code1 #x80)          
            (setq follow-num 0)
            (setq state 'found-it))
           ((utf-8-mark-p bit2 code1)
            (setq follow-num 1))
           ((utf-8-mark-p bit3 code1)
            (setq follow-num 2))
           ((utf-8-mark-p bit4 code1)
            (setq follow-num 3))
           ((utf-8-mark-p bit5 code1)
            (setq follow-num 4))
           ((utf-8-mark-p bit5 code1)
            (setq follow-num 4))
           ((utf-8-mark-p bit6 code1)
            (setq follow-num 5))
           ((utf-8-mark-p bit7 code1)
            (setq follow-num 6))
           (t
            (setq follow-num -1)
            (setq state 'not-me)
            (setq debug-code (point))
            (if debug-now
                (message "Code1 wrong: #x%X" code1))
            ))
          (while (> follow-num 0)
            (setq code2 (char-after))
            (if debug-now
                (message "Code2: #x%X" code2))
            (forward-char 1)
            (setq state 'found-it)
            (unless (utf-8-mark-p bitx code2)
              (setq state 'not-me)
              (setq follow-num -1)
              (setq debug-code (point))
              (if debug-now
                  (message "Code2 wrong: #x%X" code2))
              )
            (setq follow-num (1- follow-num))
            (setq confidence (1+ confidence))
            )
          ))
      (setq debug-code state)      
      (if (eq state 'found-it)
          (progn
            (setq debug-code 'DONE-utf-8)
            (message "This IS utf-8")
            (setq confidence 100.0)
            )
        (progn
          (message "this is not utf-8")
          (setq debug-code 'NOT-utf-8)
          (setq confidence 0.0)))
      (message "confidence of utf-8: %f" confidence)
      confidence)
    ))



;; Distribution Table for GB2312/GB18030

;;******************************************************************************
;; * 512  --> 0.79  -- 0.79
;; * 1024 --> 0.92  -- 0.13
;; * 2048 --> 0.98  -- 0.06
;; * 6768 --> 1.00  -- 0.02
;; *
;; * Idea Distribution Ratio = 0.79135/(1-0.79135) = 3.79
;; * Random Distribution Ration = 512 / (3755 - 512) = 0.157
;; * 
;; * Typical Distribution Ratio about 25% of Ideal one, still much higher that RDR
;; *****************************************************************************/

;; #define GB2312_TYPICAL_DISTRIBUTION_RATIO (float)0.9
(setq GB2312_DIST_RATIO 0.9)
(setq GB18030_DIST_RATIO GB2312_DIST_RATIO)

;; #define GB2312_TABLE_SIZE  3760
(setq GB2312_TABLE_SIZE 3760)
(setq GB18030_TABLE_SIZE GB2312_TABLE_SIZE)

(setq GB2312CharToFreqOrder
[
1671  749 1443 2364 3924 3807 2330 3921 1704 3463 2691 1511 1515  572 3191 2205 
2361  224 2558  479 1711  963 3162  440 4060 1905 2966 2947 3580 2647 3961 3842 
2204  869 4207  970 2678 5626 2944 2956 1479 4048  514 3595  588 1346 2820 3409 
 249 4088 1746 1873 2047 1774  581 1813  358 1174 3590 1014 1561 4844 2245  670 
1636 3112  889 1286  953  556 2327 3060 1290 3141  613  185 3477 1367  850 3820 
1715 2428 2642 2303 2732 3041 2562 2648 3566 3946 1349  388 3098 2091 1360 3585 
 152 1687 1539  738 1559   59 1232 2925 2267 1388 1249 1741 1679 2960  151 1566 
1125 1352 4271  924 4296  385 3166 4459  310 1245 2850   70 3285 2729 3534 3575 
2398 3298 3466 1960 2265  217 3647  864 1909 2084 4401 2773 1010 3269 5152  853 
3051 3121 1244 4251 1895  364 1499 1540 2313 1180 3655 2268  562  715 2417 3061 
 544  336 3768 2380 1752 4075  950  280 2425 4382  183 2759 3272  333 4297 2155 
1688 2356 1444 1039 4540  736 1177 3349 2443 2368 2144 2225  565  196 1482 3406 
 927 1335 4147  692  878 1311 1653 3911 3622 1378 4200 1840 2969 3149 2126 1816 
2534 1546 2393 2760  737 2494   13  447  245 2747   38 2765 2129 2589 1079  606 
 360  471 3755 2890  404  848  699 1785 1236  370 2221 1023 3746 2074 2026 2023 
2388 1581 2119  812 1141 3091 2536 1519  804 2053  406 1596 1090  784  548 4414 
1806 2264 2936 1100  343 4114 5096  622 3358  743 3668 1510 1626 5020 3567 2513 
3195 4115 5627 2489 2991   24 2065 2697 1087 2719   48 1634  315   68  985 2052 
 198 2239 1347 1107 1439  597 2366 2172  871 3307  919 2487 2790 1867  236 2570 
1413 3794  906 3365 3381 1701 1982 1818 1524 2924 1205  616 2586 2072 2004  575 
 253 3099   32 1365 1182  197 1714 2454 1201  554 3388 3224 2748  756 2587  250 
2567 1507 1517 3529 1922 2761 2337 3416 1961 1677 2452 2238 3153  615  911 1506 
1474 2495 1265 1906 2749 3756 3280 2161  898 2714 1759 3450 2243 2444  563   26 
3286 2266 3769 3344 2707 3677  611 1402  531 1028 2871 4548 1375  261 2948  835 
1190 4134  353  840 2684 1900 3082 1435 2109 1207 1674  329 1872 2781 4055 2686 
2104  608 3318 2423 2957 2768 1108 3739 3512 3271 3985 2203 1771 3520 1418 2054 
1681 1153  225 1627 2929  162 2050 2511 3687 1954  124 1859 2431 1684 3032 2894 
 585 4805 3969 2869 2704 2088 2032 2095 3656 2635 4362 2209  256  518 2042 2105 
3777 3657  643 2298 1148 1779  190  989 3544  414   11 2135 2063 2979 1471  403 
3678  126  770 1563  671 2499 3216 2877  600 1179  307 2805 4937 1268 1297 2694 
 252 4032 1448 1494 1331 1394  127 2256  222 1647 1035 1481 3056 1915 1048  873 
3651  210   33 1608 2516  200 1520  415  102    0 3389 1287  817   91 3299 2940 
 836 1814  549 2197 1396 1669 2987 3582 2297 2848 4528 1070  687   20 1819  121 
1552 1364 1461 1968 2617 3540 2824 2083  177  948 4938 2291  110 4549 2066  648 
3359 1755 2110 2114 4642 4845 1693 3937 3308 1257 1869 2123  208 1804 3159 2992 
2531 2549 3361 2418 1350 2347 2800 2568 1291 2036 2680   72  842 1990  212 1233 
1154 1586   75 2027 3410 4900 1823 1337 2710 2676  728 2810 1522 3026 4995  157 
 755 1050 4022  710  785 1936 2194 2085 1406 2777 2400  150 1250 4049 1206  807 
1910  534  529 3309 1721 1660  274   39 2827  661 2670 1578  925 3248 3815 1094 
4278 4901 4252   41 1150 3747 2572 2227 4501 3658 4902 3813 3357 3617 2884 2258 
 887  538 4187 3199 1294 2439 3042 2329 2343 2497 1255  107  543 1527  521 3478 
3568  194 5062   15  961 3870 1241 1192 2664   66 5215 3260 2111 1295 1127 2152 
3805 4135  901 1164 1976  398 1278  530 1460  748  904 1054 1966 1426   53 2909 
 509  523 2279 1534  536 1019  239 1685  460 2353  673 1065 2401 3600 4298 2272 
1272 2363  284 1753 3679 4064 1695   81  815 2677 2757 2731 1386  859  500 4221 
2190 2566  757 1006 2519 2068 1166 1455  337 2654 3203 1863 1682 1914 3025 1252 
1409 1366  847  714 2834 2038 3209  964 2970 1901  885 2553 1078 1756 3049  301 
1572 3326  688 2130 1996 2429 1805 1648 2930 3421 2750 3652 3088  262 1158 1254 
 389 1641 1812  526 1719  923 2073 1073 1902  468  489 4625 1140  857 2375 3070 
3319 2863  380  116 1328 2693 1161 2244  273 1212 1884 2769 3011 1775 1142  461 
3066 1200 2147 2212  790  702 2695 4222 1601 1058  434 2338 5153 3640   67 2360 
4099 2502  618 3472 1329  416 1132  830 2782 1807 2653 3211 3510 1662  192 2124 
 296 3979 1739 1611 3684   23  118  324  446 1239 1225  293 2520 3814 3795 2535 
3116   17 1074  467 2692 2201  387 2922   45 1326 3055 1645 3659 2817  958  243 
1903 2320 1339 2825 1784 3289  356  576  865 2315 2381 3377 3916 1088 3122 1713 
1655  935  628 4689 1034 1327  441  800  720  894 1979 2183 1528 5289 2702 1071 
4046 3572 2399 1571 3281   79  761 1103  327  134  758 1899 1371 1615  879  442 
 215 2605 2579  173 2048 2485 1057 2975 3317 1097 2253 3801 4263 1403 1650 2946 
 814 4968 3487 1548 2644 1567 1285    2  295 2636   97  946 3576  832  141 4257 
3273  760 3821 3521 3156 2607  949 1024 1733 1516 1803 1920 2125 2283 2665 3180 
1501 2064 3560 2171 1592  803 3518 1416  732 3897 4258 1363 1362 2458  119 1427 
 602 1525 2608 1605 1639 3175  694 3064   10  465   76 2000 4846 4208  444 3781 
1619 3353 2206 1273 3796  740 2483  320 1723 2377 3660 2619 1359 1137 1762 1724 
2345 2842 1850 1862  912  821 1866  612 2625 1735 2573 3369 1093  844   89  937 
 930 1424 3564 2413 2972 1004 3046 3019 2011  711 3171 1452 4178  428  801 1943 
 432  445 2811  206 4136 1472  730  349   73  397 2802 2547  998 1637 1167  789 
 396 3217  154 1218  716 1120 1780 2819 4826 1931 3334 3762 2139 1215 2627  552 
3664 3628 3232 1405 2383 3111 1356 2652 3577 3320 3101 1703  640 1045 1370 1246 
4996  371 1575 2436 1621 2210  984 4033 1734 2638   16 4529  663 2755 3255 1451 
3917 2257 1253 1955 2234 1263 2951  214 1229  617  485  359 1831 1969  473 2310 
 750 2058  165   80 2864 2419  361 4344 2416 2479 1134  796 3726 1266 2943  860 
2715  938  390 2734 1313 1384  248  202  877 1064 2854  522 3907  279 1602  297 
2357  395 3740  137 2075  944 4089 2584 1267 3802   62 1533 2285  178  176  780 
2440  201 3707  590  478 1560 4354 2117 1075   30   74 4643 4004 1635 1441 2745 
 776 2596  238 1077 1692 1912 2844  605  499 1742 3947  241 3053  980 1749  936 
2640 4511 2582  515 1543 2162 5322 2892 2993  890 2148 1924  665 1827 3581 1032 
 968 3163  339 1044 1896  270  583 1791 1720 4367 1194 3488 3669   43 2523 1657 
 163 2167  290 1209 1622 3378  550  634 2508 2510  695 2634 2384 2512 1476 1414 
 220 1469 2341 2138 2852 3183 2900 4939 2865 3502 1211 3680  854 3227 1299 2976 
3172  186 2998 1459  443 1067 3251 1495  321 1932 3054  909  753 1410 1828  436 
2441 1119 1587 3164 2186 1258  227  231 1425 1890 3200 3942  247  959  725 5254 
2741  577 2158 2079  929  120  174  838 2813  591 1115  417 2024   40 3240 1536 
1037  291 4151 2354  632 1298 2406 2500 3535 1825 1846 3451  205 1171  345 4238 
  18 1163  811  685 2208 1217  425 1312 1508 1175 4308 2552 1033  587 1381 3059 
2984 3482  340 1316 4023 3972  792 3176  519  777 4690  918  933 4130 2981 3741 
  90 3360 2911 2200 5184 4550  609 3079 2030  272 3379 2736  363 3881 1130 1447 
 286  779  357 1169 3350 3137 1630 1220 2687 2391  747 1277 3688 2618 2682 2601 
1156 3196 5290 4034 3102 1689 3596 3128  874  219 2783  798  508 1843 2461  269 
1658 1776 1392 1913 2983 3287 2866 2159 2372  829 4076   46 4253 2873 1889 1894 
 915 1834 1631 2181 2318  298  664 2818 3555 2735  954 3228 3117  527 3511 2173 
 681 2712 3033 2247 2346 3467 1652  155 2164 3382  113 1994  450  899  494  994 
1237 2958 1875 2336 1926 3727  545 1577 1550  633 3473  204 1305 3072 2410 1956 
2471  707 2134  841 2195 2196 2663 3843 1026 4940  990 3252 4997  368 1092  437 
3212 3258 1933 1829  675 2977 2893  412  943 3723 4644 3294 3283 2230 2373 5154 
2389 2241 2661 2323 1404 2524  593  787  677 3008 1275 2059  438 2709 2609 2240 
2269 2246 1446   36 1568 1373 3892 1574 2301 1456 3962  693 2276 5216 2035 1143 
2720 1919 1797 1811 2763 4137 2597 1830 1699 1488 1198 2090  424 1694  312 3634 
3390 4179 3335 2252 1214  561 1059 3243 2295 2561  975 5155 2321 2751 3772  472 
1537 3282 3398 1047 2077 2348 2878 1323 3340 3076  690 2906   51  369  170 3541 
1060 2187 2688 3670 2541 1083 1683  928 3918  459  109 4427  599 3744 4286  143 
2101 2730 2490   82 1588 3036 2121  281 1860  477 4035 1238 2812 3020 2716 3312 
1530 2188 2055 1317  843  636 1808 1173 3495  649  181 1002  147 3641 1159 2414 
3750 2289 2795  813 3123 2610 1136 4368    5 3391 4541 2174  420  429 1728  754 
1228 2115 2219  347 2223 2733  735 1518 3003 2355 3134 1764 3948 3329 1888 2424 
1001 1234 1972 3321 3363 1672 1021 1450 1584  226  765  655 2526 3404 3244 2302 
3665  731  594 2184  319 1576  621  658 2656 4299 2099 3864 1279 2071 2598 2739 
 795 3086 3699 3908 1707 2352 2402 1382 3136 2475 1465 4847 3496 3865 1085 3004 
2591 1084  213 2287 1963 3565 2250  822  793 4574 3187 1772 1789 3050  595 1484 
1959 2770 1080 2650  456  422 2996  940 3322 4328 4345 3092 2742  965 2784  739 
4124  952 1358 2498 2949 2565  332 2698 2378  660 2260 2473 4194 3856 2919  535 
1260 2651 1208 1428 1300 1949 1303 2942  433 2455 2450 1251 1946  614 1269  641 
1306 1810 2737 3078 2912  564 2365 1419 1415 1497 4460 2367 2185 1379 3005 1307 
3218 2175 1897 3063  682 1157 4040 4005 1712 1160 1941 1399  394  402 2952 1573 
1151 2986 2404  862  299 2033 1489 3006  346  171 2886 3401 1726 2932  168 2533 
  47 2507 1030 3735 1145 3370 1395 1318 1579 3609 4560 2857 4116 1457 2529 1965 
 504 1036 2690 2988 2405  745 5871  849 2397 2056 3081  863 2359 3857 2096   99 
1397 1769 2300 4428 1643 3455 1978 1757 3718 1440   35 4879 3742 1296 4228 2280 
 160 5063 1599 2013  166  520 3479 1646 3345 3012  490 1937 1545 1264 2182 2505 
1096 1188 1369 1436 2421 1667 2792 2460 1270 2122  727 3167 2143  806 1706 1012 
1800 3037  960 2218 1882  805  139 2456 1139 1521  851 1052 3093 3089  342 2039 
 744 5097 1468 1502 1585 2087  223  939  326 2140 2577  892 2481 1623 4077  982 
3708  135 2131   87 2503 3114 2326 1106  876 1616  547 2997 2831 2093 3441 4530 
4314    9 3256 4229 4148  659 1462 1986 1710 2046 2913 2231 4090 4880 5255 3392 
3274 1368 3689 4645 1477  705 3384 3635 1068 1529 2941 1458 3782 1509  100 1656 
2548  718 2339  408 1590 2780 3548 1838 4117 3719 1345 3530  717 3442 2778 3220 
2898 1892 4590 3614 3371 2043 1998 1224 3483  891  635  584 2559 3355  733 1766 
1729 1172 3789 1891 2307  781 2982 2271 1957 1580 5773 2633 2005 4195 3097 1535 
3213 1189 1934 5693 3262  586 3118 1324 1598  517 1564 2217 1868 1893 4445 3728 
2703 3139 1526 1787 1992 3882 2875 1549 1199 1056 2224 1904 2711 5098 4287  338 
1993 3129 3489 2689 1809 2815 1997  957 1855 3898 2550 3275 3057 1105 1319  627 
1505 1911 1883 3526  698 3629 3456 1833 1431  746   77 1261 2017 2296 1977 1885 
 125 1334 1600  525 1798 1109 2222 1470 1945  559 2236 1186 3443 2476 1929 1411 
2411 3135 1777 3372 2621 1841 1613 3229  668 1430 1839 2643 2916  195 1989 2671 
2358 1387  629 3205 2293 5256 4439  123 1310  888 1879 4300 3021 3605 1003 1162 
3192 2910 2010  140 2395 2859   55 1082 2012 2901  662  419 2081 1438  680 2774 
4654 3912 1620 1731 1625 5035 4065 2328  512 1344  802 5443 2163 2311 2537  524 
3399   98 1155 2103 1918 2606 3925 2816 1393 2465 1504 3773 2177 3963 1478 4346 
 180 1113 4655 3461 2028 1698  833 2696 1235 1322 1594 4408 3623 3013 3225 2040 
3022  541 2881  607 3632 2029 1665 1219  639 1385 1686 1099 2803 3231 1938 3188 
2858  427  676 2772 1168 2025  454 3253 2486 3556  230 1950  580  791 1991 1280 
1086 1974 2034  630  257 3338 2788 4903 1017   86 4790  966 2789 1995 1696 1131 
 259 3095 4188 1308  179 1463 5257  289 4107 1248   42 3413 1725 2288  896 1947 
 774 4474 4254  604 3430 4264  392 2514 2588  452  237 1408 3018  988 4531 1970 
3034 3310  540 2370 1562 1288 2990  502 4765 1147    4 1853 2708  207  294 2814 
4078 2902 2509  684   34 3105 3532 2551  644  709 2801 2344  573 1727 3573 3557 
2021 1081 3100 4315 2100 3681  199 2263 1837 2385  146 3484 1195 2776 3949  997 
1939 3973 1008 1091 1202 1962 1847 1149 4209 5444 1076  493  117 5400 2521  972 
1490 2934 1796 4542 2374 1512 2933 2657  413 2888 1135 2762 2314 2156 1355 2369 
 766 2007 2527 2170 3124 2491 2593 2632 4757 2437  234 3125 3591 1898 1750 1376 
1942 3468 3138  570 2127 2145 3276 4131  962  132 1445 4196   19  941 3624 3480 
3366 1973 1374 4461 3431 2629  283 2415 2275  808 2887 3620 2112 2563 1353 3610 
 955 1089 3103 1053   96   88 4097  823 3808 1583  399  292 4091 3313  421 1128 
 642 4006  903 2539 1877 2082  596   29 4066 1790  722 2157  130  995 1569  769 
1485  464  513 2213  288 1923 1101 2453 4316  133  486 2445   50  625  487 2207 
  57  423  481 2962  159 3729 1558  491  303  482  501  240 2837  112 3648 2392 
1783  362    8 3433 3422  610 2793 3277 1390 1284 1654   21 3823  734  367  623 
 193  287  374 1009 1483  816  476  313 2255 2340 1262 2150 2899 1146 2581  782 
2116 1659 2018 1880  255 3586 3314 1110 2867 2137 2564  986 2767 5185 2006  650 
 158  926  762  881 3157 2717 2362 3587  306 3690 3245 1542 3077 2427 1691 2478 
2118 2985 3490 2438  539 2305  983  129 1754  355 4201 2386  827 2923  104 1773 
2838 2771  411 2905 3919  376  767  122 1114  828 2422 1817 3506  266 3460 1007 
1609 4998  945 2612 4429 2274  726 1247 1964 2914 2199 2070 4002 4108  657 3323 
1422  579  455 2764 4737 1222 2895 1670  824 1223 1487 2525  558  861 3080  598 
2659 2515 1967  752 2583 2376 2214 4180  977  704 2464 4999 2622 4109 1210 2961 
 819 1541  142 2284   44  418  457 1126 3730 4347 4626 1644 1876 3671 1864  302 
1063 5694  624  723 1984 3745 1314 1676 2488 1610 1449 3558 3569 2166 2098  409 
1011 2325 3704 2306  818 1732 1383 1824 1844 3757  999 2705 3497 1216 1423 2683 
2426 2954 2501 2726 2229 1475 2554 5064 1971 1794 1666 2014 1343  783  724  191 
2434 1354 2220 5065 1763 2752 2472 4152  131  175 2885 3434   92 1466 4920 2616 
3871 3872 3866  128 1551 1632  669 1854 3682 4691 4125 1230  188 2973 3290 1302 
1213  560 3266  917  763 3909 3249 1760  868 1958  764 1782 2097  145 2277 3774 
4462   64 1491 3062  971 2132 3606 2442  221 1226 1617  218  323 1185 3207 3147 
 571  619 1473 1005 1744 2281  449 1887 2396 3685  275  375 3816 1743 3844 3731 
 845 1983 2350 4210 1377  773  967 3499 3052 3743 2725 4007 1697 1022 3943 1464 
3264 2855 2722 1952 1029 2839 2467   84 4383 2215  820 1391 2015 2448 3672  377 
1948 2168  797 2545 3536 2578 2645   94 2874 1678  405 1259 3071  771  546 1315 
 470 1243 3083  895 2468  981  969 2037  846 4181  653 1276 2928   14 2594  557 
3007 2474  156  902 1338 1740 2574  537 2518  973 2282 2216 2433 1928  138 2903 
1293 2631 1612  646 3457  839 2935  111  496 2191 2847  589 3186  149 3994 2060 
4031 2641 4067 3145 1870   37 3597 2136 1025 2051 3009 3383 3549 1121 1016 3261 
1301  251 2446 2599 2153  872 3246  637  334 3705  831  884  921 3065 3140 4092 
2198 1944  246 2964  108 2045 1152 1921 2308 1031  203 3173 4170 1907 3890  810 
1401 2003 1690  506  647 1242 2828 1761 1649 3208 2249 1589 3709 2931 5156 1708 
 498  666 2613  834 3817 1231  184 2851 1124  883 3197 2261 3710 1765 1553 2658 
1178 2639 2351   93 1193  942 2538 2141 4402  235 1821  870 1591 2192 1709 1871 
3341 1618 4126 2595 2334  603  651   69  701  268 2662 3411 2555 1380 1606  503 
 448  254 2371 2646  574 1187 2309 1770  322 2235 1292 1801  305  566 1133  229 
2067 2057  706  167  483 2002 2672 3295 1820 3561 3067  316  378 2746 3452 1112 
 136 1981  507 1651 2917 1117  285 4591  182 2580 3522 1304  335 3303 1835 2504 
1795 1792 2248  674 1018 2106 2449 1857 2292 2845  976 3047 1781 2600 2727 1389 
1281   52 3152  153  265 3950  672 3485 3951 4463  430 1183  365  278 2169   27 
1407 1336 2304  209 1340 1730 2202 1852 2403 2883  979 1737 1062  631 2829 2542 
3876 2592  825 2086 2226 3048 3625  352 1417 3724  542  991  431 1351 3938 1861 
2294  826 1361 2927 3142 3503 1738  463 2462 2723  582 1916 1595 2808  400 3845 
3891 2868 3621 2254   58 2492 1123  910 2160 2614 1372 1603 1196 1072 3385 1700 
3267 1980  696  480 2430  920  799 1570 2920 1951 2041 4047 2540 1321 4223 2469 
3562 2228 1271 2602  401 2833 3351 2575 5157  907 2312 1256  410  263 3507 1582 
 996  678 1849 2316 1480  908 3545 2237  703 2322  667 1826 2849 1531 2604 2999 
2407 3146 2151 2630 1786 3711  469 3542  497 3899 2409  858  837 4446 3393 1274 
 786  620 1845 2001 3311  484  308 3367 1204 1815 3691 2332 1532 2557 1842 2020 
2724 1927 2333 4440  567   22 1673 2728 4475 1987 1858 1144 1597  101 1832 3601 
  12  974 3783 4391  951 1412    1 3720  453 4608 4041  528 1041 1027 3230 2628 
1129  875 1051 3291 1203 2262 1069 2860 2799 2149 2615 3278  144 1758 3040   31 
 475 1680  366 2685 3184  311 1642 4008 2466 5036 1593 1493 2809  216 1420 1668 
 233  304 2128 3284  232 1429 1768 1040 2008 3407 2740 2967 2543  242 2133  778 
1565 2022 2620  505 2189 2756 1098 2273  372 1614  708  553 2846 2094 2278  169 
3626 2835 4161  228 2674 3165  809 1454 1309  466 1705 1095  900 3423  880 2667 
3751 5258 2317 3109 2571 4317 2766 1503 1342  866 4447 1118   63 2076  314 1881 
1348 1061  172  978 3515 1747  532  511 3970    6  601  905 2699 3300 1751  276 
1467 3725 2668   65 4239 2544 2779 2556 1604  578 2451 1802  992 2331 2624 1320 
3446  713 1513 1013  103 2786 2447 1661  886 1702  916  654 3574 2031 1556  751 
2178 2821 2179 1498 1538 2176  271  914 2251 2080 1325  638 1953 2937 3877 2432 
2754   95 3265 1716  260 1227 4083  775  106 1357 3254  426 1607  555 2480  772 
1985  244 2546  474  495 1046 2611 1851 2061   71 2089 1675 2590  742 3758 2843 
3222 1433  267 2180 2576 2826 2233 2092 3913 2435  956 1745 3075  856 2113 1116 
 451    3 1988 2896 1398  993 2463 1878 2049 1341 2718 2721 2870 2108  712 2904 
4363 2753 2324  277 2872 2349 2649  384  987  435  691 3000  922  164 3939  652 
1500 1184 4153 2482 3373 2165 4848 2335 3775 3508 3154 2806 2830 1554 2102 1664 
2530 1434 2408  893 1547 2623 3447 2832 2242 2532 3169 2856 3223 2078   49 3770 
3469  462  318  656 2259 3250 3069  679 1629 2758  344 1138 1104 3120 1836 1283 
3115 2154 1437 4448  934  759 1999  794 2862 1038  533 2560 1722 2342  855 2626 
1197 1663 4476 3127   85 4240 2528   25 1111 1181 3673  407 3470 4561 2679 2713 
 768 1925 2841 3986 1544 1165  932  373 1240 2146 1930 2673  721 4766  354 4333 
 391 2963  187   61 3364 1442 1102  330 1940 1767  341 3809 4118  393 2496 2062 
2211  105  331  300  439  913 1332  626  379 3304 1557  328  689 3952  309 1555 
 931  317 2517 3027  325  569  686 2107 3084   60 1042 1333 2794  264 3177 4014 
1628  258 3712    7 4464 1176 1043 1778  683  114 1975   78 1492  383 1886  510 
 386  645 5291 2891 2069 3305 4138 3867 2939 2603 2493 1935 1066 1848 3588 1015 
1282 1289 4609  697 1453 3044 2666 3611 1856 2412   54  719 1330  568 3778 2459 
1748  788  492  551 1191 1000  488 3394 3763  282 1799  348 2016 1523 3155 2390 
1049  382 2019 1788 1170  729 2968 3523  897 3926 2785 2938 3292  350 2319 3238 
1718 1717 2655 3453 3143 4465  161 2889 2980 2009 1421   56 1908 1640 2387 2232 
1917 1874 2477 4921  148   83 3438  592 4245 2882 1822 1055  741  115 1496 1624 
 381 1638 4592 1020  516 3214  458  947 4575 1432  211 1514 2926 1865 2142  189 
 852 1221 1400 1486  882 2299 4036  351   28 1122  700 6479 6480 6481 6482 6483   ;;last 512
])



;; distribution table for big

;; Big5 frequency table
;; by Taiwan's Mandarin Promotion Council 
;; <http:;;www.edu.tw:81/mandr/>

;;******************************************************************************
;; * 128  --> 0.42261
;; * 256  --> 0.57851
;; * 512  --> 0.74851
;; * 1024 --> 0.89384
;; * 2048 --> 0.97583
;; *
;; * Idea Distribution Ratio = 0.74851/(1-0.74851) =2.98
;; * Random Distribution Ration = 512/(5401-512)=0.105
;; * 
;; * Typical Distribution Ratio about 25% of Ideal one, still much higher than RDR
;; *****************************************************************************/

(setq BIG5_DIST_RATIO 0.75)


;;Char to FreqOrder table , 
(setq BIG5_TABLE_SIZE  5376)

(setq Big5CharToFreqOrder
[
   1 1801 1506  255 1431  198    9   82    6 5008  177  202 3681 1256 2821  110  ;;   16
3814   33 3274  261   76   44 2114   16 2946 2187 1176  659 3971   26 3451 2653  ;;   32
1198 3972 3350 4202  410 2215  302  590  361 1964    8  204   58 4510 5009 1932  ;;   48
  63 5010 5011  317 1614   75  222  159 4203 2417 1480 5012 3555 3091  224 2822  ;;   64
3682    3   10 3973 1471   29 2787 1135 2866 1940  873  130 3275 1123  312 5013  ;;   80
4511 2052  507  252  682 5014  142 1915  124  206 2947   34 3556 3204   64  604  ;;   96
5015 2501 1977 1978  155 1991  645  641 1606 5016 3452  337   72  406 5017   80  ;;  112
 630  238 3205 1509  263  939 1092 2654  756 1440 1094 3453  449   69 2987  591  ;;  128
 179 2096  471  115 2035 1844   60   50 2988  134  806 1869  734 2036 3454  180  ;;  144
 995 1607  156  537 2907  688 5018  319 1305  779 2145  514 2379  298 4512  359  ;;  160
2502   90 2716 1338  663   11  906 1099 2553   20 2441  182  532 1716 5019  732  ;;  176
1376 4204 1311 1420 3206   25 2317 1056  113  399  382 1950  242 3455 2474  529  ;;  192
3276  475 1447 3683 5020  117   21  656  810 1297 2300 2334 3557 5021  126 4205  ;;  208
 706  456  150  613 4513   71 1118 2037 4206  145 3092   85  835  486 2115 1246  ;;  224
1426  428  727 1285 1015  800  106  623  303 1281 5022 2128 2359  347 3815  221  ;;  240
3558 3135 5023 1956 1153 4207   83  296 1199 3093  192  624   93 5024  822 1898  ;;  256
2823 3136  795 2065  991 1554 1542 1592   27   43 2867  859  139 1456  860 4514  ;;  272
 437  712 3974  164 2397 3137  695  211 3037 2097  195 3975 1608 3559 3560 3684  ;;  288
3976  234  811 2989 2098 3977 2233 1441 3561 1615 2380  668 2077 1638  305  228  ;;  304
1664 4515  467  415 5025  262 2099 1593  239  108  300  200 1033  512 1247 2078  ;;  320
5026 5027 2176 3207 3685 2682  593  845 1062 3277   88 1723 2038 3978 1951  212  ;;  336
 266  152  149  468 1899 4208 4516   77  187 5028 3038   37    5 2990 5029 3979  ;;  352
5030 5031   39 2524 4517 2908 3208 2079   55  148   74 4518  545  483 1474 1029  ;;  368
1665  217 1870 1531 3138 1104 2655 4209   24  172 3562  900 3980 3563 3564 4519  ;;  384
  32 1408 2824 1312  329  487 2360 2251 2717  784 2683    4 3039 3351 1427 1789  ;;  400
 188  109  499 5032 3686 1717 1790  888 1217 3040 4520 5033 3565 5034 3352 1520  ;;  416
3687 3981  196 1034  775 5035 5036  929 1816  249  439   38 5037 1063 5038  794  ;;  432
3982 1435 2301   46  178 3278 2066 5039 2381 5040  214 1709 4521  804   35  707  ;;  448
 324 3688 1601 2554  140  459 4210 5041 5042 1365  839  272  978 2262 2580 3456  ;;  464
2129 1363 3689 1423  697  100 3094   48   70 1231  495 3139 2196 5043 1294 5044  ;;  480
2080  462  586 1042 3279  853  256  988  185 2382 3457 1698  434 1084 5045 3458  ;;  496
 314 2625 2788 4522 2335 2336  569 2285  637 1817 2525  757 1162 1879 1616 3459  ;;  512
 287 1577 2116  768 4523 1671 2868 3566 2526 1321 3816  909 2418 5046 4211  933  ;;  528
3817 4212 2053 2361 1222 4524  765 2419 1322  786 4525 5047 1920 1462 1677 2909  ;;  544
1699 5048 4526 1424 2442 3140 3690 2600 3353 1775 1941 3460 3983 4213  309 1369  ;;  560
1130 2825  364 2234 1653 1299 3984 3567 3985 3986 2656  525 1085 3041  902 2001  ;;  576
1475  964 4527  421 1845 1415 1057 2286  940 1364 3141  376 4528 4529 1381    7  ;;  592
2527  983 2383  336 1710 2684 1846  321 3461  559 1131 3042 2752 1809 1132 1313  ;;  608
 265 1481 1858 5049  352 1203 2826 3280  167 1089  420 2827  776  792 1724 3568  ;;  624
4214 2443 3281 5050 4215 5051  446  229  333 2753  901 3818 1200 1557 4530 2657  ;;  640
1921  395 2754 2685 3819 4216 1836  125  916 3209 2626 4531 5052 5053 3820 5054  ;;  656
5055 5056 4532 3142 3691 1133 2555 1757 3462 1510 2318 1409 3569 5057 2146  438  ;;  672
2601 2910 2384 3354 1068  958 3043  461  311 2869 2686 4217 1916 3210 4218 1979  ;;  688
 383  750 2755 2627 4219  274  539  385 1278 1442 5058 1154 1965  384  561  210  ;;  704
  98 1295 2556 3570 5059 1711 2420 1482 3463 3987 2911 1257  129 5060 3821  642  ;;  720
 523 2789 2790 2658 5061  141 2235 1333   68  176  441  876  907 4220  603 2602  ;;  736
 710  171 3464  404  549   18 3143 2398 1410 3692 1666 5062 3571 4533 2912 4534  ;;  752
5063 2991  368 5064  146  366   99  871 3693 1543  748  807 1586 1185   22 2263  ;;  768
 379 3822 3211 5065 3212  505 1942 2628 1992 1382 2319 5066  380 2362  218  702  ;;  784
1818 1248 3465 3044 3572 3355 3282 5067 2992 3694  930 3283 3823 5068   59 5069  ;;  800
 585  601 4221  497 3466 1112 1314 4535 1802 5070 1223 1472 2177 5071  749 1837  ;;  816
 690 1900 3824 1773 3988 1476  429 1043 1791 2236 2117  917 4222  447 1086 1629  ;;  832
5072  556 5073 5074 2021 1654  844 1090  105  550  966 1758 2828 1008 1783  686  ;;  848
1095 5075 2287  793 1602 5076 3573 2603 4536 4223 2948 2302 4537 3825  980 2503  ;;  864
 544  353  527 4538  908 2687 2913 5077  381 2629 1943 1348 5078 1341 1252  560  ;;  880
3095 5079 3467 2870 5080 2054  973  886 2081  143 4539 5081 5082  157 3989  496  ;;  896
4224   57  840  540 2039 4540 4541 3468 2118 1445  970 2264 1748 1966 2082 4225  ;;  912
3144 1234 1776 3284 2829 3695  773 1206 2130 1066 2040 1326 3990 1738 1725 4226  ;;  928
 279 3145   51 1544 2604  423 1578 2131 2067  173 4542 1880 5083 5084 1583  264  ;;  944
 610 3696 4543 2444  280  154 5085 5086 5087 1739  338 1282 3096  693 2871 1411  ;;  960
1074 3826 2445 5088 4544 5089 5090 1240  952 2399 5091 2914 1538 2688  685 1483  ;;  976
4227 2475 1436  953 4228 2055 4545  671 2400   79 4229 2446 3285  608  567 2689  ;;  992
3469 4230 4231 1691  393 1261 1792 2401 5092 4546 5093 5094 5095 5096 1383 1672  ;; 1008
3827 3213 1464  522 1119  661 1150  216  675 4547 3991 1432 3574  609 4548 2690  ;; 1024
2402 5097 5098 5099 4232 3045    0 5100 2476  315  231 2447  301 3356 4549 2385  ;; 1040
5101  233 4233 3697 1819 4550 4551 5102   96 1777 1315 2083 5103  257 5104 1810  ;; 1056
3698 2718 1139 1820 4234 2022 1124 2164 2791 1778 2659 5105 3097  363 1655 3214  ;; 1072
5106 2993 5107 5108 5109 3992 1567 3993  718  103 3215  849 1443  341 3357 2949  ;; 1088
1484 5110 1712  127   67  339 4235 2403  679 1412  821 5111 5112  834  738  351  ;; 1104
2994 2147  846  235 1497 1881  418 1993 3828 2719  186 1100 2148 2756 3575 1545  ;; 1120
1355 2950 2872 1377  583 3994 4236 2581 2995 5113 1298 3699 1078 2557 3700 2363  ;; 1136
  78 3829 3830  267 1289 2100 2002 1594 4237  348  369 1274 2197 2178 1838 4552  ;; 1152
1821 2830 3701 2757 2288 2003 4553 2951 2758  144 3358  882 4554 3995 2759 3470  ;; 1168
4555 2915 5114 4238 1726  320 5115 3996 3046  788 2996 5116 2831 1774 1327 2873  ;; 1184
3997 2832 5117 1306 4556 2004 1700 3831 3576 2364 2660  787 2023  506  824 3702  ;; 1200
 534  323 4557 1044 3359 2024 1901  946 3471 5118 1779 1500 1678 5119 1882 4558  ;; 1216
 165  243 4559 3703 2528  123  683 4239  764 4560   36 3998 1793  589 2916  816  ;; 1232
 626 1667 3047 2237 1639 1555 1622 3832 3999 5120 4000 2874 1370 1228 1933  891  ;; 1248
2084 2917  304 4240 5121  292 2997 2720 3577  691 2101 4241 1115 4561  118  662  ;; 1264
5122  611 1156  854 2386 1316 2875    2  386  515 2918 5123 5124 3286  868 2238  ;; 1280
1486  855 2661  785 2216 3048 5125 1040 3216 3578 5126 3146  448 5127 1525 5128  ;; 1296
2165 4562 5129 3833 5130 4242 2833 3579 3147  503  818 4001 3148 1568  814  676  ;; 1312
1444  306 1749 5131 3834 1416 1030  197 1428  805 2834 1501 4563 5132 5133 5134  ;; 1328
1994 5135 4564 5136 5137 2198   13 2792 3704 2998 3149 1229 1917 5138 3835 2132  ;; 1344
5139 4243 4565 2404 3580 5140 2217 1511 1727 1120 5141 5142  646 3836 2448  307  ;; 1360
5143 5144 1595 3217 5145 5146 5147 3705 1113 1356 4002 1465 2529 2530 5148  519  ;; 1376
5149  128 2133   92 2289 1980 5150 4003 1512  342 3150 2199 5151 2793 2218 1981  ;; 1392
3360 4244  290 1656 1317  789  827 2365 5152 3837 4566  562  581 4004 5153  401  ;; 1408
4567 2252   94 4568 5154 1399 2794 5155 1463 2025 4569 3218 1944 5156  828 1105  ;; 1424
4245 1262 1394 5157 4246  605 4570 5158 1784 2876 5159 2835  819 2102  578 2200  ;; 1440
2952 5160 1502  436 3287 4247 3288 2836 4005 2919 3472 3473 5161 2721 2320 5162  ;; 1456
5163 2337 2068   23 4571  193  826 3838 2103  699 1630 4248 3098  390 1794 1064  ;; 1472
3581 5164 1579 3099 3100 1400 5165 4249 1839 1640 2877 5166 4572 4573  137 4250  ;; 1488
 598 3101 1967  780  104  974 2953 5167  278  899  253  402  572  504  493 1339  ;; 1504
5168 4006 1275 4574 2582 2558 5169 3706 3049 3102 2253  565 1334 2722  863   41  ;; 1520
5170 5171 4575 5172 1657 2338   19  463 2760 4251  606 5173 2999 3289 1087 2085  ;; 1536
1323 2662 3000 5174 1631 1623 1750 4252 2691 5175 2878  791 2723 2663 2339  232  ;; 1552
2421 5176 3001 1498 5177 2664 2630  755 1366 3707 3290 3151 2026 1609  119 1918  ;; 1568
3474  862 1026 4253 5178 4007 3839 4576 4008 4577 2265 1952 2477 5179 1125  817  ;; 1584
4254 4255 4009 1513 1766 2041 1487 4256 3050 3291 2837 3840 3152 5180 5181 1507  ;; 1600
5182 2692  733   40 1632 1106 2879  345 4257  841 2531  230 4578 3002 1847 3292  ;; 1616
3475 5183 1263  986 3476 5184  735  879  254 1137  857  622 1300 1180 1388 1562  ;; 1632
4010 4011 2954  967 2761 2665 1349  592 2134 1692 3361 3003 1995 4258 1679 4012  ;; 1648
1902 2188 5185  739 3708 2724 1296 1290 5186 4259 2201 2202 1922 1563 2605 2559  ;; 1664
1871 2762 3004 5187  435 5188  343 1108  596   17 1751 4579 2239 3477 3709 5189  ;; 1680
4580  294 3582 2955 1693  477  979  281 2042 3583  643 2043 3710 2631 2795 2266  ;; 1696
1031 2340 2135 2303 3584 4581  367 1249 2560 5190 3585 5191 4582 1283 3362 2005  ;; 1712
 240 1762 3363 4583 4584  836 1069 3153  474 5192 2149 2532  268 3586 5193 3219  ;; 1728
1521 1284 5194 1658 1546 4260 5195 3587 3588 5196 4261 3364 2693 1685 4262  961  ;; 1744
1673 2632  190 2006 2203 3841 4585 4586 5197  570 2504 3711 1490 5198 4587 2633  ;; 1760
3293 1957 4588  584 1514  396 1045 1945 5199 4589 1968 2449 5200 5201 4590 4013  ;; 1776
 619 5202 3154 3294  215 2007 2796 2561 3220 4591 3221 4592  763 4263 3842 4593  ;; 1792
5203 5204 1958 1767 2956 3365 3712 1174  452 1477 4594 3366 3155 5205 2838 1253  ;; 1808
2387 2189 1091 2290 4264  492 5206  638 1169 1825 2136 1752 4014  648  926 1021  ;; 1824
1324 4595  520 4596  997  847 1007  892 4597 3843 2267 1872 3713 2405 1785 4598  ;; 1840
1953 2957 3103 3222 1728 4265 2044 3714 4599 2008 1701 3156 1551   30 2268 4266  ;; 1856
5207 2027 4600 3589 5208  501 5209 4267  594 3478 2166 1822 3590 3479 3591 3223  ;; 1872
 829 2839 4268 5210 1680 3157 1225 4269 5211 3295 4601 4270 3158 2341 5212 4602  ;; 1888
4271 5213 4015 4016 5214 1848 2388 2606 3367 5215 4603  374 4017  652 4272 4273  ;; 1904
 375 1140  798 5216 5217 5218 2366 4604 2269  546 1659  138 3051 2450 4605 5219  ;; 1920
2254  612 1849  910  796 3844 1740 1371  825 3845 3846 5220 2920 2562 5221  692  ;; 1936
 444 3052 2634  801 4606 4274 5222 1491  244 1053 3053 4275 4276  340 5223 4018  ;; 1952
1041 3005  293 1168   87 1357 5224 1539  959 5225 2240  721  694 4277 3847  219  ;; 1968
1478  644 1417 3368 2666 1413 1401 1335 1389 4019 5226 5227 3006 2367 3159 1826  ;; 1984
 730 1515  184 2840   66 4607 5228 1660 2958  246 3369  378 1457  226 3480  975  ;; 2000
4020 2959 1264 3592  674  696 5229  163 5230 1141 2422 2167  713 3593 3370 4608  ;; 2016
4021 5231 5232 1186   15 5233 1079 1070 5234 1522 3224 3594  276 1050 2725  758  ;; 2032
1126  653 2960 3296 5235 2342  889 3595 4022 3104 3007  903 1250 4609 4023 3481  ;; 2048
3596 1342 1681 1718  766 3297  286   89 2961 3715 5236 1713 5237 2607 3371 3008  ;; 2064
5238 2962 2219 3225 2880 5239 4610 2505 2533  181  387 1075 4024  731 2190 3372  ;; 2080
5240 3298  310  313 3482 2304  770 4278   54 3054  189 4611 3105 3848 4025 5241  ;; 2096
1230 1617 1850  355 3597 4279 4612 3373  111 4280 3716 1350 3160 3483 3055 4281  ;; 2112
2150 3299 3598 5242 2797 4026 4027 3009  722 2009 5243 1071  247 1207 2343 2478  ;; 2128
1378 4613 2010  864 1437 1214 4614  373 3849 1142 2220  667 4615  442 2763 2563  ;; 2144
3850 4028 1969 4282 3300 1840  837  170 1107  934 1336 1883 5244 5245 2119 4283  ;; 2160
2841  743 1569 5246 4616 4284  582 2389 1418 3484 5247 1803 5248  357 1395 1729  ;; 2176
3717 3301 2423 1564 2241 5249 3106 3851 1633 4617 1114 2086 4285 1532 5250  482  ;; 2192
2451 4618 5251 5252 1492  833 1466 5253 2726 3599 1641 2842 5254 1526 1272 3718  ;; 2208
4286 1686 1795  416 2564 1903 1954 1804 5255 3852 2798 3853 1159 2321 5256 2881  ;; 2224
4619 1610 1584 3056 2424 2764  443 3302 1163 3161 5257 5258 4029 5259 4287 2506  ;; 2240
3057 4620 4030 3162 2104 1647 3600 2011 1873 4288 5260 4289  431 3485 5261  250  ;; 2256
  97   81 4290 5262 1648 1851 1558  160  848 5263  866  740 1694 5264 2204 2843  ;; 2272
3226 4291 4621 3719 1687  950 2479  426  469 3227 3720 3721 4031 5265 5266 1188  ;; 2288
 424 1996  861 3601 4292 3854 2205 2694  168 1235 3602 4293 5267 2087 1674 4622  ;; 2304
3374 3303  220 2565 1009 5268 3855  670 3010  332 1208  717 5269 5270 3603 2452  ;; 2320
4032 3375 5271  513 5272 1209 2882 3376 3163 4623 1080 5273 5274 5275 5276 2534  ;; 2336
3722 3604  815 1587 4033 4034 5277 3605 3486 3856 1254 4624 1328 3058 1390 4035  ;; 2352
1741 4036 3857 4037 5278  236 3858 2453 3304 5279 5280 3723 3859 1273 3860 4625  ;; 2368
5281  308 5282 4626  245 4627 1852 2480 1307 2583  430  715 2137 2454 5283  270  ;; 2384
 199 2883 4038 5284 3606 2727 1753  761 1754  725 1661 1841 4628 3487 3724 5285  ;; 2400
5286  587   14 3305  227 2608  326  480 2270  943 2765 3607  291  650 1884 5287  ;; 2416
1702 1226  102 1547   62 3488  904 4629 3489 1164 4294 5288 5289 1224 1548 2766  ;; 2432
 391  498 1493 5290 1386 1419 5291 2056 1177 4630  813  880 1081 2368  566 1145  ;; 2448
4631 2291 1001 1035 2566 2609 2242  394 1286 5292 5293 2069 5294   86 1494 1730  ;; 2464
4039  491 1588  745  897 2963  843 3377 4040 2767 2884 3306 1768  998 2221 2070  ;; 2480
 397 1827 1195 1970 3725 3011 3378  284 5295 3861 2507 2138 2120 1904 5296 4041  ;; 2496
2151 4042 4295 1036 3490 1905  114 2567 4296  209 1527 5297 5298 2964 2844 2635  ;; 2512
2390 2728 3164  812 2568 5299 3307 5300 1559  737 1885 3726 1210  885   28 2695  ;; 2528
3608 3862 5301 4297 1004 1780 4632 5302  346 1982 2222 2696 4633 3863 1742  797  ;; 2544
1642 4043 1934 1072 1384 2152  896 4044 3308 3727 3228 2885 3609 5303 2569 1959  ;; 2560
4634 2455 1786 5304 5305 5306 4045 4298 1005 1308 3728 4299 2729 4635 4636 1528  ;; 2576
2610  161 1178 4300 1983  987 4637 1101 4301  631 4046 1157 3229 2425 1343 1241  ;; 2592
1016 2243 2570  372  877 2344 2508 1160  555 1935  911 4047 5307  466 1170  169  ;; 2608
1051 2921 2697 3729 2481 3012 1182 2012 2571 1251 2636 5308  992 2345 3491 1540  ;; 2624
2730 1201 2071 2406 1997 2482 5309 4638  528 1923 2191 1503 1874 1570 2369 3379  ;; 2640
3309 5310  557 1073 5311 1828 3492 2088 2271 3165 3059 3107  767 3108 2799 4639  ;; 2656
1006 4302 4640 2346 1267 2179 3730 3230  778 4048 3231 2731 1597 2667 5312 4641  ;; 2672
5313 3493 5314 5315 5316 3310 2698 1433 3311  131   95 1504 4049  723 4303 3166  ;; 2688
1842 3610 2768 2192 4050 2028 2105 3731 5317 3013 4051 1218 5318 3380 3232 4052  ;; 2704
4304 2584  248 1634 3864  912 5319 2845 3732 3060 3865  654   53 5320 3014 5321  ;; 2720
1688 4642  777 3494 1032 4053 1425 5322  191  820 2121 2846  971 4643  931 3233  ;; 2736
 135  664  783 3866 1998  772 2922 1936 4054 3867 4644 2923 3234  282 2732  640  ;; 2752
1372 3495 1127  922  325 3381 5323 5324  711 2045 5325 5326 4055 2223 2800 1937  ;; 2768
4056 3382 2224 2255 3868 2305 5327 4645 3869 1258 3312 4057 3235 2139 2965 4058  ;; 2784
4059 5328 2225  258 3236 4646  101 1227 5329 3313 1755 5330 1391 3314 5331 2924  ;; 2800
2057  893 5332 5333 5334 1402 4305 2347 5335 5336 3237 3611 5337 5338  878 1325  ;; 2816
1781 2801 4647  259 1385 2585  744 1183 2272 4648 5339 4060 2509 5340  684 1024  ;; 2832
4306 5341  472 3612 3496 1165 3315 4061 4062  322 2153  881  455 1695 1152 1340  ;; 2848
 660  554 2154 4649 1058 4650 4307  830 1065 3383 4063 4651 1924 5342 1703 1919  ;; 2864
5343  932 2273  122 5344 4652  947  677 5345 3870 2637  297 1906 1925 2274 4653  ;; 2880
2322 3316 5346 5347 4308 5348 4309   84 4310  112  989 5349  547 1059 4064  701  ;; 2896
3613 1019 5350 4311 5351 3497  942  639  457 2306 2456  993 2966  407  851  494  ;; 2912
4654 3384  927 5352 1237 5353 2426 3385  573 4312  680  921 2925 1279 1875  285  ;; 2928
 790 1448 1984  719 2168 5354 5355 4655 4065 4066 1649 5356 1541  563 5357 1077  ;; 2944
5358 3386 3061 3498  511 3015 4067 4068 3733 4069 1268 2572 3387 3238 4656 4657  ;; 2960
5359  535 1048 1276 1189 2926 2029 3167 1438 1373 2847 2967 1134 2013 5360 4313  ;; 2976
1238 2586 3109 1259 5361  700 5362 2968 3168 3734 4314 5363 4315 1146 1876 1907  ;; 2992
4658 2611 4070  781 2427  132 1589  203  147  273 2802 2407  898 1787 2155 4071  ;; 3008
4072 5364 3871 2803 5365 5366 4659 4660 5367 3239 5368 1635 3872  965 5369 1805  ;; 3024
2699 1516 3614 1121 1082 1329 3317 4073 1449 3873   65 1128 2848 2927 2769 1590  ;; 3040
3874 5370 5371   12 2668   45  976 2587 3169 4661  517 2535 1013 1037 3240 5372  ;; 3056
3875 2849 5373 3876 5374 3499 5375 2612  614 1999 2323 3877 3110 2733 2638 5376  ;; 3072
2588 4316  599 1269 5377 1811 3735 5378 2700 3111  759 1060  489 1806 3388 3318  ;; 3088
1358 5379 5380 2391 1387 1215 2639 2256  490 5381 5382 4317 1759 2392 2348 5383  ;; 3104
4662 3878 1908 4074 2640 1807 3241 4663 3500 3319 2770 2349  874 5384 5385 3501  ;; 3120
3736 1859   91 2928 3737 3062 3879 4664 5386 3170 4075 2669 5387 3502 1202 1403  ;; 3136
3880 2969 2536 1517 2510 4665 3503 2511 5388 4666 5389 2701 1886 1495 1731 4076  ;; 3152
2370 4667 5390 2030 5391 5392 4077 2702 1216  237 2589 4318 2324 4078 3881 4668  ;; 3168
4669 2703 3615 3504  445 4670 5393 5394 5395 5396 2771   61 4079 3738 1823 4080  ;; 3184
5397  687 2046  935  925  405 2670  703 1096 1860 2734 4671 4081 1877 1367 2704  ;; 3200
3389  918 2106 1782 2483  334 3320 1611 1093 4672  564 3171 3505 3739 3390  945  ;; 3216
2641 2058 4673 5398 1926  872 4319 5399 3506 2705 3112  349 4320 3740 4082 4674  ;; 3232
3882 4321 3741 2156 4083 4675 4676 4322 4677 2408 2047  782 4084  400  251 4323  ;; 3248
1624 5400 5401  277 3742  299 1265  476 1191 3883 2122 4324 4325 1109  205 5402  ;; 3264
2590 1000 2157 3616 1861 5403 5404 5405 4678 5406 4679 2573  107 2484 2158 4085  ;; 3280
3507 3172 5407 1533  541 1301  158  753 4326 2886 3617 5408 1696  370 1088 4327  ;; 3296
4680 3618  579  327  440  162 2244  269 1938 1374 3508  968 3063   56 1396 3113  ;; 3312
2107 3321 3391 5409 1927 2159 4681 3016 5410 3619 5411 5412 3743 4682 2485 5413  ;; 3328
2804 5414 1650 4683 5415 2613 5416 5417 4086 2671 3392 1149 3393 4087 3884 4088  ;; 3344
5418 1076   49 5419  951 3242 3322 3323  450 2850  920 5420 1812 2805 2371 4328  ;; 3360
1909 1138 2372 3885 3509 5421 3243 4684 1910 1147 1518 2428 4685 3886 5422 4686  ;; 3376
2393 2614  260 1796 3244 5423 5424 3887 3324  708 5425 3620 1704 5426 3621 1351  ;; 3392
1618 3394 3017 1887  944 4329 3395 4330 3064 3396 4331 5427 3744  422  413 1714  ;; 3408
3325  500 2059 2350 4332 2486 5428 1344 1911  954 5429 1668 5430 5431 4089 2409  ;; 3424
4333 3622 3888 4334 5432 2307 1318 2512 3114  133 3115 2887 4687  629   31 2851  ;; 3440
2706 3889 4688  850  949 4689 4090 2970 1732 2089 4335 1496 1853 5433 4091  620  ;; 3456
3245  981 1242 3745 3397 1619 3746 1643 3326 2140 2457 1971 1719 3510 2169 5434  ;; 3472
3246 5435 5436 3398 1829 5437 1277 4690 1565 2048 5438 1636 3623 3116 5439  869  ;; 3488
2852  655 3890 3891 3117 4092 3018 3892 1310 3624 4691 5440 5441 5442 1733  558  ;; 3504
4692 3747  335 1549 3065 1756 4336 3748 1946 3511 1830 1291 1192  470 2735 2108  ;; 3520
2806  913 1054 4093 5443 1027 5444 3066 4094 4693  982 2672 3399 3173 3512 3247  ;; 3536
3248 1947 2807 5445  571 4694 5446 1831 5447 3625 2591 1523 2429 5448 2090  984  ;; 3552
4695 3749 1960 5449 3750  852  923 2808 3513 3751  969 1519  999 2049 2325 1705  ;; 3568
5450 3118  615 1662  151  597 4095 2410 2326 1049  275 4696 3752 4337  568 3753  ;; 3584
3626 2487 4338 3754 5451 2430 2275  409 3249 5452 1566 2888 3514 1002  769 2853  ;; 3600
 194 2091 3174 3755 2226 3327 4339  628 1505 5453 5454 1763 2180 3019 4096  521  ;; 3616
1161 2592 1788 2206 2411 4697 4097 1625 4340 4341  412   42 3119  464 5455 2642  ;; 3632
4698 3400 1760 1571 2889 3515 2537 1219 2207 3893 2643 2141 2373 4699 4700 3328  ;; 3648
1651 3401 3627 5456 5457 3628 2488 3516 5458 3756 5459 5460 2276 2092  460 5461  ;; 3664
4701 5462 3020  962  588 3629  289 3250 2644 1116   52 5463 3067 1797 5464 5465  ;; 3680
5466 1467 5467 1598 1143 3757 4342 1985 1734 1067 4702 1280 3402  465 4703 1572  ;; 3696
 510 5468 1928 2245 1813 1644 3630 5469 4704 3758 5470 5471 2673 1573 1534 5472  ;; 3712
5473  536 1808 1761 3517 3894 3175 2645 5474 5475 5476 4705 3518 2929 1912 2809  ;; 3728
5477 3329 1122  377 3251 5478  360 5479 5480 4343 1529  551 5481 2060 3759 1769  ;; 3744
2431 5482 2930 4344 3330 3120 2327 2109 2031 4706 1404  136 1468 1479  672 1171  ;; 3760
3252 2308  271 3176 5483 2772 5484 2050  678 2736  865 1948 4707 5485 2014 4098  ;; 3776
2971 5486 2737 2227 1397 3068 3760 4708 4709 1735 2931 3403 3631 5487 3895  509  ;; 3792
2854 2458 2890 3896 5488 5489 3177 3178 4710 4345 2538 4711 2309 1166 1010  552  ;; 3808
 681 1888 5490 5491 2972 2973 4099 1287 1596 1862 3179  358  453  736  175  478  ;; 3824
1117  905 1167 1097 5492 1854 1530 5493 1706 5494 2181 3519 2292 3761 3520 3632  ;; 3840
4346 2093 4347 5495 3404 1193 2489 4348 1458 2193 2208 1863 1889 1421 3331 2932  ;; 3856
3069 2182 3521  595 2123 5496 4100 5497 5498 4349 1707 2646  223 3762 1359  751  ;; 3872
3121  183 3522 5499 2810 3021  419 2374  633  704 3897 2394  241 5500 5501 5502  ;; 3888
 838 3022 3763 2277 2773 2459 3898 1939 2051 4101 1309 3122 2246 1181 5503 1136  ;; 3904
2209 3899 2375 1446 4350 2310 4712 5504 5505 4351 1055 2615  484 3764 5506 4102  ;; 3920
 625 4352 2278 3405 1499 4353 4103 5507 4104 4354 3253 2279 2280 3523 5508 5509  ;; 3936
2774  808 2616 3765 3406 4105 4355 3123 2539  526 3407 3900 4356  955 5510 1620  ;; 3952
4357 2647 2432 5511 1429 3766 1669 1832  994  928 5512 3633 1260 5513 5514 5515  ;; 3968
1949 2293  741 2933 1626 4358 2738 2460  867 1184  362 3408 1392 5516 5517 4106  ;; 3984
4359 1770 1736 3254 2934 4713 4714 1929 2707 1459 1158 5518 3070 3409 2891 1292  ;; 4000
1930 2513 2855 3767 1986 1187 2072 2015 2617 4360 5519 2574 2514 2170 3768 2490  ;; 4016
3332 5520 3769 4715 5521 5522  666 1003 3023 1022 3634 4361 5523 4716 1814 2257  ;; 4032
 574 3901 1603  295 1535  705 3902 4362  283  858  417 5524 5525 3255 4717 4718  ;; 4048
3071 1220 1890 1046 2281 2461 4107 1393 1599  689 2575  388 4363 5526 2491  802  ;; 4064
5527 2811 3903 2061 1405 2258 5528 4719 3904 2110 1052 1345 3256 1585 5529  809  ;; 4080
5530 5531 5532  575 2739 3524  956 1552 1469 1144 2328 5533 2329 1560 2462 3635  ;; 4096
3257 4108  616 2210 4364 3180 2183 2294 5534 1833 5535 3525 4720 5536 1319 3770  ;; 4112
3771 1211 3636 1023 3258 1293 2812 5537 5538 5539 3905  607 2311 3906  762 2892  ;; 4128
1439 4365 1360 4721 1485 3072 5540 4722 1038 4366 1450 2062 2648 4367 1379 4723  ;; 4144
2593 5541 5542 4368 1352 1414 2330 2935 1172 5543 5544 3907 3908 4724 1798 1451  ;; 4160
5545 5546 5547 5548 2936 4109 4110 2492 2351  411 4111 4112 3637 3333 3124 4725  ;; 4176
1561 2674 1452 4113 1375 5549 5550   47 2974  316 5551 1406 1591 2937 3181 5552  ;; 4192
1025 2142 3125 3182  354 2740  884 2228 4369 2412  508 3772  726 3638  996 2433  ;; 4208
3639  729 5553  392 2194 1453 4114 4726 3773 5554 5555 2463 3640 2618 1675 2813  ;; 4224
 919 2352 2975 2353 1270 4727 4115   73 5556 5557  647 5558 3259 2856 2259 1550  ;; 4240
1346 3024 5559 1332  883 3526 5560 5561 5562 5563 3334 2775 5564 1212  831 1347  ;; 4256
4370 4728 2331 3909 1864 3073  720 3910 4729 4730 3911 5565 4371 5566 5567 4731  ;; 4272
5568 5569 1799 4732 3774 2619 4733 3641 1645 2376 4734 5570 2938  669 2211 2675  ;; 4288
2434 5571 2893 5572 5573 1028 3260 5574 4372 2413 5575 2260 1353 5576 5577 4735  ;; 4304
3183  518 5578 4116 5579 4373 1961 5580 2143 4374 5581 5582 3025 2354 2355 3912  ;; 4320
 516 1834 1454 4117 2708 4375 4736 2229 2620 1972 1129 3642 5583 2776 5584 2976  ;; 4336
1422  577 1470 3026 1524 3410 5585 5586  432 4376 3074 3527 5587 2594 1455 2515  ;; 4352
2230 1973 1175 5588 1020 2741 4118 3528 4737 5589 2742 5590 1743 1361 3075 3529  ;; 4368
2649 4119 4377 4738 2295  895  924 4378 2171  331 2247 3076  166 1627 3077 1098  ;; 4384
5591 1232 2894 2231 3411 4739  657  403 1196 2377  542 3775 3412 1600 4379 3530  ;; 4400
5592 4740 2777 3261  576  530 1362 4741 4742 2540 2676 3776 4120 5593  842 3913  ;; 4416
5594 2814 2032 1014 4121  213 2709 3413  665  621 4380 5595 3777 2939 2435 5596  ;; 4432
2436 3335 3643 3414 4743 4381 2541 4382 4744 3644 1682 4383 3531 1380 5597  724  ;; 4448
2282  600 1670 5598 1337 1233 4745 3126 2248 5599 1621 4746 5600  651 4384 5601  ;; 4464
1612 4385 2621 5602 2857 5603 2743 2312 3078 5604  716 2464 3079  174 1255 2710  ;; 4480
4122 3645  548 1320 1398  728 4123 1574 5605 1891 1197 3080 4124 5606 3081 3082  ;; 4496
3778 3646 3779  747 5607  635 4386 4747 5608 5609 5610 4387 5611 5612 4748 5613  ;; 4512
3415 4749 2437  451 5614 3780 2542 2073 4388 2744 4389 4125 5615 1764 4750 5616  ;; 4528
4390  350 4751 2283 2395 2493 5617 4391 4126 2249 1434 4127  488 4752  458 4392  ;; 4544
4128 3781  771 1330 2396 3914 2576 3184 2160 2414 1553 2677 3185 4393 5618 2494  ;; 4560
2895 2622 1720 2711 4394 3416 4753 5619 2543 4395 5620 3262 4396 2778 5621 2016  ;; 4576
2745 5622 1155 1017 3782 3915 5623 3336 2313  201 1865 4397 1430 5624 4129 5625  ;; 4592
5626 5627 5628 5629 4398 1604 5630  414 1866  371 2595 4754 4755 3532 2017 3127  ;; 4608
4756 1708  960 4399  887  389 2172 1536 1663 1721 5631 2232 4130 2356 2940 1580  ;; 4624
5632 5633 1744 4757 2544 4758 4759 5634 4760 5635 2074 5636 4761 3647 3417 2896  ;; 4640
4400 5637 4401 2650 3418 2815  673 2712 2465  709 3533 4131 3648 4402 5638 1148  ;; 4656
 502  634 5639 5640 1204 4762 3649 1575 4763 2623 3783 5641 3784 3128  948 3263  ;; 4672
 121 1745 3916 1110 5642 4403 3083 2516 3027 4132 3785 1151 1771 3917 1488 4133  ;; 4688
1987 5643 2438 3534 5644 5645 2094 5646 4404 3918 1213 1407 2816  531 2746 2545  ;; 4704
3264 1011 1537 4764 2779 4405 3129 1061 5647 3786 3787 1867 2897 5648 2018  120  ;; 4720
4406 4407 2063 3650 3265 2314 3919 2678 3419 1955 4765 4134 5649 3535 1047 2713  ;; 4736
1266 5650 1368 4766 2858  649 3420 3920 2546 2747 1102 2859 2679 5651 5652 2000  ;; 4752
5653 1111 3651 2977 5654 2495 3921 3652 2817 1855 3421 3788 5655 5656 3422 2415  ;; 4768
2898 3337 3266 3653 5657 2577 5658 3654 2818 4135 1460  856 5659 3655 5660 2899  ;; 4784
2978 5661 2900 3922 5662 4408  632 2517  875 3923 1697 3924 2296 5663 5664 4767  ;; 4800
3028 1239  580 4768 4409 5665  914  936 2075 1190 4136 1039 2124 5666 5667 5668  ;; 4816
5669 3423 1473 5670 1354 4410 3925 4769 2173 3084 4137  915 3338 4411 4412 3339  ;; 4832
1605 1835 5671 2748  398 3656 4413 3926 4138  328 1913 2860 4139 3927 1331 4414  ;; 4848
3029  937 4415 5672 3657 4140 4141 3424 2161 4770 3425  524  742  538 3085 1012  ;; 4864
5673 5674 3928 2466 5675  658 1103  225 3929 5676 5677 4771 5678 4772 5679 3267  ;; 4880
1243 5680 4142  963 2250 4773 5681 2714 3658 3186 5682 5683 2596 2332 5684 4774  ;; 4896
5685 5686 5687 3536  957 3426 2547 2033 1931 2941 2467  870 2019 3659 1746 2780  ;; 4912
2781 2439 2468 5688 3930 5689 3789 3130 3790 3537 3427 3791 5690 1179 3086 5691  ;; 4928
3187 2378 4416 3792 2548 3188 3131 2749 4143 5692 3428 1556 2549 2297  977 2901  ;; 4944
2034 4144 1205 3429 5693 1765 3430 3189 2125 1271  714 1689 4775 3538 5694 2333  ;; 4960
3931  533 4417 3660 2184  617 5695 2469 3340 3539 2315 5696 5697 3190 5698 5699  ;; 4976
3932 1988  618  427 2651 3540 3431 5700 5701 1244 1690 5702 2819 4418 4776 5703  ;; 4992
3541 4777 5704 2284 1576  473 3661 4419 3432  972 5705 3662 5706 3087 5707 5708  ;; 5008
4778 4779 5709 3793 4145 4146 5710  153 4780  356 5711 1892 2902 4420 2144  408  ;; 5024
 803 2357 5712 3933 5713 4421 1646 2578 2518 4781 4782 3934 5714 3935 4422 5715  ;; 5040
2416 3433  752 5716 5717 1962 3341 2979 5718  746 3030 2470 4783 4423 3794  698  ;; 5056
4784 1893 4424 3663 2550 4785 3664 3936 5719 3191 3434 5720 1824 1302 4147 2715  ;; 5072
3937 1974 4425 5721 4426 3192  823 1303 1288 1236 2861 3542 4148 3435  774 3938  ;; 5088
5722 1581 4786 1304 2862 3939 4787 5723 2440 2162 1083 3268 4427 4149 4428  344  ;; 5104
1173  288 2316  454 1683 5724 5725 1461 4788 4150 2597 5726 5727 4789  985  894  ;; 5120
5728 3436 3193 5729 1914 2942 3795 1989 5730 2111 1975 5731 4151 5732 2579 1194  ;; 5136
 425 5733 4790 3194 1245 3796 4429 5734 5735 2863 5736  636 4791 1856 3940  760  ;; 5152
1800 5737 4430 2212 1508 4792 4152 1894 1684 2298 5738 5739 4793 4431 4432 2213  ;; 5168
 479 5740 5741  832 5742 4153 2496 5743 2980 2497 3797  990 3132  627 1815 2652  ;; 5184
4433 1582 4434 2126 2112 3543 4794 5744  799 4435 3195 5745 4795 2113 1737 3031  ;; 5200
1018  543  754 4436 3342 1676 4796 4797 4154 4798 1489 5746 3544 5747 2624 2903  ;; 5216
4155 5748 5749 2981 5750 5751 5752 5753 3196 4799 4800 2185 1722 5754 3269 3270  ;; 5232
1843 3665 1715  481  365 1976 1857 5755 5756 1963 2498 4801 5757 2127 3666 3271  ;; 5248
 433 1895 2064 2076 5758  602 2750 5759 5760 5761 5762 5763 3032 1628 3437 5764  ;; 5264
3197 4802 4156 2904 4803 2519 5765 2551 2782 5766 5767 5768 3343 4804 2905 5769  ;; 5280
4805 5770 2864 4806 4807 1221 2982 4157 2520 5771 5772 5773 1868 1990 5774 5775  ;; 5296
5776 1896 5777 5778 4808 1897 4158  318 5779 2095 4159 4437 5780 5781  485 5782  ;; 5312
 938 3941  553 2680  116 5783 3942 3667 5784 3545 2681 2783 3438 3344 2820 5785  ;; 5328
3668 2943 4160 1747 2944 2983 5786 5787  207 5788 4809 5789 4810 2521 5790 3033  ;; 5344
 890 3669 3943 5791 1878 3798 3439 5792 2186 2358 3440 1652 5793 5794 5795  941  ;; 5360
2299  208 3546 4161 2020  330 4438 3944 2906 2499 3799 4439 4811 5796 5797 5798  ;; 5376  ;;last 512
])




;; JIS Freq table

;;Sampling from about 20M text materials include literature and computer technology

;; Japanese frequency table, applied to both S-JIS and EUC-JP
;;They are sorted in order. 

;;******************************************************************************
;; * 128  --> 0.77094
;; * 256  --> 0.85710
;; * 512  --> 0.92635
;; * 1024 --> 0.97130
;; * 2048 --> 0.99431
;; *
;; * Idea Distribution Ratio = 0.92635 / (1-0.92635) = 12.58
;; * Random Distribution Ration = 512 / (2965+62+83+86-512) = 0.191
;; * 
;; * Typical Distribution Ratio, 25% of IDR 
;; *****************************************************************************/

(setq JIS_DIST_RATIO 3.0)


;;Char to FreqOrder table , 
(setq JIS_TABLE_SIZE  4368)

(setq JISCharToFreqOrder
[
  40    1    6  182  152  180  295 2127  285  381 3295 4304 3068 4606 3165 3510  ;;   16
3511 1822 2785 4607 1193 2226 5070 4608  171 2996 1247   18  179 5071  856 1661  ;;   32
1262 5072  619  127 3431 3512 3230 1899 1700  232  228 1294 1298  284  283 2041  ;;   48
2042 1061 1062   48   49   44   45  433  434 1040 1041  996  787 2997 1255 4305  ;;   64
2108 4609 1684 1648 5073 5074 5075 5076 5077 5078 3687 5079 4610 5080 3927 3928  ;;   80
5081 3296 3432  290 2285 1471 2187 5082 2580 2825 1303 2140 1739 1445 2691 3375  ;;   96
1691 3297 4306 4307 4611  452 3376 1182 2713 3688 3069 4308 5083 5084 5085 5086  ;;  112
5087 5088 5089 5090 5091 5092 5093 5094 5095 5096 5097 5098 5099 5100 5101 5102  ;;  128
5103 5104 5105 5106 5107 5108 5109 5110 5111 5112 4097 5113 5114 5115 5116 5117  ;;  144
5118 5119 5120 5121 5122 5123 5124 5125 5126 5127 5128 5129 5130 5131 5132 5133  ;;  160
5134 5135 5136 5137 5138 5139 5140 5141 5142 5143 5144 5145 5146 5147 5148 5149  ;;  176
5150 5151 5152 4612 5153 5154 5155 5156 5157 5158 5159 5160 5161 5162 5163 5164  ;;  192
5165 5166 5167 5168 5169 5170 5171 5172 5173 5174 5175 1472  598  618  820 1205  ;;  208
1309 1412 1858 1307 1692 5176 5177 5178 5179 5180 5181 5182 1142 1452 1234 1172  ;;  224
1875 2043 2149 1793 1382 2973  925 2404 1067 1241  960 1377 2935 1491  919 1217  ;;  240
1865 2030 1406 1499 2749 4098 5183 5184 5185 5186 5187 5188 2561 4099 3117 1804  ;;  256
2049 3689 4309 3513 1663 5189 3166 3118 3298 1587 1561 3433 5190 3119 1625 2998  ;;  272
3299 4613 1766 3690 2786 4614 5191 5192 5193 5194 2161   26 3377    2 3929   20  ;;  288
3691   47 4100   50   17   16   35  268   27  243   42  155   24  154   29  184  ;;  304
   4   91   14   92   53  396   33  289    9   37   64  620   21   39  321    5  ;;  320
  12   11   52   13    3  208  138    0    7   60  526  141  151 1069  181  275  ;;  336
1591   83  132 1475  126  331  829   15   69  160   59   22  157   55 1079  312  ;;  352
 109   38   23   25   10   19   79 5195   61  382 1124    8   30 5196 5197 5198  ;;  368
5199 5200 5201 5202 5203 5204 5205 5206   89   62   74   34 2416  112  139  196  ;;  384
 271  149   84  607  131  765   46   88  153  683   76  874  101  258   57   80  ;;  400
  32  364  121 1508  169 1547   68  235  145 2999   41  360 3027   70   63   31  ;;  416
  43  259  262 1383   99  533  194   66   93  846  217  192   56  106   58  565  ;;  432
 280  272  311  256  146   82  308   71  100  128  214  655  110  261  104 1140  ;;  448
  54   51   36   87   67 3070  185 2618 2936 2020   28 1066 2390 2059 5207 5208  ;;  464
5209 5210 5211 5212 5213 5214 5215 5216 4615 5217 5218 5219 5220 5221 5222 5223  ;;  480
5224 5225 5226 5227 5228 5229 5230 5231 5232 5233 5234 5235 5236 3514 5237 5238  ;;  496
5239 5240 5241 5242 5243 5244 2297 2031 4616 4310 3692 5245 3071 5246 3598 5247  ;;  512
4617 3231 3515 5248 4101 4311 4618 3808 4312 4102 5249 4103 4104 3599 5250 5251  ;;  528
5252 5253 5254 5255 5256 5257 5258 5259 5260 5261 5262 5263 5264 5265 5266 5267  ;;  544
5268 5269 5270 5271 5272 5273 5274 5275 5276 5277 5278 5279 5280 5281 5282 5283  ;;  560
5284 5285 5286 5287 5288 5289 5290 5291 5292 5293 5294 5295 5296 5297 5298 5299  ;;  576
5300 5301 5302 5303 5304 5305 5306 5307 5308 5309 5310 5311 5312 5313 5314 5315  ;;  592
5316 5317 5318 5319 5320 5321 5322 5323 5324 5325 5326 5327 5328 5329 5330 5331  ;;  608
5332 5333 5334 5335 5336 5337 5338 5339 5340 5341 5342 5343 5344 5345 5346 5347  ;;  624
5348 5349 5350 5351 5352 5353 5354 5355 5356 5357 5358 5359 5360 5361 5362 5363  ;;  640
5364 5365 5366 5367 5368 5369 5370 5371 5372 5373 5374 5375 5376 5377 5378 5379  ;;  656
5380 5381  363  642 2787 2878 2788 2789 2316 3232 2317 3434 2011  165 1942 3930  ;;  672
3931 3932 3933 5382 4619 5383 4620 5384 5385 5386 5387 5388 5389 5390 5391 5392  ;;  688
5393 5394 5395 5396 5397 5398 5399 5400 5401 5402 5403 5404 5405 5406 5407 5408  ;;  704
5409 5410 5411 5412 5413 5414 5415 5416 5417 5418 5419 5420 5421 5422 5423 5424  ;;  720
5425 5426 5427 5428 5429 5430 5431 5432 5433 5434 5435 5436 5437 5438 5439 5440  ;;  736
5441 5442 5443 5444 5445 5446 5447 5448 5449 5450 5451 5452 5453 5454 5455 5456  ;;  752
5457 5458 5459 5460 5461 5462 5463 5464 5465 5466 5467 5468 5469 5470 5471 5472  ;;  768
5473 5474 5475 5476 5477 5478 5479 5480 5481 5482 5483 5484 5485 5486 5487 5488  ;;  784
5489 5490 5491 5492 5493 5494 5495 5496 5497 5498 5499 5500 5501 5502 5503 5504  ;;  800
5505 5506 5507 5508 5509 5510 5511 5512 5513 5514 5515 5516 5517 5518 5519 5520  ;;  816
5521 5522 5523 5524 5525 5526 5527 5528 5529 5530 5531 5532 5533 5534 5535 5536  ;;  832
5537 5538 5539 5540 5541 5542 5543 5544 5545 5546 5547 5548 5549 5550 5551 5552  ;;  848
5553 5554 5555 5556 5557 5558 5559 5560 5561 5562 5563 5564 5565 5566 5567 5568  ;;  864
5569 5570 5571 5572 5573 5574 5575 5576 5577 5578 5579 5580 5581 5582 5583 5584  ;;  880
5585 5586 5587 5588 5589 5590 5591 5592 5593 5594 5595 5596 5597 5598 5599 5600  ;;  896
5601 5602 5603 5604 5605 5606 5607 5608 5609 5610 5611 5612 5613 5614 5615 5616  ;;  912
5617 5618 5619 5620 5621 5622 5623 5624 5625 5626 5627 5628 5629 5630 5631 5632  ;;  928
5633 5634 5635 5636 5637 5638 5639 5640 5641 5642 5643 5644 5645 5646 5647 5648  ;;  944
5649 5650 5651 5652 5653 5654 5655 5656 5657 5658 5659 5660 5661 5662 5663 5664  ;;  960
5665 5666 5667 5668 5669 5670 5671 5672 5673 5674 5675 5676 5677 5678 5679 5680  ;;  976
5681 5682 5683 5684 5685 5686 5687 5688 5689 5690 5691 5692 5693 5694 5695 5696  ;;  992
5697 5698 5699 5700 5701 5702 5703 5704 5705 5706 5707 5708 5709 5710 5711 5712  ;; 1008
5713 5714 5715 5716 5717 5718 5719 5720 5721 5722 5723 5724 5725 5726 5727 5728  ;; 1024
5729 5730 5731 5732 5733 5734 5735 5736 5737 5738 5739 5740 5741 5742 5743 5744  ;; 1040
5745 5746 5747 5748 5749 5750 5751 5752 5753 5754 5755 5756 5757 5758 5759 5760  ;; 1056
5761 5762 5763 5764 5765 5766 5767 5768 5769 5770 5771 5772 5773 5774 5775 5776  ;; 1072
5777 5778 5779 5780 5781 5782 5783 5784 5785 5786 5787 5788 5789 5790 5791 5792  ;; 1088
5793 5794 5795 5796 5797 5798 5799 5800 5801 5802 5803 5804 5805 5806 5807 5808  ;; 1104
5809 5810 5811 5812 5813 5814 5815 5816 5817 5818 5819 5820 5821 5822 5823 5824  ;; 1120
5825 5826 5827 5828 5829 5830 5831 5832 5833 5834 5835 5836 5837 5838 5839 5840  ;; 1136
5841 5842 5843 5844 5845 5846 5847 5848 5849 5850 5851 5852 5853 5854 5855 5856  ;; 1152
5857 5858 5859 5860 5861 5862 5863 5864 5865 5866 5867 5868 5869 5870 5871 5872  ;; 1168
5873 5874 5875 5876 5877 5878 5879 5880 5881 5882 5883 5884 5885 5886 5887 5888  ;; 1184
5889 5890 5891 5892 5893 5894 5895 5896 5897 5898 5899 5900 5901 5902 5903 5904  ;; 1200
5905 5906 5907 5908 5909 5910 5911 5912 5913 5914 5915 5916 5917 5918 5919 5920  ;; 1216
5921 5922 5923 5924 5925 5926 5927 5928 5929 5930 5931 5932 5933 5934 5935 5936  ;; 1232
5937 5938 5939 5940 5941 5942 5943 5944 5945 5946 5947 5948 5949 5950 5951 5952  ;; 1248
5953 5954 5955 5956 5957 5958 5959 5960 5961 5962 5963 5964 5965 5966 5967 5968  ;; 1264
5969 5970 5971 5972 5973 5974 5975 5976 5977 5978 5979 5980 5981 5982 5983 5984  ;; 1280
5985 5986 5987 5988 5989 5990 5991 5992 5993 5994 5995 5996 5997 5998 5999 6000  ;; 1296
6001 6002 6003 6004 6005 6006 6007 6008 6009 6010 6011 6012 6013 6014 6015 6016  ;; 1312
6017 6018 6019 6020 6021 6022 6023 6024 6025 6026 6027 6028 6029 6030 6031 6032  ;; 1328
6033 6034 6035 6036 6037 6038 6039 6040 6041 6042 6043 6044 6045 6046 6047 6048  ;; 1344
6049 6050 6051 6052 6053 6054 6055 6056 6057 6058 6059 6060 6061 6062 6063 6064  ;; 1360
6065 6066 6067 6068 6069 6070 6071 6072 6073 6074 6075 6076 6077 6078 6079 6080  ;; 1376
6081 6082 6083 6084 6085 6086 6087 6088 6089 6090 6091 6092 6093 6094 6095 6096  ;; 1392
6097 6098 6099 6100 6101 6102 6103 6104 6105 6106 6107 6108 6109 6110 6111 6112  ;; 1408
6113 6114 2044 2060 4621  997 1235  473 1186 4622  920 3378 6115 6116  379 1108  ;; 1424
4313 2657 2735 3934 6117 3809  636 3233  573 1026 3693 3435 2974 3300 2298 4105  ;; 1440
 854 2937 2463  393 2581 2417  539  752 1280 2750 2480  140 1161  440  708 1569  ;; 1456
 665 2497 1746 1291 1523 3000  164 1603  847 1331  537 1997  486  508 1693 2418  ;; 1472
1970 2227  878 1220  299 1030  969  652 2751  624 1137 3301 2619   65 3302 2045  ;; 1488
1761 1859 3120 1930 3694 3516  663 1767  852  835 3695  269  767 2826 2339 1305  ;; 1504
 896 1150  770 1616 6118  506 1502 2075 1012 2519  775 2520 2975 2340 2938 4314  ;; 1520
3028 2086 1224 1943 2286 6119 3072 4315 2240 1273 1987 3935 1557  175  597  985  ;; 1536
3517 2419 2521 1416 3029  585  938 1931 1007 1052 1932 1685 6120 3379 4316 4623  ;; 1552
 804  599 3121 1333 2128 2539 1159 1554 2032 3810  687 2033 2904  952  675 1467  ;; 1568
3436 6121 2241 1096 1786 2440 1543 1924  980 1813 2228  781 2692 1879  728 1918  ;; 1584
3696 4624  548 1950 4625 1809 1088 1356 3303 2522 1944  502  972  373  513 2827  ;; 1600
 586 2377 2391 1003 1976 1631 6122 2464 1084  648 1776 4626 2141  324  962 2012  ;; 1616
2177 2076 1384  742 2178 1448 1173 1810  222  102  301  445  125 2420  662 2498  ;; 1632
 277  200 1476 1165 1068  224 2562 1378 1446  450 1880  659  791  582 4627 2939  ;; 1648
3936 1516 1274  555 2099 3697 1020 1389 1526 3380 1762 1723 1787 2229  412 2114  ;; 1664
1900 2392 3518  512 2597  427 1925 2341 3122 1653 1686 2465 2499  697  330  273  ;; 1680
 380 2162  951  832  780  991 1301 3073  965 2270 3519  668 2523 2636 1286  535  ;; 1696
1407  518  671  957 2658 2378  267  611 2197 3030 6123  248 2299  967 1799 2356  ;; 1712
 850 1418 3437 1876 1256 1480 2828 1718 6124 6125 1755 1664 2405 6126 4628 2879  ;; 1728
2829  499 2179  676 4629  557 2329 2214 2090  325 3234  464  811 3001  992 2342  ;; 1744
2481 1232 1469  303 2242  466 1070 2163  603 1777 2091 4630 2752 4631 2714  322  ;; 1760
2659 1964 1768  481 2188 1463 2330 2857 3600 2092 3031 2421 4632 2318 2070 1849  ;; 1776
2598 4633 1302 2254 1668 1701 2422 3811 2905 3032 3123 2046 4106 1763 1694 4634  ;; 1792
1604  943 1724 1454  917  868 2215 1169 2940  552 1145 1800 1228 1823 1955  316  ;; 1808
1080 2510  361 1807 2830 4107 2660 3381 1346 1423 1134 4108 6127  541 1263 1229  ;; 1824
1148 2540  545  465 1833 2880 3438 1901 3074 2482  816 3937  713 1788 2500  122  ;; 1840
1575  195 1451 2501 1111 6128  859  374 1225 2243 2483 4317  390 1033 3439 3075  ;; 1856
2524 1687  266  793 1440 2599  946  779  802  507  897 1081  528 2189 1292  711  ;; 1872
1866 1725 1167 1640  753  398 2661 1053  246  348 4318  137 1024 3440 1600 2077  ;; 1888
2129  825 4319  698  238  521  187 2300 1157 2423 1641 1605 1464 1610 1097 2541  ;; 1904
1260 1436  759 2255 1814 2150  705 3235  409 2563 3304  561 3033 2005 2564  726  ;; 1920
1956 2343 3698 4109  949 3812 3813 3520 1669  653 1379 2525  881 2198  632 2256  ;; 1936
1027  778 1074  733 1957  514 1481 2466  554 2180  702 3938 1606 1017 1398 6129  ;; 1952
1380 3521  921  993 1313  594  449 1489 1617 1166  768 1426 1360  495 1794 3601  ;; 1968
1177 3602 1170 4320 2344  476  425 3167 4635 3168 1424  401 2662 1171 3382 1998  ;; 1984
1089 4110  477 3169  474 6130 1909  596 2831 1842  494  693 1051 1028 1207 3076  ;; 2000
 606 2115  727 2790 1473 1115  743 3522  630  805 1532 4321 2021  366 1057  838  ;; 2016
 684 1114 2142 4322 2050 1492 1892 1808 2271 3814 2424 1971 1447 1373 3305 1090  ;; 2032
1536 3939 3523 3306 1455 2199  336  369 2331 1035  584 2393  902  718 2600 6131  ;; 2048
2753  463 2151 1149 1611 2467  715 1308 3124 1268  343 1413 3236 1517 1347 2663  ;; 2064
2093 3940 2022 1131 1553 2100 2941 1427 3441 2942 1323 2484 6132 1980  872 2368  ;; 2080
2441 2943  320 2369 2116 1082  679 1933 3941 2791 3815  625 1143 2023  422 2200  ;; 2096
3816 6133  730 1695  356 2257 1626 2301 2858 2637 1627 1778  937  883 2906 2693  ;; 2112
3002 1769 1086  400 1063 1325 3307 2792 4111 3077  456 2345 1046  747 6134 1524  ;; 2128
 884 1094 3383 1474 2164 1059  974 1688 2181 2258 1047  345 1665 1187  358  875  ;; 2144
3170  305  660 3524 2190 1334 1135 3171 1540 1649 2542 1527  927  968 2793  885  ;; 2160
1972 1850  482  500 2638 1218 1109 1085 2543 1654 2034  876   78 2287 1482 1277  ;; 2176
 861 1675 1083 1779  724 2754  454  397 1132 1612 2332  893  672 1237  257 2259  ;; 2192
2370  135 3384  337 2244  547  352  340  709 2485 1400  788 1138 2511  540  772  ;; 2208
1682 2260 2272 2544 2013 1843 1902 4636 1999 1562 2288 4637 2201 1403 1533  407  ;; 2224
 576 3308 1254 2071  978 3385  170  136 1201 3125 2664 3172 2394  213  912  873  ;; 2240
3603 1713 2202  699 3604 3699  813 3442  493  531 1054  468 2907 1483  304  281  ;; 2256
4112 1726 1252 2094  339 2319 2130 2639  756 1563 2944  748  571 2976 1588 2425  ;; 2272
2715 1851 1460 2426 1528 1392 1973 3237  288 3309  685 3386  296  892 2716 2216  ;; 2288
1570 2245  722 1747 2217  905 3238 1103 6135 1893 1441 1965  251 1805 2371 3700  ;; 2304
2601 1919 1078   75 2182 1509 1592 1270 2640 4638 2152 6136 3310 3817  524  706  ;; 2320
1075  292 3818 1756 2602  317   98 3173 3605 3525 1844 2218 3819 2502  814  567  ;; 2336
 385 2908 1534 6137  534 1642 3239  797 6138 1670 1529  953 4323  188 1071  538  ;; 2352
 178  729 3240 2109 1226 1374 2000 2357 2977  731 2468 1116 2014 2051 6139 1261  ;; 2368
1593  803 2859 2736 3443  556  682  823 1541 6140 1369 2289 1706 2794  845  462  ;; 2384
2603 2665 1361  387  162 2358 1740  739 1770 1720 1304 1401 3241 1049  627 1571  ;; 2400
2427 3526 1877 3942 1852 1500  431 1910 1503  677  297 2795  286 1433 1038 1198  ;; 2416
2290 1133 1596 4113 4639 2469 1510 1484 3943 6141 2442  108  712 4640 2372  866  ;; 2432
3701 2755 3242 1348  834 1945 1408 3527 2395 3243 1811  824  994 1179 2110 1548  ;; 2448
1453  790 3003  690 4324 4325 2832 2909 3820 1860 3821  225 1748  310  346 1780  ;; 2464
2470  821 1993 2717 2796  828  877 3528 2860 2471 1702 2165 2910 2486 1789  453  ;; 2480
 359 2291 1676   73 1164 1461 1127 3311  421  604  314 1037  589  116 2487  737  ;; 2496
 837 1180  111  244  735 6142 2261 1861 1362  986  523  418  581 2666 3822  103  ;; 2512
 855  503 1414 1867 2488 1091  657 1597  979  605 1316 4641 1021 2443 2078 2001  ;; 2528
1209   96  587 2166 1032  260 1072 2153  173   94  226 3244  819 2006 4642 4114  ;; 2544
2203  231 1744  782   97 2667  786 3387  887  391  442 2219 4326 1425 6143 2694  ;; 2560
 633 1544 1202  483 2015  592 2052 1958 2472 1655  419  129 4327 3444 3312 1714  ;; 2576
1257 3078 4328 1518 1098  865 1310 1019 1885 1512 1734  469 2444  148  773  436  ;; 2592
1815 1868 1128 1055 4329 1245 2756 3445 2154 1934 1039 4643  579 1238  932 2320  ;; 2608
 353  205  801  115 2428  944 2321 1881  399 2565 1211  678  766 3944  335 2101  ;; 2624
1459 1781 1402 3945 2737 2131 1010  844  981 1326 1013  550 1816 1545 2620 1335  ;; 2640
1008  371 2881  936 1419 1613 3529 1456 1395 2273 1834 2604 1317 2738 2503  416  ;; 2656
1643 4330  806 1126  229  591 3946 1314 1981 1576 1837 1666  347 1790  977 3313  ;; 2672
 764 2861 1853  688 2429 1920 1462   77  595  415 2002 3034  798 1192 4115 6144  ;; 2688
2978 4331 3035 2695 2582 2072 2566  430 2430 1727  842 1396 3947 3702  613  377  ;; 2704
 278  236 1417 3388 3314 3174  757 1869  107 3530 6145 1194  623 2262  207 1253  ;; 2720
2167 3446 3948  492 1117 1935  536 1838 2757 1246 4332  696 2095 2406 1393 1572  ;; 2736
3175 1782  583  190  253 1390 2230  830 3126 3389  934 3245 1703 1749 2979 1870  ;; 2752
2545 1656 2204  869 2346 4116 3176 1817  496 1764 4644  942 1504  404 1903 1122  ;; 2768
1580 3606 2945 1022  515  372 1735  955 2431 3036 6146 2797 1110 2302 2798  617  ;; 2784
6147  441  762 1771 3447 3607 3608 1904  840 3037   86  939 1385  572 1370 2445  ;; 2800
1336  114 3703  898  294  203 3315  703 1583 2274  429  961 4333 1854 1951 3390  ;; 2816
2373 3704 4334 1318 1381  966 1911 2322 1006 1155  309  989  458 2718 1795 1372  ;; 2832
1203  252 1689 1363 3177  517 1936  168 1490  562  193 3823 1042 4117 1835  551  ;; 2848
 470 4645  395  489 3448 1871 1465 2583 2641  417 1493  279 1295  511 1236 1119  ;; 2864
  72 1231 1982 1812 3004  871 1564  984 3449 1667 2696 2096 4646 2347 2833 1673  ;; 2880
3609  695 3246 2668  807 1183 4647  890  388 2333 1801 1457 2911 1765 1477 1031  ;; 2896
3316 3317 1278 3391 2799 2292 2526  163 3450 4335 2669 1404 1802 6148 2323 2407  ;; 2912
1584 1728 1494 1824 1269  298  909 3318 1034 1632  375  776 1683 2061  291  210  ;; 2928
1123  809 1249 1002 2642 3038  206 1011 2132  144  975  882 1565  342  667  754  ;; 2944
1442 2143 1299 2303 2062  447  626 2205 1221 2739 2912 1144 1214 2206 2584  760  ;; 2960
1715  614  950 1281 2670 2621  810  577 1287 2546 4648  242 2168  250 2643  691  ;; 2976
 123 2644  647  313 1029  689 1357 2946 1650  216  771 1339 1306  808 2063  549  ;; 2992
 913 1371 2913 2914 6149 1466 1092 1174 1196 1311 2605 2396 1783 1796 3079  406  ;; 3008
2671 2117 3949 4649  487 1825 2220 6150 2915  448 2348 1073 6151 2397 1707  130  ;; 3024
 900 1598  329  176 1959 2527 1620 6152 2275 4336 3319 1983 2191 3705 3610 2155  ;; 3040
3706 1912 1513 1614 6153 1988  646  392 2304 1589 3320 3039 1826 1239 1352 1340  ;; 3056
2916  505 2567 1709 1437 2408 2547  906 6154 2672  384 1458 1594 1100 1329  710  ;; 3072
 423 3531 2064 2231 2622 1989 2673 1087 1882  333  841 3005 1296 2882 2379  580  ;; 3088
1937 1827 1293 2585  601  574  249 1772 4118 2079 1120  645  901 1176 1690  795  ;; 3104
2207  478 1434  516 1190 1530  761 2080  930 1264  355  435 1552  644 1791  987  ;; 3120
 220 1364 1163 1121 1538  306 2169 1327 1222  546 2645  218  241  610 1704 3321  ;; 3136
1984 1839 1966 2528  451 6155 2586 3707 2568  907 3178  254 2947  186 1845 4650  ;; 3152
 745  432 1757  428 1633  888 2246 2221 2489 3611 2118 1258 1265  956 3127 1784  ;; 3168
4337 2490  319  510  119  457 3612  274 2035 2007 4651 1409 3128  970 2758  590  ;; 3184
2800  661 2247 4652 2008 3950 1420 1549 3080 3322 3951 1651 1375 2111  485 2491  ;; 3200
1429 1156 6156 2548 2183 1495  831 1840 2529 2446  501 1657  307 1894 3247 1341  ;; 3216
 666  899 2156 1539 2549 1559  886  349 2208 3081 2305 1736 3824 2170 2759 1014  ;; 3232
1913 1386  542 1397 2948  490  368  716  362  159  282 2569 1129 1658 1288 1750  ;; 3248
2674  276  649 2016  751 1496  658 1818 1284 1862 2209 2087 2512 3451  622 2834  ;; 3264
 376  117 1060 2053 1208 1721 1101 1443  247 1250 3179 1792 3952 2760 2398 3953  ;; 3280
6157 2144 3708  446 2432 1151 2570 3452 2447 2761 2835 1210 2448 3082  424 2222  ;; 3296
1251 2449 2119 2836  504 1581 4338  602  817  857 3825 2349 2306  357 3826 1470  ;; 3312
1883 2883  255  958  929 2917 3248  302 4653 1050 1271 1751 2307 1952 1430 2697  ;; 3328
2719 2359  354 3180  777  158 2036 4339 1659 4340 4654 2308 2949 2248 1146 2232  ;; 3344
3532 2720 1696 2623 3827 6158 3129 1550 2698 1485 1297 1428  637  931 2721 2145  ;; 3360
 914 2550 2587   81 2450  612  827 2646 1242 4655 1118 2884  472 1855 3181 3533  ;; 3376
3534  569 1353 2699 1244 1758 2588 4119 2009 2762 2171 3709 1312 1531 6159 1152  ;; 3392
1938  134 1830  471 3710 2276 1112 1535 3323 3453 3535  982 1337 2950  488  826  ;; 3408
 674 1058 1628 4120 2017  522 2399  211  568 1367 3454  350  293 1872 1139 3249  ;; 3424
1399 1946 3006 1300 2360 3324  588  736 6160 2606  744  669 3536 3828 6161 1358  ;; 3440
 199  723  848  933  851 1939 1505 1514 1338 1618 1831 4656 1634 3613  443 2740  ;; 3456
3829  717 1947  491 1914 6162 2551 1542 4121 1025 6163 1099 1223  198 3040 2722  ;; 3472
 370  410 1905 2589  998 1248 3182 2380  519 1449 4122 1710  947  928 1153 4341  ;; 3488
2277  344 2624 1511  615  105  161 1212 1076 1960 3130 2054 1926 1175 1906 2473  ;; 3504
 414 1873 2801 6164 2309  315 1319 3325  318 2018 2146 2157  963  631  223 4342  ;; 3520
4343 2675  479 3711 1197 2625 3712 2676 2361 6165 4344 4123 6166 2451 3183 1886  ;; 3536
2184 1674 1330 1711 1635 1506  799  219 3250 3083 3954 1677 3713 3326 2081 3614  ;; 3552
1652 2073 4657 1147 3041 1752  643 1961  147 1974 3955 6167 1716 2037  918 3007  ;; 3568
1994  120 1537  118  609 3184 4345  740 3455 1219  332 1615 3830 6168 1621 2980  ;; 3584
1582  783  212  553 2350 3714 1349 2433 2082 4124  889 6169 2310 1275 1410  973  ;; 3600
 166 1320 3456 1797 1215 3185 2885 1846 2590 2763 4658  629  822 3008  763  940  ;; 3616
1990 2862  439 2409 1566 1240 1622  926 1282 1907 2764  654 2210 1607  327 1130  ;; 3632
3956 1678 1623 6170 2434 2192  686  608 3831 3715  903 3957 3042 6171 2741 1522  ;; 3648
1915 1105 1555 2552 1359  323 3251 4346 3457  738 1354 2553 2311 2334 1828 2003  ;; 3664
3832 1753 2351 1227 6172 1887 4125 1478 6173 2410 1874 1712 1847  520 1204 2607  ;; 3680
 264 4659  836 2677 2102  600 4660 3833 2278 3084 6174 4347 3615 1342  640  532  ;; 3696
 543 2608 1888 2400 2591 1009 4348 1497  341 1737 3616 2723 1394  529 3252 1321  ;; 3712
 983 4661 1515 2120  971 2592  924  287 1662 3186 4349 2700 4350 1519  908 1948  ;; 3728
2452  156  796 1629 1486 2223 2055  694 4126 1259 1036 3392 1213 2249 2742 1889  ;; 3744
1230 3958 1015  910  408  559 3617 4662  746  725  935 4663 3959 3009 1289  563  ;; 3760
 867 4664 3960 1567 2981 2038 2626  988 2263 2381 4351  143 2374  704 1895 6175  ;; 3776
1188 3716 2088  673 3085 2362 4352  484 1608 1921 2765 2918  215  904 3618 3537  ;; 3792
 894  509  976 3043 2701 3961 4353 2837 2982  498 6176 6177 1102 3538 1332 3393  ;; 3808
1487 1636 1637  233  245 3962  383  650  995 3044  460 1520 1206 2352  749 3327  ;; 3824
 530  700  389 1438 1560 1773 3963 2264  719 2951 2724 3834  870 1832 1644 1000  ;; 3840
 839 2474 3717  197 1630 3394  365 2886 3964 1285 2133  734  922  818 1106  732  ;; 3856
 480 2083 1774 3458  923 2279 1350  221 3086   85 2233 2234 3835 1585 3010 2147  ;; 3872
1387 1705 2382 1619 2475  133  239 2802 1991 1016 2084 2383  411 2838 1113  651  ;; 3888
1985 1160 3328  990 1863 3087 1048 1276 2647  265 2627 1599 3253 2056  150  638  ;; 3904
2019  656  853  326 1479  680 1439 4354 1001 1759  413 3459 3395 2492 1431  459  ;; 3920
4355 1125 3329 2265 1953 1450 2065 2863  849  351 2678 3131 3254 3255 1104 1577  ;; 3936
 227 1351 1645 2453 2193 1421 2887  812 2121  634   95 2435  201 2312 4665 1646  ;; 3952
1671 2743 1601 2554 2702 2648 2280 1315 1366 2089 3132 1573 3718 3965 1729 1189  ;; 3968
 328 2679 1077 1940 1136  558 1283  964 1195  621 2074 1199 1743 3460 3619 1896  ;; 3984
1916 1890 3836 2952 1154 2112 1064  862  378 3011 2066 2113 2803 1568 2839 6178  ;; 4000
3088 2919 1941 1660 2004 1992 2194  142  707 1590 1708 1624 1922 1023 1836 1233  ;; 4016
1004 2313  789  741 3620 6179 1609 2411 1200 4127 3719 3720 4666 2057 3721  593  ;; 4032
2840  367 2920 1878 6180 3461 1521  628 1168  692 2211 2649  300  720 2067 2571  ;; 4048
2953 3396  959 2504 3966 3539 3462 1977  701 6181  954 1043  800  681  183 3722  ;; 4064
1803 1730 3540 4128 2103  815 2314  174  467  230 2454 1093 2134  755 3541 3397  ;; 4080
1141 1162 6182 1738 2039  270 3256 2513 1005 1647 2185 3837  858 1679 1897 1719  ;; 4096
2954 2324 1806  402  670  167 4129 1498 2158 2104  750 6183  915  189 1680 1551  ;; 4112
 455 4356 1501 2455  405 1095 2955  338 1586 1266 1819  570  641 1324  237 1556  ;; 4128
2650 1388 3723 6184 1368 2384 1343 1978 3089 2436  879 3724  792 1191  758 3012  ;; 4144
1411 2135 1322 4357  240 4667 1848 3725 1574 6185  420 3045 1546 1391  714 4358  ;; 4160
1967  941 1864  863  664  426  560 1731 2680 1785 2864 1949 2363  403 3330 1415  ;; 4176
1279 2136 1697 2335  204  721 2097 3838   90 6186 2085 2505  191 3967  124 2148  ;; 4192
1376 1798 1178 1107 1898 1405  860 4359 1243 1272 2375 2983 1558 2456 1638  113  ;; 4208
3621  578 1923 2609  880  386 4130  784 2186 2266 1422 2956 2172 1722  497  263  ;; 4224
2514 1267 2412 2610  177 2703 3542  774 1927 1344  616 1432 1595 1018  172 4360  ;; 4240
2325  911 4361  438 1468 3622  794 3968 2024 2173 1681 1829 2957  945  895 3090  ;; 4256
 575 2212 2476  475 2401 2681  785 2744 1745 2293 2555 1975 3133 2865  394 4668  ;; 4272
3839  635 4131  639  202 1507 2195 2766 1345 1435 2572 3726 1908 1184 1181 2457  ;; 4288
3727 3134 4362  843 2611  437  916 4669  234  769 1884 3046 3047 3623  833 6187  ;; 4304
1639 2250 2402 1355 1185 2010 2047  999  525 1732 1290 1488 2612  948 1578 3728  ;; 4320
2413 2477 1216 2725 2159  334 3840 1328 3624 2921 1525 4132  564 1056  891 4363  ;; 4336
1444 1698 2385 2251 3729 1365 2281 2235 1717 6188  864 3841 2515  444  527 2767  ;; 4352
2922 3625  544  461 6189  566  209 2437 3398 2098 1065 2068 3331 3626 3257 2137  ;; 4368  ;;last 512
])


;; euc-kr freq table

;;Sampling from about 20M text materials include literature and computer technology

;;******************************************************************************
;; * 128  --> 0.79
;; * 256  --> 0.92
;; * 512  --> 0.986
;; * 1024 --> 0.99944
;; * 2048 --> 0.99999
;; *
;; * Idea Distribution Ratio = 0.98653 / (1-0.98653) = 73.24
;; * Random Distribution Ration = 512 / (2350-512) = 0.279.
;; * 
;; * Typical Distribution Ratio  
;; *****************************************************************************/

(setq EUCKR_DIST_RATIO  6.0)

(setq EUCKR_TABLE_SIZE  2352)

;;Char to FreqOrder table , 
(setq EUCKRCharToFreqOrder
[
  13  130  120 1396  481 1719 1720  328  609  212 1721  707  400  299 1722   87 
1397 1723  104  536 1117 1203 1724 1267  685 1268  508 1725 1726 1727 1728 1398 
1399 1729 1730 1731  141  621  326 1057  368 1732  267  488   20 1733 1269 1734 
 945 1400 1735   47  904 1270 1736 1737  773  248 1738  409  313  786  429 1739 
 116  987  813 1401  683   75 1204  145 1740 1741 1742 1743   16  847  667  622 
 708 1744 1745 1746  966  787  304  129 1747   60  820  123  676 1748 1749 1750 
1751  617 1752  626 1753 1754 1755 1756  653 1757 1758 1759 1760 1761 1762  856 
 344 1763 1764 1765 1766   89  401  418  806  905  848 1767 1768 1769  946 1205 
 709 1770 1118 1771  241 1772 1773 1774 1271 1775  569 1776  999 1777 1778 1779 
1780  337  751 1058   28  628  254 1781  177  906  270  349  891 1079 1782   19 
1783  379 1784  315 1785  629  754 1402  559 1786  636  203 1206 1787  710  567 
1788  935  814 1789 1790 1207  766  528 1791 1792 1208 1793 1794 1795 1796 1797 
1403 1798 1799  533 1059 1404 1405 1156 1406  936  884 1080 1800  351 1801 1802 
1803 1804 1805  801 1806 1807 1808 1119 1809 1157  714  474 1407 1810  298  899 
 885 1811 1120  802 1158 1812  892 1813 1814 1408  659 1815 1816 1121 1817 1818 
1819 1820 1821 1822  319 1823  594  545 1824  815  937 1209 1825 1826  573 1409 
1022 1827 1210 1828 1829 1830 1831 1832 1833  556  722  807 1122 1060 1834  697 
1835  900  557  715 1836 1410  540 1411  752 1159  294  597 1211  976  803  770 
1412 1837 1838   39  794 1413  358 1839  371  925 1840  453  661  788  531  723 
 544 1023 1081  869   91 1841  392  430  790  602 1414  677 1082  457 1415 1416 
1842 1843  475  327 1024 1417  795  121 1844  733  403 1418 1845 1846 1847  300 
 119  711 1212  627 1848 1272  207 1849 1850  796 1213  382 1851  519 1852 1083 
 893 1853 1854 1855  367  809  487  671 1856  663 1857 1858  956  471  306  857 
1859 1860 1160 1084 1861 1862 1863 1864 1865 1061 1866 1867 1868 1869 1870 1871 
 282   96  574 1872  502 1085 1873 1214 1874  907 1875 1876  827  977 1419 1420 
1421  268 1877 1422 1878 1879 1880  308 1881    2  537 1882 1883 1215 1884 1885 
 127  791 1886 1273 1423 1887   34  336  404  643 1888  571  654  894  840 1889 
   0  886 1274  122  575  260  908  938 1890 1275  410  316 1891 1892  100 1893 
1894 1123   48 1161 1124 1025 1895  633  901 1276 1896 1897  115  816 1898  317 
1899  694 1900  909  734 1424  572  866 1425  691   85  524 1010  543  394  841 
1901 1902 1903 1026 1904 1905 1906 1907 1908 1909   30  451  651  988  310 1910 
1911 1426  810 1216   93 1912 1913 1277 1217 1914  858  759   45   58  181  610 
 269 1915 1916  131 1062  551  443 1000  821 1427  957  895 1086 1917 1918  375 
1919  359 1920  687 1921  822 1922  293 1923 1924   40  662  118  692   29  939 
 887  640  482  174 1925   69 1162  728 1428  910 1926 1278 1218 1279  386  870 
 217  854 1163  823 1927 1928 1929 1930  834 1931   78 1932  859 1933 1063 1934 
1935 1936 1937  438 1164  208  595 1938 1939 1940 1941 1219 1125 1942  280  888 
1429 1430 1220 1431 1943 1944 1945 1946 1947 1280  150  510 1432 1948 1949 1950 
1951 1952 1953 1954 1011 1087 1955 1433 1043 1956  881 1957  614  958 1064 1065 
1221 1958  638 1001  860  967  896 1434  989  492  553 1281 1165 1959 1282 1002 
1283 1222 1960 1961 1962 1963   36  383  228  753  247  454 1964  876  678 1965 
1966 1284  126  464  490  835  136  672  529  940 1088 1435  473 1967 1968  467 
  50  390  227  587  279  378  598  792  968  240  151  160  849  882 1126 1285 
 639 1044  133  140  288  360  811  563 1027  561  142  523 1969 1970 1971    7 
 103  296  439  407  506  634  990 1972 1973 1974 1975  645 1976 1977 1978 1979 
1980 1981  236 1982 1436 1983 1984 1089  192  828  618  518 1166  333 1127 1985 
 818 1223 1986 1987 1988 1989 1990 1991 1992 1993  342 1128 1286  746  842 1994 
1995  560  223 1287   98    8  189  650  978 1288 1996 1437 1997   17  345  250 
 423  277  234  512  226   97  289   42  167 1998  201 1999 2000  843  836  824 
 532  338  783 1090  182  576  436 1438 1439  527  500 2001  947  889 2002 2003 
2004 2005  262  600  314  447 2006  547 2007  693  738 1129 2008   71 1440  745 
 619  688 2009  829 2010 2011  147 2012   33  948 2013 2014   74  224 2015   61 
 191  918  399  637 2016 1028 1130  257  902 2017 2018 2019 2020 2021 2022 2023 
2024 2025 2026  837 2027 2028 2029 2030  179  874  591   52  724  246 2031 2032 
2033 2034 1167  969 2035 1289  630  605  911 1091 1168 2036 2037 2038 1441  912 
2039  623 2040 2041  253 1169 1290 2042 1442  146  620  611  577  433 2043 1224 
 719 1170  959  440  437  534   84  388  480 1131  159  220  198  679 2044 1012 
 819 1066 1443  113 1225  194  318 1003 1029 2045 2046 2047 2048 1067 2049 2050 
2051 2052 2053   59  913  112 2054  632 2055  455  144  739 1291 2056  273  681 
 499 2057  448 2058 2059  760 2060 2061  970  384  169  245 1132 2062 2063  414 
1444 2064 2065   41  235 2066  157  252  877  568  919  789  580 2067  725 2068 
2069 1292 2070 2071 1445 2072 1446 2073 2074   55  588   66 1447  271 1092 2075 
1226 2076  960 1013  372 2077 2078 2079 2080 2081 1293 2082 2083 2084 2085  850 
2086 2087 2088 2089 2090  186 2091 1068  180 2092 2093 2094  109 1227  522  606 
2095  867 1448 1093  991 1171  926  353 1133 2096  581 2097 2098 2099 1294 1449 
1450 2100  596 1172 1014 1228 2101 1451 1295 1173 1229 2102 2103 1296 1134 1452 
 949 1135 2104 2105 1094 1453 1454 1455 2106 1095 2107 2108 2109 2110 2111 2112 
2113 2114 2115 2116 2117  804 2118 2119 1230 1231  805 1456  405 1136 2120 2121 
2122 2123 2124  720  701 1297  992 1457  927 1004 2125 2126 2127 2128 2129 2130 
  22  417 2131  303 2132  385 2133  971  520  513 2134 1174   73 1096  231  274 
 962 1458  673 2135 1459 2136  152 1137 2137 2138 2139 2140 1005 1138 1460 1139 
2141 2142 2143 2144   11  374  844 2145  154 1232   46 1461 2146  838  830  721 
1233  106 2147   90  428  462  578  566 1175  352 2148 2149  538 1234  124 1298 
2150 1462  761  565 2151  686 2152  649 2153   72  173 2154  460  415 2155 1463 
2156 1235  305 2157 2158 2159 2160 2161 2162  579 2163 2164 2165 2166 2167  747 
2168 2169 2170 2171 1464  669 2172 2173 2174 2175 2176 1465 2177   23  530  285 
2178  335  729 2179  397 2180 2181 2182 1030 2183 2184  698 2185 2186  325 2187 
2188  369 2189  799 1097 1015  348 2190 1069  680 2191  851 1466 2192 2193   10 
2194  613  424 2195  979  108  449  589   27  172   81 1031   80  774  281  350 
1032  525  301  582 1176 2196  674 1045 2197 2198 1467  730  762 2199 2200 2201 
2202 1468 2203  993 2204 2205  266 1070  963 1140 2206 2207 2208  664 1098  972 
2209 2210 2211 1177 1469 1470  871 2212 2213 2214 2215 2216 1471 2217 2218 2219 
2220 2221 2222 2223 2224 2225 2226 2227 1472 1236 2228 2229 2230 2231 2232 2233 
2234 2235 1299 2236 2237  200 2238  477  373 2239 2240  731  825  777 2241 2242 
2243  521  486  548 2244 2245 2246 1473 1300   53  549  137  875   76  158 2247 
1301 1474  469  396 1016  278  712 2248  321  442  503  767  744  941 1237 1178 
1475 2249   82  178 1141 1179  973 2250 1302 2251  297 2252 2253  570 2254 2255 
2256   18  450  206 2257  290  292 1142 2258  511  162   99  346  164  735 2259 
1476 1477    4  554  343  798 1099 2260 1100 2261   43  171 1303  139  215 2262 
2263  717  775 2264 1033  322  216 2265  831 2266  149 2267 1304 2268 2269  702 
1238  135  845  347  309 2270  484 2271  878  655  238 1006 1478 2272   67 2273 
 295 2274 2275  461 2276  478  942  412 2277 1034 2278 2279 2280  265 2281  541 
2282 2283 2284 2285 2286   70  852 1071 2287 2288 2289 2290   21   56  509  117 
 432 2291 2292  331  980  552 1101  148  284  105  393 1180 1239  755 2293  187 
2294 1046 1479 2295  340 2296   63 1047  230 2297 2298 1305  763 1306  101  800 
 808  494 2299 2300 2301  903 2302   37 1072   14    5 2303   79  675 2304  312 
2305 2306 2307 2308 2309 1480    6 1307 2310 2311 2312    1  470   35   24  229 
2313  695  210   86  778   15  784  592  779   32   77  855  964 2314  259 2315 
 501  380 2316 2317   83  981  153  689 1308 1481 1482 1483 2318 2319  716 1484 
2320 2321 2322 2323 2324 2325 1485 2326 2327  128   57   68  261 1048  211  170 
1240   31 2328   51  435  742 2329 2330 2331  635 2332  264  456 2333 2334 2335 
 425 2336 1486  143  507  263  943 2337  363  920 1487  256 1488 1102  243  601 
1489 2338 2339 2340 2341 2342 2343 2344  861 2345 2346 2347 2348 2349 2350  395 
2351 1490 1491   62  535  166  225 2352 2353  668  419 1241  138  604  928 2354 
1181 2355 1492 1493 2356 2357 2358 1143 2359  696 2360  387  307 1309  682  476 
2361 2362  332   12  222  156 2363  232 2364  641  276  656  517 1494 1495 1035 
 416  736 1496 2365 1017  586 2366 2367 2368 1497 2369  242 2370 2371 2372 1498 
2373  965  713 2374 2375 2376 2377  740  982 1499  944 1500 1007 2378 2379 1310 
1501 2380 2381 2382  785  329 2383 2384 1502 2385 2386 2387  932 2388 1503 2389 
2390 2391 2392 1242 2393 2394 2395 2396 2397  994  950 2398 2399 2400 2401 1504 
1311 2402 2403 2404 2405 1049  749 2406 2407  853  718 1144 1312 2408 1182 1505 
2409 2410  255  516  479  564  550  214 1506 1507 1313  413  239  444  339 1145 
1036 1508 1509 1314 1037 1510 1315 2411 1511 2412 2413 2414  176  703  497  624 
 593  921  302 2415  341  165 1103 1512 2416 1513 2417 2418 2419  376 2420  700 
2421 2422 2423  258  768 1316 2424 1183 2425  995  608 2426 2427 2428 2429  221 
2430 2431 2432 2433 2434 2435 2436 2437  195  323  726  188  897  983 1317  377 
 644 1050  879 2438  452 2439 2440 2441 2442 2443 2444  914 2445 2446 2447 2448 
 915  489 2449 1514 1184 2450 2451  515   64  427  495 2452  583 2453  483  485 
1038  562  213 1515  748  666 2454 2455 2456 2457  334 2458  780  996 1008  705 
1243 2459 2460 2461 2462 2463  114 2464  493 1146  366  163 1516  961 1104 2465 
 291 2466 1318 1105 2467 1517  365 2468  355  951 1244 2469 1319 2470  631 2471 
2472  218 1320  364  320  756 1518 1519 1321 1520 1322 2473 2474 2475 2476  997 
2477 2478 2479 2480  665 1185 2481  916 1521 2482 2483 2484  584  684 2485 2486 
 797 2487 1051 1186 2488 2489 2490 1522 2491 2492  370 2493 1039 1187   65 2494 
 434  205  463 1188 2495  125  812  391  402  826  699  286  398  155  781  771 
 585 2496  590  505 1073 2497  599  244  219  917 1018  952  646 1523 2498 1323 
2499 2500   49  984  354  741 2501  625 2502 1324 2503 1019  190  357  757  491 
  95  782  868 2504 2505 2506 2507 2508 2509  134 1524 1074  422 1525  898 2510 
 161 2511 2512 2513 2514  769 2515 1526 2516 2517  411 1325 2518  472 1527 2519 
2520 2521 2522 2523 2524  985 2525 2526 2527 2528 2529 2530  764 2531 1245 2532 
2533   25  204  311 2534  496 2535 1052 2536 2537 2538 2539 2540 2541 2542  199 
 704  504  468  758  657 1528  196   44  839 1246  272  750 2543  765  862 2544 
2545 1326 2546  132  615  933 2547  732 2548 2549 2550 1189 1529 2551  283 1247 
1053  607  929 2552 2553 2554  930  183  872  616 1040 1147 2555 1148 1020  441 
 249 1075 2556 2557 2558  466  743 2559 2560 2561   92  514  426  420  526 2562 
2563 2564 2565 2566 2567 2568  185 2569 2570 2571 2572  776 1530  658 2573  362 
2574  361  922 1076  793 2575 2576 2577 2578 2579 2580 1531  251 2581 2582 2583 
2584 1532   54  612  237 1327 2585 2586  275  408  647  111 2587 1533 1106  465 
   3  458    9   38 2588  107  110  890  209   26  737  498 2589 1534 2590  431 
 202   88 1535  356  287 1107  660 1149 2591  381 1536  986 1150  445 1248 1151 
 974 2592 2593  846 2594  446  953  184 1249 1250  727 2595  923  193  883 2596 
2597 2598  102  324  539  817 2599  421 1041 2600  832 2601   94  175  197  406 
2602  459 2603 2604 2605 2606 2607  330  555 2608 2609 2610  706 1108  389 2611 
2612 2613 2614  233 2615  833  558  931  954 1251 2616 2617 1537  546 2618 2619 
1009 2620 2621 2622 1538  690 1328 2623  955 2624 1539 2625 2626  772 2627 2628 
2629 2630 2631  924  648  863  603 2632 2633  934 1540  864  865 2634  642 1042 
 670 1190 2635 2636 2637 2638  168 2639  652  873  542 1054 1541 2640 2641 2642   ;;512  256
])



;; EUCTW frequency table
;; Converted from big5 work 
;; by Taiwan's Mandarin Promotion Council 
;; <http://www.edu.tw:81/mandr/>


;;******************************************************************************
;; * 128  --> 0.42261
;; * 256  --> 0.57851
;; * 512  --> 0.74851
;; * 1024 --> 0.89384
;; * 2048 --> 0.97583
;; *
;; * Idea Distribution Ratio = 0.74851/(1-0.74851) =2.98
;; * Random Distribution Ration = 512/(5401-512)=0.105
;; * 
;; * Typical Distribution Ratio about 25% of Ideal one, still much higher than RDR
;; *****************************************************************************/

(setq EUCTW_DIST_RATIO 0.75)

;;Char to FreqOrder table , 
(setq EUCTW_TABLE_SIZE  8102)

(setq EUCTWCharToFreqOrder
[
   1 1800 1506  255 1431  198    9   82    6 7310  177  202 3615 1256 2808  110  ;; 2742
3735   33 3241  261   76   44 2113   16 2931 2184 1176  659 3868   26 3404 2643  ;; 2758
1198 3869 3313 4060  410 2211  302  590  361 1963    8  204   58 4296 7311 1931  ;; 2774
  63 7312 7313  317 1614   75  222  159 4061 2412 1480 7314 3500 3068  224 2809  ;; 2790
3616    3   10 3870 1471   29 2774 1135 2852 1939  873  130 3242 1123  312 7315  ;; 2806
4297 2051  507  252  682 7316  142 1914  124  206 2932   34 3501 3173   64  604  ;; 2822
7317 2494 1976 1977  155 1990  645  641 1606 7318 3405  337   72  406 7319   80  ;; 2838
 630  238 3174 1509  263  939 1092 2644  756 1440 1094 3406  449   69 2969  591  ;; 2854
 179 2095  471  115 2034 1843   60   50 2970  134  806 1868  734 2035 3407  180  ;; 2870
 995 1607  156  537 2893  688 7320  319 1305  779 2144  514 2374  298 4298  359  ;; 2886
2495   90 2707 1338  663   11  906 1099 2545   20 2436  182  532 1716 7321  732  ;; 2902
1376 4062 1311 1420 3175   25 2312 1056  113  399  382 1949  242 3408 2467  529  ;; 2918
3243  475 1447 3617 7322  117   21  656  810 1297 2295 2329 3502 7323  126 4063  ;; 2934
 706  456  150  613 4299   71 1118 2036 4064  145 3069   85  835  486 2114 1246  ;; 2950
1426  428  727 1285 1015  800  106  623  303 1281 7324 2127 2354  347 3736  221  ;; 2966
3503 3110 7325 1955 1153 4065   83  296 1199 3070  192  624   93 7326  822 1897  ;; 2982
2810 3111  795 2064  991 1554 1542 1592   27   43 2853  859  139 1456  860 4300  ;; 2998
 437  712 3871  164 2392 3112  695  211 3017 2096  195 3872 1608 3504 3505 3618  ;; 3014
3873  234  811 2971 2097 3874 2229 1441 3506 1615 2375  668 2076 1638  305  228  ;; 3030
1664 4301  467  415 7327  262 2098 1593  239  108  300  200 1033  512 1247 2077  ;; 3046
7328 7329 2173 3176 3619 2673  593  845 1062 3244   88 1723 2037 3875 1950  212  ;; 3062
 266  152  149  468 1898 4066 4302   77  187 7330 3018   37    5 2972 7331 3876  ;; 3078
7332 7333   39 2517 4303 2894 3177 2078   55  148   74 4304  545  483 1474 1029  ;; 3094
1665  217 1869 1531 3113 1104 2645 4067   24  172 3507  900 3877 3508 3509 4305  ;; 3110
  32 1408 2811 1312  329  487 2355 2247 2708  784 2674    4 3019 3314 1427 1788  ;; 3126
 188  109  499 7334 3620 1717 1789  888 1217 3020 4306 7335 3510 7336 3315 1520  ;; 3142
3621 3878  196 1034  775 7337 7338  929 1815  249  439   38 7339 1063 7340  794  ;; 3158
3879 1435 2296   46  178 3245 2065 7341 2376 7342  214 1709 4307  804   35  707  ;; 3174
 324 3622 1601 2546  140  459 4068 7343 7344 1365  839  272  978 2257 2572 3409  ;; 3190
2128 1363 3623 1423  697  100 3071   48   70 1231  495 3114 2193 7345 1294 7346  ;; 3206
2079  462  586 1042 3246  853  256  988  185 2377 3410 1698  434 1084 7347 3411  ;; 3222
 314 2615 2775 4308 2330 2331  569 2280  637 1816 2518  757 1162 1878 1616 3412  ;; 3238
 287 1577 2115  768 4309 1671 2854 3511 2519 1321 3737  909 2413 7348 4069  933  ;; 3254
3738 7349 2052 2356 1222 4310  765 2414 1322  786 4311 7350 1919 1462 1677 2895  ;; 3270
1699 7351 4312 1424 2437 3115 3624 2590 3316 1774 1940 3413 3880 4070  309 1369  ;; 3286
1130 2812  364 2230 1653 1299 3881 3512 3882 3883 2646  525 1085 3021  902 2000  ;; 3302
1475  964 4313  421 1844 1415 1057 2281  940 1364 3116  376 4314 4315 1381    7  ;; 3318
2520  983 2378  336 1710 2675 1845  321 3414  559 1131 3022 2742 1808 1132 1313  ;; 3334
 265 1481 1857 7352  352 1203 2813 3247  167 1089  420 2814  776  792 1724 3513  ;; 3350
4071 2438 3248 7353 4072 7354  446  229  333 2743  901 3739 1200 1557 4316 2647  ;; 3366
1920  395 2744 2676 3740 4073 1835  125  916 3178 2616 4317 7355 7356 3741 7357  ;; 3382
7358 7359 4318 3117 3625 1133 2547 1757 3415 1510 2313 1409 3514 7360 2145  438  ;; 3398
2591 2896 2379 3317 1068  958 3023  461  311 2855 2677 4074 1915 3179 4075 1978  ;; 3414
 383  750 2745 2617 4076  274  539  385 1278 1442 7361 1154 1964  384  561  210  ;; 3430
  98 1295 2548 3515 7362 1711 2415 1482 3416 3884 2897 1257  129 7363 3742  642  ;; 3446
 523 2776 2777 2648 7364  141 2231 1333   68  176  441  876  907 4077  603 2592  ;; 3462
 710  171 3417  404  549   18 3118 2393 1410 3626 1666 7365 3516 4319 2898 4320  ;; 3478
7366 2973  368 7367  146  366   99  871 3627 1543  748  807 1586 1185   22 2258  ;; 3494
 379 3743 3180 7368 3181  505 1941 2618 1991 1382 2314 7369  380 2357  218  702  ;; 3510
1817 1248 3418 3024 3517 3318 3249 7370 2974 3628  930 3250 3744 7371   59 7372  ;; 3526
 585  601 4078  497 3419 1112 1314 4321 1801 7373 1223 1472 2174 7374  749 1836  ;; 3542
 690 1899 3745 1772 3885 1476  429 1043 1790 2232 2116  917 4079  447 1086 1629  ;; 3558
7375  556 7376 7377 2020 1654  844 1090  105  550  966 1758 2815 1008 1782  686  ;; 3574
1095 7378 2282  793 1602 7379 3518 2593 4322 4080 2933 2297 4323 3746  980 2496  ;; 3590
 544  353  527 4324  908 2678 2899 7380  381 2619 1942 1348 7381 1341 1252  560  ;; 3606
3072 7382 3420 2856 7383 2053  973  886 2080  143 4325 7384 7385  157 3886  496  ;; 3622
4081   57  840  540 2038 4326 4327 3421 2117 1445  970 2259 1748 1965 2081 4082  ;; 3638
3119 1234 1775 3251 2816 3629  773 1206 2129 1066 2039 1326 3887 1738 1725 4083  ;; 3654
 279 3120   51 1544 2594  423 1578 2130 2066  173 4328 1879 7386 7387 1583  264  ;; 3670
 610 3630 4329 2439  280  154 7388 7389 7390 1739  338 1282 3073  693 2857 1411  ;; 3686
1074 3747 2440 7391 4330 7392 7393 1240  952 2394 7394 2900 1538 2679  685 1483  ;; 3702
4084 2468 1436  953 4085 2054 4331  671 2395   79 4086 2441 3252  608  567 2680  ;; 3718
3422 4087 4088 1691  393 1261 1791 2396 7395 4332 7396 7397 7398 7399 1383 1672  ;; 3734
3748 3182 1464  522 1119  661 1150  216  675 4333 3888 1432 3519  609 4334 2681  ;; 3750
2397 7400 7401 7402 4089 3025    0 7403 2469  315  231 2442  301 3319 4335 2380  ;; 3766
7404  233 4090 3631 1818 4336 4337 7405   96 1776 1315 2082 7406  257 7407 1809  ;; 3782
3632 2709 1139 1819 4091 2021 1124 2163 2778 1777 2649 7408 3074  363 1655 3183  ;; 3798
7409 2975 7410 7411 7412 3889 1567 3890  718  103 3184  849 1443  341 3320 2934  ;; 3814
1484 7413 1712  127   67  339 4092 2398  679 1412  821 7414 7415  834  738  351  ;; 3830
2976 2146  846  235 1497 1880  418 1992 3749 2710  186 1100 2147 2746 3520 1545  ;; 3846
1355 2935 2858 1377  583 3891 4093 2573 2977 7416 1298 3633 1078 2549 3634 2358  ;; 3862
  78 3750 3751  267 1289 2099 2001 1594 4094  348  369 1274 2194 2175 1837 4338  ;; 3878
1820 2817 3635 2747 2283 2002 4339 2936 2748  144 3321  882 4340 3892 2749 3423  ;; 3894
4341 2901 7417 4095 1726  320 7418 3893 3026  788 2978 7419 2818 1773 1327 2859  ;; 3910
3894 2819 7420 1306 4342 2003 1700 3752 3521 2359 2650  787 2022  506  824 3636  ;; 3926
 534  323 4343 1044 3322 2023 1900  946 3424 7421 1778 1500 1678 7422 1881 4344  ;; 3942
 165  243 4345 3637 2521  123  683 4096  764 4346   36 3895 1792  589 2902  816  ;; 3958
 626 1667 3027 2233 1639 1555 1622 3753 3896 7423 3897 2860 1370 1228 1932  891  ;; 3974
2083 2903  304 4097 7424  292 2979 2711 3522  691 2100 4098 1115 4347  118  662  ;; 3990
7425  611 1156  854 2381 1316 2861    2  386  515 2904 7426 7427 3253  868 2234  ;; 4006
1486  855 2651  785 2212 3028 7428 1040 3185 3523 7429 3121  448 7430 1525 7431  ;; 4022
2164 4348 7432 3754 7433 4099 2820 3524 3122  503  818 3898 3123 1568  814  676  ;; 4038
1444  306 1749 7434 3755 1416 1030  197 1428  805 2821 1501 4349 7435 7436 7437  ;; 4054
1993 7438 4350 7439 7440 2195   13 2779 3638 2980 3124 1229 1916 7441 3756 2131  ;; 4070
7442 4100 4351 2399 3525 7443 2213 1511 1727 1120 7444 7445  646 3757 2443  307  ;; 4086
7446 7447 1595 3186 7448 7449 7450 3639 1113 1356 3899 1465 2522 2523 7451  519  ;; 4102
7452  128 2132   92 2284 1979 7453 3900 1512  342 3125 2196 7454 2780 2214 1980  ;; 4118
3323 7455  290 1656 1317  789  827 2360 7456 3758 4352  562  581 3901 7457  401  ;; 4134
4353 2248   94 4354 1399 2781 7458 1463 2024 4355 3187 1943 7459  828 1105 4101  ;; 4150
1262 1394 7460 4102  605 4356 7461 1783 2862 7462 2822  819 2101  578 2197 2937  ;; 4166
7463 1502  436 3254 4103 3255 2823 3902 2905 3425 3426 7464 2712 2315 7465 7466  ;; 4182
2332 2067   23 4357  193  826 3759 2102  699 1630 4104 3075  390 1793 1064 3526  ;; 4198
7467 1579 3076 3077 1400 7468 4105 1838 1640 2863 7469 4358 4359  137 4106  598  ;; 4214
3078 1966  780  104  974 2938 7470  278  899  253  402  572  504  493 1339 7471  ;; 4230
3903 1275 4360 2574 2550 7472 3640 3029 3079 2249  565 1334 2713  863   41 7473  ;; 4246
7474 4361 7475 1657 2333   19  463 2750 4107  606 7476 2981 3256 1087 2084 1323  ;; 4262
2652 2982 7477 1631 1623 1750 4108 2682 7478 2864  791 2714 2653 2334  232 2416  ;; 4278
7479 2983 1498 7480 2654 2620  755 1366 3641 3257 3126 2025 1609  119 1917 3427  ;; 4294
 862 1026 4109 7481 3904 3760 4362 3905 4363 2260 1951 2470 7482 1125  817 4110  ;; 4310
4111 3906 1513 1766 2040 1487 4112 3030 3258 2824 3761 3127 7483 7484 1507 7485  ;; 4326
2683  733   40 1632 1106 2865  345 4113  841 2524  230 4364 2984 1846 3259 3428  ;; 4342
7486 1263  986 3429 7487  735  879  254 1137  857  622 1300 1180 1388 1562 3907  ;; 4358
3908 2939  967 2751 2655 1349  592 2133 1692 3324 2985 1994 4114 1679 3909 1901  ;; 4374
2185 7488  739 3642 2715 1296 1290 7489 4115 2198 2199 1921 1563 2595 2551 1870  ;; 4390
2752 2986 7490  435 7491  343 1108  596   17 1751 4365 2235 3430 3643 7492 4366  ;; 4406
 294 3527 2940 1693  477  979  281 2041 3528  643 2042 3644 2621 2782 2261 1031  ;; 4422
2335 2134 2298 3529 4367  367 1249 2552 7493 3530 7494 4368 1283 3325 2004  240  ;; 4438
1762 3326 4369 4370  836 1069 3128  474 7495 2148 2525  268 3531 7496 3188 1521  ;; 4454
1284 7497 1658 1546 4116 7498 3532 3533 7499 4117 3327 2684 1685 4118  961 1673  ;; 4470
2622  190 2005 2200 3762 4371 4372 7500  570 2497 3645 1490 7501 4373 2623 3260  ;; 4486
1956 4374  584 1514  396 1045 1944 7502 4375 1967 2444 7503 7504 4376 3910  619  ;; 4502
7505 3129 3261  215 2006 2783 2553 3189 4377 3190 4378  763 4119 3763 4379 7506  ;; 4518
7507 1957 1767 2941 3328 3646 1174  452 1477 4380 3329 3130 7508 2825 1253 2382  ;; 4534
2186 1091 2285 4120  492 7509  638 1169 1824 2135 1752 3911  648  926 1021 1324  ;; 4550
4381  520 4382  997  847 1007  892 4383 3764 2262 1871 3647 7510 2400 1784 4384  ;; 4566
1952 2942 3080 3191 1728 4121 2043 3648 4385 2007 1701 3131 1551   30 2263 4122  ;; 4582
7511 2026 4386 3534 7512  501 7513 4123  594 3431 2165 1821 3535 3432 3536 3192  ;; 4598
 829 2826 4124 7514 1680 3132 1225 4125 7515 3262 4387 4126 3133 2336 7516 4388  ;; 4614
4127 7517 3912 3913 7518 1847 2383 2596 3330 7519 4389  374 3914  652 4128 4129  ;; 4630
 375 1140  798 7520 7521 7522 2361 4390 2264  546 1659  138 3031 2445 4391 7523  ;; 4646
2250  612 1848  910  796 3765 1740 1371  825 3766 3767 7524 2906 2554 7525  692  ;; 4662
 444 3032 2624  801 4392 4130 7526 1491  244 1053 3033 4131 4132  340 7527 3915  ;; 4678
1041 2987  293 1168   87 1357 7528 1539  959 7529 2236  721  694 4133 3768  219  ;; 4694
1478  644 1417 3331 2656 1413 1401 1335 1389 3916 7530 7531 2988 2362 3134 1825  ;; 4710
 730 1515  184 2827   66 4393 7532 1660 2943  246 3332  378 1457  226 3433  975  ;; 4726
3917 2944 1264 3537  674  696 7533  163 7534 1141 2417 2166  713 3538 3333 4394  ;; 4742
3918 7535 7536 1186   15 7537 1079 1070 7538 1522 3193 3539  276 1050 2716  758  ;; 4758
1126  653 2945 3263 7539 2337  889 3540 3919 3081 2989  903 1250 4395 3920 3434  ;; 4774
3541 1342 1681 1718  766 3264  286   89 2946 3649 7540 1713 7541 2597 3334 2990  ;; 4790
7542 2947 2215 3194 2866 7543 4396 2498 2526  181  387 1075 3921  731 2187 3335  ;; 4806
7544 3265  310  313 3435 2299  770 4134   54 3034  189 4397 3082 3769 3922 7545  ;; 4822
1230 1617 1849  355 3542 4135 4398 3336  111 4136 3650 1350 3135 3436 3035 4137  ;; 4838
2149 3266 3543 7546 2784 3923 3924 2991  722 2008 7547 1071  247 1207 2338 2471  ;; 4854
1378 4399 2009  864 1437 1214 4400  373 3770 1142 2216  667 4401  442 2753 2555  ;; 4870
3771 3925 1968 4138 3267 1839  837  170 1107  934 1336 1882 7548 7549 2118 4139  ;; 4886
2828  743 1569 7550 4402 4140  582 2384 1418 3437 7551 1802 7552  357 1395 1729  ;; 4902
3651 3268 2418 1564 2237 7553 3083 3772 1633 4403 1114 2085 4141 1532 7554  482  ;; 4918
2446 4404 7555 7556 1492  833 1466 7557 2717 3544 1641 2829 7558 1526 1272 3652  ;; 4934
4142 1686 1794  416 2556 1902 1953 1803 7559 3773 2785 3774 1159 2316 7560 2867  ;; 4950
4405 1610 1584 3036 2419 2754  443 3269 1163 3136 7561 7562 3926 7563 4143 2499  ;; 4966
3037 4406 3927 3137 2103 1647 3545 2010 1872 4144 7564 4145  431 3438 7565  250  ;; 4982
  97   81 4146 7566 1648 1850 1558  160  848 7567  866  740 1694 7568 2201 2830  ;; 4998
3195 4147 4407 3653 1687  950 2472  426  469 3196 3654 3655 3928 7569 7570 1188  ;; 5014
 424 1995  861 3546 4148 3775 2202 2685  168 1235 3547 4149 7571 2086 1674 4408  ;; 5030
3337 3270  220 2557 1009 7572 3776  670 2992  332 1208  717 7573 7574 3548 2447  ;; 5046
3929 3338 7575  513 7576 1209 2868 3339 3138 4409 1080 7577 7578 7579 7580 2527  ;; 5062
3656 3549  815 1587 3930 3931 7581 3550 3439 3777 1254 4410 1328 3038 1390 3932  ;; 5078
1741 3933 3778 3934 7582  236 3779 2448 3271 7583 7584 3657 3780 1273 3781 4411  ;; 5094
7585  308 7586 4412  245 4413 1851 2473 1307 2575  430  715 2136 2449 7587  270  ;; 5110
 199 2869 3935 7588 3551 2718 1753  761 1754  725 1661 1840 4414 3440 3658 7589  ;; 5126
7590  587   14 3272  227 2598  326  480 2265  943 2755 3552  291  650 1883 7591  ;; 5142
1702 1226  102 1547   62 3441  904 4415 3442 1164 4150 7592 7593 1224 1548 2756  ;; 5158
 391  498 1493 7594 1386 1419 7595 2055 1177 4416  813  880 1081 2363  566 1145  ;; 5174
4417 2286 1001 1035 2558 2599 2238  394 1286 7596 7597 2068 7598   86 1494 1730  ;; 5190
3936  491 1588  745  897 2948  843 3340 3937 2757 2870 3273 1768  998 2217 2069  ;; 5206
 397 1826 1195 1969 3659 2993 3341  284 7599 3782 2500 2137 2119 1903 7600 3938  ;; 5222
2150 3939 4151 1036 3443 1904  114 2559 4152  209 1527 7601 7602 2949 2831 2625  ;; 5238
2385 2719 3139  812 2560 7603 3274 7604 1559  737 1884 3660 1210  885   28 2686  ;; 5254
3553 3783 7605 4153 1004 1779 4418 7606  346 1981 2218 2687 4419 3784 1742  797  ;; 5270
1642 3940 1933 1072 1384 2151  896 3941 3275 3661 3197 2871 3554 7607 2561 1958  ;; 5286
4420 2450 1785 7608 7609 7610 3942 4154 1005 1308 3662 4155 2720 4421 4422 1528  ;; 5302
2600  161 1178 4156 1982  987 4423 1101 4157  631 3943 1157 3198 2420 1343 1241  ;; 5318
1016 2239 2562  372  877 2339 2501 1160  555 1934  911 3944 7611  466 1170  169  ;; 5334
1051 2907 2688 3663 2474 2994 1182 2011 2563 1251 2626 7612  992 2340 3444 1540  ;; 5350
2721 1201 2070 2401 1996 2475 7613 4424  528 1922 2188 1503 1873 1570 2364 3342  ;; 5366
3276 7614  557 1073 7615 1827 3445 2087 2266 3140 3039 3084  767 3085 2786 4425  ;; 5382
1006 4158 4426 2341 1267 2176 3664 3199  778 3945 3200 2722 1597 2657 7616 4427  ;; 5398
7617 3446 7618 7619 7620 3277 2689 1433 3278  131   95 1504 3946  723 4159 3141  ;; 5414
1841 3555 2758 2189 3947 2027 2104 3665 7621 2995 3948 1218 7622 3343 3201 3949  ;; 5430
4160 2576  248 1634 3785  912 7623 2832 3666 3040 3786  654   53 7624 2996 7625  ;; 5446
1688 4428  777 3447 1032 3950 1425 7626  191  820 2120 2833  971 4429  931 3202  ;; 5462
 135  664  783 3787 1997  772 2908 1935 3951 3788 4430 2909 3203  282 2723  640  ;; 5478
1372 3448 1127  922  325 3344 7627 7628  711 2044 7629 7630 3952 2219 2787 1936  ;; 5494
3953 3345 2220 2251 3789 2300 7631 4431 3790 1258 3279 3954 3204 2138 2950 3955  ;; 5510
3956 7632 2221  258 3205 4432  101 1227 7633 3280 1755 7634 1391 3281 7635 2910  ;; 5526
2056  893 7636 7637 7638 1402 4161 2342 7639 7640 3206 3556 7641 7642  878 1325  ;; 5542
1780 2788 4433  259 1385 2577  744 1183 2267 4434 7643 3957 2502 7644  684 1024  ;; 5558
4162 7645  472 3557 3449 1165 3282 3958 3959  322 2152  881  455 1695 1152 1340  ;; 5574
 660  554 2153 4435 1058 4436 4163  830 1065 3346 3960 4437 1923 7646 1703 1918  ;; 5590
7647  932 2268  122 7648 4438  947  677 7649 3791 2627  297 1905 1924 2269 4439  ;; 5606
2317 3283 7650 7651 4164 7652 4165   84 4166  112  989 7653  547 1059 3961  701  ;; 5622
3558 1019 7654 4167 7655 3450  942  639  457 2301 2451  993 2951  407  851  494  ;; 5638
4440 3347  927 7656 1237 7657 2421 3348  573 4168  680  921 2911 1279 1874  285  ;; 5654
 790 1448 1983  719 2167 7658 7659 4441 3962 3963 1649 7660 1541  563 7661 1077  ;; 5670
7662 3349 3041 3451  511 2997 3964 3965 3667 3966 1268 2564 3350 3207 4442 4443  ;; 5686
7663  535 1048 1276 1189 2912 2028 3142 1438 1373 2834 2952 1134 2012 7664 4169  ;; 5702
1238 2578 3086 1259 7665  700 7666 2953 3143 3668 4170 7667 4171 1146 1875 1906  ;; 5718
4444 2601 3967  781 2422  132 1589  203  147  273 2789 2402  898 1786 2154 3968  ;; 5734
3969 7668 3792 2790 7669 7670 4445 4446 7671 3208 7672 1635 3793  965 7673 1804  ;; 5750
2690 1516 3559 1121 1082 1329 3284 3970 1449 3794   65 1128 2835 2913 2759 1590  ;; 5766
3795 7674 7675   12 2658   45  976 2579 3144 4447  517 2528 1013 1037 3209 7676  ;; 5782
3796 2836 7677 3797 7678 3452 7679 2602  614 1998 2318 3798 3087 2724 2628 7680  ;; 5798
2580 4172  599 1269 7681 1810 3669 7682 2691 3088  759 1060  489 1805 3351 3285  ;; 5814
1358 7683 7684 2386 1387 1215 2629 2252  490 7685 7686 4173 1759 2387 2343 7687  ;; 5830
4448 3799 1907 3971 2630 1806 3210 4449 3453 3286 2760 2344  874 7688 7689 3454  ;; 5846
3670 1858   91 2914 3671 3042 3800 4450 7690 3145 3972 2659 7691 3455 1202 1403  ;; 5862
3801 2954 2529 1517 2503 4451 3456 2504 7692 4452 7693 2692 1885 1495 1731 3973  ;; 5878
2365 4453 7694 2029 7695 7696 3974 2693 1216  237 2581 4174 2319 3975 3802 4454  ;; 5894
4455 2694 3560 3457  445 4456 7697 7698 7699 7700 2761   61 3976 3672 1822 3977  ;; 5910
7701  687 2045  935  925  405 2660  703 1096 1859 2725 4457 3978 1876 1367 2695  ;; 5926
3352  918 2105 1781 2476  334 3287 1611 1093 4458  564 3146 3458 3673 3353  945  ;; 5942
2631 2057 4459 7702 1925  872 4175 7703 3459 2696 3089  349 4176 3674 3979 4460  ;; 5958
3803 4177 3675 2155 3980 4461 4462 4178 4463 2403 2046  782 3981  400  251 4179  ;; 5974
1624 7704 7705  277 3676  299 1265  476 1191 3804 2121 4180 4181 1109  205 7706  ;; 5990
2582 1000 2156 3561 1860 7707 7708 7709 4464 7710 4465 2565  107 2477 2157 3982  ;; 6006
3460 3147 7711 1533  541 1301  158  753 4182 2872 3562 7712 1696  370 1088 4183  ;; 6022
4466 3563  579  327  440  162 2240  269 1937 1374 3461  968 3043   56 1396 3090  ;; 6038
2106 3288 3354 7713 1926 2158 4467 2998 7714 3564 7715 7716 3677 4468 2478 7717  ;; 6054
2791 7718 1650 4469 7719 2603 7720 7721 3983 2661 3355 1149 3356 3984 3805 3985  ;; 6070
7722 1076   49 7723  951 3211 3289 3290  450 2837  920 7724 1811 2792 2366 4184  ;; 6086
1908 1138 2367 3806 3462 7725 3212 4470 1909 1147 1518 2423 4471 3807 7726 4472  ;; 6102
2388 2604  260 1795 3213 7727 7728 3808 3291  708 7729 3565 1704 7730 3566 1351  ;; 6118
1618 3357 2999 1886  944 4185 3358 4186 3044 3359 4187 7731 3678  422  413 1714  ;; 6134
3292  500 2058 2345 4188 2479 7732 1344 1910  954 7733 1668 7734 7735 3986 2404  ;; 6150
4189 3567 3809 4190 7736 2302 1318 2505 3091  133 3092 2873 4473  629   31 2838  ;; 6166
2697 3810 4474  850  949 4475 3987 2955 1732 2088 4191 1496 1852 7737 3988  620  ;; 6182
3214  981 1242 3679 3360 1619 3680 1643 3293 2139 2452 1970 1719 3463 2168 7738  ;; 6198
3215 7739 7740 3361 1828 7741 1277 4476 1565 2047 7742 1636 3568 3093 7743  869  ;; 6214
2839  655 3811 3812 3094 3989 3000 3813 1310 3569 4477 7744 7745 7746 1733  558  ;; 6230
4478 3681  335 1549 3045 1756 4192 3682 1945 3464 1829 1291 1192  470 2726 2107  ;; 6246
2793  913 1054 3990 7747 1027 7748 3046 3991 4479  982 2662 3362 3148 3465 3216  ;; 6262
3217 1946 2794 7749  571 4480 7750 1830 7751 3570 2583 1523 2424 7752 2089  984  ;; 6278
4481 3683 1959 7753 3684  852  923 2795 3466 3685  969 1519  999 2048 2320 1705  ;; 6294
7754 3095  615 1662  151  597 3992 2405 2321 1049  275 4482 3686 4193  568 3687  ;; 6310
3571 2480 4194 3688 7755 2425 2270  409 3218 7756 1566 2874 3467 1002  769 2840  ;; 6326
 194 2090 3149 3689 2222 3294 4195  628 1505 7757 7758 1763 2177 3001 3993  521  ;; 6342
1161 2584 1787 2203 2406 4483 3994 1625 4196 4197  412   42 3096  464 7759 2632  ;; 6358
4484 3363 1760 1571 2875 3468 2530 1219 2204 3814 2633 2140 2368 4485 4486 3295  ;; 6374
1651 3364 3572 7760 7761 3573 2481 3469 7762 3690 7763 7764 2271 2091  460 7765  ;; 6390
4487 7766 3002  962  588 3574  289 3219 2634 1116   52 7767 3047 1796 7768 7769  ;; 6406
7770 1467 7771 1598 1143 3691 4198 1984 1734 1067 4488 1280 3365  465 4489 1572  ;; 6422
 510 7772 1927 2241 1812 1644 3575 7773 4490 3692 7774 7775 2663 1573 1534 7776  ;; 6438
7777 4199  536 1807 1761 3470 3815 3150 2635 7778 7779 7780 4491 3471 2915 1911  ;; 6454
2796 7781 3296 1122  377 3220 7782  360 7783 7784 4200 1529  551 7785 2059 3693  ;; 6470
1769 2426 7786 2916 4201 3297 3097 2322 2108 2030 4492 1404  136 1468 1479  672  ;; 6486
1171 3221 2303  271 3151 7787 2762 7788 2049  678 2727  865 1947 4493 7789 2013  ;; 6502
3995 2956 7790 2728 2223 1397 3048 3694 4494 4495 1735 2917 3366 3576 7791 3816  ;; 6518
 509 2841 2453 2876 3817 7792 7793 3152 3153 4496 4202 2531 4497 2304 1166 1010  ;; 6534
 552  681 1887 7794 7795 2957 2958 3996 1287 1596 1861 3154  358  453  736  175  ;; 6550
 478 1117  905 1167 1097 7796 1853 1530 7797 1706 7798 2178 3472 2287 3695 3473  ;; 6566
3577 4203 2092 4204 7799 3367 1193 2482 4205 1458 2190 2205 1862 1888 1421 3298  ;; 6582
2918 3049 2179 3474  595 2122 7800 3997 7801 7802 4206 1707 2636  223 3696 1359  ;; 6598
 751 3098  183 3475 7803 2797 3003  419 2369  633  704 3818 2389  241 7804 7805  ;; 6614
7806  838 3004 3697 2272 2763 2454 3819 1938 2050 3998 1309 3099 2242 1181 7807  ;; 6630
1136 2206 3820 2370 1446 4207 2305 4498 7808 7809 4208 1055 2605  484 3698 7810  ;; 6646
3999  625 4209 2273 3368 1499 4210 4000 7811 4001 4211 3222 2274 2275 3476 7812  ;; 6662
7813 2764  808 2606 3699 3369 4002 4212 3100 2532  526 3370 3821 4213  955 7814  ;; 6678
1620 4214 2637 2427 7815 1429 3700 1669 1831  994  928 7816 3578 1260 7817 7818  ;; 6694
7819 1948 2288  741 2919 1626 4215 2729 2455  867 1184  362 3371 1392 7820 7821  ;; 6710
4003 4216 1770 1736 3223 2920 4499 4500 1928 2698 1459 1158 7822 3050 3372 2877  ;; 6726
1292 1929 2506 2842 3701 1985 1187 2071 2014 2607 4217 7823 2566 2507 2169 3702  ;; 6742
2483 3299 7824 3703 4501 7825 7826  666 1003 3005 1022 3579 4218 7827 4502 1813  ;; 6758
2253  574 3822 1603  295 1535  705 3823 4219  283  858  417 7828 7829 3224 4503  ;; 6774
4504 3051 1220 1889 1046 2276 2456 4004 1393 1599  689 2567  388 4220 7830 2484  ;; 6790
 802 7831 2798 3824 2060 1405 2254 7832 4505 3825 2109 1052 1345 3225 1585 7833  ;; 6806
 809 7834 7835 7836  575 2730 3477  956 1552 1469 1144 2323 7837 2324 1560 2457  ;; 6822
3580 3226 4005  616 2207 3155 2180 2289 7838 1832 7839 3478 4506 7840 1319 3704  ;; 6838
3705 1211 3581 1023 3227 1293 2799 7841 7842 7843 3826  607 2306 3827  762 2878  ;; 6854
1439 4221 1360 7844 1485 3052 7845 4507 1038 4222 1450 2061 2638 4223 1379 4508  ;; 6870
2585 7846 7847 4224 1352 1414 2325 2921 1172 7848 7849 3828 3829 7850 1797 1451  ;; 6886
7851 7852 7853 7854 2922 4006 4007 2485 2346  411 4008 4009 3582 3300 3101 4509  ;; 6902
1561 2664 1452 4010 1375 7855 7856   47 2959  316 7857 1406 1591 2923 3156 7858  ;; 6918
1025 2141 3102 3157  354 2731  884 2224 4225 2407  508 3706  726 3583  996 2428  ;; 6934
3584  729 7859  392 2191 1453 4011 4510 3707 7860 7861 2458 3585 2608 1675 2800  ;; 6950
 919 2347 2960 2348 1270 4511 4012   73 7862 7863  647 7864 3228 2843 2255 1550  ;; 6966
1346 3006 7865 1332  883 3479 7866 7867 7868 7869 3301 2765 7870 1212  831 1347  ;; 6982
4226 4512 2326 3830 1863 3053  720 3831 4513 4514 3832 7871 4227 7872 7873 4515  ;; 6998
7874 7875 1798 4516 3708 2609 4517 3586 1645 2371 7876 7877 2924  669 2208 2665  ;; 7014
2429 7878 2879 7879 7880 1028 3229 7881 4228 2408 7882 2256 1353 7883 7884 4518  ;; 7030
3158  518 7885 4013 7886 4229 1960 7887 2142 4230 7888 7889 3007 2349 2350 3833  ;; 7046
 516 1833 1454 4014 2699 4231 4519 2225 2610 1971 1129 3587 7890 2766 7891 2961  ;; 7062
1422  577 1470 3008 1524 3373 7892 7893  432 4232 3054 3480 7894 2586 1455 2508  ;; 7078
2226 1972 1175 7895 1020 2732 4015 3481 4520 7896 2733 7897 1743 1361 3055 3482  ;; 7094
2639 4016 4233 4521 2290  895  924 4234 2170  331 2243 3056  166 1627 3057 1098  ;; 7110
7898 1232 2880 2227 3374 4522  657  403 1196 2372  542 3709 3375 1600 4235 3483  ;; 7126
7899 4523 2767 3230  576  530 1362 7900 4524 2533 2666 3710 4017 7901  842 3834  ;; 7142
7902 2801 2031 1014 4018  213 2700 3376  665  621 4236 7903 3711 2925 2430 7904  ;; 7158
2431 3302 3588 3377 7905 4237 2534 4238 4525 3589 1682 4239 3484 1380 7906  724  ;; 7174
2277  600 1670 7907 1337 1233 4526 3103 2244 7908 1621 4527 7909  651 4240 7910  ;; 7190
1612 4241 2611 7911 2844 7912 2734 2307 3058 7913  716 2459 3059  174 1255 2701  ;; 7206
4019 3590  548 1320 1398  728 4020 1574 7914 1890 1197 3060 4021 7915 3061 3062  ;; 7222
3712 3591 3713  747 7916  635 4242 4528 7917 7918 7919 4243 7920 7921 4529 7922  ;; 7238
3378 4530 2432  451 7923 3714 2535 2072 4244 2735 4245 4022 7924 1764 4531 7925  ;; 7254
4246  350 7926 2278 2390 2486 7927 4247 4023 2245 1434 4024  488 4532  458 4248  ;; 7270
4025 3715  771 1330 2391 3835 2568 3159 2159 2409 1553 2667 3160 4249 7928 2487  ;; 7286
2881 2612 1720 2702 4250 3379 4533 7929 2536 4251 7930 3231 4252 2768 7931 2015  ;; 7302
2736 7932 1155 1017 3716 3836 7933 3303 2308  201 1864 4253 1430 7934 4026 7935  ;; 7318
7936 7937 7938 7939 4254 1604 7940  414 1865  371 2587 4534 4535 3485 2016 3104  ;; 7334
4536 1708  960 4255  887  389 2171 1536 1663 1721 7941 2228 4027 2351 2926 1580  ;; 7350
7942 7943 7944 1744 7945 2537 4537 4538 7946 4539 7947 2073 7948 7949 3592 3380  ;; 7366
2882 4256 7950 4257 2640 3381 2802  673 2703 2460  709 3486 4028 3593 4258 7951  ;; 7382
1148  502  634 7952 7953 1204 4540 3594 1575 4541 2613 3717 7954 3718 3105  948  ;; 7398
3232  121 1745 3837 1110 7955 4259 3063 2509 3009 4029 3719 1151 1771 3838 1488  ;; 7414
4030 1986 7956 2433 3487 7957 7958 2093 7959 4260 3839 1213 1407 2803  531 2737  ;; 7430
2538 3233 1011 1537 7960 2769 4261 3106 1061 7961 3720 3721 1866 2883 7962 2017  ;; 7446
 120 4262 4263 2062 3595 3234 2309 3840 2668 3382 1954 4542 7963 7964 3488 1047  ;; 7462
2704 1266 7965 1368 4543 2845  649 3383 3841 2539 2738 1102 2846 2669 7966 7967  ;; 7478
1999 7968 1111 3596 2962 7969 2488 3842 3597 2804 1854 3384 3722 7970 7971 3385  ;; 7494
2410 2884 3304 3235 3598 7972 2569 7973 3599 2805 4031 1460  856 7974 3600 7975  ;; 7510
2885 2963 7976 2886 3843 7977 4264  632 2510  875 3844 1697 3845 2291 7978 7979  ;; 7526
4544 3010 1239  580 4545 4265 7980  914  936 2074 1190 4032 1039 2123 7981 7982  ;; 7542
7983 3386 1473 7984 1354 4266 3846 7985 2172 3064 4033  915 3305 4267 4268 3306  ;; 7558
1605 1834 7986 2739  398 3601 4269 3847 4034  328 1912 2847 4035 3848 1331 4270  ;; 7574
3011  937 4271 7987 3602 4036 4037 3387 2160 4546 3388  524  742  538 3065 1012  ;; 7590
7988 7989 3849 2461 7990  658 1103  225 3850 7991 7992 4547 7993 4548 7994 3236  ;; 7606
1243 7995 4038  963 2246 4549 7996 2705 3603 3161 7997 7998 2588 2327 7999 4550  ;; 7622
8000 8001 8002 3489 3307  957 3389 2540 2032 1930 2927 2462  870 2018 3604 1746  ;; 7638
2770 2771 2434 2463 8003 3851 8004 3723 3107 3724 3490 3390 3725 8005 1179 3066  ;; 7654
8006 3162 2373 4272 3726 2541 3163 3108 2740 4039 8007 3391 1556 2542 2292  977  ;; 7670
2887 2033 4040 1205 3392 8008 1765 3393 3164 2124 1271 1689  714 4551 3491 8009  ;; 7686
2328 3852  533 4273 3605 2181  617 8010 2464 3308 3492 2310 8011 8012 3165 8013  ;; 7702
8014 3853 1987  618  427 2641 3493 3394 8015 8016 1244 1690 8017 2806 4274 4552  ;; 7718
8018 3494 8019 8020 2279 1576  473 3606 4275 3395  972 8021 3607 8022 3067 8023  ;; 7734
8024 4553 4554 8025 3727 4041 4042 8026  153 4555  356 8027 1891 2888 4276 2143  ;; 7750
 408  803 2352 8028 3854 8029 4277 1646 2570 2511 4556 4557 3855 8030 3856 4278  ;; 7766
8031 2411 3396  752 8032 8033 1961 2964 8034  746 3012 2465 8035 4279 3728  698  ;; 7782
4558 1892 4280 3608 2543 4559 3609 3857 8036 3166 3397 8037 1823 1302 4043 2706  ;; 7798
3858 1973 4281 8038 4282 3167  823 1303 1288 1236 2848 3495 4044 3398  774 3859  ;; 7814
8039 1581 4560 1304 2849 3860 4561 8040 2435 2161 1083 3237 4283 4045 4284  344  ;; 7830
1173  288 2311  454 1683 8041 8042 1461 4562 4046 2589 8043 8044 4563  985  894  ;; 7846
8045 3399 3168 8046 1913 2928 3729 1988 8047 2110 1974 8048 4047 8049 2571 1194  ;; 7862
 425 8050 4564 3169 1245 3730 4285 8051 8052 2850 8053  636 4565 1855 3861  760  ;; 7878
1799 8054 4286 2209 1508 4566 4048 1893 1684 2293 8055 8056 8057 4287 4288 2210  ;; 7894
 479 8058 8059  832 8060 4049 2489 8061 2965 2490 3731  990 3109  627 1814 2642  ;; 7910
4289 1582 4290 2125 2111 3496 4567 8062  799 4291 3170 8063 4568 2112 1737 3013  ;; 7926
1018  543  754 4292 3309 1676 4569 4570 4050 8064 1489 8065 3497 8066 2614 2889  ;; 7942
4051 8067 8068 2966 8069 8070 8071 8072 3171 4571 4572 2182 1722 8073 3238 3239  ;; 7958
1842 3610 1715  481  365 1975 1856 8074 8075 1962 2491 4573 8076 2126 3611 3240  ;; 7974
 433 1894 2063 2075 8077  602 2741 8078 8079 8080 8081 8082 3014 1628 3400 8083  ;; 7990
3172 4574 4052 2890 4575 2512 8084 2544 2772 8085 8086 8087 3310 4576 2891 8088  ;; 8006
4577 8089 2851 4578 4579 1221 2967 4053 2513 8090 8091 8092 1867 1989 8093 8094  ;; 8022
8095 1895 8096 8097 4580 1896 4054  318 8098 2094 4055 4293 8099 8100  485 8101  ;; 8038
 938 3862  553 2670  116 8102 3863 3612 8103 3498 2671 2773 3401 3311 2807 8104  ;; 8054
3613 2929 4056 1747 2930 2968 8105 8106  207 8107 8108 2672 4581 2514 8109 3015  ;; 8070
 890 3614 3864 8110 1877 3732 3402 8111 2183 2353 3403 1652 8112 8113 8114  941  ;; 8086
2294  208 3499 4057 2019  330 4294 3865 2892 2492 3733 4295 8115 8116 8117 8118  ;; 8102
])