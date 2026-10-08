import Foundation

public struct PropertyReference: Hashable, Sendable {
    private let identity = UUID()
    package let name: String
    package let displayLabel: String?

    package init(name: String, displayLabel: String? = nil) {
        self.name = name
        self.displayLabel = displayLabel
    }
}

public protocol ModelProperty: Sendable {
    var reference: PropertyReference { get }
}

public struct InvariantHandle: ModelProperty {
    public let reference: PropertyReference

    package init(name: String, label: String? = nil) { reference = .init(name: name, displayLabel: label) }

    public func callAsFunction(@InvariantBuilder _ body: () -> StateExpr) -> InvDecl {
        .init(reference: reference, body: body())
    }
}

public func Invariant(label: String? = nil, _name: String = "") -> InvariantHandle {
    .init(name: _name, label: label)
}

public struct ReachableHandle: ModelProperty {
    public let reference: PropertyReference

    package init(name: String, label: String? = nil) { reference = .init(name: name, displayLabel: label) }

    public func callAsFunction(@InvariantBuilder _ body: () -> StateExpr) -> ReachableDecl {
        .init(reference: reference, body: body())
    }
}

public func Reachable(label: String? = nil, _name: String = "") -> ReachableHandle {
    .init(name: _name, label: label)
}

public enum ValidationExpectation: String, Sendable, Codable {
    case satisfied
    case violated
}

public enum ValidationCheckingMode: Equatable, Sendable, Codable {
    case exhaustive
    case decisiveCounterexample
    case simulation(traces: Int, maximumDepth: Int)

    public var rawValue: String {
        switch self {
        case .exhaustive: "exhaustive"
        case .decisiveCounterexample: "decisiveCounterexample"
        case .simulation(let traces, let maximumDepth): "simulation:\(traces):\(maximumDepth)"
        }
    }
}

public struct FairnessProfileReference: Hashable, Sendable {
    private let identity = UUID()
}

public struct FairnessProfileDecl: SpecComponent, Sendable {
    package let name: String
    package let reference: FairnessProfileReference
    package let excludedLabels: [AlgorithmLabelModel]

    package init(name: String, excludedLabels: [AlgorithmLabelModel]) {
        self.name = name
        reference = .init()
        self.excludedLabels = excludedLabels
    }
}

public func FairnessProfile<Label: CaseIterable & RawRepresentable & Sendable>(
    _name: String = "", excluding labels: [Label]
) -> FairnessProfileDecl where Label.RawValue == String {
    .init(name: _name, excludedLabels: labels.map { .init(name: $0.rawValue) })
}

public struct ModelChecks<Property: Hashable & Sendable>: Equatable, Sendable {
    public let properties: Set<Property>
    public let checkDeadlock: Bool

    public init(properties: Set<Property>, checkDeadlock: Bool = true) {
        self.properties = properties
        self.checkDeadlock = checkDeadlock
    }
}

public protocol ModelValidationScenario: Sendable {
    associatedtype Machine: StateMachine
    associatedtype Property: Hashable, Sendable where Property == Machine.Property
    var name: String { get }
    var displayName: String { get }
    var checking: ModelChecks<Property> { get }
    var checkingMode: ValidationCheckingMode { get }
    var behavior: ModelBehavior { get }
    var expectations: [Property: ValidationExpectation] { get }
    var deadlockExpectation: ValidationExpectation? { get }
    func initialMachines() throws -> [Machine]
    func fairnessConditions(on machine: Machine) throws -> [MachineFairnessCondition<Machine.Snapshot, Machine.Action>]
    func render() throws -> RenderedSpecification
    var formalPropertyNames: [Property: String] { get }
    var usesView: Bool { get }
    func runValidation(initialMachines: [Machine], maximumStates: Int, checking: ModelChecks<Property>,
        stopOnViolation: Bool, stopOnReachability: Bool,
        emit: (MachineValidationEvent<Machine>) throws -> Void) throws -> MachineValidationSummary<Property>
    func formalIdentityProjection(of snapshot: Machine.Snapshot, using machine: Machine,
        atLevel level: Int) throws -> TLAStateProjection
}

/// The product result for a configured module with no state machine.
public struct AssumptionEvaluation: Sendable {
    public let satisfied: Bool
    public let evaluatedValues: [TLAValue]

    public init(satisfied: Bool, evaluatedValues: [TLAValue]) {
        self.satisfied = satisfied
        self.evaluatedValues = evaluatedValues
    }
}

/// A configured module that evaluates assumptions but declares no state machine.
public protocol AssumptionValidationScenario: Sendable {
    var name: String { get }
    var displayName: String { get }
    func evaluateAssumptions() throws -> AssumptionEvaluation
    func render() throws -> RenderedSpecification
}

extension ModelValidationScenario {
    public var checkingMode: ValidationCheckingMode { .exhaustive }
    public var usesView: Bool { false }

    public func runValidation(maximumStates: Int, checking: ModelChecks<Property>,
        stopOnViolation: Bool, stopOnReachability: Bool,
        emit: (MachineValidationEvent<Machine>) throws -> Void) throws -> MachineValidationSummary<Property> {
        try runValidation(initialMachines: initialMachines(), maximumStates: maximumStates,
            checking: checking, stopOnViolation: stopOnViolation,
            stopOnReachability: stopOnReachability, emit: emit)
    }

    public func runValidation(initialMachines: [Machine], maximumStates: Int, checking: ModelChecks<Property>,
        stopOnViolation: Bool, stopOnReachability: Bool,
        emit: (MachineValidationEvent<Machine>) throws -> Void) throws -> MachineValidationSummary<Property> {
        try MachineValidator.run(initialMachines: initialMachines, maximumStates: maximumStates,
            checking: checking, stopOnViolation: stopOnViolation,
            stopOnReachability: stopOnReachability, emit: emit)
    }

    public func formalIdentityProjection(of snapshot: Machine.Snapshot, using machine: Machine,
        atLevel level: Int) throws -> TLAStateProjection {
        return try machine.formalProjection(of: snapshot)
    }

    public func fairnessConditions(on machine: Machine) throws -> [MachineFairnessCondition<Machine.Snapshot, Machine.Action>] {
        try machine.fairnessConditions()
    }

    public func check(maximumStates: Int) throws -> NativeCheckResult<Machine> {
        guard !usesView else { throw ExplorationError.viewRequiresStreamingValidation }
        let initial = try initialMachines()
        let fairness = behavior == .specification ? try initial.first.map { try fairnessConditions(on: $0) } : nil
        return try ReachabilityGraph.check(initialMachines: initial, maximumStates: maximumStates,
                                    checking: checking, behavior: behavior, fairness: fairness)
    }

    public func explore(maximumStates: Int) throws -> ReachabilityGraph<Machine> {
        guard !usesView else { throw ExplorationError.viewRequiresStreamingValidation }
        let initial = try initialMachines()
        let fairness = behavior == .specification ? try initial.first.map { try fairnessConditions(on: $0) } : nil
        return try ReachabilityGraph(initialMachines: initial, maximumStates: maximumStates,
            checking: checking, behavior: behavior, fairness: fairness)
    }

    public func simulate<Generator: RandomNumberGenerator>(
        maximumDepth: Int, traceCount: Int = 1, using generator: inout Generator
    ) throws -> NativeSimulationResult<Machine> {
        let initial = try initialMachines()
        let fairness = behavior == .specification ? try initial.first.map { try fairnessConditions(on: $0) } : nil
        return try MachineSimulator.runConfigured(initialMachines: initial, maximumDepth: maximumDepth,
            traceCount: traceCount, checking: checking, behavior: behavior, fairness: fairness, using: &generator)
    }

    public func simulate<Generator: RandomNumberGenerator>(
        using generator: inout Generator
    ) throws -> NativeSimulationResult<Machine> {
        try simulate(initialMachines: initialMachines(), using: &generator)
    }

    package func simulate<Generator: RandomNumberGenerator>(
        initialMachines: [Machine], using generator: inout Generator
    ) throws -> NativeSimulationResult<Machine> {
        guard case .simulation(let traces, let maximumDepth) = checkingMode else {
            throw ExplorationError.simulationNotConfigured
        }
        let fairness = behavior == .specification
            ? try initialMachines.first.map { try fairnessConditions(on: $0) } : nil
        return try MachineSimulator.runConfigured(initialMachines: initialMachines,
            maximumDepth: maximumDepth, traceCount: traces, checking: checking,
            behavior: behavior, fairness: fairness, using: &generator)
    }
}

public struct ValidationBinding: Sendable {
    package let parameter: ParameterReference
    package let value: StateExpr
    package init(parameter: ParameterReference, value: StateExpr) {
        self.parameter = parameter
        self.value = value
    }
}

public func Bind<Value: TLAValueType>(_ parameter: ModelParameter<Value>, to value: Value) -> ValidationBinding {
    .init(parameter: parameter.reference, value: value.stateExpr)
}

@resultBuilder
public enum ValidationBuilder {
    public static func buildBlock(_ bindings: ValidationBinding...) -> [ValidationBinding] { bindings }
}

public struct ValidationDeclaration: SpecComponent {
    package let name: String
    package let displayLabel: String?
    package let bindings: [ValidationBinding]
    package var expectations: [(property: PropertyReference, expected: ValidationExpectation)] = []
    package var deadlockExpectations: [ValidationExpectation] = []
    package var propertySelections: [[PropertyReference]] = []
    package var deadlockSelections: [Bool] = []
    package var behaviorSelections: [ModelBehavior] = []
    package var fairnessProfileSelections: [FairnessProfileReference] = []
    package var checkingModeSelections: [ValidationCheckingMode] = []
    package var symmetrySelections: [SymmetryReference] = []
    package var viewSelections: [StateExpr] = []

    package init(name: String, displayLabel: String? = nil, bindings: [ValidationBinding]) {
        self.name = name
        self.displayLabel = displayLabel
        self.bindings = bindings
    }

    public func expect(_ property: some ModelProperty, _ expected: ValidationExpectation) -> Self {
        var copy = self
        copy.expectations.append((property.reference, expected))
        return copy
    }

    public func expectDeadlock(_ expected: ValidationExpectation) -> Self {
        var copy = self
        copy.deadlockExpectations.append(expected)
        return copy
    }

    public func checking(only properties: [any ModelProperty]) -> Self {
        var copy = self
        copy.propertySelections.append(properties.map(\.reference))
        return copy
    }

    public func checkingDeadlock(_ enabled: Bool) -> Self {
        var copy = self
        copy.deadlockSelections.append(enabled)
        return copy
    }

    public func behavior(_ behavior: ModelBehavior) -> Self {
        var copy = self
        copy.behaviorSelections.append(behavior)
        return copy
    }

    public func usingFairness(_ profile: FairnessProfileDecl) -> Self {
        var copy = self
        copy.fairnessProfileSelections.append(profile.reference)
        return copy
    }

    public func checkingMode(_ mode: ValidationCheckingMode) -> Self {
        var copy = self
        copy.checkingModeSelections.append(mode)
        return copy
    }

    public func simulating(traces: Int, maximumDepth: Int = 100) -> Self {
        checkingMode(.simulation(traces: traces, maximumDepth: maximumDepth))
    }

    public func usingSymmetry(_ symmetry: SymmetrySetDecl) -> Self {
        var copy = self
        copy.symmetrySelections.append(symmetry.reference)
        return copy
    }

    /// Selects the typed value TLC uses to identify explored states for this scenario.
    public func viewing<Value: TLAValueType>(_ value: some TypedExpression<Value>) -> Self {
        var copy = self
        copy.viewSelections.append(value.stateExpr)
        return copy
    }
}

package func Validation(_ name: String, label: String? = nil,
                       @ValidationBuilder _ bindings: () -> [ValidationBinding]) -> ValidationDeclaration {
    .init(name: name, displayLabel: label, bindings: bindings())
}

/// Used by `#spec` after it supplies the enclosing immutable binding name.
public func Validation(_name name: String, label: String? = nil,
                       @ValidationBuilder _ bindings: () -> [ValidationBinding]) -> ValidationDeclaration {
    .init(name: name, displayLabel: label, bindings: bindings())
}

public func Validation(label: String? = nil,
                       @ValidationBuilder _ bindings: () -> [ValidationBinding]) -> ValidationDeclaration {
    preconditionFailure("An unnamed Validation must be bound to let inside #spec.")
}
