import SwiftTLA

/// Instruments the checker boundary while delegating every transition to generated code.
struct CheckingContextProbe: StateMachine {
    typealias Snapshot = ConvergingFrontiers.Snapshot
    typealias Action = ConvergingFrontiers.Action
    typealias Property = ConvergingFrontiers.Property

    struct CheckingRegisters: Sendable {
        var visited: Set<Int> = []
    }
    enum Failure: Error {
        case lostRegisters, wrongLevel, bypassedContext
    }

    let machine: ConvergingFrontiers
    var snapshot: Snapshot { machine.snapshot }
    func hasSameConfiguration(as other: Self) -> Bool { machine.hasSameConfiguration(as: other.machine) }
    func formalProjection(of snapshot: Snapshot) throws -> TLAStateProjection { try machine.formalProjection(of: snapshot) }
    func formalCall(for action: Action) throws -> FormalActionCall { try machine.formalCall(for: action) }
    static var formalPropertyNames: [Property: String] { ConvergingFrontiers.formalPropertyNames }
    static var propertyDisplayNames: [Property: String] { ConvergingFrontiers.propertyDisplayNames }
    static var checksDeadlock: Bool { ConvergingFrontiers.checksDeadlock }
    func assumptionsHold() throws -> Bool { try machine.assumptionsHold() }
    func satisfiesStateConstraint() throws -> Bool { try machine.satisfiesStateConstraint() }
    func fairnessConditions() throws -> [(name: String, isStrong: Bool, matches: @Sendable (Action) -> Bool, changes: (@Sendable (Snapshot, Snapshot) throws -> Bool)?)] {
        try machine.fairnessConditions()
    }
    func temporalProperties(checking: Set<Property>) throws -> [Property: TemporalCondition<@Sendable (Snapshot, Snapshot) throws -> Bool>] {
        try machine.temporalProperties(checking: checking)
    }
    func violatedInvariants(checking: Set<Property>) throws -> [Property] { try machine.violatedInvariants(checking: checking) }
    static var reachabilityProperties: [Property] { ConvergingFrontiers.reachabilityProperties }
    func matchedReachabilityProperties(checking: Set<Property>) throws -> [Property] { try machine.matchedReachabilityProperties(checking: checking) }
    func refinementFailures(in graph: inout ReachabilityGraph<Self>, checking: Set<Property>) throws -> [Property: RefinementFailure<Snapshot, Action>] { [:] }
    func initialCheckingRegisters() throws -> CheckingRegisters { CheckingRegisters() }
    func successors() throws -> [(action: Action, machine: Self)] { throw Failure.bypassedContext }

    func successors(checking context: inout CheckingContext<CheckingRegisters>) throws -> [(action: Action, machine: Self)] {
        let node = machine.state.node
        let expectedLevel = node == 256 ? 3 : Int.bitWidth - node.leadingZeroBitCount
        guard context.level == expectedLevel else { throw Failure.wrongLevel }
        guard node == 1 || context.registers.visited.contains(1) else { throw Failure.lostRegisters }
        guard context.registers.visited.insert(node).inserted else { throw Failure.lostRegisters }
        return try machine.successors().map { ($0.action, Self(machine: $0.machine)) }
    }
}
