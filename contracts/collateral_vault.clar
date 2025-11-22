;; ------------------------------------------------------------
;; Contract: collateral_vault
;; Purpose: Programmable collateral vault with automated
;;          risk shields (dynamic collateral ratios).
;; ------------------------------------------------------------

;; -------------------------
;; Data Variables
;; -------------------------

;; Oracle allowed to update volatility and adjust risk shields
(define-data-var oracle principal tx-sender)

;; Current collateral requirement (percentage * 100)
;; Example: 15000 = 150% collateralization
(define-data-var collateral-ratio uint u15000)

;; Maximum allowed ratio change per update (to avoid drastic risk spikes)
(define-data-var max-step uint u2000) ;; 20% max jump per update

;; Maps each user to collateral deposited
(define-map collateral
  { user: principal }
  { amount: uint })

;; Maps each user to borrowed amount
(define-map debts
  { user: principal }
  { amount: uint })


;; -------------------------
;; Error Codes
;; -------------------------

(define-constant ERR-NOT-ORACLE     (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u102))
(define-constant ERR-NO-DEBT        (err u103))
(define-constant ERR-LIQUIDATION-NOT-ALLOWED (err u104))


;; -------------------------
;; Helper Accessors
;; -------------------------

(define-read-only (is-oracle (sender principal))
  (is-eq sender (var-get oracle))
)

(define-read-only (get-collateral (user principal))
  (default-to { amount: u0 } (map-get? collateral { user: user }))
)

(define-read-only (get-debt (user principal))
  (default-to { amount: u0 } (map-get? debts { user: user }))
)

;; Check if user is sufficiently collateralized under current ratio
(define-read-only (is-safe (user principal))
  (let
    (
      (col (get amount (get-collateral user)))
      (debt (get amount (get-debt user)))
      (ratio (var-get collateral-ratio))
    )
    (if (is-eq debt u0)
        true
        (>= (* col u10000) (* debt ratio))
    )
  )
)


;; -------------------------
;; Set Oracle (Oracle Only)
;; -------------------------

(define-public (set-oracle (new-oracle principal))
  (begin
    (asserts! (is-oracle tx-sender) ERR-NOT-ORACLE)
    (asserts! (not (is-eq new-oracle (as-contract tx-sender))) ERR-INVALID-AMOUNT)
    (var-set oracle new-oracle)
    (ok true)
  )
)


;; -------------------------
;; User Deposits Collateral
;; -------------------------

(define-public (deposit (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Transfer
    (match (stx-transfer? amount tx-sender (as-contract tx-sender))
      success
        (let
          (
            (prev (default-to u0 (get amount (map-get? collateral { user: tx-sender }))))
            (new (+ prev amount))
          )
          (begin
            (map-set collateral { user: tx-sender } { amount: new })
            (ok new)
          )
        )
      error (err u200)
    )
  )
)


;; -------------------------
;; User Borrows (requires safe collateral ratio)
;; -------------------------

(define-public (borrow (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    (let
      (
        (current-col (get amount (get-collateral tx-sender)))
        (current-debt (get amount (get-debt tx-sender)))
        (ratio (var-get collateral-ratio))
        (new-debt (+ current-debt amount))
      )

      (begin
        ;; Check collateralization: col * 100% >= debt * ratio
        (asserts!
          (>= (* current-col u10000) (* new-debt ratio))
          ERR-INSUFFICIENT-COLLATERAL
        )

        ;; Increase debt
        (map-set debts { user: tx-sender } { amount: new-debt })

        ;; Send borrowed STX (loan)
        (as-contract
          (match (stx-transfer? amount (as-contract tx-sender) tx-sender)
            success (ok new-debt)
            error   (err u201)
          )
        )
      )
    )
  )
)


;; -------------------------
;; Repay Loan
;; -------------------------

(define-public (repay (amount uint))
  (begin
    (let
      (
        (debt (get amount (get-debt tx-sender)))
      )

      (asserts! (> debt u0) ERR-NO-DEBT)
      (asserts! (> amount u0) ERR-INVALID-AMOUNT)

      (let ((repay-amount (if (> amount debt) debt amount)))

        ;; Transfer STX to contract
        (match (stx-transfer? repay-amount tx-sender (as-contract tx-sender))
          success
            (let ((new (- debt repay-amount)))
              (map-set debts { user: tx-sender } { amount: new })
              (ok new)
            )
          error (err u202)
        )
      )
    )
  )
)


;; -------------------------
;; Oracle Updates Risk Shield (collateral ratio)
;; -------------------------

(define-public (update-ratio (new-ratio uint))
  (begin
    (asserts! (is-oracle tx-sender) ERR-NOT-ORACLE)
    (asserts! (> new-ratio u0) ERR-INVALID-AMOUNT)

    ;; Prevent extreme risk jumps
    (let
      (
        (current (var-get collateral-ratio))
        (step (if (> new-ratio current)
                  (- new-ratio current)
                  (- current new-ratio)))
      )

      (asserts! (<= step (var-get max-step)) ERR-INVALID-AMOUNT)

      (var-set collateral-ratio new-ratio)
      (ok new-ratio)
    )
  )
)


;; -------------------------
;; Liquidation (Anyone Can Call)
;; If user falls below required ratio
;; -------------------------

(define-public (liquidate (victim principal))
  (begin
    (asserts! (not (is-safe victim)) ERR-LIQUIDATION-NOT-ALLOWED)

    (let
      (
        (col (get amount (get-collateral victim)))
        (debt (get amount (get-debt victim)))
      )

      ;; Liquidation: pool takes collateral, debt is zeroed
      (begin
        (map-set collateral { user: victim } { amount: u0 })
        (map-set debts { user: victim } { amount: u0 })

        ;; Liquidator gets 5% reward
        (let
          (
            (reward (/ (* col u5) u100))
          )

          (as-contract
            (match (stx-transfer? reward (as-contract tx-sender) tx-sender)
              success (ok reward)
              error   (err u203)
            )
          )
        )
      )
    )
  )
)


;; -------------------------
;; Views
;; -------------------------

(define-read-only (get-ratio)
  (var-get collateral-ratio)
)

(define-read-only (position (user principal))
  {
    collateral: (get amount (get-collateral user)),
    debt: (get amount (get-debt user)),
    safe: (is-safe user)
  }
)
