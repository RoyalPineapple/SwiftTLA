import SwiftTLA

/// Dijkstra's asynchronous ring-termination detector from EWD 998.
///
/// The finite node domain and its two shared functions are formal values.
/// Parameterized actions replace the old raw existential action bodies, so the
/// same authoring surface drives the parser, builder, and generated machine.
public struct EWD998TerminationModel: Sendable {
    public enum Node: Int, CaseIterable, FiniteTLAValueDomain {
        case zero = 0
        case one = 1
        case two = 2
        case three = 3

        public static var defaultValue: Self { .zero }
        public static let finiteValues = allCases

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    public static var spec: TLASpec {
        TLASpec("AsyncTerminationDetection", scoped: specificationComponents)
    }

    private static func terminateAction(
        active: SharedVariable<Function<Node, Bool>>,
        pending: SharedVariable<Function<Node, Int>>,
        terminationDetected: SharedVariable<Bool>
    ) -> ActionExpr {
        let node = Expr<Node>(.variable("node"))
        let nodeIsActive: StateExpr = active[node] == true
        let zeroInactive: StateExpr = active[.zero] == false
        let oneInactive: StateExpr = active[.one] == false
        let twoInactive: StateExpr = active[.two] == false
        let threeInactive: StateExpr = active[.three] == false
        let firstTwoNodesInactive: StateExpr = .and(zeroInactive, oneInactive)
        let firstThreeNodesInactive: StateExpr = .and(firstTwoNodesInactive, twoInactive)
        let allNodesInactive: StateExpr = .and(firstThreeNodesInactive, threeInactive)
        let zeroPending: StateExpr = pending[.zero] == 0
        let onePending: StateExpr = pending[.one] == 0
        let twoPending: StateExpr = pending[.two] == 0
        let threePending: StateExpr = pending[.three] == 0
        let firstTwoPending: StateExpr = .and(zeroPending, onePending)
        let firstThreePending: StateExpr = .and(firstTwoPending, twoPending)
        let noPendingMessages: StateExpr = .and(firstThreePending, threePending)
        let terminationIsDetectable: StateExpr = .and(allNodesInactive, noPendingMessages)
        let zeroActive: StateExpr = .notEqual(active[.zero].raw, .value(.bool(false)))
        let oneActive: StateExpr = .notEqual(active[.one].raw, .value(.bool(false)))
        let twoActive: StateExpr = .notEqual(active[.two].raw, .value(.bool(false)))
        let threeActive: StateExpr = .notEqual(active[.three].raw, .value(.bool(false)))
        let zeroHasPendingMessages: StateExpr = .notEqual(pending[.zero].raw, .value(.int(0)))
        let oneHasPendingMessages: StateExpr = .notEqual(pending[.one].raw, .value(.int(0)))
        let twoHasPendingMessages: StateExpr = .notEqual(pending[.two].raw, .value(.int(0)))
        let threeHasPendingMessages: StateExpr = .notEqual(pending[.three].raw, .value(.int(0)))
        let firstTwoActive: StateExpr = .or(zeroActive, oneActive)
        let firstThreeActive: StateExpr = .or(firstTwoActive, twoActive)
        let anyNodeActive: StateExpr = .or(firstThreeActive, threeActive)
        let zeroOrOnePending: StateExpr = .or(zeroHasPendingMessages, oneHasPendingMessages)
        let firstThreePendingWork: StateExpr = .or(zeroOrOnePending, twoHasPendingMessages)
        let anyPendingWork: StateExpr = .or(firstThreePendingWork, threeHasPendingMessages)
        let activeOrPendingWorkRemains: StateExpr = .or(anyNodeActive, anyPendingWork)
        let detectTermination: ActionExpr = .and(.guard_(terminationIsDetectable), terminationDetected.becomes(true))
        let preserveTerminationStatus: ActionExpr = .and(.guard_(activeOrPendingWorkRemains), terminationDetected.stays)
        let terminationStatus: ActionExpr = .or(detectTermination, preserveTerminationStatus)
        let deactivateNode: ActionExpr = active.becomes(active.updating(node, to: false))
        let preservePendingMessages: ActionExpr = pending.stays

        let activeNodeTerminates: ActionExpr = .and(.guard_(nodeIsActive), deactivateNode)
        let pendingMessagesPreserved: ActionExpr = .and(activeNodeTerminates, preservePendingMessages)
        return .and(pendingMessagesPreserved, terminationStatus)
    }

    private static func specificationComponents(_ scope: SpecificationScope) -> [SpecComponent] {
        let active = scope.sharedVar("active", in: SetExpr<Function<Node, Bool>>.literal(
            Function<Node, Bool>.literal((.zero, false), (.one, false), (.two, false), (.three, false)),
            Function<Node, Bool>.literal((.zero, false), (.one, false), (.two, false), (.three, true)),
            Function<Node, Bool>.literal((.zero, false), (.one, false), (.two, true), (.three, false)),
            Function<Node, Bool>.literal((.zero, false), (.one, false), (.two, true), (.three, true)),
            Function<Node, Bool>.literal((.zero, false), (.one, true), (.two, false), (.three, false)),
            Function<Node, Bool>.literal((.zero, false), (.one, true), (.two, false), (.three, true)),
            Function<Node, Bool>.literal((.zero, false), (.one, true), (.two, true), (.three, false)),
            Function<Node, Bool>.literal((.zero, false), (.one, true), (.two, true), (.three, true)),
            Function<Node, Bool>.literal((.zero, true), (.one, false), (.two, false), (.three, false)),
            Function<Node, Bool>.literal((.zero, true), (.one, false), (.two, false), (.three, true)),
            Function<Node, Bool>.literal((.zero, true), (.one, false), (.two, true), (.three, false)),
            Function<Node, Bool>.literal((.zero, true), (.one, false), (.two, true), (.three, true)),
            Function<Node, Bool>.literal((.zero, true), (.one, true), (.two, false), (.three, false)),
            Function<Node, Bool>.literal((.zero, true), (.one, true), (.two, false), (.three, true)),
            Function<Node, Bool>.literal((.zero, true), (.one, true), (.two, true), (.three, false)),
            Function<Node, Bool>.literal((.zero, true), (.one, true), (.two, true), (.three, true))
        ))
        let pending = scope.sharedVar("pending", initial: Function<Node, Int>.literal(
            (.zero, 0), (.one, 0), (.two, 0), (.three, 0)
        ))
        let terminationDetected = scope.sharedVar("terminationDetected", initial: false)

        let standardModules: SpecComponent = Extends(.naturals)
        let pendingBound: SpecComponent = Constraint(
            pending[.zero] <= 3 && pending[.one] <= 3
                && pending[.two] <= 3 && pending[.three] <= 3
        )

        let typeOK: SpecComponent = Invariant("TypeOK") {
            pending[.zero] >= 0 && pending[.one] >= 0
                && pending[.two] >= 0 && pending[.three] >= 0
        }

        let safety: SpecComponent = Invariant("Safe") {
            !terminationDetected || (
                active[.zero] == false && active[.one] == false
                    && active[.two] == false && active[.three] == false
                    && pending[.zero] == 0 && pending[.one] == 0
                    && pending[.two] == 0 && pending[.three] == 0
            )
        }

        let terminate: SpecComponent = SwiftTLA.Action("Terminate", parameters: [
                ActionParameter("node", values: Node.finiteValues)
            ]) {
                terminateAction(
                    active: active,
                    pending: pending,
                    terminationDetected: terminationDetected
                )
        }

        let receiveMessage: SpecComponent = SwiftTLA.Action("RcvMsg", parameters: [
                ActionParameter("node", values: Node.finiteValues)
            ]) {
                let node = Expr<Node>(.variable("node"))
                pending[node] > 0
                    && active.becomes(active.updating(node, to: true))
                    && pending.becomes(pending.updating(node) { current in current - 1 })
                    && terminationDetected.stays
        }

        let sendMessage: SpecComponent = SwiftTLA.Action("SendMsg", parameters: [
                ActionParameter("sender", values: Node.finiteValues),
                ActionParameter("receiver", values: Node.finiteValues)
            ]) {
                let sender = Expr<Node>(.variable("sender"))
                let receiver = Expr<Node>(.variable("receiver"))
                active[sender] == true
                    && pending.becomes(pending.updating(receiver) { current in current + 1 })
                    && active.stays
                    && terminationDetected.stays
        }

        let detectTermination: SpecComponent = SwiftTLA.Action("DetectTermination") {
            active[.zero] == false && active[.one] == false
                && active[.two] == false && active[.three] == false
                && pending[.zero] == 0 && pending[.one] == 0
                && pending[.two] == 0 && pending[.three] == 0
                && terminationDetected.becomes(true)
                && active.stays && pending.stays
        }

        var components: [SpecComponent] = []
        components.append(standardModules)
        components.append(pendingBound)
        components.append(typeOK)
        components.append(safety)
        components.append(terminate)
        components.append(receiveMessage)
        components.append(sendMessage)
        components.append(detectTermination)
        return components
    }
}

extension Example {
    public static let ewd998 = Entry(
        id: "ewd998/AsyncTerminationDetection",
        upstreamSpec: "ewd998",
        upstreamModule: "specifications/ewd998/AsyncTerminationDetection.tla",
        upstreamCfg: "specifications/ewd998/AsyncTerminationDetection.cfg",
        expectedDistinct: 4097,
        spec: EWD998TerminationModel.spec,
        notes: "N=4. Typed active/pending functions and parameterized asynchronous actions. Constraint pending<=3. Safe."
    )
}
