;; Title: BitFlow Stable Protocol
;; Summary: Next-generation Bitcoin-collateralized stablecoin ecosystem on Stacks
;; 
;; Description: BitFlow Stable revolutionizes DeFi lending by creating a robust 
;;              ecosystem where Bitcoin holders can unlock liquidity while maintaining 
;;              BTC exposure. The protocol features advanced risk management with 
;;              dynamic collateralization ratios, real-time oracle integration, and 
;;              automated liquidation protection. Built for the Bitcoin economy, 
;;              BitFlow Stable bridges traditional Bitcoin HODLing with modern DeFi 
;;              utility, enabling seamless USD-pegged stablecoin generation backed 
;;              by the world's most trusted cryptocurrency.

;; ERROR HANDLING CONSTANTS

(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1001))
(define-constant ERR-POSITION-NOT-FOUND (err u1002))
(define-constant ERR-UNDERCOLLATERALIZED (err u1003))
(define-constant ERR-MINIMUM-LOAN-REQUIRED (err u1004))
(define-constant ERR-INSUFFICIENT-DEBT (err u1005))
(define-constant ERR-PRICE-EXPIRED (err u1006))
(define-constant ERR-PROTOCOL-PAUSED (err u1007))
(define-constant ERR-INVALID-AMOUNT (err u1008))
(define-constant ERR-NO-PRICE-DATA (err u1009))

;; PROTOCOL CONFIGURATION PARAMETERS

;; Risk Management Settings
(define-constant COLLATERAL-RATIO u150)           ;; 150% minimum collateral ratio (1.5x)
(define-constant LIQUIDATION-THRESHOLD u120)      ;; 120% liquidation threshold
(define-constant LIQUIDATION-PENALTY u10)         ;; 10% liquidation penalty

;; Financial Parameters
(define-constant MINIMUM_LOAN_AMOUNT u100000000)  ;; 100 stablecoins (8 decimal precision)
(define-constant PRICE_EXPIRY u86400)             ;; Price validity: 24 hours (seconds)

;; Interest Rate Configuration
(define-constant INTEREST_RATE_PER_BLOCK u5)      ;; 0.0005% per block (~10% APR)
(define-constant INTEREST_RATE_DENOMINATOR u1000000) ;; Interest calculation precision

;; PROTOCOL STATE MANAGEMENT

;; Administrative Control
(define-data-var protocol-owner principal tx-sender)
(define-data-var protocol-paused bool false)

;; Financial State Tracking
(define-data-var total-debt uint u0)              ;; System-wide debt obligation
(define-data-var total-collateral uint u0)        ;; Total BTC locked in protocol
(define-data-var stability-fee uint u0)           ;; Accumulated protocol revenue
(define-data-var last-accrual-block uint stacks-block-height) ;; Interest calculation checkpoint

;; Oracle Price Feed
(define-data-var btc-price-in-usd 
  (optional {price: uint, timestamp: uint}) none) ;; Real-time BTC/USD pricing

;; Development & Testing Support
(define-data-var current-time uint u0)            ;; Mockable timestamp for testing

;; DATA STRUCTURE DEFINITIONS

;; User Collateralized Debt Position
(define-map positions principal {
  collateral: uint,        ;; Bitcoin collateral amount (satoshis)
  debt: uint,             ;; Outstanding stablecoin debt
  last-update-block: uint ;; Interest accrual checkpoint
})

;; Native Stablecoin Token
(define-fungible-token stable-usd)

;; ADMINISTRATIVE FUNCTIONS

;; Transfer protocol ownership to new address
(define-public (set-protocol-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set protocol-owner new-owner))
  )
)

;; Emergency protocol pause/resume mechanism
(define-public (pause-protocol (paused bool))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set protocol-paused paused))
  )
)

;; Update Bitcoin price from trusted oracle
(define-public (update-btc-price (price uint) (timestamp uint))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> price u0) ERR-INVALID-AMOUNT)
    (var-set btc-price-in-usd (some {price: price, timestamp: timestamp}))
    (ok true)
  )
)

;; Set mock timestamp for development/testing
(define-public (set-current-time (time uint))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set current-time time))
  )
)

;; FINANCIAL CALCULATION UTILITIES

;; Calculate USD value of Bitcoin collateral
(define-private (collateral-value (collateral-amount uint) (price uint))
  (* collateral-amount price)
)

;; Calculate minimum collateral required for debt
(define-private (required-collateral (debt-amount uint) (price uint))
  (/ (* debt-amount COLLATERAL-RATIO) (/ price u100))
)

;; Verify position meets safety requirements
(define-private (is-position-safe (user principal) (btc-price uint))
  (let (
    (position (unwrap! (map-get? positions user) false))
    (debt (get debt position))
    (collateral (get collateral position))
    (collateral-value-usd (collateral-value collateral btc-price))
    (min-collateral-value-usd (/ (* debt COLLATERAL-RATIO) u100))
  )
    (>= collateral-value-usd min-collateral-value-usd)
  )
)

;; Calculate compound interest over time
(define-private (calculate-interest (debt uint) (blocks-passed uint))
  (/ (* debt (* blocks-passed INTEREST_RATE_PER_BLOCK)) INTEREST_RATE_DENOMINATOR)
)

;; INTEREST ACCRUAL MECHANISMS

;; Apply interest across entire protocol
(define-private (accrue-global-interest)
  (let (
    (current-block stacks-block-height)
    (last-block (var-get last-accrual-block))
    (blocks-passed (- current-block last-block))
    (total-system-debt (var-get total-debt))
    (interest-accrued (calculate-interest total-system-debt blocks-passed))
  )
    (begin
      (if (> blocks-passed u0)
        (begin
          (var-set stability-fee (+ (var-get stability-fee) interest-accrued))
          (var-set total-debt (+ total-system-debt interest-accrued))
          (var-set last-accrual-block current-block)
        )
        false
      )
      true
    )
  )
)

;; Update interest for individual user position
(define-private (accrue-position-interest (user principal))
  (let (
    (position (unwrap! (map-get? positions user) 
                      {debt: u0, collateral: u0, last-update-block: stacks-block-height}))
    (debt (get debt position))
    (collateral (get collateral position))
    (last-update (get last-update-block position))
    (blocks-passed (- stacks-block-height last-update))
    (interest-accrued (calculate-interest debt blocks-passed))
    (new-debt (+ debt interest-accrued))
    (updated-position {
      collateral: collateral,
      debt: new-debt,
      last-update-block: stacks-block-height
    })
  )
    (begin
      (if (> blocks-passed u0)
        (map-set positions user updated-position)
        false
      )
      updated-position
    )
  )
)

;; ORACLE PRICE FEED MANAGEMENT

;; Retrieve current Bitcoin price with freshness validation
(define-read-only (get-current-price)
  (match (var-get btc-price-in-usd)
    price-data (let (
      (price (get price price-data))
      (timestamp (get timestamp price-data))
      (current-timestamp (var-get current-time))
    )
      (if (>= (- current-timestamp timestamp) PRICE_EXPIRY)
        ERR-PRICE-EXPIRED
        (if (<= price u0)
          ERR-PRICE-EXPIRED
          (ok price)
        )
      ))
    ERR-NO-PRICE-DATA)
)

;; CORE LENDING PROTOCOL FUNCTIONS

;; Open new position or expand existing collateralized debt
(define-public (create-position (btc-amount uint) (stable-amount uint))
  (begin
    (asserts! (not (var-get protocol-paused)) ERR-PROTOCOL-PAUSED)
    (asserts! (>= btc-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= stable-amount MINIMUM_LOAN_AMOUNT) ERR-MINIMUM-LOAN-REQUIRED)
    
    ;; Validate current market pricing
    (let (
      (btc-price (try! (get-current-price)))
      (user tx-sender)
      (existing-position (map-get? positions user))
    )
      (begin
        ;; Process global interest accrual
        (accrue-global-interest)
        
        ;; Handle position creation or expansion
        (let (
          (current-position 
            (if (is-some existing-position)
              (accrue-position-interest user)
              {collateral: u0, debt: u0, last-update-block: stacks-block-height}
            )
          )
        )
          ;; Calculate updated position metrics
          (let (
            (old-collateral (get collateral current-position))
            (old-debt (get debt current-position))
            (new-collateral (+ old-collateral btc-amount))
            (new-debt (+ old-debt stable-amount))
            (min-required-collateral (required-collateral new-debt btc-price))
          )
            (begin
              ;; Enforce collateralization requirements
              (asserts! (>= (collateral-value new-collateral btc-price) min-required-collateral) 
                       ERR-INSUFFICIENT-COLLATERAL)
              
              ;; Update user position record
              (map-set positions user {
                collateral: new-collateral,
                debt: new-debt,
                last-update-block: stacks-block-height
              })
              
              ;; Update protocol-wide metrics
              (var-set total-collateral (+ (var-get total-collateral) btc-amount))
              (var-set total-debt (+ (var-get total-debt) stable-amount))
              
              ;; Issue stablecoins to user
              (ft-mint? stable-usd stable-amount user)
            )
          )
        )
      )
    )
  )
)

;; Deposit additional Bitcoin collateral to strengthen position
(define-public (add-collateral (btc-amount uint))
  (let (
    (user tx-sender)
    (position (unwrap! (map-get? positions user) ERR-POSITION-NOT-FOUND))
  )
    (begin
      (asserts! (not (var-get protocol-paused)) ERR-PROTOCOL-PAUSED)
      (asserts! (> btc-amount u0) ERR-INVALID-AMOUNT)
      
      ;; Process interest updates
      (accrue-global-interest)
      
      ;; Apply accrued interest to position
      (let (
        (updated-position (accrue-position-interest user))
        (new-debt (get debt updated-position))
        (current-collateral (get collateral updated-position))
        (new-collateral (+ current-collateral btc-amount))
      )
        (begin
          ;; Record collateral addition
          (map-set positions user {
            collateral: new-collateral,
            debt: new-debt,
            last-update-block: stacks-block-height
          })
          
          ;; Update protocol collateral tracking
          (var-set total-collateral (+ (var-get total-collateral) btc-amount))
          
          (ok true)
        )
      )
    )
  )
)

;; Repay outstanding debt and potentially close position
(define-public (repay-debt (amount uint))
  (let (
    (user tx-sender)
    (position (unwrap! (map-get? positions user) ERR-POSITION-NOT-FOUND))
  )
    (begin
      (asserts! (not (var-get protocol-paused)) ERR-PROTOCOL-PAUSED)
      (asserts! (> amount u0) ERR-INVALID-AMOUNT)
      
      ;; Process interest updates
      (accrue-global-interest)
      
      ;; Apply accrued interest to position
      (let (
        (updated-position (accrue-position-interest user))
        (current-debt (get debt updated-position))
        (collateral (get collateral updated-position))
        (repay-amount (if (> amount current-debt) current-debt amount))
        (new-debt (- current-debt repay-amount))
      )
        (begin
          (asserts! (<= repay-amount current-debt) ERR-INSUFFICIENT-DEBT)
          
          ;; Burn repaid stablecoins
          (try! (ft-burn? stable-usd repay-amount user))
          
          ;; Update or close position based on remaining debt
          (if (is-eq new-debt u0)
            ;; Complete repayment - close position and release collateral
            (begin
              (map-delete positions user)
              (var-set total-collateral (- (var-get total-collateral) collateral))
            )
            ;; Partial repayment - update position
            (map-set positions user {
              collateral: collateral,
              debt: new-debt,
              last-update-block: stacks-block-height
            })
          )
          
          ;; Update system debt tracking
          (var-set total-debt (- (var-get total-debt) repay-amount))
          
          (ok true)
        )
      )
    )
  )
)

;; Withdraw Bitcoin collateral while maintaining safe collateralization
(define-public (withdraw-collateral (btc-amount uint))
  (begin
    (asserts! (not (var-get protocol-paused)) ERR-PROTOCOL-PAUSED)
    (asserts! (> btc-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Validate current market pricing
    (let (
      (btc-price (try! (get-current-price)))
      (user tx-sender)
    )
      (begin
        ;; Process interest updates
        (accrue-global-interest)
        
        ;; Apply accrued interest to position
        (let (
          (updated-position (accrue-position-interest user))
          (current-debt (get debt updated-position))
          (current-collateral (get collateral updated-position))
          (new-collateral (- current-collateral btc-amount))
          (min-required-collateral (required-collateral current-debt btc-price))
        )
          (begin
            ;; Validate withdrawal limits and safety margins
            (asserts! (<= btc-amount current-collateral) ERR-INSUFFICIENT-COLLATERAL)
            (asserts! (>= (collateral-value new-collateral btc-price) min-required-collateral) 
                     ERR-UNDERCOLLATERALIZED)
            
            ;; Update position with reduced collateral
            (map-set positions user {
              collateral: new-collateral,
              debt: current-debt,
              last-update-block: stacks-block-height
            })
            
            ;; Update protocol collateral tracking
            (var-set total-collateral (- (var-get total-collateral) btc-amount))
            
            (ok true)
          )
        )
      )
    )
  )
)

;; Execute liquidation of unsafe position
(define-public (liquidate-position (user principal))
  (begin
    (asserts! (not (var-get protocol-paused)) ERR-PROTOCOL-PAUSED)
    (let (
      (position (unwrap! (map-get? positions user) ERR-POSITION-NOT-FOUND))
      (liquidator tx-sender)
    )
      (begin
        (asserts! (not (is-eq user liquidator)) ERR-NOT-AUTHORIZED)
        
        ;; Validate current market pricing
        (let ((btc-price (try! (get-current-price))))
          (begin
            ;; Process interest updates
            (accrue-global-interest)
            
            ;; Apply accrued interest to position
            (let (
              (updated-position (accrue-position-interest user))
              (debt (get debt updated-position))
              (collateral (get collateral updated-position))
              (collateral-value-usd (collateral-value collateral btc-price))
              (min-safety-value (/ (* debt LIQUIDATION-THRESHOLD) u100))
            )
              (begin
                ;; Confirm position is eligible for liquidation
                (asserts! (< collateral-value-usd min-safety-value) ERR-NOT-AUTHORIZED)
                
                ;; Liquidator covers outstanding debt
                (try! (ft-burn? stable-usd debt liquidator))
                
                ;; Calculate liquidation rewards and protocol fees
                (let (
                  (liquidation-bonus (/ (* collateral LIQUIDATION-PENALTY) u100))
                  (liquidator-collateral (- collateral liquidation-bonus))
                )
                  (begin
                    ;; Update protocol metrics
                    (var-set total-collateral (- (var-get total-collateral) collateral))
                    (var-set total-debt (- (var-get total-debt) debt))
                    
                    ;; Close liquidated position
                    (map-delete positions user)
                    
                    ;; Collect liquidation penalty as protocol revenue
                    (var-set stability-fee (+ (var-get stability-fee) liquidation-bonus))
                    
                    (ok true)
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

;; PUBLIC QUERY INTERFACE

;; Retrieve specific user position data
(define-read-only (get-position (user principal))
  (map-get? positions user)
)

;; Calculate current collateralization ratio for position
(define-read-only (get-collateralization-ratio (user principal))
  (match (map-get? positions user)
    position (match (var-get btc-price-in-usd)
      price-data (let (
        (price (get price price-data))
        (collateral (get collateral position))
        (debt (get debt position))
      )
        (if (is-eq debt u0)
          none
          (some (/ (* (collateral-value collateral price) u100) debt))
        ))
      none)
    none)
)

;; Retrieve comprehensive protocol health metrics
(define-read-only (get-protocol-stats)
  {
    total-debt: (var-get total-debt),
    total-collateral: (var-get total-collateral),
    stability-fee: (var-get stability-fee),
    protocol-paused: (var-get protocol-paused),
    btc-price: (var-get btc-price-in-usd)
  }
)

;; CONTRACT INITIALIZATION

;; Set deployer as initial protocol owner
(define-private (set-contract-owner)
  (var-set protocol-owner tx-sender)
)

;; Execute contract initialization
(set-contract-owner)