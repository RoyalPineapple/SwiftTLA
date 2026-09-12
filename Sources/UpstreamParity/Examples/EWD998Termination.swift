import SwiftTLA

/// Dijkstra's asynchronous ring-termination detector from EWD 998.
///
/// The finite node domain and its two shared functions are formal values.
package struct EWD998TerminationModel: Sendable {
    package enum Node: Int, CaseIterable, FiniteTLAValueDomain {
        case zero = 0
        case one = 1
        case two = 2
        case three = 3

        package static var defaultValue: Self { .zero }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .int(rawValue) }
    }

    package static var spec: TLASpec {
        TLASpec("AsyncTerminationDetection", scoped: specificationComponents)
    }

    private static func terminateAction(
        active: SharedVariable<Function<Node, Bool>>,
        pending: SharedVariable<Function<Node, Int>>,
        terminationDetected: SharedVariable<Bool>
    ) -> ActionExpr {
        let node = Expr<Node>(.variable("node"))
        let nodeIsActive = active[node]
        let allNodesInactive = !active[.zero] && !active[.one] && !active[.two] && !active[.three]
        let noPendingMessages = pending[.zero] == 0 && pending[.one] == 0
            && pending[.two] == 0 && pending[.three] == 0
        let terminationIsDetectable = allNodesInactive && noPendingMessages
        let detectTermination = terminationDetected.becomes(true).when(terminationIsDetectable)
        let preserveTerminationStatus = terminationDetected.stays.when(!terminationIsDetectable)
        let terminationStatus: ActionExpr = .or(detectTermination, preserveTerminationStatus)
        let deactivateNode: ActionExpr = active.becomes(active.updating(node, to: false))
        let preservePendingMessages: ActionExpr = pending.stays

        let activeNodeTerminates: ActionExpr = deactivateNode.when(nodeIsActive)
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
    package static let ewd998 = FiniteModelFixture(
        expectedDistinct: 4097,
        maximumStateLimit: 50_000,
        spec: EWD998TerminationModel.spec,
    )
}
