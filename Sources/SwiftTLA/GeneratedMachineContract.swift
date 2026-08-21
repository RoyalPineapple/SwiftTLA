import Foundation

/// The non-formal facts needed to emit a Swift machine surface.
///
/// These facts are keyed by declarations in the compiled specification. They
/// intentionally contain type and source-shape information only; expressions,
/// invariants, and transition bodies stay in `TLASpec`.
public struct MachineSurfaceSwiftFacts: Sendable, Equatable {
    public struct SymmetricCollection: Sendable, Equatable {
        public let elementType: String
        public let valueType: String

        public init(elementType: String, valueType: String) {
            self.elementType = elementType
            self.valueType = valueType
        }
    }

    public let variableTypes: [String: String]
    public let actionBindingTypes: [String: [String: String]]
    public let symmetricCollections: [String: SymmetricCollection]
    public let collectionActions: [String: String]

    public init(
        variableTypes: [String: String] = [:],
        actionBindingTypes: [String: [String: String]] = [:],
        symmetricCollections: [String: SymmetricCollection] = [:],
        collectionActions: [String: String] = [:]
    ) {
        self.variableTypes = variableTypes
        self.actionBindingTypes = actionBindingTypes
        self.symmetricCollections = symmetricCollections
        self.collectionActions = collectionActions
    }
}

/// A typed failure at the generated-machine boundary.
///
/// This diagnostic deliberately contains no raw formal state dictionary. A
/// caller can distinguish an inconsistent generated surface from a finite
/// evaluation that could not complete without crossing that boundary.
public struct GeneratedMachineContractDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Sendable, Equatable {
        case unknownSwiftFact
        case metadataDomainMismatch
        case actionLabelRoundTripMismatch
        case projectionDecodeMismatch
        case behaviorMismatch
        case compilationIdentityMismatch
        case schemaMismatch
        case evaluationUnavailable
    }

    public let code: Code
    public let path: String
    public let expected: String
    public let actual: String
    public let nextSafeAction: String

    public init(
        code: Code,
        path: String,
        expected: String,
        actual: String,
        nextSafeAction: String
    ) {
        self.code = code
        self.path = path
        self.expected = expected
        self.actual = actual
        self.nextSafeAction = nextSafeAction
    }

    public var description: String {
        "Generated-machine contract failed [\(code.rawValue)] at \(path). "
            + "Expected: \(expected). Actual: \(actual). "
            + "Next safe action: \(nextSafeAction)"
    }
}

/// The one emitted-machine view of a compiled specification.
///
/// The plan carries declaration descriptors and finite invocation domains, not
/// a second executable AST. The macro, metadata, label conversion, state
/// projection codecs, and contract checker all consume these descriptors.
public struct MachineSurfacePlan: Sendable, Equatable {
    public enum FormalValueShape: String, Sendable, Equatable {
        case integer
        case boolean
        case string
        case set
        case tuple
        case record
        case function
        case constant

        init(_ value: TLAValue) {
            switch value {
            case .int: self = .integer
            case .bool: self = .boolean
            case .string: self = .string
            case .set: self = .set
            case .tuple: self = .tuple
            case .record: self = .record
            case .function: self = .function
            case .constant: self = .constant
            }
        }
    }

    public struct Variable: Sendable, Equatable {
        public let formalName: String
        public let swiftType: String
        public let valueShape: FormalValueShape
        public let collectionType: CollectionVarType

        public init(
            formalName: String,
            swiftType: String,
            valueShape: FormalValueShape,
            collectionType: CollectionVarType
        ) {
            self.formalName = formalName
            self.swiftType = swiftType
            self.valueShape = valueShape
            self.collectionType = collectionType
        }
    }

    public struct Binding: Sendable, Equatable {
        public let formalName: String
        public let swiftType: String
        public let domain: [TLAValue]
        public let isPublic: Bool

        public init(formalName: String, swiftType: String, domain: [TLAValue], isPublic: Bool) {
            self.formalName = formalName
            self.swiftType = swiftType
            self.domain = domain
            self.isPublic = isPublic
        }
    }

    public struct Action: Sendable, Equatable {
        public let formalName: String
        public let swiftIdentifier: String
        public let bindings: [Binding]

        public init(formalName: String, swiftIdentifier: String, bindings: [Binding]) {
            self.formalName = formalName
            self.swiftIdentifier = swiftIdentifier
            self.bindings = bindings
        }
    }

    public struct SymmetricCollection: Sendable, Equatable {
        public let formalName: String
        public let verificationScope: Int
        public let initial: TLAValue
        public let elementType: String
        public let valueType: String

        public init(
            formalName: String,
            verificationScope: Int,
            initial: TLAValue,
            elementType: String,
            valueType: String
        ) {
            self.formalName = formalName
            self.verificationScope = verificationScope
            self.initial = initial
            self.elementType = elementType
            self.valueType = valueType
        }
    }

    public let compilationIdentity: CompilationIdentity
    public let variables: [Variable]
    public let actions: [Action]
    public let symmetricCollections: [SymmetricCollection]
    public let collectionActions: [String: String]
    public let schemaIdentifier: String

    public init(
        compilation: CompiledSpecification,
        swiftFacts: MachineSurfaceSwiftFacts = .init()
    ) throws {
        let spec = compilation.spec
        let variableNames = Set(spec.variables.map(\.name))
        for name in swiftFacts.variableTypes.keys where !variableNames.contains(name) {
            throw Self.unknownFact("variables.\(name)")
        }
        for name in swiftFacts.symmetricCollections.keys where !variableNames.contains(name) {
            throw Self.unknownFact("symmetricCollections.\(name)")
        }
        let declaredCollections = Dictionary(uniqueKeysWithValues: spec.symmetricCollections.map { ($0.name, $0) })
        for name in swiftFacts.symmetricCollections.keys where declaredCollections[name] == nil {
            throw Self.unknownFact("symmetricCollections.\(name)")
        }

        let actionsByName = Dictionary(uniqueKeysWithValues: spec.actions.map { ($0.name, $0) })
        for (actionName, bindings) in swiftFacts.actionBindingTypes {
            guard let action = actionsByName[actionName] else {
                throw Self.unknownFact("actions.\(actionName)")
            }
            let formalBindings = Set(action.bindings.map(\.name))
            for bindingName in bindings.keys where !formalBindings.contains(bindingName) {
                throw Self.unknownFact("actions.\(actionName).bindings.\(bindingName)")
            }
        }
        for (actionName, collectionName) in swiftFacts.collectionActions {
            guard actionsByName[actionName] != nil, swiftFacts.symmetricCollections[collectionName] != nil else {
                throw Self.unknownFact("collectionActions.\(actionName)")
            }
        }

        let variablesByName = Dictionary(uniqueKeysWithValues: spec.variables.map { ($0.name, $0) })
        let variables = try compilation.layout.variables.map { layout in
            guard let variable = variablesByName[layout.declaration.name] else {
                throw Self.unknownFact("compiledLayout.variables.\(layout.declaration.name)")
            }
            return Variable(
                formalName: layout.declaration.name,
                swiftType: swiftFacts.variableTypes[layout.declaration.name] ?? Self.defaultSwiftType(for: variable.initial),
                valueShape: .init(variable.initial),
                collectionType: variable.collectionType
            )
        }
        let actionIdentifiers = Self.generatedActionIdentifiers(compilation.layout.actions.map(\.declaration.name))
        let actions = try zip(compilation.layout.actions, actionIdentifiers).map { layout, identifier in
            guard let action = actionsByName[layout.declaration.name] else {
                throw Self.unknownFact("compiledLayout.actions.\(layout.declaration.name)")
            }
            return Action(
                formalName: layout.declaration.name,
                swiftIdentifier: identifier,
                bindings: action.bindings.map { binding in
                    Binding(
                        formalName: binding.name,
                        swiftType: Self.publicActionBindingSwiftType(
                            swiftFacts.actionBindingTypes[action.name]?[binding.name]
                                ?? Self.defaultActionBindingSwiftType(for: binding.values[0])
                        ),
                        domain: binding.values,
                        isPublic: binding.values.count > 1
                    )
                }
            )
        }
        let symmetricCollections: [SymmetricCollection] = swiftFacts.symmetricCollections.keys.sorted().compactMap { name in
            guard let fact = swiftFacts.symmetricCollections[name], let declaration = declaredCollections[name] else {
                return nil
            }
            return SymmetricCollection(
                formalName: name,
                verificationScope: declaration.verificationScope,
                initial: declaration.initial,
                elementType: fact.elementType,
                valueType: fact.valueType
            )
        }

        self.compilationIdentity = compilation.identity
        self.variables = variables
        self.actions = actions
        self.symmetricCollections = symmetricCollections
        self.collectionActions = swiftFacts.collectionActions
        self.schemaIdentifier = Self.schemaIdentifier(
            identity: compilation.identity,
            variables: variables,
            actions: actions,
            symmetricCollections: symmetricCollections,
            collectionActions: swiftFacts.collectionActions
        )
    }

    public var metadata: GeneratedMachineMetadata {
        .init(
            compilationIdentity: compilationIdentity,
            schemaIdentifier: schemaIdentifier,
            variables: variables,
            actions: actions
        )
    }

    struct ActionInput: Sendable, Equatable {
        let ordinal: Int
        let arguments: [TLAValue]
    }

    var actionInputs: [ActionInput] {
        actions.enumerated().flatMap { ordinal, action in
            let argumentLists = action.bindings.reduce([[]]) { partial, binding in
                partial.flatMap { arguments in
                    binding.domain.map { arguments + [$0] }
                }
            }
            return argumentLists.map { ActionInput(ordinal: ordinal, arguments: $0) }
        }
    }

    private static func unknownFact(_ path: String) -> GeneratedMachineContractDiagnostic {
        .init(
            code: .unknownSwiftFact,
            path: path,
            expected: "a declaration in the compiled specification",
            actual: "no matching declaration",
            nextSafeAction: "Correct the source-only fact key, then compile the model again."
        )
    }

    private static func defaultSwiftType(for value: TLAValue) -> String {
        switch value {
        case .int: "Int"
        case .bool: "Bool"
        case .string, .constant: "String"
        default: "TLAValue"
        }
    }

    private static func defaultActionBindingSwiftType(for value: TLAValue) -> String {
        switch value {
        case .int: "Int"
        case .bool: "Bool"
        case .string, .constant: "String"
        case .set, .tuple, .record, .function: "TLAValue"
        }
    }

    private static func publicActionBindingSwiftType(_ type: String) -> String {
        switch type.replacingOccurrences(of: " ", with: "") {
        case "[String:TLAValue]", "[TLAValue:TLAValue]": "TLAValue"
        default: type
        }
    }

    private static func generatedActionIdentifiers(_ names: [String]) -> [String] {
        let reserved: Set<String> = ["init", "deinit", "subscript", "toInvocation", "rawValue"]
        var used: Set<String> = []
        return names.map { name in
            let scalars = name.unicodeScalars.map { scalar -> Character in
                switch scalar.value {
                case 65...90, 97...122, 48...57, 95: Character(String(scalar))
                default: "_"
                }
            }
            var base = String(scalars)
            if base.isEmpty { base = "action" }
            if base.unicodeScalars.first.map({ (48...57).contains($0.value) }) == true || reserved.contains(base) {
                base = "action_\(base)"
            }
            var identifier = base
            var suffix = 2
            while used.contains(identifier) {
                identifier = "\(base)_\(suffix)"
                suffix += 1
            }
            used.insert(identifier)
            return identifier
        }
    }

    private static func schemaIdentifier(
        identity: CompilationIdentity,
        variables: [Variable],
        actions: [Action],
        symmetricCollections: [SymmetricCollection],
        collectionActions: [String: String]
    ) -> String {
        func field(_ value: String) -> String { "\(value.utf8.count):\(value)" }
        var source = field(identity.value)
        for variable in variables {
            source += field(variable.formalName)
            source += field(variable.swiftType)
            source += field(variable.valueShape.rawValue)
            source += field(String(describing: variable.collectionType))
        }
        for action in actions {
            source += field(action.formalName)
            source += field(action.swiftIdentifier)
            for binding in action.bindings {
                source += field(binding.formalName)
                source += field(binding.swiftType)
                source += field(String(binding.isPublic))
                for value in binding.domain { source += field(String(describing: value)) }
            }
        }
        for collection in symmetricCollections {
            source += field(collection.formalName)
            source += field(String(collection.verificationScope))
            source += field(String(describing: collection.initial))
            source += field(collection.elementType)
            source += field(collection.valueType)
        }
        for (action, collection) in collectionActions.sorted(by: { $0.key < $1.key }) {
            source += field(action)
            source += field(collection)
        }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "machine-%016llx", hash)
    }
}

/// Stable metadata emitted next to the generated Swift machine surface.
public struct GeneratedMachineMetadata: Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let compilationIdentity: CompilationIdentity
    public let schemaIdentifier: String
    public let variables: [MachineSurfacePlan.Variable]
    public let actions: [MachineSurfacePlan.Action]

    public init(
        compilationIdentity: CompilationIdentity,
        schemaIdentifier: String,
        variables: [MachineSurfacePlan.Variable],
        actions: [MachineSurfacePlan.Action],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.compilationIdentity = compilationIdentity
        self.schemaIdentifier = schemaIdentifier
        self.variables = variables
        self.actions = actions
    }
}

public struct GeneratedMachineBehavior: Sendable {
    public struct Action: Sendable {
        public let successors: @Sendable (TLAStateProjection) throws -> [TLAStateProjection]

        public init(
            successors: @escaping @Sendable (TLAStateProjection) throws -> [TLAStateProjection]
        ) {
            self.successors = successors
        }
    }

    public let initialStates: @Sendable () throws -> [TLAStateProjection]
    public let actions: [Action]

    public init(
        initialStates: @escaping @Sendable () throws -> [TLAStateProjection],
        actions: [Action]
    ) {
        self.initialStates = initialStates
        self.actions = actions
    }
}

/// The result of a finite generated-machine contract check.
public struct GeneratedMachineContractReport: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case exact
        case difference
        case unavailable
    }

    public let status: Status
    public let initialStateCount: Int
    public let transitionCount: Int
    public let invariantCheckCount: Int
    public let diagnostic: GeneratedMachineContractDiagnostic?

    public init(
        status: Status,
        initialStateCount: Int,
        transitionCount: Int,
        invariantCheckCount: Int = 0,
        diagnostic: GeneratedMachineContractDiagnostic? = nil
    ) {
        self.status = status
        self.initialStateCount = initialStateCount
        self.transitionCount = transitionCount
        self.invariantCheckCount = invariantCheckCount
        self.diagnostic = diagnostic
    }
}

/// Bounded translation validation for the generated Swift surface.
///
/// The expected graph is still produced by the one compiled formal machine.
/// The verifier only checks the generated boundary: metadata, labels, decoded
/// projections, and the generated-behavior witness.
public enum GeneratedMachineContractVerifier {
    public static func verify(
        compilation: CompiledSpecification,
        plan: MachineSurfacePlan,
        metadata: GeneratedMachineMetadata,
        expectedSchemaIdentifier: String,
        verificationStateLimit: Int,
        decodeState: @escaping @Sendable (TLAStateProjection) throws -> Void,
        behavior: GeneratedMachineBehavior
    ) -> GeneratedMachineContractReport {
        guard verificationStateLimit > 0 else {
            return unavailable(
                code: .evaluationUnavailable,
                path: "verificationStateLimit",
                expected: "a positive finite state limit",
                actual: String(verificationStateLimit)
            )
        }
        guard compilation.identity == plan.compilationIdentity else {
            return difference(
                code: .compilationIdentityMismatch,
                path: "machineSurfacePlan",
                expected: compilation.identity.value,
                actual: plan.compilationIdentity.value
            )
        }
        guard metadata.schemaVersion == GeneratedMachineMetadata.currentSchemaVersion else {
            return difference(
                code: .schemaMismatch,
                path: "metadata.schemaVersion",
                expected: String(GeneratedMachineMetadata.currentSchemaVersion),
                actual: String(metadata.schemaVersion)
            )
        }
        guard plan.schemaIdentifier == expectedSchemaIdentifier,
              metadata.schemaIdentifier == expectedSchemaIdentifier else {
            return difference(
                code: .schemaMismatch,
                path: "schemaIdentifier",
                expected: expectedSchemaIdentifier,
                actual: "plan=\(plan.schemaIdentifier), metadata=\(metadata.schemaIdentifier)"
            )
        }
        guard metadata == plan.metadata else {
            return difference(
                code: .metadataDomainMismatch,
                path: "metadata",
                expected: "metadata derived from \(plan.schemaIdentifier)",
                actual: "a differing generated-machine metadata surface"
            )
        }

        let exploration: ModelExplorationResult
        do {
            exploration = try ModelChecker(
                compilation: compilation,
                maxStates: verificationStateLimit
            ).explore()
        } catch {
            return unavailable(
                code: .evaluationUnavailable,
                path: "formalMachine",
                expected: "a finite exploration",
                actual: String(describing: error)
            )
        }
        guard exploration.isComplete else {
            return unavailable(
                code: .evaluationUnavailable,
                path: "formalMachine",
                expected: "a complete graph within \(verificationStateLimit) states",
                actual: String(describing: exploration.result)
            )
        }

        let graph = exploration.graph
        let expectedInitial: [TLAStateProjection]
        do {
            expectedInitial = try exploration.initialStateIDs.map { id in
                guard let state = graph.states[id] else {
                    throw GeneratedMachineContractDiagnostic(
                        code: .evaluationUnavailable,
                        path: "initialStates.\(id)",
                        expected: "a graph state",
                        actual: "missing state",
                        nextSafeAction: "Re-run the bounded formal exploration."
                    )
                }
                return state
            }
            for state in expectedInitial { try decodeState(state) }
        } catch let diagnostic as GeneratedMachineContractDiagnostic {
            return unavailable(diagnostic)
        } catch {
            return difference(
                code: .projectionDecodeMismatch,
                path: "initialStates",
                expected: "every formal initial state to decode as generated State",
                actual: String(describing: error)
            )
        }

        do {
            let actualInitial = try behavior.initialStates()
            do {
                for state in actualInitial { try decodeState(state) }
            } catch {
                return difference(
                    code: .projectionDecodeMismatch,
                    path: "generatedBehavior.initialStates",
                    expected: "every generated initial state to decode as generated State",
                    actual: String(describing: error)
                )
            }
            guard sameMultiset(actualInitial, expectedInitial) else {
                return difference(
                    code: .behaviorMismatch,
                    path: "initialStates",
                    expected: "the exact formal initial projection multiset",
                    actual: "a differing generated initial projection multiset"
                )
            }
        } catch {
            return unavailable(
                code: .evaluationUnavailable,
                path: "generatedBehavior.initialStates",
                expected: "a finite generated initial-state result",
                actual: String(describing: error)
            )
        }

        let actionInputs = plan.actionInputs
        guard behavior.actions.count == actionInputs.count else {
            return difference(
                code: .actionLabelRoundTripMismatch,
                path: "generatedBehavior.actions",
                expected: "\(actionInputs.count) generated actions",
                actual: "\(behavior.actions.count) generated actions"
            )
        }

        var transitionCount = 0
        for (fromID, source) in graph.states {
            let sourceProjection: TLAStateProjection
            do {
                sourceProjection = source
                try decodeState(sourceProjection)
            } catch {
                return difference(
                    code: .projectionDecodeMismatch,
                    path: "transitions.\(fromID).source",
                    expected: "a generated State projection",
                    actual: String(describing: error)
                )
            }
            let transitions = graph.transitions[fromID] ?? []
            for (index, input) in actionInputs.enumerated() {
                let expectedTargets: [TLAStateProjection]
                do {
                    expectedTargets = try transitions
                        .filter {
                            $0.label.actionOrdinal == input.ordinal
                                && $0.label.arguments == input.arguments
                        }
                        .map { transition in
                            guard let target = graph.states[transition.target] else {
                                throw GeneratedMachineContractDiagnostic(
                                    code: .evaluationUnavailable,
                                    path: "transitions.\(fromID).target",
                                    expected: "a graph target state",
                                    actual: "missing state",
                                    nextSafeAction: "Re-run the bounded formal exploration."
                                )
                            }
                            let targetProjection = target
                            try decodeState(targetProjection)
                            return targetProjection
                        }
                } catch let diagnostic as GeneratedMachineContractDiagnostic {
                    return unavailable(diagnostic)
                } catch {
                    return difference(
                        code: .projectionDecodeMismatch,
                        path: "transitions.\(fromID).\(input.ordinal).target",
                        expected: "a generated State projection",
                        actual: String(describing: error)
                    )
                }
                do {
                    let actualTargets = try behavior.actions[index].successors(sourceProjection)
                    do {
                        for target in actualTargets { try decodeState(target) }
                    } catch {
                        return difference(
                            code: .projectionDecodeMismatch,
                            path: "generatedBehavior.actions.\(index).target",
                            expected: "every generated target to decode as generated State",
                            actual: String(describing: error)
                        )
                    }
                    guard sameMultiset(actualTargets, expectedTargets) else {
                        return difference(
                            code: .behaviorMismatch,
                            path: "transitions.\(fromID).\(input.ordinal)",
                            expected: "the exact formal labeled target multiset",
                            actual: "a differing generated labeled target multiset"
                        )
                    }
                } catch {
                    return unavailable(
                        code: .evaluationUnavailable,
                        path: "generatedBehavior.actions.\(index)",
                        expected: "a finite generated transition result",
                        actual: String(describing: error)
                    )
                }
                transitionCount += expectedTargets.count
            }
        }
        return .init(
            status: .exact,
            initialStateCount: expectedInitial.count,
            transitionCount: transitionCount,
            invariantCheckCount: graph.states.count * compilation.semantics.invariants.count
        )
    }

    private static func sameMultiset(
        _ lhs: [TLAStateProjection],
        _ rhs: [TLAStateProjection]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var unmatched = rhs
        for value in lhs {
            guard let index = unmatched.firstIndex(of: value) else { return false }
            unmatched.remove(at: index)
        }
        return unmatched.isEmpty
    }

    private static func difference(
        code: GeneratedMachineContractDiagnostic.Code,
        path: String,
        expected: String,
        actual: String
    ) -> GeneratedMachineContractReport {
        .init(
            status: .difference,
            initialStateCount: 0,
            transitionCount: 0,
            diagnostic: .init(
                code: code,
                path: path,
                expected: expected,
                actual: actual,
                nextSafeAction: "Regenerate the machine surface from the same compiled specification."
            )
        )
    }

    private static func unavailable(
        code: GeneratedMachineContractDiagnostic.Code,
        path: String,
        expected: String,
        actual: String
    ) -> GeneratedMachineContractReport {
        unavailable(.init(
            code: code,
            path: path,
            expected: expected,
            actual: actual,
            nextSafeAction: "Resolve the finite evaluation problem, then run the bounded contract check again."
        ))
    }

    private static func unavailable(_ diagnostic: GeneratedMachineContractDiagnostic) -> GeneratedMachineContractReport {
        .init(status: .unavailable, initialStateCount: 0, transitionCount: 0, diagnostic: diagnostic)
    }
}
