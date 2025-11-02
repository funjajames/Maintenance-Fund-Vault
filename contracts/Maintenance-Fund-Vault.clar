(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_STATUS (err u105))
(define-constant ERR_VOTING_CLOSED (err u106))
(define-constant ERR_ALREADY_VOTED (err u107))
(define-constant ERR_MILESTONE_ALREADY_CLAIMED (err u108))
(define-constant ERR_MILESTONE_NOT_REACHED (err u109))

(define-data-var total-funds uint u0)
(define-data-var next-request-id uint u1)
(define-data-var voting-duration uint u144)
(define-data-var total-funds-distributed uint u0)
(define-data-var total-approved-requests uint u0)
(define-data-var total-rejected-requests uint u0)
(define-data-var next-milestone-id uint u1)

(define-map contributors
    principal
    uint
)
(define-map maintenance-requests
    uint
    {
        requester: principal,
        amount: uint,
        description: (string-ascii 500),
        status: (string-ascii 20),
        votes-for: uint,
        votes-against: uint,
        created-at: uint,
        voting-ends: uint,
    }
)
(define-map user-votes
    {
        request-id: uint,
        voter: principal,
    }
    bool
)
(define-map approved-vendors
    principal
    bool
)

;; NEW: Fund Milestone System Maps
(define-map fund-milestones
    uint
    {
        target-amount: uint,
        reward-percentage: uint,
        description: (string-ascii 200),
        created-at: uint,
        is-active: bool,
        total-claimed: uint,
    }
)
(define-map milestone-claims
    {
        milestone-id: uint,
        claimer: principal,
    }
    {
        amount-claimed: uint,
        claimed-at: uint,
    }
)

(define-read-only (get-total-funds)
    (var-get total-funds)
)

(define-read-only (get-contributor-balance (contributor principal))
    (default-to u0 (map-get? contributors contributor))
)

(define-read-only (get-maintenance-request (request-id uint))
    (map-get? maintenance-requests request-id)
)

(define-read-only (get-voting-duration)
    (var-get voting-duration)
)

(define-read-only (has-voted
        (request-id uint)
        (voter principal)
    )
    (is-some (map-get? user-votes {
        request-id: request-id,
        voter: voter,
    }))
)

(define-read-only (is-approved-vendor (vendor principal))
    (default-to false (map-get? approved-vendors vendor))
)

(define-read-only (get-request-status (request-id uint))
    (match (map-get? maintenance-requests request-id)
        request (some (get status request))
        none
    )
)

;; NEW: Fund Milestone Read-Only Functions
(define-read-only (get-milestone (milestone-id uint))
    (map-get? fund-milestones milestone-id)
)

(define-read-only (get-milestone-claim
        (milestone-id uint)
        (claimer principal)
    )
    (map-get? milestone-claims {
        milestone-id: milestone-id,
        claimer: claimer,
    })
)

(define-read-only (calculate-milestone-reward
        (milestone-id uint)
        (contributor principal)
    )
    (let (
            (milestone (unwrap! (map-get? fund-milestones milestone-id) (err u0)))
            (contributor-balance (get-contributor-balance contributor))
            (current-total-funds (var-get total-funds))
            (reward-percentage (get reward-percentage milestone))
            (target-amount (get target-amount milestone))
        )
        (if (and
                (>= current-total-funds target-amount)
                (> contributor-balance u0)
                (get is-active milestone)
            )
            (ok (/ (* contributor-balance reward-percentage) u100))
            (ok u0)
        )
    )
)

(define-read-only (get-active-milestones)
    (let (
            (current-milestone-id (var-get next-milestone-id))
            (current-funds (var-get total-funds))
        )
        ;; Return info about milestones that can be achieved with current funds
        {
            current-funds: current-funds,
            next-milestone-id: current-milestone-id,
            total-milestone-count: (- current-milestone-id u1),
        }
    )
)

(define-public (contribute (amount uint))
    (begin
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set total-funds (+ (var-get total-funds) amount))
        (map-set contributors tx-sender
            (+ (get-contributor-balance tx-sender) amount)
        )
        (ok amount)
    )
)

(define-public (submit-maintenance-request
        (amount uint)
        (description (string-ascii 500))
    )
    (let (
            (request-id (var-get next-request-id))
            (current-block stacks-block-height)
        )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (> (len description) u0) ERR_INVALID_AMOUNT)
        (map-set maintenance-requests request-id {
            requester: tx-sender,
            amount: amount,
            description: description,
            status: "pending",
            votes-for: u0,
            votes-against: u0,
            created-at: current-block,
            voting-ends: (+ current-block (var-get voting-duration)),
        })
        (var-set next-request-id (+ request-id u1))
        (ok request-id)
    )
)

(define-public (vote-on-request
        (request-id uint)
        (vote-for bool)
    )
    (let (
            (request (unwrap! (map-get? maintenance-requests request-id) ERR_NOT_FOUND))
            (current-block stacks-block-height)
            (contributor-balance (get-contributor-balance tx-sender))
        )
        (asserts! (> contributor-balance u0) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status request) "pending") ERR_INVALID_STATUS)
        (asserts! (<= current-block (get voting-ends request)) ERR_VOTING_CLOSED)
        (asserts! (not (has-voted request-id tx-sender)) ERR_ALREADY_VOTED)

        (map-set user-votes {
            request-id: request-id,
            voter: tx-sender,
        }
            vote-for
        )

        (if vote-for
            (map-set maintenance-requests request-id
                (merge request { votes-for: (+ (get votes-for request) contributor-balance) })
            )
            (map-set maintenance-requests request-id
                (merge request { votes-against: (+ (get votes-against request) contributor-balance) })
            )
        )
        (ok vote-for)
    )
)

(define-public (finalize-request (request-id uint))
    (let (
            (request (unwrap! (map-get? maintenance-requests request-id) ERR_NOT_FOUND))
            (current-block stacks-block-height)
            (total-votes (+ (get votes-for request) (get votes-against request)))
            (approval-threshold (/ (var-get total-funds) u2))
        )
        (asserts! (is-eq (get status request) "pending") ERR_INVALID_STATUS)
        (asserts! (> current-block (get voting-ends request)) ERR_VOTING_CLOSED)

        (if (and
                (>= (get votes-for request) approval-threshold)
                (> (get votes-for request) (get votes-against request))
            )
            (begin
                (map-set maintenance-requests request-id
                    (merge request { status: "approved" })
                )
                (var-set total-approved-requests
                    (+ (var-get total-approved-requests) u1)
                )
            )
            (begin
                (map-set maintenance-requests request-id
                    (merge request { status: "rejected" })
                )
                (var-set total-rejected-requests
                    (+ (var-get total-rejected-requests) u1)
                )
            )
        )
        (ok (get status
            (unwrap! (map-get? maintenance-requests request-id) ERR_NOT_FOUND)
        ))
    )
)

(define-public (execute-approved-request (request-id uint))
    (let (
            (request (unwrap! (map-get? maintenance-requests request-id) ERR_NOT_FOUND))
            (amount (get amount request))
            (requester (get requester request))
        )
        (asserts! (is-eq (get status request) "approved") ERR_INVALID_STATUS)
        (asserts! (>= (var-get total-funds) amount) ERR_INSUFFICIENT_FUNDS)
        (asserts!
            (or
                (is-eq tx-sender CONTRACT_OWNER)
                (is-approved-vendor tx-sender)
            )
            ERR_UNAUTHORIZED
        )

        (try! (as-contract (stx-transfer? amount tx-sender requester)))
        (var-set total-funds (- (var-get total-funds) amount))
        (var-set total-funds-distributed
            (+ (var-get total-funds-distributed) amount)
        )
        (map-set maintenance-requests request-id
            (merge request { status: "executed" })
        )
        (ok amount)
    )
)

(define-public (withdraw-contribution (amount uint))
    (let (
            (contributor-balance (get-contributor-balance tx-sender))
            (max-withdrawal (if (<= contributor-balance (/ (var-get total-funds) u4))
                contributor-balance
                (/ (var-get total-funds) u4)
            ))
        )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount max-withdrawal) ERR_INSUFFICIENT_FUNDS)
        (asserts! (>= (var-get total-funds) amount) ERR_INSUFFICIENT_FUNDS)

        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (var-set total-funds (- (var-get total-funds) amount))
        (map-set contributors tx-sender (- contributor-balance amount))
        (ok amount)
    )
)

;; NEW: Fund Milestone System Functions
(define-public (create-milestone
        (target-amount uint)
        (reward-percentage uint)
        (description (string-ascii 200))
    )
    (let (
            (milestone-id (var-get next-milestone-id))
            (current-block stacks-block-height)
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> target-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= reward-percentage u10) ERR_INVALID_AMOUNT)
        ;; Max 10% reward
        (asserts! (> (len description) u0) ERR_INVALID_AMOUNT)

        (map-set fund-milestones milestone-id {
            target-amount: target-amount,
            reward-percentage: reward-percentage,
            description: description,
            created-at: current-block,
            is-active: true,
            total-claimed: u0,
        })
        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

(define-public (claim-milestone-reward (milestone-id uint))
    (let (
            (milestone (unwrap! (map-get? fund-milestones milestone-id) ERR_NOT_FOUND))
            (contributor-balance (get-contributor-balance tx-sender))
            (current-funds (var-get total-funds))
            (target-amount (get target-amount milestone))
            (reward-percentage (get reward-percentage milestone))
            (reward-amount (unwrap! (calculate-milestone-reward milestone-id tx-sender)
                ERR_INVALID_AMOUNT
            ))
            (current-block stacks-block-height)
        )
        (asserts! (get is-active milestone) ERR_INVALID_STATUS)
        (asserts! (>= current-funds target-amount) ERR_MILESTONE_NOT_REACHED)
        (asserts! (> contributor-balance u0) ERR_UNAUTHORIZED)
        (asserts! (> reward-amount u0) ERR_INVALID_AMOUNT)
        (asserts!
            (is-none (map-get? milestone-claims {
                milestone-id: milestone-id,
                claimer: tx-sender,
            }))
            ERR_MILESTONE_ALREADY_CLAIMED
        )

        ;; Record the claim
        (map-set milestone-claims {
            milestone-id: milestone-id,
            claimer: tx-sender,
        } {
            amount-claimed: reward-amount,
            claimed-at: current-block,
        })

        ;; Update milestone total claimed
        (map-set fund-milestones milestone-id
            (merge milestone { total-claimed: (+ (get total-claimed milestone) reward-amount) })
        )

        ;; Transfer reward (from contract balance as bonus)
        (try! (as-contract (stx-transfer? reward-amount tx-sender tx-sender)))

        (ok reward-amount)
    )
)

(define-public (deactivate-milestone (milestone-id uint))
    (let ((milestone (unwrap! (map-get? fund-milestones milestone-id) ERR_NOT_FOUND)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (get is-active milestone) ERR_INVALID_STATUS)

        (map-set fund-milestones milestone-id
            (merge milestone { is-active: false })
        )
        (ok milestone-id)
    )
)

(define-public (add-approved-vendor (vendor principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set approved-vendors vendor true)
        (ok vendor)
    )
)

(define-public (remove-approved-vendor (vendor principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-delete approved-vendors vendor)
        (ok vendor)
    )
)

(define-public (update-voting-duration (new-duration uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> new-duration u0) ERR_INVALID_AMOUNT)
        (var-set voting-duration new-duration)
        (ok new-duration)
    )
)

(define-public (emergency-withdraw)
    (let ((contract-balance (var-get total-funds)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> contract-balance u0) ERR_INSUFFICIENT_FUNDS)

        (try! (as-contract (stx-transfer? contract-balance tx-sender CONTRACT_OWNER)))
        (var-set total-funds u0)
        (ok contract-balance)
    )
)

(define-read-only (get-contract-info)
    {
        total-funds: (var-get total-funds),
        next-request-id: (var-get next-request-id),
        voting-duration: (var-get voting-duration),
        contract-owner: CONTRACT_OWNER,
        next-milestone-id: (var-get next-milestone-id),
    }
)

(define-read-only (calculate-voting-power (contributor principal))
    (let (
            (balance (get-contributor-balance contributor))
            (total-fund-balance (var-get total-funds))
        )
        (if (> total-fund-balance u0)
            (/ (* balance u100) total-fund-balance)
            u0
        )
    )
)

(define-read-only (get-fund-analytics)
    (let (
            (current-funds (var-get total-funds))
            (distributed-funds (var-get total-funds-distributed))
            (approved-count (var-get total-approved-requests))
            (rejected-count (var-get total-rejected-requests))
            (total-requests (+ approved-count rejected-count))
        )
        {
            total-funds-raised: (+ current-funds distributed-funds),
            current-fund-balance: current-funds,
            total-distributed: distributed-funds,
            utilization-rate: (if (> (+ current-funds distributed-funds) u0)
                (/ (* distributed-funds u100) (+ current-funds distributed-funds))
                u0
            ),
            total-requests: total-requests,
            approved-requests: approved-count,
            rejected-requests: rejected-count,
            approval-rate: (if (> total-requests u0)
                (/ (* approved-count u100) total-requests)
                u0
            ),
        }
    )
)

(define-read-only (get-performance-metrics)
    (let (
            (analytics (get-fund-analytics))
            (efficiency-score (/ (+ (get utilization-rate analytics) (get approval-rate analytics))
                u2
            ))
        )
        {
            fund-efficiency-score: efficiency-score,
            is-performing-well: (> efficiency-score u50),
            funds-utilization-status: (if (> (get utilization-rate analytics) u75)
                "high-activity"
                (if (> (get utilization-rate analytics) u25)
                    "moderate-activity"
                    "low-activity"
                )
            ),
        }
    )
)

;; NEW: Enhanced analytics including milestone data
(define-read-only (get-milestone-analytics)
    (let (
            (total-milestones (- (var-get next-milestone-id) u1))
            (current-funds (var-get total-funds))
        )
        {
            total-milestones-created: total-milestones,
            current-fund-level: current-funds,
            milestone-system-active: (> total-milestones u0),
        }
    )
)
