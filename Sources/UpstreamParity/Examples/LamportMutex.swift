import SwiftTLA

package struct LamportMutexModel: Sendable {
    package enum Node: Int, CaseIterable, FiniteTLAValueDomain {
        case one = 1
        case two = 2

        package static var defaultValue: Self { .one }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .int(rawValue) }
    }

    package enum MessageKind: String, TLAValueType {
        case request = "req"
        case acknowledgement = "ack"
        case release = "rel"

        package static var defaultValue: Self { .request }
    }

    package struct MessageFields {
        package let kind: MessageKind
        package let clock: Int
    }

    package enum MessageSchema: TLARecordSchema {
        package typealias Fields = MessageFields

        package static let fieldNames: Set<String> = ["type", "clock"]
        package static let defaultRecord: TLAValue = .record([
            "type": MessageKind.request.tlaValue,
            "clock": 0
        ])

        package static func fieldName<Value>(for field: KeyPath<MessageFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \MessageFields.kind { return "type" }
            if key == \MessageFields.clock { return "clock" }
            return nil
        }

        package static let kind = field(\MessageFields.kind)
        package static let clock = field(\MessageFields.clock)
    }

    private typealias Clock = Function<Node, Int>
    private typealias Requests = Function<Node, Clock>
    private typealias Acknowledgements = Function<Node, SetExpr<Node>>
    private typealias MessageQueue = TupleExpr<Record<MessageSchema>>
    private typealias NetworkPeers = Function<Node, MessageQueue>
    private typealias Network = Function<Node, NetworkPeers>

    package static var spec: TLASpec {
        TLASpec("LamportMutex", scoped: specificationComponents)
    }

    private static func requestMessage(_ clock: Expr<Int>) -> Expr<Record<MessageSchema>> {
        Record<MessageSchema>.literal(
            .init(MessageSchema.kind, .request),
            .init(MessageSchema.clock, clock)
        )
    }

    private static func acknowledgementMessage() -> Expr<Record<MessageSchema>> {
        Record<MessageSchema>.literal(
            .init(MessageSchema.kind, .acknowledgement),
            .init(MessageSchema.clock, 0)
        )
    }

    private static func releaseMessage() -> Expr<Record<MessageSchema>> {
        Record<MessageSchema>.literal(
            .init(MessageSchema.kind, .release),
            .init(MessageSchema.clock, 0)
        )
    }

    private static func queueHead(_ queue: Expr<MessageQueue>) -> Expr<Record<MessageSchema>> {
        Expr(.tupleHead(queue.raw))
    }

    private static func queueTail(_ queue: Expr<MessageQueue>) -> Expr<MessageQueue> {
        Expr(.tupleTail(queue.raw))
    }

    private static func specificationComponents(_ scope: SpecificationScope) -> [SpecComponent] {
        let clock = scope.sharedVar("clock", initial: Clock.literal((.one, 1), (.two, 1)))
        let noRequests = Clock.literal((.one, 0), (.two, 0))
        let req = scope.sharedVar("req", initial: Requests.literal(
            (.one, noRequests),
            (.two, noRequests)
        ))
        let noAcknowledgements = SetExpr<Node>()
        let ack = scope.sharedVar("ack", initial: Acknowledgements.literal(
            (.one, noAcknowledgements),
            (.two, noAcknowledgements)
        ))
        let emptyQueue = MessageQueue()
        let noMessages = NetworkPeers.literal((.one, emptyQueue), (.two, emptyQueue))
        let network = scope.sharedVar("network", initial: Network.literal(
            (.one, noMessages),
            (.two, noMessages)
        ))
        let crit = scope.sharedVar("crit", initial: SetExpr<Node>())

        let mutex: SpecComponent = Invariant("Mutex") { crit.expr.cardinality <= 1 }
        let boundedClock: SpecComponent = Constraint(clock[.one] <= 2 && clock[.two] <= 2)

        let request: SpecComponent = SwiftTLA.Action("Request", parameters: [
            ActionParameter("p", values: Node.finiteValues),
            ActionParameter("q", values: Node.finiteValues)
        ]) {
            let p = Expr<Node>(.variable("p"))
            let q = Expr<Node>(.variable("q"))
            p != q
                && req[p][p] == 0
                && req.becomes(req.expr.updating(p, to: req[p].updating(p, to: clock[p])))
                && network.becomes(network.expr.updating(
                    p,
                    to: network[p].updating(q, to: network[p][q].appending(requestMessage(Expr<Int>(p.raw))))
                ))
                && ack.becomes(ack.expr.updating(p, to: SetExpr<Node>.literal(p)))
                && clock.stays && crit.stays
        }

        let receiveRequest: SpecComponent = SwiftTLA.Action("ReceiveReq", parameters: [
            ActionParameter("p", values: Node.finiteValues),
            ActionParameter("q", values: Node.finiteValues)
        ]) {
            let p = Expr<Node>(.variable("p"))
            let q = Expr<Node>(.variable("q"))
            let messages = network[q][p]
            let message = queueHead(messages)
            p != q
                && messages.count > 0
                && message[MessageSchema.kind] == .request
                && req.becomes(req.expr.updating(p, to: req[p].updating(q, to: message[MessageSchema.clock])))
                && clock.becomes(clock.expr.updating(
                    p,
                    to: If(
                        message[MessageSchema.clock] > clock[p],
                        then: message[MessageSchema.clock] + 1,
                        else: clock[p] + 1
                    )
                ))
                && network.becomes(network.expr
                    .updating(q, to: network[q].updating(p, to: queueTail(messages)))
                    .updating(p, to: network[p].updating(q, to: network[p][q].appending(acknowledgementMessage())))
                )
                && ack.stays && crit.stays
        }

        let receiveAcknowledgement: SpecComponent = SwiftTLA.Action("ReceiveAck", parameters: [
            ActionParameter("p", values: Node.finiteValues),
            ActionParameter("q", values: Node.finiteValues)
        ]) {
            let p = Expr<Node>(.variable("p"))
            let q = Expr<Node>(.variable("q"))
            let messages = network[q][p]
            let message = queueHead(messages)
            p != q
                && messages.count > 0
                && message[MessageSchema.kind] == .acknowledgement
                && ack.becomes(ack.expr.updating(p, to: ack[p].inserting(q)))
                && network.becomes(network.expr.updating(q, to: network[q].updating(p, to: queueTail(messages))))
                && clock.stays && req.stays && crit.stays
        }

        let enter: SpecComponent = SwiftTLA.Action("Enter", parameters: [
            ActionParameter("p", values: Node.finiteValues),
            ActionParameter("q", values: Node.finiteValues)
        ]) {
            let p = Expr<Node>(.variable("p"))
            let q = Expr<Node>(.variable("q"))
            p != q
                && ack[p].cardinality == 2
                && (
                    req[p][q] == 0
                        || req[p][p] < req[p][q]
                        || (req[p][p] == req[p][q] && p < q)
                )
                && crit.becomes(crit.expr.inserting(p))
                && clock.stays && req.stays && ack.stays && network.stays
        }

        let exit: SpecComponent = SwiftTLA.Action("Exit", parameters: [
            ActionParameter("p", values: Node.finiteValues),
            ActionParameter("q", values: Node.finiteValues)
        ]) {
            let p = Expr<Node>(.variable("p"))
            let q = Expr<Node>(.variable("q"))
            p != q
                && crit.expr.contains(p)
                && crit.becomes(crit.expr.removing(p))
                && network.becomes(network.expr.updating(
                    p,
                    to: network[p].updating(q, to: network[p][q].appending(releaseMessage()))
                ))
                && req.becomes(req.expr.updating(p, to: req[p].updating(p, to: 0)))
                && ack.becomes(ack.expr.updating(p, to: SetExpr<Node>()))
                && clock.stays
        }

        let receiveRelease: SpecComponent = SwiftTLA.Action("ReceiveRel", parameters: [
            ActionParameter("p", values: Node.finiteValues),
            ActionParameter("q", values: Node.finiteValues)
        ]) {
            let p = Expr<Node>(.variable("p"))
            let q = Expr<Node>(.variable("q"))
            let messages = network[q][p]
            let message = queueHead(messages)
            p != q
                && messages.count > 0
                && message[MessageSchema.kind] == .release
                && req.becomes(req.expr.updating(p, to: req[p].updating(q, to: 0)))
                && network.becomes(network.expr.updating(q, to: network[q].updating(p, to: queueTail(messages))))
                && clock.stays && ack.stays && crit.stays
        }

        return [
            Extends(.integers),
            mutex,
            boundedClock,
            request,
            receiveRequest,
            receiveAcknowledgement,
            enter,
            exit,
            receiveRelease
        ]
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
        notes: "N=2, maxClock=2. Typed finite nodes, records, functions, and parameterized actions.",
    )
}
