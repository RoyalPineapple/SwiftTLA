import SwiftTLA

// Lamport's distributed mutual-exclusion algorithm.
// N=2 processes, maxClock=2. Uses nested functions, Head/Tail, @ self-ref.
// Port: 1:1 translation. Mutex safety. 19 states.
// Upstream: specifications/lamport_mutex/LamportMutex.tla

extension Example {
    static let lamportMutexN2 = Example.Entry(
        id: "lamport_mutex/LamportMutex_N2",
        upstreamSpec: "lamport_mutex",
        upstreamModule: "specifications/lamport_mutex/LamportMutex.tla",
        upstreamCfg: "specifications/lamport_mutex/MCLamportMutex.cfg",
        expectedDistinct: 19,
        spec: lamportMutexSpec(),
        notes: "N=2, maxClock=2. Nested functions + sequences + @ self-ref. Constraint bounds clocks.",
    )
}

private func lamportMutexSpec() -> TLASpec {
    let N = 2
    let nodes = Array(1...N)

    let clock   = Var<TLAFunctionType>("clock")
    let req     = Var<TLAFunctionType>("req")
    let ack     = Var<TLAFunctionType>("ack")
    let network = Var<TLAFunctionType>("network")
    let crit    = Var<TLASetType>("crit")

    func reqMsg(_ c: Int) -> StateExpr {
        .recordLiteral(["type": .value(.string("req")), "clock": .value(.int(c))])
    }
    let ackMsg: StateExpr = .recordLiteral(["type": .value(.string("ack")), "clock": .value(.int(0))])
    let relMsg: StateExpr = .recordLiteral(["type": .value(.string("rel")), "clock": .value(.int(0))])

    let dict: [TLAValue: TLAValue] = [
        .int(1): TLAValue.function([.int(1): 0, .int(2): 0]),
        .int(2): TLAValue.function([.int(1): 0, .int(2): 0])]
    return TLASpec("LamportMutex") {
        Extends("Integers")
        Variable(clock, TLAValue.function([.int(1): 1, .int(2): 1]))
        Variable(req, TLAValue.function(dict))
        Variable(ack, TLAValue.function([.int(1): TLAValue.set([]), .int(2): TLAValue.set([])]))
        Variable(network, TLAValue.function([
            .int(1): TLAValue.function([.int(2): TLAValue.tuple([])]),
            .int(2): TLAValue.function([.int(1): TLAValue.tuple([])])]))
        Variable(crit, TLAValue.set([]))

        Invariant("Mutex") { crit.cardinality <= 1 }
        Constraint(clock.applying(1) <= 2 && clock.applying(2) <= 2)

        for p in nodes {
            let q = p == 1 ? 2 : 1
            // Request: set own req, broadcast, set ack
            Action("Request_\(p)") {
                req.applying(p).applying(p) == 0
                && req.becomes(req.updated(at: p,
                    to: req.applying(p).updated(at: p, to: clock.applying(p))))
                && network.becomes(network.updated(at: p,
                    to: network.applying(p).updated(at: q,
                        to: network.applying(p).applying(q).appending(reqMsg(p)))))
                && ack.becomes(Expr(.except(ack, p, StateExpr.setLiteral([StateExpr.value(.int(p)))])))
                && clock.stays && crit.stays
            }
            // ReceiveRequest from q: update clock, req, network
            Action("ReceiveReq_\(p)_\(q)") {
                let m = network.applying(q).applying(p)
                m.count > 0 && StateExpr.recordAccess(m.head, "type") == "req"
                && req.becomes(req.updated(at: p,
                    to: req.applying(p).updated(at: q, to: StateExpr.recordAccess(m.head, "clock"))))
                && clock.becomes(clock.updated(at: p,
                    to: StateExpr.if(StateExpr.recordAccess(m.head, "clock") > clock.applying(p),
                        then: StateExpr.recordAccess(m.head, "clock") + 1, else: clock.applying(p) + 1)))
                && network.becomes(network
                    .updated(at: q, to: network.applying(q).updated(at: p, to: m.tail))
                    .updated(at: p, to: network.applying(p).updated(at: q,
                        to: network.applying(p).applying(q).appending(ackMsg))))
                && ack.stays && crit.stays
            }
            // ReceiveAck from q
            Action("ReceiveAck_\(p)_\(q)") {
                let m = network.applying(q).applying(p)
                m.count > 0 && StateExpr.recordAccess(m.head, "type") == "ack"
                && ack.becomes(ack.updated(at: p,
                    to: ack.applying(p).union(StateExpr.setLiteral([StateExpr.value(.int(q))]))))
                && network.becomes(network.updated(at: q,
                    to: network.applying(q).updated(at: p, to: m.tail)))
                && clock.stays && req.stays && crit.stays
            }
            // Enter critical section
            Action("Enter_\(p)") {
                ack.applying(p).cardinality == N
                && (req.applying(p).applying(q) == 0
                    || req.applying(p).applying(p) < req.applying(p).applying(q)
                    || (StateExpr.equal(req.applying(p).applying(p), req.applying(p).applying(q))
                        && p < q))
                && crit.becomes(Expr(.union(crit, StateExpr.setLiteral([StateExpr.value(.int(p)))])))
                && clock.stays && req.stays && ack.stays && network.stays
            }
            // Exit critical section
            Action("Exit_\(p)") {
                StateExpr.in(StateExpr.value(.int(p)), StateExpr.variable("crit"))
                && crit.becomes(Expr(.setDifference(crit, StateExpr.setLiteral([StateExpr.value(.int(p)))])))
                && network.becomes(network.updated(at: p,
                    to: network.applying(p).updated(at: q,
                        to: network.applying(p).applying(q).appending(relMsg))))
                && req.becomes(req.updated(at: p,
                    to: req.applying(p).updated(at: p, to: 0)))
                && ack.becomes(ack.updated(at: p, to: StateExpr.setLiteral([]))))
                && clock.stays
            }
            // ReceiveRelease from q
            Action("ReceiveRel_\(p)_\(q)") {
                let m = network.applying(q).applying(p)
                m.count > 0 && StateExpr.recordAccess(m.head, "type") == "rel"
                && req.becomes(req.updated(at: p,
                    to: req.applying(p).updated(at: q, to: 0)))
                && network.becomes(network.updated(at: q,
                    to: network.applying(q).updated(at: p, to: m.tail)))
                && clock.stays && ack.stays && crit.stays
            }
        }
    }
}
