(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_STATUS (err u105))
(define-constant ERR_VOTING_CLOSED (err u106))
(define-constant ERR_ALREADY_VOTED (err u107))

(define-data-var total-funds uint u0)
(define-data-var next-request-id uint u1)
(define-data-var voting-duration uint u144)

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
            (map-set maintenance-requests request-id
                (merge request { status: "approved" })
            )
            (map-set maintenance-requests request-id
                (merge request { status: "rejected" })
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
    }
)

(define-read-only (calculate-voting-power (contributor principal))
    (let (
            (balance (get-contributor-balance contributor))
            (total (var-get total-funds))
        )
        (if (> total u0)
            (/ (* balance u100) total)
            u0
        )
    )
)
