import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct LamportMutexModel: Sendable {
    public static var spec: TLASpec {
        let N = 2
        let nodes = Array(1...N)

        func reqMsg(_ c: Int) -> StateExpr {
            StateExpr.record(["type": .value(.string("req")), "clock": .value(.int(c))])
        }
        let ackMsg: StateExpr = StateExpr.record(["type": .value(.string("ack")), "clock": .value(.int(0))])
        let relMsg: StateExpr = StateExpr.record(["type": .value(.string("rel")), "clock": .value(.int(0))])

        let dict: [TLAValue: TLAValue] = [
            .int(1): TLAValue.function([.int(1): 0, .int(2): 0]),
            .int(2): TLAValue.function([.int(1): 0, .int(2): 0])]

        return #spec("LamportMutex") {
            Extends(.integers)
            let clock = Var<TLAValue>("clock")
            let req = Var<TLAValue>("req")
            let ack = Var<TLAValue>("ack")
            let network = Var<TLAValue>("network")
            let crit = Var<TLAValue>("crit")
            Variable(clock, TLAValue.function([.int(1): 1, .int(2): 1]))
            Variable(req, TLAValue.function(dict))
            Variable(ack, TLAValue.function([.int(1): TLAValue.set([]), .int(2): TLAValue.set([])]))
            Variable(network, TLAValue.function([
                .int(1): TLAValue.function([.int(2): TLAValue.tuple([])]),
                .int(2): TLAValue.function([.int(1): TLAValue.tuple([])])]))
            Variable(crit, TLAValue.set([]))

            Invariant("Mutex") { crit.stateExpr.cardinality <= 1 }
            Constraint(clock.stateExpr.applying(1) <= 2 && clock.stateExpr.applying(2) <= 2)

            for p in nodes {
                let q = p == 1 ? 2 : 1
                Action("Request_\(p)") {
                    req.stateExpr.applying(p).applying(p) == 0
                    && .assign(req.name, req.stateExpr.updated(at: p,
                        to: req.stateExpr.applying(p).updated(at: p, to: clock.stateExpr.applying(p))))
                    && .assign(network.name, network.stateExpr.updated(at: p,
                        to: network.stateExpr.applying(p).updated(at: q,
                            to: network.stateExpr.applying(p).applying(q).appending(reqMsg(p)))))
                    && .assign(ack.name, ack.stateExpr.updated(at: p, to: StateExpr.singleton(StateExpr.int(p))))
                    && clock.stays && crit.stays
                }
                Action("ReceiveReq_\(p)_\(q)") {
                    let m = network.stateExpr.applying(q).applying(p)
                    m.count > 0 && StateExpr.recordAccess(m.head, "type") == "req"
                    && .assign(req.name, req.stateExpr.updated(at: p,
                        to: req.stateExpr.applying(p).updated(at: q, to: StateExpr.recordAccess(m.head, "clock"))))
                    && .assign(clock.name, clock.stateExpr.updated(at: p,
                        to: StateExpr.if(StateExpr.recordAccess(m.head, "clock") > clock.stateExpr.applying(p),
                            then: StateExpr.recordAccess(m.head, "clock") + 1, else: clock.stateExpr.applying(p) + 1)))
                    && .assign(network.name, network.stateExpr
                        .updated(at: q, to: network.stateExpr.applying(q).updated(at: p, to: m.tail))
                        .updated(at: p, to: network.stateExpr.applying(p).updated(at: q,
                            to: network.stateExpr.applying(p).applying(q).appending(ackMsg))))
                    && ack.stays && crit.stays
                }
                Action("ReceiveAck_\(p)_\(q)") {
                    let m = network.stateExpr.applying(q).applying(p)
                    m.count > 0 && StateExpr.recordAccess(m.head, "type") == "ack"
                    && .assign(ack.name, ack.stateExpr.updated(at: p,
                        to: ack.stateExpr.applying(p).union(StateExpr.singleton(StateExpr.int(q)))))
                    && .assign(network.name, network.stateExpr.updated(at: q,
                        to: network.stateExpr.applying(q).updated(at: p, to: m.tail)))
                    && clock.stays && req.stays && crit.stays
                }
                Action("Enter_\(p)") {
                    ack.stateExpr.applying(p).cardinality == N
                    && (req.stateExpr.applying(p).applying(q) == 0
                        || req.stateExpr.applying(p).applying(p) < req.stateExpr.applying(p).applying(q)
                        || (StateExpr.equal(req.stateExpr.applying(p).applying(p), req.stateExpr.applying(p).applying(q))
                            && p < q))
                    && .assign(crit.name, crit.stateExpr.union(StateExpr.singleton(StateExpr.int(p))))
                    && clock.stays && req.stays && ack.stays && network.stays
                }
                Action("Exit_\(p)") {
                    StateExpr.in(StateExpr.value(.int(p)), StateExpr.variable("crit"))
                    && .assign(crit.name, .setDifference(crit.stateExpr, StateExpr.singleton(StateExpr.int(p))))
                    && .assign(network.name, network.stateExpr.updated(at: p,
                        to: network.stateExpr.applying(p).updated(at: q,
                            to: network.stateExpr.applying(p).applying(q).appending(relMsg))))
                    && .assign(req.name, req.stateExpr.updated(at: p,
                        to: req.stateExpr.applying(p).updated(at: p, to: 0)))
                    && .assign(ack.name, ack.stateExpr.updated(at: p, to: StateExpr.setLiteral([])))
                    && clock.stays
                }
                Action("ReceiveRel_\(p)_\(q)") {
                    let m = network.stateExpr.applying(q).applying(p)
                    m.count > 0 && StateExpr.recordAccess(m.head, "type") == "rel"
                    && .assign(req.name, req.stateExpr.updated(at: p,
                        to: req.stateExpr.applying(p).updated(at: q, to: 0)))
                    && .assign(network.name, network.stateExpr.updated(at: q,
                        to: network.stateExpr.applying(q).updated(at: p, to: m.tail)))
                    && clock.stays && ack.stays && crit.stays
                }
            }
        }
    }
}

extension Example {
    static let lamportMutexN2 = Example.Entry(
        id: "lamport_mutex/LamportMutex_N2",
        upstreamSpec: "lamport_mutex",
        upstreamModule: "specifications/lamport_mutex/LamportMutex.tla",
        upstreamCfg: "specifications/lamport_mutex/MCLamportMutex.cfg",
        expectedDistinct: 19,
        spec: LamportMutexModel.spec,
        notes: "N=2, maxClock=2. Nested functions + sequences + @ self-ref. Constraint bounds clocks.",
    )
}
