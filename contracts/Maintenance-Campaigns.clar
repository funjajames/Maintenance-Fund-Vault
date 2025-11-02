(define-constant ERR_UNAUTHORIZED (err u900))
(define-constant ERR_INVALID (err u901))
(define-constant ERR_NOT_FOUND (err u902))
(define-constant ERR_TOO_EARLY (err u903))
(define-constant ERR_TOO_LATE (err u904))
(define-constant ERR_ALREADY_FINALIZED (err u905))
(define-constant ERR_NOT_FINALIZED (err u906))
(define-constant ERR_ALREADY_CLAIMED (err u907))
(define-constant ERR_INSUFFICIENT (err u908))

(define-data-var next-campaign-id uint u1)

(define-map campaigns
    uint
    {
        creator: principal,
        target-amount: uint,
        deadline: uint,
        total-raised: uint,
        finalized: bool,
        success: bool,
        payout-claimed: bool,
    }
)

(define-map contributions
    {
        campaign-id: uint,
        contributor: principal,
    }
    uint
)

(define-read-only (get-campaign (id uint))
    (map-get? campaigns id)
)

(define-read-only (get-contribution
        (id uint)
        (who principal)
    )
    (map-get? contributions {
        campaign-id: id,
        contributor: who,
    })
)

(define-read-only (get-campaign-stats (id uint))
    (map-get? campaigns id)
)

(define-public (create-campaign
        (target uint)
        (duration uint)
    )
    (let (
            (id (var-get next-campaign-id))
            (now stacks-block-height)
        )
        (asserts! (> target u0) ERR_INVALID)
        (asserts! (> duration u0) ERR_INVALID)
        (map-set campaigns id {
            creator: tx-sender,
            target-amount: target,
            deadline: (+ now duration),
            total-raised: u0,
            finalized: false,
            success: false,
            payout-claimed: false,
        })
        (var-set next-campaign-id (+ id u1))
        (ok id)
    )
)

(define-public (contribute-to-campaign
        (id uint)
        (amount uint)
    )
    (let (
            (data (unwrap! (map-get? campaigns id) ERR_NOT_FOUND))
            (now stacks-block-height)
            (prev (default-to u0
                (map-get? contributions {
                    campaign-id: id,
                    contributor: tx-sender,
                })
            ))
        )
        (asserts! (not (get finalized data)) ERR_ALREADY_FINALIZED)
        (asserts! (> amount u0) ERR_INVALID)
        (asserts! (<= now (get deadline data)) ERR_TOO_LATE)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set contributions {
            campaign-id: id,
            contributor: tx-sender,
        }
            (+ prev amount)
        )
        (map-set campaigns id
            (merge data { total-raised: (+ (get total-raised data) amount) })
        )
        (ok amount)
    )
)

(define-public (finalize-campaign (id uint))
    (let (
            (data (unwrap! (map-get? campaigns id) ERR_NOT_FOUND))
            (now stacks-block-height)
        )
        (asserts! (is-eq (get creator data) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (get finalized data)) ERR_ALREADY_FINALIZED)
        (asserts! (> now (get deadline data)) ERR_TOO_EARLY)
        (map-set campaigns id
            (merge data {
                finalized: true,
                success: (>= (get total-raised data) (get target-amount data)),
            })
        )
        (ok id)
    )
)

(define-public (claim-payout (id uint))
    (let ((data (unwrap! (map-get? campaigns id) ERR_NOT_FOUND)))
        (asserts! (is-eq (get creator data) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (get finalized data) ERR_NOT_FINALIZED)
        (asserts! (get success data) ERR_INVALID)
        (asserts! (not (get payout-claimed data)) ERR_ALREADY_CLAIMED)
        (try! (as-contract (stx-transfer? (get total-raised data) tx-sender tx-sender)))
        (map-set campaigns id (merge data { payout-claimed: true }))
        (ok (get total-raised data))
    )
)

(define-public (refund
        (id uint)
        (amount uint)
    )
    (let (
            (data (unwrap! (map-get? campaigns id) ERR_NOT_FOUND))
            (contrib (default-to u0
                (map-get? contributions {
                    campaign-id: id,
                    contributor: tx-sender,
                })
            ))
        )
        (asserts! (get finalized data) ERR_NOT_FINALIZED)
        (asserts! (not (get success data)) ERR_INVALID)
        (asserts! (> amount u0) ERR_INVALID)
        (asserts! (<= amount contrib) ERR_INSUFFICIENT)
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (map-set contributions {
            campaign-id: id,
            contributor: tx-sender,
        }
            (- contrib amount)
        )
        (map-set campaigns id
            (merge data { total-raised: (- (get total-raised data) amount) })
        )
        (ok amount)
    )
)
