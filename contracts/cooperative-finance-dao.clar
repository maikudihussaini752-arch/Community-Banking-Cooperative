;; Cooperative Finance DAO - Democratic decision-making for community lending and investment
;; This contract manages voting, proposals, lending, and collective investment decisions
;; within a community banking cooperative system.

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-AMOUNT (err u201))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u202))
(define-constant ERR-ALREADY-VOTED (err u203))
(define-constant ERR-VOTING-CLOSED (err u204))
(define-constant ERR-LOAN-NOT-FOUND (err u205))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u206))
(define-constant ERR-LOAN-NOT-APPROVED (err u207))
(define-constant ERR-LOAN-ALREADY-FUNDED (err u208))
(define-constant ERR-PAYMENT-OVERDUE (err u209))
(define-constant ERR-INVESTMENT-NOT-FOUND (err u210))
(define-constant ERR-MINIMUM-THRESHOLD-NOT-MET (err u211))
(define-constant ERR-MEMBER-NOT-ELIGIBLE (err u212))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant VOTING-PERIOD u1008) ;; ~7 days in blocks
(define-constant MIN-VOTE-THRESHOLD u3) ;; Minimum votes needed for proposal to pass
(define-constant MAX-LOAN-AMOUNT u100000) ;; Maximum loan amount in local currency
(define-constant COLLATERAL-RATIO u150) ;; 150% collateral requirement

;; DAO governance variables
(define-data-var proposal-counter uint u0)
(define-data-var loan-counter uint u0)
(define-data-var investment-counter uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var total-members uint u0)
(define-data-var loan-interest-rate uint u5) ;; 5% annual interest

;; Member management
(define-map dao-members principal {
  voting-power: uint,
  membership-level: (string-ascii 20), ;; "basic", "active", "coordinator", "founding"
  joined-at: uint,
  total-votes-cast: uint,
  total-proposals-made: uint,
  reputation-score: uint,
  is-eligible: bool
})

;; Proposal system
(define-map governance-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    proposal-type: (string-ascii 30), ;; "lending", "investment", "policy", "treasury"
    title: (string-ascii 100),
    description: (string-utf8 500),
    amount-requested: uint,
    recipient: (optional principal),
    created-at: uint,
    voting-ends-at: uint,
    status: (string-ascii 20), ;; "active", "passed", "rejected", "executed"
    yes-votes: uint,
    no-votes: uint,
    abstain-votes: uint,
    minimum-quorum: uint,
    execution-data: (optional (string-utf8 300))
  }
)

;; Voting records
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  {
    vote: (string-ascii 10), ;; "yes", "no", "abstain"
    voting-power: uint,
    timestamp: uint,
    rationale: (optional (string-utf8 200))
  }
)

;; Community lending system
(define-map loan-applications
  { loan-id: uint }
  {
    borrower: principal,
    loan-amount: uint,
    purpose: (string-utf8 300),
    collateral-amount: uint,
    collateral-type: (string-ascii 50),
    interest-rate: uint,
    term-length: uint, ;; in blocks
    monthly-payment: uint,
    status: (string-ascii 20), ;; "pending", "approved", "funded", "active", "repaid", "defaulted"
    created-at: uint,
    approved-at: (optional uint),
    funded-at: (optional uint),
    next-payment-due: (optional uint),
    total-paid: uint,
    guarantors: (list 5 principal),
    approval-votes: uint,
    rejection-votes: uint
  }
)

;; Loan payment tracking
(define-map loan-payments
  { loan-id: uint, payment-number: uint }
  {
    amount: uint,
    principal-amount: uint,
    interest-amount: uint,
    paid-at: uint,
    late-fee: uint
  }
)

;; Investment opportunities
(define-map investment-opportunities
  { investment-id: uint }
  {
    proposer: principal,
    project-name: (string-ascii 100),
    description: (string-utf8 600),
    funding-goal: uint,
    current-funding: uint,
    funding-deadline: uint,
    expected-return: uint, ;; percentage
    risk-level: (string-ascii 20), ;; "low", "medium", "high"
    status: (string-ascii 20), ;; "open", "funded", "active", "completed", "failed"
    backers: (list 50 principal),
    backer-amounts: (list 50 uint),
    created-at: uint,
    milestones: (list 10 (string-utf8 100))
  }
)

;; Treasury management
(define-map treasury-transactions
  { tx-id: uint }
  {
    transaction-type: (string-ascii 20), ;; "deposit", "withdrawal", "loan", "return"
    amount: uint,
    from-account: (optional principal),
    to-account: (optional principal),
    purpose: (string-utf8 200),
    authorized-by: principal,
    timestamp: uint
  }
)

;; DAO coordinators with special permissions
(define-map dao-coordinators principal bool)

(define-data-var transaction-counter uint u0)

;; Private helper functions

;; Check if caller is DAO coordinator
(define-private (is-dao-coordinator (caller principal))
  (or (is-eq caller CONTRACT-OWNER)
      (default-to false (map-get? dao-coordinators caller))
  )
)

;; Calculate voting power based on membership level and reputation
(define-private (calculate-voting-power (member principal))
  (let (
    (member-data (unwrap! (map-get? dao-members member) u0))
    (base-power u1)
    (level (get membership-level member-data))
    (reputation (get reputation-score member-data))
  )
    (+ base-power 
       (if (is-eq level "founding") u3
           (if (is-eq level "coordinator") u2
               (if (is-eq level "active") u1 u0)))
       (/ reputation u10)
    )
  )
)

;; Check if proposal has reached quorum
(define-private (has-reached-quorum (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) false))
    (total-votes (+ (+ (get yes-votes proposal) (get no-votes proposal)) (get abstain-votes proposal)))
    (required-quorum (get minimum-quorum proposal))
  )
    (>= total-votes required-quorum)
  )
)

;; Public functions

;; Join DAO as member
(define-public (join-dao (membership-level (string-ascii 20)))
  (let (
    (caller tx-sender)
    (existing-member (map-get? dao-members caller))
  )
    (asserts! (is-none existing-member) ERR-NOT-AUTHORIZED)
    
    (map-set dao-members caller {
      voting-power: (calculate-voting-power caller),
      membership-level: membership-level,
      joined-at: stacks-block-height,
      total-votes-cast: u0,
      total-proposals-made: u0,
      reputation-score: u10,
      is-eligible: true
    })
    
    (var-set total-members (+ (var-get total-members) u1))
    (ok true)
  )
)

;; Create governance proposal
(define-public (create-proposal
  (proposal-type (string-ascii 30))
  (title (string-ascii 100))
  (description (string-utf8 500))
  (amount-requested uint)
  (recipient (optional principal))
)
  (let (
    (proposer tx-sender)
    (proposal-id (var-get proposal-counter))
    (voting-ends (+ stacks-block-height VOTING-PERIOD))
    (quorum (let ((calc-quorum (/ (var-get total-members) u3)))
              (if (> calc-quorum MIN-VOTE-THRESHOLD) calc-quorum MIN-VOTE-THRESHOLD)))
  )
    (asserts! (is-some (map-get? dao-members proposer)) ERR-MEMBER-NOT-ELIGIBLE)
    (asserts! (get is-eligible (unwrap! (map-get? dao-members proposer) ERR-MEMBER-NOT-ELIGIBLE)) ERR-MEMBER-NOT-ELIGIBLE)
    
    (map-set governance-proposals { proposal-id: proposal-id } {
      proposer: proposer,
      proposal-type: proposal-type,
      title: title,
      description: description,
      amount-requested: amount-requested,
      recipient: recipient,
      created-at: stacks-block-height,
      voting-ends-at: voting-ends,
      status: "active",
      yes-votes: u0,
      no-votes: u0,
      abstain-votes: u0,
      minimum-quorum: quorum,
      execution-data: none
    })
    
    ;; Update proposer stats
    (map-set dao-members proposer
      (merge 
        (unwrap! (map-get? dao-members proposer) ERR-MEMBER-NOT-ELIGIBLE)
        { total-proposals-made: (+ (get total-proposals-made 
                                    (unwrap! (map-get? dao-members proposer) ERR-MEMBER-NOT-ELIGIBLE)) u1) }
      )
    )
    
    (var-set proposal-counter (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Vote on governance proposal
(define-public (vote-on-proposal
  (proposal-id uint)
  (vote (string-ascii 10))
  (rationale (optional (string-utf8 200)))
)
  (let (
    (voter tx-sender)
    (proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
    (existing-vote (map-get? proposal-votes { proposal-id: proposal-id, voter: voter }))
    (member-data (unwrap! (map-get? dao-members voter) ERR-MEMBER-NOT-ELIGIBLE))
    (voting-power (calculate-voting-power voter))
  )
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    (asserts! (<= stacks-block-height (get voting-ends-at proposal)) ERR-VOTING-CLOSED)
    (asserts! (get is-eligible member-data) ERR-MEMBER-NOT-ELIGIBLE)
    (asserts! (is-eq (get status proposal) "active") ERR-VOTING-CLOSED)
    
    ;; Record vote
    (map-set proposal-votes { proposal-id: proposal-id, voter: voter } {
      vote: vote,
      voting-power: voting-power,
      timestamp: stacks-block-height,
      rationale: rationale
    })
    
    ;; Update proposal vote counts
    (let (
      (new-yes (if (is-eq vote "yes") (+ (get yes-votes proposal) voting-power) (get yes-votes proposal)))
      (new-no (if (is-eq vote "no") (+ (get no-votes proposal) voting-power) (get no-votes proposal)))
      (new-abstain (if (is-eq vote "abstain") (+ (get abstain-votes proposal) voting-power) (get abstain-votes proposal)))
    )
      (map-set governance-proposals { proposal-id: proposal-id }
        (merge proposal {
          yes-votes: new-yes,
          no-votes: new-no,
          abstain-votes: new-abstain
        })
      )
    )
    
    ;; Update voter stats
    (map-set dao-members voter
      (merge member-data {
        total-votes-cast: (+ (get total-votes-cast member-data) u1)
      })
    )
    
    (ok voting-power)
  )
)

;; Execute approved proposal
(define-public (execute-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
    (executor tx-sender)
  )
    (asserts! (> stacks-block-height (get voting-ends-at proposal)) ERR-VOTING-CLOSED)
    (asserts! (has-reached-quorum proposal-id) ERR-MINIMUM-THRESHOLD-NOT-MET)
    (asserts! (> (get yes-votes proposal) (get no-votes proposal)) ERR-MINIMUM-THRESHOLD-NOT-MET)
    
    ;; Execute based on proposal type
    (let (
      (proposal-type (get proposal-type proposal))
      (amount (get amount-requested proposal))
    )
      (if (is-eq proposal-type "treasury")
        (begin
          (asserts! (is-dao-coordinator executor) ERR-NOT-AUTHORIZED)
          (var-set treasury-balance (+ (var-get treasury-balance) amount))
        )
        (if (is-eq proposal-type "lending")
          (begin
            ;; Create approved loan opportunity
            (var-set loan-counter (+ (var-get loan-counter) u1))
          )
          true ;; Other proposal types handled elsewhere
        )
      )
    )
    
    ;; Mark proposal as executed
    (map-set governance-proposals { proposal-id: proposal-id }
      (merge proposal { status: "executed" })
    )
    
    (ok true)
  )
)

;; Apply for community loan
(define-public (apply-for-loan
  (loan-amount uint)
  (purpose (string-utf8 300))
  (collateral-amount uint)
  (collateral-type (string-ascii 50))
  (term-length uint)
  (guarantors (list 5 principal))
)
  (let (
    (borrower tx-sender)
    (loan-id (var-get loan-counter))
    (required-collateral (/ (* loan-amount COLLATERAL-RATIO) u100))
    (interest-rate (var-get loan-interest-rate))
    (monthly-payment (/ (* loan-amount (+ u100 interest-rate)) (* term-length u12)))
  )
    (asserts! (is-some (map-get? dao-members borrower)) ERR-MEMBER-NOT-ELIGIBLE)
    (asserts! (<= loan-amount MAX-LOAN-AMOUNT) ERR-INVALID-AMOUNT)
    (asserts! (>= collateral-amount required-collateral) ERR-INSUFFICIENT-COLLATERAL)
    (asserts! (> term-length u0) ERR-INVALID-AMOUNT)
    
    (map-set loan-applications { loan-id: loan-id } {
      borrower: borrower,
      loan-amount: loan-amount,
      purpose: purpose,
      collateral-amount: collateral-amount,
      collateral-type: collateral-type,
      interest-rate: interest-rate,
      term-length: term-length,
      monthly-payment: monthly-payment,
      status: "pending",
      created-at: stacks-block-height,
      approved-at: none,
      funded-at: none,
      next-payment-due: none,
      total-paid: u0,
      guarantors: guarantors,
      approval-votes: u0,
      rejection-votes: u0
    })
    
    (var-set loan-counter (+ loan-id u1))
    (ok loan-id)
  )
)

;; Vote on loan application
(define-public (vote-on-loan (loan-id uint) (approve bool))
  (let (
    (voter tx-sender)
    (loan (unwrap! (map-get? loan-applications { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    (member-data (unwrap! (map-get? dao-members voter) ERR-MEMBER-NOT-ELIGIBLE))
  )
    (asserts! (get is-eligible member-data) ERR-MEMBER-NOT-ELIGIBLE)
    (asserts! (is-eq (get status loan) "pending") ERR-LOAN-NOT-APPROVED)
    
    (let (
      (new-approval-votes (if approve (+ (get approval-votes loan) u1) (get approval-votes loan)))
      (new-rejection-votes (if (not approve) (+ (get rejection-votes loan) u1) (get rejection-votes loan)))
    )
      (map-set loan-applications { loan-id: loan-id }
        (merge loan {
          approval-votes: new-approval-votes,
          rejection-votes: new-rejection-votes,
          status: (if (>= new-approval-votes MIN-VOTE-THRESHOLD) "approved" 
                      (if (>= new-rejection-votes MIN-VOTE-THRESHOLD) "rejected" "pending"))
        })
      )
    )
    
    (ok true)
  )
)

;; Fund approved loan
(define-public (fund-loan (loan-id uint))
  (let (
    (funder tx-sender)
    (loan (unwrap! (map-get? loan-applications { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    (loan-amount (get loan-amount loan))
  )
    (asserts! (is-dao-coordinator funder) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status loan) "approved") ERR-LOAN-NOT-APPROVED)
    (asserts! (>= (var-get treasury-balance) loan-amount) ERR-INVALID-AMOUNT)
    
    ;; Update loan status
    (map-set loan-applications { loan-id: loan-id }
      (merge loan {
        status: "funded",
        funded-at: (some stacks-block-height),
        next-payment-due: (some (+ stacks-block-height u720)) ;; ~30 days
      })
    )
    
    ;; Update treasury
    (var-set treasury-balance (- (var-get treasury-balance) loan-amount))
    
    ;; Record treasury transaction
    (map-set treasury-transactions { tx-id: (var-get transaction-counter) } {
      transaction-type: "loan",
      amount: loan-amount,
      from-account: none,
      to-account: (some (get borrower loan)),
      purpose: u"Loan disbursement",
      authorized-by: funder,
      timestamp: stacks-block-height
    })
    
    (var-set transaction-counter (+ (var-get transaction-counter) u1))
    (ok loan-amount)
  )
)

;; Make loan payment
(define-public (make-loan-payment (loan-id uint) (payment-amount uint))
  (let (
    (borrower tx-sender)
    (loan (unwrap! (map-get? loan-applications { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    (payment-number (+ (/ (get total-paid loan) (get monthly-payment loan)) u1))
  )
    (asserts! (is-eq borrower (get borrower loan)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status loan) "funded") ERR-LOAN-NOT-APPROVED)
    (asserts! (>= payment-amount (get monthly-payment loan)) ERR-INVALID-AMOUNT)
    
    ;; Calculate interest and principal
    (let (
      (interest-portion (/ (* payment-amount (get interest-rate loan)) u100))
      (principal-portion (- payment-amount interest-portion))
    )
      ;; Record payment
      (map-set loan-payments { loan-id: loan-id, payment-number: payment-number } {
        amount: payment-amount,
        principal-amount: principal-portion,
        interest-amount: interest-portion,
        paid-at: stacks-block-height,
        late-fee: u0
      })
      
      ;; Update loan status
      (let (
        (new-total-paid (+ (get total-paid loan) payment-amount))
        (total-owed (* (get monthly-payment loan) (get term-length loan)))
      )
        (map-set loan-applications { loan-id: loan-id }
          (merge loan {
            total-paid: new-total-paid,
            status: (if (>= new-total-paid total-owed) "repaid" "active"),
            next-payment-due: (some (+ stacks-block-height u720))
          })
        )
      )
      
      ;; Add to treasury
      (var-set treasury-balance (+ (var-get treasury-balance) payment-amount))
    )
    
    (ok payment-amount)
  )
)

;; Create investment opportunity
(define-public (create-investment-opportunity
  (project-name (string-ascii 100))
  (description (string-utf8 600))
  (funding-goal uint)
  (funding-deadline uint)
  (expected-return uint)
  (risk-level (string-ascii 20))
)
  (let (
    (proposer tx-sender)
    (investment-id (var-get investment-counter))
  )
    (asserts! (is-some (map-get? dao-members proposer)) ERR-MEMBER-NOT-ELIGIBLE)
    (asserts! (> funding-goal u0) ERR-INVALID-AMOUNT)
    (asserts! (> funding-deadline stacks-block-height) ERR-INVALID-AMOUNT)
    
    (map-set investment-opportunities { investment-id: investment-id } {
      proposer: proposer,
      project-name: project-name,
      description: description,
      funding-goal: funding-goal,
      current-funding: u0,
      funding-deadline: funding-deadline,
      expected-return: expected-return,
      risk-level: risk-level,
      status: "open",
      backers: (list),
      backer-amounts: (list),
      created-at: stacks-block-height,
      milestones: (list)
    })
    
    (var-set investment-counter (+ investment-id u1))
    (ok investment-id)
  )
)

;; Invest in community project
(define-public (invest-in-project (investment-id uint) (investment-amount uint))
  (let (
    (investor tx-sender)
    (investment (unwrap! (map-get? investment-opportunities { investment-id: investment-id }) ERR-INVESTMENT-NOT-FOUND))
  )
    (asserts! (is-some (map-get? dao-members investor)) ERR-MEMBER-NOT-ELIGIBLE)
    (asserts! (is-eq (get status investment) "open") ERR-VOTING-CLOSED)
    (asserts! (>= (get funding-deadline investment) stacks-block-height) ERR-VOTING-CLOSED)
    (asserts! (> investment-amount u0) ERR-INVALID-AMOUNT)
    
    (let (
      (new-funding (+ (get current-funding investment) investment-amount))
      (goal (get funding-goal investment))
    )
      (map-set investment-opportunities { investment-id: investment-id }
        (merge investment {
          current-funding: new-funding,
          status: (if (>= new-funding goal) "funded" "open"),
          backers: (unwrap-panic (as-max-len? (append (get backers investment) investor) u50)),
          backer-amounts: (unwrap-panic (as-max-len? (append (get backer-amounts investment) investment-amount) u50))
        })
      )
    )
    
    (ok investment-amount)
  )
)

;; Authorize DAO coordinator
(define-public (authorize-dao-coordinator (coordinator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set dao-coordinators coordinator true)
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-dao-member (member principal))
  (map-get? dao-members member)
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-loan-application (loan-id uint))
  (map-get? loan-applications { loan-id: loan-id })
)

(define-read-only (get-loan-payment (loan-id uint) (payment-number uint))
  (map-get? loan-payments { loan-id: loan-id, payment-number: payment-number })
)

(define-read-only (get-investment (investment-id uint))
  (map-get? investment-opportunities { investment-id: investment-id })
)

(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (get-dao-stats)
  {
    total-members: (var-get total-members),
    treasury-balance: (var-get treasury-balance),
    total-proposals: (var-get proposal-counter),
    total-loans: (var-get loan-counter),
    total-investments: (var-get investment-counter),
    current-interest-rate: (var-get loan-interest-rate)
  }
)

