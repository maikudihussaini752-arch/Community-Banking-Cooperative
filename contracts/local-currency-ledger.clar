;; Local Currency Ledger - Community currency circulation and mutual aid tracking
;; This contract manages local currency issuance, transfers, and mutual aid transactions
;; within a community banking cooperative system.

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-MEMBER-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-MEMBER (err u104))
(define-constant ERR-INVALID-EXCHANGE-RATE (err u105))
(define-constant ERR-MUTUAL-AID-NOT-FOUND (err u106))
(define-constant ERR-RESOURCE-NOT-AVAILABLE (err u107))
(define-constant ERR-INVALID-STATUS (err u108))

;; Contract owner and governance
(define-constant CONTRACT-OWNER tx-sender)
(define-data-var currency-name (string-ascii 50) "CommunityToken")
(define-data-var currency-symbol (string-ascii 10) "COMM")
(define-data-var total-supply uint u0)
(define-data-var exchange-rate uint u100) ;; 1 STX = 100 COMM by default
(define-data-var mutual-aid-counter uint u0)
(define-data-var resource-counter uint u0)

;; Member management
(define-map community-members principal {
  balance: uint,
  joined-at: uint,
  is-active: bool,
  reputation-score: uint,
  total-contributions: uint,
  total-received: uint
})

;; Currency transaction history
(define-map transaction-history
  { tx-id: uint }
  {
    from: principal,
    to: principal,
    amount: uint,
    tx-type: (string-ascii 20), ;; "transfer", "mint", "burn", "mutual-aid"
    timestamp: uint,
    memo: (optional (string-utf8 200))
  }
)

;; Mutual aid tracking
(define-map mutual-aid-requests
  { request-id: uint }
  {
    requester: principal,
    request-type: (string-ascii 30), ;; "emergency", "tools", "services", "materials"
    description: (string-utf8 400),
    amount-needed: uint,
    amount-fulfilled: uint,
    status: (string-ascii 20), ;; "open", "partial", "fulfilled", "closed"
    created-at: uint,
    deadline: uint,
    contributors: (list 20 principal),
    contribution-amounts: (list 20 uint)
  }
)

;; Community resource sharing
(define-map shared-resources
  { resource-id: uint }
  {
    owner: principal,
    resource-type: (string-ascii 30), ;; "tools", "equipment", "space", "vehicle"
    name: (string-ascii 100),
    description: (string-utf8 300),
    daily-cost: uint, ;; in local currency
    is-available: bool,
    current-borrower: (optional principal),
    borrowing-history: (list 50 principal),
    total-usage-days: uint,
    condition: (string-ascii 20) ;; "excellent", "good", "fair", "poor"
  }
)

;; Exchange rate management
(define-map exchange-history
  { block-height: uint }
  {
    old-rate: uint,
    new-rate: uint,
    changed-by: principal,
    timestamp: uint
  }
)

;; Community coordinators with different permission levels
(define-map community-coordinators principal bool)

(define-data-var transaction-counter uint u0)

;; Private helper functions

;; Check if caller is authorized coordinator
(define-private (is-coordinator (caller principal))
  (or (is-eq caller CONTRACT-OWNER)
      (default-to false (map-get? community-coordinators caller))
  )
)

;; Calculate reputation score based on community participation
(define-private (calculate-reputation (member principal))
  (let (
    (member-data (unwrap! (map-get? community-members member) u0))
    (contributions (get total-contributions member-data))
    (received (get total-received member-data))
  )
    ;; Simple reputation formula: contributions * 2 - received (encouraging giving)
    (if (>= contributions received)
        (+ (* contributions u2) (- contributions received))
        (if (> contributions u0) contributions u1)
    )
  )
)

;; Public functions for member management

;; Join the community cooperative
(define-public (join-community)
  (let (
    (caller tx-sender)
    (existing-member (map-get? community-members caller))
  )
    (asserts! (is-none existing-member) ERR-ALREADY-MEMBER)
    
    (map-set community-members caller {
      balance: u0,
      joined-at: block-height,
      is-active: true,
      reputation-score: u1,
      total-contributions: u0,
      total-received: u0
    })
    
    (ok true)
  )
)

;; Issue local currency to member (coordinator only)
(define-public (mint-currency (recipient principal) (amount uint) (memo (optional (string-utf8 200))))
  (let (
    (caller tx-sender)
    (current-balance (get balance (default-to { balance: u0, joined-at: u0, is-active: false, reputation-score: u0, total-contributions: u0, total-received: u0 } 
                      (map-get? community-members recipient))))
    (tx-id (var-get transaction-counter))
  )
    (asserts! (is-coordinator caller) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-some (map-get? community-members recipient)) ERR-MEMBER-NOT-FOUND)
    
    ;; Update recipient balance
    (map-set community-members recipient
      (merge 
        (unwrap! (map-get? community-members recipient) ERR-MEMBER-NOT-FOUND)
        { balance: (+ current-balance amount) }
      )
    )
    
    ;; Update total supply
    (var-set total-supply (+ (var-get total-supply) amount))
    
    ;; Record transaction
    (map-set transaction-history { tx-id: tx-id } {
      from: caller,
      to: recipient,
      amount: amount,
      tx-type: "mint",
      timestamp: block-height,
      memo: memo
    })
    
    (var-set transaction-counter (+ tx-id u1))
    (ok amount)
  )
)

;; Transfer local currency between members
(define-public (transfer-currency (recipient principal) (amount uint) (memo (optional (string-utf8 200))))
  (let (
    (sender tx-sender)
    (sender-balance (get balance (default-to { balance: u0, joined-at: u0, is-active: false, reputation-score: u0, total-contributions: u0, total-received: u0 } 
                     (map-get? community-members sender))))
    (recipient-balance (get balance (default-to { balance: u0, joined-at: u0, is-active: false, reputation-score: u0, total-contributions: u0, total-received: u0 } 
                       (map-get? community-members recipient))))
    (tx-id (var-get transaction-counter))
  )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (is-some (map-get? community-members sender)) ERR-MEMBER-NOT-FOUND)
    (asserts! (is-some (map-get? community-members recipient)) ERR-MEMBER-NOT-FOUND)
    
    ;; Update sender balance
    (map-set community-members sender
      (merge 
        (unwrap! (map-get? community-members sender) ERR-MEMBER-NOT-FOUND)
        { balance: (- sender-balance amount) }
      )
    )
    
    ;; Update recipient balance
    (map-set community-members recipient
      (merge 
        (unwrap! (map-get? community-members recipient) ERR-MEMBER-NOT-FOUND)
        { balance: (+ recipient-balance amount) }
      )
    )
    
    ;; Record transaction
    (map-set transaction-history { tx-id: tx-id } {
      from: sender,
      to: recipient,
      amount: amount,
      tx-type: "transfer",
      timestamp: block-height,
      memo: memo
    })
    
    (var-set transaction-counter (+ tx-id u1))
    (ok amount)
  )
)

;; Create mutual aid request
(define-public (create-mutual-aid-request 
  (request-type (string-ascii 30))
  (description (string-utf8 400))
  (amount-needed uint)
  (deadline uint)
)
  (let (
    (caller tx-sender)
    (request-id (var-get mutual-aid-counter))
  )
    (asserts! (is-some (map-get? community-members caller)) ERR-MEMBER-NOT-FOUND)
    (asserts! (> amount-needed u0) ERR-INVALID-AMOUNT)
    (asserts! (> deadline block-height) ERR-INVALID-AMOUNT)
    
    (map-set mutual-aid-requests { request-id: request-id } {
      requester: caller,
      request-type: request-type,
      description: description,
      amount-needed: amount-needed,
      amount-fulfilled: u0,
      status: "open",
      created-at: block-height,
      deadline: deadline,
      contributors: (list),
      contribution-amounts: (list)
    })
    
    (var-set mutual-aid-counter (+ request-id u1))
    (ok request-id)
  )
)

;; Contribute to mutual aid request
(define-public (contribute-to-mutual-aid (request-id uint) (amount uint))
  (let (
    (contributor tx-sender)
    (contributor-balance (get balance (default-to { balance: u0, joined-at: u0, is-active: false, reputation-score: u0, total-contributions: u0, total-received: u0 } 
                         (map-get? community-members contributor))))
    (request-data (unwrap! (map-get? mutual-aid-requests { request-id: request-id }) ERR-MUTUAL-AID-NOT-FOUND))
    (current-fulfilled (get amount-fulfilled request-data))
    (needed (get amount-needed request-data))
    (requester (get requester request-data))
    (tx-id (var-get transaction-counter))
  )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= contributor-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (is-some (map-get? community-members contributor)) ERR-MEMBER-NOT-FOUND)
    (asserts! (is-eq (get status request-data) "open") ERR-INVALID-STATUS)
    
    ;; Transfer currency from contributor to requester
    (try! (transfer-currency requester amount (some u"Mutual aid contribution")))
    
    ;; Update mutual aid request
    (let (
      (new-fulfilled (+ current-fulfilled amount))
      (new-status (if (>= new-fulfilled needed) "fulfilled" "partial"))
    )
      (map-set mutual-aid-requests { request-id: request-id }
        (merge request-data {
          amount-fulfilled: new-fulfilled,
          status: new-status,
          contributors: (unwrap-panic (as-max-len? (append (get contributors request-data) contributor) u20)),
          contribution-amounts: (unwrap-panic (as-max-len? (append (get contribution-amounts request-data) amount) u20))
        })
      )
    )
    
    ;; Update contributor stats
    (map-set community-members contributor
      (merge 
        (unwrap! (map-get? community-members contributor) ERR-MEMBER-NOT-FOUND)
        { 
          total-contributions: (+ (get total-contributions 
                                   (unwrap! (map-get? community-members contributor) ERR-MEMBER-NOT-FOUND)) amount),
          reputation-score: (calculate-reputation contributor)
        }
      )
    )
    
    ;; Update requester stats
    (map-set community-members requester
      (merge 
        (unwrap! (map-get? community-members requester) ERR-MEMBER-NOT-FOUND)
        { 
          total-received: (+ (get total-received 
                              (unwrap! (map-get? community-members requester) ERR-MEMBER-NOT-FOUND)) amount)
        }
      )
    )
    
    (ok amount)
  )
)

;; Add shared resource to community pool
(define-public (add-shared-resource 
  (resource-type (string-ascii 30))
  (name (string-ascii 100))
  (description (string-utf8 300))
  (daily-cost uint)
  (condition (string-ascii 20))
)
  (let (
    (owner tx-sender)
    (resource-id (var-get resource-counter))
  )
    (asserts! (is-some (map-get? community-members owner)) ERR-MEMBER-NOT-FOUND)
    
    (map-set shared-resources { resource-id: resource-id } {
      owner: owner,
      resource-type: resource-type,
      name: name,
      description: description,
      daily-cost: daily-cost,
      is-available: true,
      current-borrower: none,
      borrowing-history: (list),
      total-usage-days: u0,
      condition: condition
    })
    
    (var-set resource-counter (+ resource-id u1))
    (ok resource-id)
  )
)

;; Borrow shared resource
(define-public (borrow-resource (resource-id uint) (days uint))
  (let (
    (borrower tx-sender)
    (resource-data (unwrap! (map-get? shared-resources { resource-id: resource-id }) ERR-MUTUAL-AID-NOT-FOUND))
    (total-cost (* (get daily-cost resource-data) days))
    (borrower-balance (get balance (default-to { balance: u0, joined-at: u0, is-active: false, reputation-score: u0, total-contributions: u0, total-received: u0 } 
                      (map-get? community-members borrower))))
    (resource-owner (get owner resource-data))
  )
    (asserts! (is-some (map-get? community-members borrower)) ERR-MEMBER-NOT-FOUND)
    (asserts! (get is-available resource-data) ERR-RESOURCE-NOT-AVAILABLE)
    (asserts! (>= borrower-balance total-cost) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> days u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer payment to resource owner
    (try! (transfer-currency resource-owner total-cost 
           (some u"Resource rental payment")))
    
    ;; Update resource status
    (map-set shared-resources { resource-id: resource-id }
      (merge resource-data {
        is-available: false,
        current-borrower: (some borrower),
        borrowing-history: (unwrap-panic (as-max-len? (append (get borrowing-history resource-data) borrower) u50)),
        total-usage-days: (+ (get total-usage-days resource-data) days)
      })
    )
    
    (ok total-cost)
  )
)

;; Return shared resource
(define-public (return-resource (resource-id uint))
  (let (
    (returner tx-sender)
    (resource-data (unwrap! (map-get? shared-resources { resource-id: resource-id }) ERR-MUTUAL-AID-NOT-FOUND))
    (current-borrower (get current-borrower resource-data))
  )
    (asserts! (is-some current-borrower) ERR-RESOURCE-NOT-AVAILABLE)
    (asserts! (is-eq (some returner) current-borrower) ERR-NOT-AUTHORIZED)
    
    ;; Update resource status
    (map-set shared-resources { resource-id: resource-id }
      (merge resource-data {
        is-available: true,
        current-borrower: none
      })
    )
    
    (ok true)
  )
)

;; Update exchange rate (coordinator only)
(define-public (update-exchange-rate (new-rate uint))
  (let (
    (caller tx-sender)
    (old-rate (var-get exchange-rate))
  )
    (asserts! (is-coordinator caller) ERR-NOT-AUTHORIZED)
    (asserts! (> new-rate u0) ERR-INVALID-EXCHANGE-RATE)
    
    (var-set exchange-rate new-rate)
    
    ;; Record exchange rate change
    (map-set exchange-history { block-height: block-height } {
      old-rate: old-rate,
      new-rate: new-rate,
      changed-by: caller,
      timestamp: block-height
    })
    
    (ok new-rate)
  )
)

;; Authorize community coordinator
(define-public (authorize-coordinator (coordinator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set community-coordinators coordinator true)
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-member-info (member principal))
  (map-get? community-members member)
)

(define-read-only (get-member-balance (member principal))
  (get balance (default-to { balance: u0, joined-at: u0, is-active: false, reputation-score: u0, total-contributions: u0, total-received: u0 } 
               (map-get? community-members member)))
)

(define-read-only (get-total-supply)
  (var-get total-supply)
)

(define-read-only (get-exchange-rate)
  (var-get exchange-rate)
)

(define-read-only (get-currency-info)
  {
    name: (var-get currency-name),
    symbol: (var-get currency-symbol),
    total-supply: (var-get total-supply),
    exchange-rate: (var-get exchange-rate)
  }
)

(define-read-only (get-mutual-aid-request (request-id uint))
  (map-get? mutual-aid-requests { request-id: request-id })
)

(define-read-only (get-shared-resource (resource-id uint))
  (map-get? shared-resources { resource-id: resource-id })
)

(define-read-only (get-transaction (tx-id uint))
  (map-get? transaction-history { tx-id: tx-id })
)
