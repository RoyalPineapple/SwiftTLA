import SwiftTLA

struct CollidingReachabilityMachine: StateMachine {
    struct Snapshot: Hashable, Sendable {
        let base: ReachabilityExportModel.Snapshot

        func hash(into hasher: inout Hasher) { hasher.combine(0) }
    }

    typealias Action = ReachabilityExportModel.Action
    typealias Property = ReachabilityExportModel.Property
    typealias CheckingRegisters = ReachabilityExportModel.CheckingRegisters

    let base: ReachabilityExportModel

    var snapshot: Snapshot { Snapshot(base: base.snapshot) }
    func hasSameConfiguration(as other: Self) -> Bool { base.hasSameConfiguration(as: other.base) }
    func formalProjection(of snapshot: Snapshot) throws -> TLAStateProjection {
        try base.formalProjection(of: snapshot.base)
    }
    func formalCall(for action: Action) throws -> FormalActionCall { try base.formalCall(for: action) }
    static var formalPropertyNames: [Property: String] { ReachabilityExportModel.formalPropertyNames }
    static var propertyDisplayNames: [Property: String] { ReachabilityExportModel.propertyDisplayNames }
    static var checksDeadlock: Bool { ReachabilityExportModel.checksDeadlock }
    func assumptionsHold() throws -> Bool { try base.assumptionsHold() }
    func satisfiesStateConstraint() throws -> Bool { try base.satisfiesStateConstraint() }
    func fairnessConditions() throws -> [(name: String, isStrong: Bool, matches: @Sendable (Action) -> Bool,
        changes: (@Sendable (Snapshot, Snapshot) throws -> Bool)?)] { [] }
    func temporalProperties(checking: Set<Property>) throws
        -> [Property: TemporalCondition<@Sendable (Snapshot, Snapshot) throws -> Bool>] { [:] }
    func violatedInvariants(checking: Set<Property>) throws -> [Property] {
        try base.violatedInvariants(checking: checking)
    }
    static var invariantProperties: [Property] { ReachabilityExportModel.invariantProperties }
    static var reachabilityProperties: [Property] { ReachabilityExportModel.reachabilityProperties }
    static var refinementProperties: [Property] { ReachabilityExportModel.refinementProperties }
    func matchedReachabilityProperties(checking: Set<Property>) throws -> [Property] {
        try base.matchedReachabilityProperties(checking: checking)
    }
    func refinementFailures(in graph: inout ReachabilityGraph<Self>, checking: Set<Property>) throws
        -> [Property: RefinementFailure<Snapshot, Action>] { [:] }
    func validationRefinementFailures(in graph: inout MachineValidationGraph<Self>, checking: Set<Property>) throws
        -> [Property: RefinementFailure<Snapshot, Action>] { [:] }
    func successors() throws -> [(action: Action, machine: Self)] {
        try base.successors().map { ($0.action, Self(base: $0.machine)) }
    }
    func initialCheckingRegisters() throws -> CheckingRegisters { try base.initialCheckingRegisters() }
    func successors(checking context: inout CheckingContext<CheckingRegisters>) throws
        -> [(action: Action, machine: Self)] {
        try base.successors(checking: &context).map { ($0.action, Self(base: $0.machine)) }
    }
    func visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>,
                         _ visit: (Action, Self) throws -> Bool) throws -> Bool {
        try base.visitSuccessors(checking: &context) { action, machine in
            try visit(action, Self(base: machine))
        }
    }
}
