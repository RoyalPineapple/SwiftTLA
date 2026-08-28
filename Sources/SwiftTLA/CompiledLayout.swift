private enum FieldDiscoveryTask {
    case value(TLAValue)
    case expression(StateExpr)
    case operation(FormalOperator)
    case argument(FormalCallArgument)
    case action(ActionExpr)
    case name(String)
}

private enum BindingValidationTask {
    case expression(StateExpr, path: String, scope: [String: BinderID])
    case action(ActionExpr, path: String, scope: [String: BinderID])
    case bindExpression(
        names: [String],
        binderPath: String,
        expression: StateExpr,
        expressionPath: String,
        scope: [String: BinderID]
    )
    case bindAction(
        name: String,
        binderPath: String,
        action: ActionExpr,
        actionPath: String,
        scope: [String: BinderID]
    )
    case formalOperator(FormalOperator, path: String, scope: [String: BinderID])
    case formalArgument(FormalCallArgument, path: String, scope: [String: BinderID])
    case recordFields(
        [StateRecordExpression.Field],
        index: Int,
        seen: Set<String>,
        path: String,
        scope: [String: BinderID]
    )
    case bindField(String, path: String)
    case localOperators([LocalOperator], body: StateExpr, path: String, scope: [String: BinderID])
    case localOperator(LocalOperator, id: OperatorID, path: String, scope: [String: BinderID])
    case finishLocalOperator(OperatorID, referencePathsBeforeBody: Set<String>, declarationPath: String)
    case restoreOperators([String: OperatorID])
}

struct VariableID: Hashable, Sendable {
    let ordinal: Int
}

struct BinderID: Hashable, Sendable {
    let ordinal: Int
}

package struct ActionID: Hashable, Sendable {
    let ordinal: Int
}

struct PropertyID: Hashable, Sendable {
    let ordinal: Int
}

struct ControlLocationID: Hashable, Sendable {
    let ordinal: Int
}

struct OperatorID: Hashable, Sendable {
    let ordinal: Int
}

struct ModuleInstanceID: Hashable, Sendable {
    let ordinal: Int
}

struct FieldID: Hashable, Sendable {
    let ordinal: Int
}

struct CompiledDeclaration: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case variable
        case action
        case invariant
        case temporalProperty
    }

    let kind: Kind
    let name: String
    let sourceOffset: Int?
    let origin: VariableOrigin

    init(
        kind: Kind,
        name: String,
        sourceOffset: Int?,
        origin: VariableOrigin = .source
    ) {
        self.kind = kind
        self.name = name
        self.sourceOffset = sourceOffset
        self.origin = origin
    }
}

struct CompiledVariableLayout: Hashable, Sendable {
    let id: VariableID
    let declaration: CompiledDeclaration
    let generatedSwiftType: String?
    let symmetricCollection: CompiledSymmetricCollectionLayout?
}

struct CompiledSymmetricCollectionLayout: Hashable, Sendable {
    let members: [TLAValue]
    let elementType: String?
    let valueType: String?
}

struct CompiledActionLayout: Hashable, Sendable {
    let id: ActionID
    let declaration: CompiledDeclaration
    let renderedName: String
}

struct CompiledPropertyLayout: Hashable, Sendable {
    let id: PropertyID
    let declaration: CompiledDeclaration
}

struct CompiledFieldLayout: Hashable, Sendable {
    let id: FieldID
    let renderedName: String
}

struct CompiledProcedureLayout: Hashable, Sendable {
    let algorithm: String
    let name: String
    let sourceOffset: Int?
}

enum ControlOwner: Hashable, Sendable {
    case sequential(algorithm: String)
    case process(algorithm: String, ordinal: Int, typeName: String)
    case procedure(algorithm: String, name: String)
    case generated(algorithm: String, purpose: String)

    var canonicalEncoding: String {
        switch self {
        case .sequential(let algorithm):
            return "sequential:\(algorithm)"
        case .process(let algorithm, let ordinal, let typeName):
            return "process:\(algorithm):\(ordinal):\(typeName)"
        case .procedure(let algorithm, let name):
            return "procedure:\(algorithm):\(name)"
        case .generated(let algorithm, let purpose):
            return "generated:\(algorithm):\(purpose)"
        }
    }
}

public struct ControlLocationReference: Hashable, Sendable {
    let owner: ControlOwner?
    let sourceName: String

    static let done = Self(CompilerControlSymbol.done.rawValue)

    init(_ sourceName: String) {
        self.owner = nil
        self.sourceName = sourceName
    }

    init(owner: ControlOwner, sourceName: String) {
        self.owner = owner
        self.sourceName = sourceName
    }
}

extension ControlOwner {
    var description: ControlOwnerDescription {
        switch self {
        case .sequential(let algorithm):
            return .sequential(algorithm: algorithm)
        case .process(let algorithm, let ordinal, let typeName):
            return .process(
                algorithm: algorithm,
                declarationOrder: ordinal,
                typeName: typeName
            )
        case .procedure(let algorithm, let name):
            return .procedure(algorithm: algorithm, name: name)
        case .generated(let algorithm, let purpose):
            return .generated(algorithm: algorithm, purpose: purpose)
        }
    }
}

struct CompiledControlLocation: Hashable, Sendable {
    let id: ControlLocationID
    let owner: ControlOwner
    let sourceName: String
    let renderedName: String
}

struct CompiledModuleInstanceLayout: Hashable, Sendable {
    let id: ModuleInstanceID
    let namespace: String
}

struct CompiledLayout: Hashable, Sendable {
    let variables: [CompiledVariableLayout]
    let actions: [CompiledActionLayout]
    let stateProperties: [CompiledPropertyLayout]
    let temporalProperties: [CompiledPropertyLayout]
    let fields: [CompiledFieldLayout]
    let procedures: [CompiledProcedureLayout]
    let controlLocations: [CompiledControlLocation]
    let moduleInstances: [CompiledModuleInstanceLayout]
    let declarations: [CompiledDeclaration]

    init(source spec: TLASpec) {
        self.init(spec: spec, modules: [spec])
    }

    init(spec: TLASpec, closure: FormalModuleClosure) {
        self.init(spec: spec, modules: closure.entries.map(\.module))
    }

    private init(spec: TLASpec, modules: [TLASpec]) {
        variables = spec.variables.enumerated().map { ordinal, variable in
            let collection = spec.symmetricCollections.first { $0.name == variable.name }
            return CompiledVariableLayout(
                id: VariableID(ordinal: ordinal),
                declaration: .init(
                    kind: .variable,
                    name: variable.name,
                    sourceOffset: nil,
                    origin: variable.origin
                ),
                generatedSwiftType: variable.generatedSwiftType,
                symmetricCollection: collection.map {
                    .init(
                        members: $0.metadata.members,
                        elementType: $0.generatedElementType,
                        valueType: $0.generatedValueType
                    )
                }
            )
        }
        let controlLocations = Self.controlLocations(
            in: spec.sourceAlgorithms,
            actions: spec.actions,
            hasProgramCounter: spec.variables.contains { $0.name == CompilerControlSymbol.programCounter.rawValue }
        )
        actions = Self.actions(
            spec.actions,
            controlLocations: controlLocations
        )
        stateProperties = spec.invariants.enumerated().map { ordinal, invariant in
            .init(
                id: .init(ordinal: ordinal),
                declaration: .init(kind: .invariant, name: invariant.name, sourceOffset: nil)
            )
        }
        let statePropertyCount = spec.invariants.count
        temporalProperties = spec.temporalProperties.enumerated().map { ordinal, temporal in
            .init(
                id: .init(ordinal: statePropertyCount + ordinal),
                declaration: .init(kind: .temporalProperty, name: temporal.name, sourceOffset: nil)
            )
        }
        fields = Self.fields(in: modules).enumerated().map { ordinal, name in
            .init(id: .init(ordinal: ordinal), renderedName: name)
        }
        procedures = spec.sourceAlgorithms.flatMap { algorithm in
            algorithm.model.procedures.map { procedure in
                .init(algorithm: algorithm.model.name, name: procedure.name, sourceOffset: nil)
            }
        }
        self.controlLocations = controlLocations
        moduleInstances = spec.moduleInstances.enumerated().map {
            .init(id: .init(ordinal: $0.offset), namespace: $0.element.name)
        }
        declarations = variables.map(\.declaration)
            + actions.map(\.declaration)
            + stateProperties.map(\.declaration)
            + temporalProperties.map(\.declaration)
    }

    func variableID(named name: String) -> VariableID? {
        variables.first { $0.declaration.name == name }?.id
    }

    func programCounterID() -> VariableID? {
        variables.first {
            $0.declaration.origin == .programCounter
        }?.id
    }

    func procedureStackID() -> VariableID? {
        variables.first {
            $0.declaration.origin == .procedureStack
        }?.id
    }

    func actionID(named name: String) -> ActionID? {
        actions.first { $0.declaration.name == name }?.id
    }

    func propertyID(kind: CompiledDeclaration.Kind, named name: String) -> PropertyID? {
        let properties = kind == .invariant ? stateProperties : temporalProperties
        return properties.first { $0.declaration.name == name }?.id
    }

    func moduleInstanceID(named namespace: String) -> ModuleInstanceID? {
        moduleInstances.first { $0.namespace == namespace }?.id
    }

    func fieldID(named name: String) -> FieldID? {
        fields.first { $0.renderedName == name }?.id
    }

    func field(_ id: FieldID) -> CompiledFieldLayout? {
        fields.first { $0.id == id }
    }

    func controlLocationID(owner: ControlOwner, named sourceName: String) -> ControlLocationID? {
        controlLocations.first {
            $0.owner == owner && $0.sourceName == sourceName
        }?.id
    }

    func controlLocation(_ id: ControlLocationID) -> CompiledControlLocation? {
        controlLocations.first { $0.id == id }
    }

    func controlLocationID(for reference: ControlLocationReference) -> ControlLocationID? {
        if let owner = reference.owner {
            return controlLocationID(owner: owner, named: reference.sourceName)
        }
        let matches = controlLocations.filter { $0.sourceName == reference.sourceName }
        guard matches.count == 1 else { return nil }
        return matches.first?.id
    }

    var canonicalEncoding: String {
        let declarationEncoding = declarations.enumerated().map { ordinal, declaration in
            let kind = declaration.kind.rawValue
            let name = declaration.name
            let origin: String
            switch declaration.origin {
            case .source: origin = "source"
            case .compiler: origin = "compiler"
            case .programCounter: origin = "programCounter"
            case .procedureStack: origin = "procedureStack"
            }
            return "\(ordinal):\(kind.utf8.count):\(kind)\(name.utf8.count):\(name)\(origin.utf8.count):\(origin)"
        }.joined(separator: "|")
        let controlEncoding = controlLocations.map { label in
            let owner = label.owner.canonicalEncoding
            return "\(label.id.ordinal):\(owner.utf8.count):\(owner)\(label.sourceName.utf8.count):\(label.sourceName)\(label.renderedName.utf8.count):\(label.renderedName)"
        }.joined(separator: "|")
        let actionEncoding = actions.map { action in
            "\(action.id.ordinal):\(action.renderedName.utf8.count):\(action.renderedName)"
        }.joined(separator: "|")
        let procedureEncoding = procedures.map { procedure in
            "\(procedure.algorithm.utf8.count):\(procedure.algorithm)\(procedure.name.utf8.count):\(procedure.name)"
        }.joined(separator: "|")
        let fieldEncoding = fields.map { field in
            "\(field.id.ordinal):\(field.renderedName.utf8.count):\(field.renderedName)"
        }.joined(separator: "|")
        let instanceEncoding = moduleInstances.map { "\($0.id.ordinal):\($0.namespace)" }.joined(separator: "|")
        return "declarations[\(declarationEncoding)]actions[\(actionEncoding)]fields[\(fieldEncoding)]procedures[\(procedureEncoding)]controls[\(controlEncoding)]instances[\(instanceEncoding)]"
    }

    private static func fields(in modules: [TLASpec]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []

        func append(_ name: String) {
            guard seen.insert(name).inserted else { return }
            names.append(name)
        }

        func visit(_ initial: FieldDiscoveryTask) {
            var pending = [initial]
            while let task = pending.popLast() {
                switch task {
                case .name(let name):
                    append(name)
                case .value(let value):
                    switch value {
                    case .int, .bool, .string, .constant:
                        break
                    case .set(let values):
                        pending.append(contentsOf: values.sorted().reversed().map(FieldDiscoveryTask.value))
                    case .tuple(let values):
                        pending.append(contentsOf: values.reversed().map(FieldDiscoveryTask.value))
                    case .record(let record):
                        for field in record.fields.reversed() {
                            pending.append(.value(field.value))
                            pending.append(.name(field.name))
                        }
                    case .function(let values):
                        for entry in values.sorted(by: { $0.key < $1.key }).reversed() {
                            pending.append(.value(entry.value))
                            pending.append(.value(entry.key))
                        }
                    }
                case .operation(let operation):
                    if case .lambda(let lambda) = operation {
                        pending.append(.expression(lambda.body))
                    }
                case .argument(let argument):
                    switch argument {
                    case .value(let expression): pending.append(.expression(expression))
                    case .operator(let operation): pending.append(.operation(operation))
                    }
                case .action(let action):
                    switch action {
                    case .assign(_, let value), .guard_(let value), .chooseAction(_, let value):
                        pending.append(.expression(value))
                    case .unchanged:
                        break
                    case .existsAction(_, let set, let body), .define(_, let set, let body):
                        pending.append(.action(body))
                        pending.append(.expression(set))
                    case .ifElse(let condition, let then, let otherwise):
                        pending.append(.action(otherwise))
                        pending.append(.action(then))
                        pending.append(.expression(condition))
                    case .and(let lhs, let rhs), .or(let lhs, let rhs):
                        pending.append(.action(rhs))
                        pending.append(.action(lhs))
                    }
                case .expression(let expression):
                    switch expression {
                    case .sourceIssue, .variable, .processLocalFamily, .currentProcess, .programCounter,
                         .procedureStack, .controlLocation, .enabledAction:
                        break
                    case .value(let value):
                        pending.append(.value(value))
                    case .negate(let value), .not(let value), .cardinality(let value), .powerSet(let value),
                         .unionAll(let value), .tupleAccess(let value, _), .tupleLength(let value),
                         .tupleHead(let value), .tupleTail(let value), .domain(let value),
                         .sequenceFromSet(let value):
                        pending.append(.expression(value))
                    case .add(let lhs, let rhs), .subtract(let lhs, let rhs), .multiply(let lhs, let rhs),
                         .divide(let lhs, let rhs), .modulo(let lhs, let rhs), .integerDivide(let lhs, let rhs),
                         .equal(let lhs, let rhs), .notEqual(let lhs, let rhs), .lessThan(let lhs, let rhs),
                         .lessOrEqual(let lhs, let rhs), .greaterThan(let lhs, let rhs), .greaterOrEqual(let lhs, let rhs),
                         .and(let lhs, let rhs), .or(let lhs, let rhs), .in(let lhs, let rhs), .subset(let lhs, let rhs),
                         .union(let lhs, let rhs), .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs),
                         .tupleDynamicAccess(let lhs, let rhs), .tupleAppend(let lhs, let rhs),
                         .tupleConcatenate(let lhs, let rhs), .functionApply(let lhs, let rhs),
                         .functionSet(let lhs, let rhs), .setSum(let lhs, let rhs),
                         .integerRange(let lhs, let rhs):
                        pending.append(.expression(rhs))
                        pending.append(.expression(lhs))
                    case .ifThenElse(let condition, let then, let otherwise):
                        pending.append(.expression(otherwise))
                        pending.append(.expression(then))
                        pending.append(.expression(condition))
                    case .setLiteral(let values), .tupleLiteral(let values):
                        pending.append(contentsOf: values.reversed().map(FieldDiscoveryTask.expression))
                    case .recordLiteral(let record):
                        for field in record.fields.reversed() {
                            pending.append(.expression(field.value))
                            pending.append(.name(field.name))
                        }
                    case .recordAccess(let value, let field):
                        pending.append(.name(field))
                        pending.append(.expression(value))
                    case .except(let function, let key, let value):
                        pending.append(.expression(value))
                        pending.append(.expression(key))
                        pending.append(.expression(function))
                    case .caseExpr(let branches, let otherwise):
                        if let otherwise { pending.append(.expression(otherwise)) }
                        pending.append(contentsOf: branches.reversed().map(FieldDiscoveryTask.expression))
                    case .setFilter(let domain, _, let body), .functionLiteral(let domain, _, let body),
                         .forAll(let domain, _, let body), .exists(let domain, _, let body),
                         .choose(let domain, _, let body):
                        pending.append(.expression(body))
                        pending.append(.expression(domain))
                    case .setMap(let body, _, let domain):
                        pending.append(.expression(domain))
                        pending.append(.expression(body))
                    case .foldFunction(let lambda, let initial, let sequence):
                        pending.append(.expression(sequence))
                        pending.append(.expression(initial))
                        pending.append(.expression(lambda.body))
                    case .operatorApplication(let operation, let arguments):
                        pending.append(contentsOf: arguments.reversed().map(FieldDiscoveryTask.argument))
                        pending.append(.operation(operation))
                    case .recursiveCall(_, let arguments):
                        pending.append(contentsOf: arguments.reversed().map(FieldDiscoveryTask.expression))
                    case .letValue(_, let value, let body):
                        pending.append(.expression(body))
                        pending.append(.expression(value))
                    case .letIn(let definitions, let body):
                        pending.append(.expression(body))
                        for definition in definitions.reversed() {
                            pending.append(.expression(definition.body))
                            if let domain = definition.domain { pending.append(.expression(domain)) }
                        }
                    }
                }
            }
        }

        func visit(_ value: TLAValue) { visit(FieldDiscoveryTask.value(value)) }
        func visit(_ expression: StateExpr) { visit(FieldDiscoveryTask.expression(expression)) }
        func visit(_ action: ActionExpr) { visit(FieldDiscoveryTask.action(action)) }

        for module in modules {
            module.constants.forEach { visit($0.value) }
            for variable in module.variables {
                switch variable.initialization {
                case .value(let value): visit(value)
                case .expression(let expression), .memberOf(let expression): visit(expression)
                }
            }
            for action in module.actions {
                action.bindings.flatMap(\.values).forEach(visit)
                visit(action.body)
            }
            module.invariants.forEach { visit($0.body) }
            module.temporalProperties.forEach { temporal in
                switch temporal.expr {
                case .always(let expression), .eventually(let expression), .alwaysEventually(let expression), .eventuallyAlways(let expression):
                    visit(expression)
                case .leadsTo(let lhs, let rhs):
                    visit(lhs)
                    visit(rhs)
                }
            }
            if let constraint = module.constraint { visit(constraint) }
            if let assume = module.assume { visit(assume) }
            module.formalOperatorDefinitions.forEach { definition in
                visit(definition.body)
            }
            module.recursiveFuncs.forEach { function in
                visit(function.body)
            }
            module.importConfigurations.flatMap(\.replacements).forEach { replacement in
                visit(replacement.expression)
            }
        }
        return names
    }

    private static func controlLocations(
        in algorithms: [Algorithm],
        actions: [NamedAction],
        hasProgramCounter: Bool
    ) -> [CompiledControlLocation] {
        var labels: [CompiledControlLocation] = []

        func append(
            _ steps: [AlgorithmStepModel],
            owner: ControlOwner,
            renderedName: (AlgorithmStepModel) -> String
        ) {
            for step in steps {
                labels.append(
                    .init(
                        id: .init(ordinal: labels.count),
                        owner: owner,
                        sourceName: step.label.name,
                        renderedName: renderedName(step)
                    )
                )
            }
        }

        for algorithm in algorithms {
            let model = algorithm.model
            append(
                model.sequentialSteps,
                owner: .sequential(algorithm: model.name),
                renderedName: { $0.label.name }
            )
            for (ordinal, process) in model.processes.enumerated() {
                append(
                    process.steps,
                    owner: .process(
                        algorithm: model.name,
                        ordinal: ordinal,
                        typeName: process.typeName
                    ),
                    renderedName: { $0.label.name }
                )
            }
            for procedure in model.procedures {
                append(
                    procedure.steps,
                    owner: .procedure(algorithm: model.name, name: procedure.name),
                    renderedName: { "procedure.\(procedure.name).\($0.label.name)" }
                )
            }
            if model.sequentialSteps.isEmpty == false || model.processes.isEmpty == false {
                labels.append(
                    .init(
                        id: .init(ordinal: labels.count),
                        owner: .generated(algorithm: model.name, purpose: CompilerControlSymbol.done.rawValue),
                        sourceName: CompilerControlSymbol.done.rawValue,
                        renderedName: CompilerControlSymbol.done.rawValue
                    )
                )
            }
        }
        let knownActionNames = Set(labels.flatMap { [$0.sourceName, $0.renderedName] })
        for action in actions where action.name != CompilerControlSymbol.terminatingAction.rawValue && knownActionNames.contains(action.name) == false {
            labels.append(
                .init(
                    id: .init(ordinal: labels.count),
                    owner: .generated(algorithm: algorithms.first?.model.name ?? "", purpose: action.name),
                    sourceName: action.name,
                    renderedName: action.name
                )
            )
        }
        if hasProgramCounter, labels.contains(where: { $0.sourceName == CompilerControlSymbol.done.rawValue }) == false {
            labels.append(
                .init(
                    id: .init(ordinal: labels.count),
                    owner: .generated(algorithm: algorithms.first?.model.name ?? "", purpose: CompilerControlSymbol.done.rawValue),
                    sourceName: CompilerControlSymbol.done.rawValue,
                    renderedName: CompilerControlSymbol.done.rawValue
                )
            )
        }
        return labels
    }

    private static func actions(
        _ declarations: [NamedAction],
        controlLocations: [CompiledControlLocation]
    ) -> [CompiledActionLayout] {
        let actionNames = Set(declarations.map(\.name))
        let procedureControls = controlLocations.compactMap { label -> (qualified: String, label: String)? in
            guard case .procedure = label.owner else { return nil }
            return (qualified: label.renderedName, label: label.sourceName)
        }
        let labelCounts = Dictionary(grouping: procedureControls, by: \.label).mapValues(\.count)
        let unqualifiedActions = actionNames.subtracting(Set(procedureControls.map(\.qualified)))
        let preferredNames: [String: String] = Dictionary(uniqueKeysWithValues: procedureControls.compactMap { candidate -> (String, String)? in
            guard actionNames.contains(candidate.qualified),
                  labelCounts[candidate.label] == 1,
                  !unqualifiedActions.contains(candidate.label) else {
                return nil
            }
            return (candidate.qualified, candidate.label)
        })

        var used: Set<String> = []
        return declarations.enumerated().map { ordinal, action in
            let raw = (preferredNames[action.name] ?? action.name).unicodeScalars.map { scalar -> String in
                switch scalar.value {
                case 48...57, 65...90, 97...122, 95: String(scalar)
                default: "_"
                }
            }.joined()
            let candidate = raw.isEmpty ? "Action" : (raw.first?.isNumber == true ? "_\(raw)" : raw)
            let stem = isTLADeclarationName(candidate) ? candidate : "_\(candidate)"
            var renderedName = stem.isEmpty ? "Action" : stem
            var suffix = 2
            while !used.insert(renderedName).inserted {
                renderedName = "\(stem)__\(suffix)"
                suffix += 1
            }
            return .init(
                id: .init(ordinal: ordinal),
                declaration: .init(kind: .action, name: action.name, sourceOffset: nil),
                renderedName: renderedName
            )
        }
    }
}

enum CompiledReference: Hashable, Sendable {
    case variable(VariableID)
    case binder(BinderID)
    case action(ActionID)
    case property(PropertyID)
    case controlLocation(ControlLocationID)
    case field(FieldID)
    case constant(TLAValue)
    case `operator`(OperatorID)
}

struct CompiledBindingTable: Sendable {
    let binders: [BinderID: String]
    let operatorNames: [OperatorID: String]
    let localOperatorDependencies: [OperatorID: Set<OperatorID>]
    let references: [String: CompiledReference]

    init(
        operatorNames: [OperatorID: String] = [:],
        binders: [BinderID: String] = [:],
        localOperatorDependencies: [OperatorID: Set<OperatorID>] = [:],
        references: [String: CompiledReference] = [:]
    ) {
        self.binders = binders
        self.operatorNames = operatorNames
        self.localOperatorDependencies = localOperatorDependencies
        self.references = references
    }

    func binderName(_ id: BinderID) -> String? { binders[id] }

    func operatorName(_ id: OperatorID) -> String? { operatorNames[id] }
}

struct BindingValidator {
    private let layout: CompiledLayout
    private let closure: FormalModuleClosure
    private let constants: [ConstantDecl]
    private let formalParameters: Set<String>
    private let symmetricMembers: [TLAValue]
    private let incomingModuleParameters: [FormalModuleReplacement]
    private let reservedRenderedNames: Set<String>
    private var operators: [String: OperatorID]
    private var operatorNames: [OperatorID: String]
    private var operatorArities: [OperatorID: Int]
    private var nextBinderOrdinal = 0
    private var nextOperatorOrdinal = 0
    private var knownBinderNames: Set<String> = []
    private var binders: [BinderID: String] = [:]
    private var localOperatorDependencies: [OperatorID: Set<OperatorID>] = [:]
    private var references: [String: CompiledReference] = [:]

    init(
        spec: TLASpec,
        layout: CompiledLayout,
        closure: FormalModuleClosure,
        incomingModuleParameters: [FormalModuleReplacement] = []
    ) {
        self.layout = layout
        self.closure = closure
        constants = spec.constants
        formalParameters = Set(spec.formalParameters.map(\.name))
        symmetricMembers = spec.symmetricCollections.flatMap { $0.metadata.members }
        self.incomingModuleParameters = incomingModuleParameters
        var reservedRenderedNames = spec.renderedDeclarationNames()
        reservedRenderedNames.formUnion(spec.symmetricCollections.flatMap(\.metadata.generatedSymbols))
        reservedRenderedNames.formUnion(spec.symmetrySets.map { "Symm\($0.variableName)" })
        reservedRenderedNames.formUnion(incomingModuleParameters.map(\.operatorName))
        self.reservedRenderedNames = reservedRenderedNames
        let signatures = spec.formalOperatorDefinitions.map { ($0.name, $0.parameters.count) }
            + spec.recursiveFuncs.map { ($0.name, $0.params.count) }
            + closure.linkedOperators.formalOperatorDefinitions.map { ($0.name, $0.parameters.count) }
            + closure.linkedOperators.recursiveFunctions.map { ($0.name, $0.params.count) }
        var allocated: [String: OperatorID] = [:]
        var arities: [OperatorID: Int] = [:]
        for (name, arity) in signatures where allocated[name] == nil {
            let id = OperatorID(ordinal: allocated.count)
            allocated[name] = id
            arities[id] = arity
        }
        operators = allocated
        operatorArities = arities
        operatorNames = Dictionary(uniqueKeysWithValues: operators.map { ($0.value, $0.key) })
        nextOperatorOrdinal = operators.count
    }

    mutating func validate(spec: TLASpec) throws -> CompiledBindingTable {
        for constant in spec.constants {
            try validateValue(constant.value, at: "constants.\(constant.name)")
        }
        for (index, variable) in spec.variables.enumerated() {
            let path = "variables.\(variable.name)"
            switch variable.initialization {
            case .value(let value):
                if spec.symmetricCollections.contains(where: { $0.name == variable.name }) == false {
                    try validateValue(value, at: "\(path).initialization")
                }
            case .expression(let expression), .memberOf(let expression):
                try validateExpression(expression, at: "\(path).initialization", scope: [:])
            }
            if layout.variables.indices.contains(index) {
                references["\(path).declaration"] = .variable(layout.variables[index].id)
            }
        }
        for action in spec.actions {
            guard let id = layout.actionID(named: action.name) else {
                throw diagnostic(
                    code: .unknownReference,
                    path: "actions.\(action.name).declaration",
                    expected: "a declared action",
                    actual: "no action identity"
                )
            }
            references["actions.\(action.name).declaration"] = .action(id)
            for (index, value) in action.bindings.flatMap(\.values).enumerated() {
                try validateValue(value, at: "actions.\(action.name).bindings[\(index)]")
            }
            let scope = try bind(action.bindings.map(\.name), at: "actions.\(action.name).bindings", scope: [:])
            try validate([.action(action.body, path: "actions.\(action.name).body", scope: scope)])
        }
        for (offset, condition) in spec.fairness.enumerated() {
            try validate(condition, at: "fairness[\(offset)]")
        }
        for invariant in spec.invariants {
            let path = "invariants.\(invariant.name)"
            guard let id = layout.propertyID(kind: .invariant, named: invariant.name) else {
                throw diagnostic(code: .unknownReference, path: "\(path).declaration", expected: "a declared invariant", actual: "no property identity")
            }
            references["\(path).declaration"] = .property(id)
            try validateExpression(invariant.body, at: "\(path).body", scope: [:])
        }
        for temporal in spec.temporalProperties {
            let path = "temporalProperties.\(temporal.name)"
            guard let id = layout.propertyID(kind: .temporalProperty, named: temporal.name) else {
                throw diagnostic(code: .unknownReference, path: "\(path).declaration", expected: "a declared temporal property", actual: "no property identity")
            }
            references["\(path).declaration"] = .property(id)
            try validate(temporal.expr, at: path)
        }
        try validateExpression(spec.constraint, at: "constraint", scope: [:])
        try validateExpression(spec.assume, at: "assume", scope: [:])
        for definition in spec.formalOperatorDefinitions {
            if let issue = definition.sourceIssue {
                throw issue.compilationDiagnostic(stage: .binding, path: "formalOperators.\(definition.name)")
            }
            guard let id = operators[definition.name] else {
                throw diagnostic(code: .unknownReference, path: "formalOperators.\(definition.name)", expected: "a declared operator", actual: "no operator identity")
            }
            references["formalOperators.\(definition.name).declaration"] = .operator(id)
            let outerOperators = operators
            let scope = try bindFormalParameters(definition.parameters, at: "formalOperators.\(definition.name).parameters", scope: [:])
            try validateExpression(definition.body, at: "formalOperators.\(definition.name).body", scope: scope)
            operators = outerOperators
        }
        for function in spec.recursiveFuncs {
            guard let id = operators[function.name] else {
                throw diagnostic(code: .unknownReference, path: "recursiveFunctions.\(function.name)", expected: "a declared operator", actual: "no operator identity")
            }
            references["recursiveFunctions.\(function.name).declaration"] = .operator(id)
            let scope = try bind(function.params, at: "recursiveFunctions.\(function.name).parameters", scope: [:])
            try validateExpression(function.body, at: "recursiveFunctions.\(function.name).body", scope: scope)
        }
        let localFormalNames = Set(spec.formalOperatorDefinitions.map(\.name))
        for definition in closure.linkedOperators.formalOperatorDefinitions where !localFormalNames.contains(definition.name) {
            guard let id = operators[definition.name] else {
                throw diagnostic(code: .unknownReference, path: "linkedFormalOperators.\(definition.name)", expected: "a declared operator", actual: "no operator identity")
            }
            references["linkedFormalOperators.\(definition.name).declaration"] = .operator(id)
            let outerOperators = operators
            let scope = try bindFormalParameters(definition.parameters, at: "linkedFormalOperators.\(definition.name).parameters", scope: [:])
            try validateExpression(definition.body, at: "linkedFormalOperators.\(definition.name).body", scope: scope)
            operators = outerOperators
        }
        let localRecursiveNames = Set(spec.recursiveFuncs.map(\.name))
        for function in closure.linkedOperators.recursiveFunctions where !localRecursiveNames.contains(function.name) {
            guard let id = operators[function.name] else {
                throw diagnostic(code: .unknownReference, path: "linkedRecursiveFunctions.\(function.name)", expected: "a declared operator", actual: "no operator identity")
            }
            references["linkedRecursiveFunctions.\(function.name).declaration"] = .operator(id)
            let scope = try bind(function.params, at: "linkedRecursiveFunctions.\(function.name).parameters", scope: [:])
            try validateExpression(function.body, at: "linkedRecursiveFunctions.\(function.name).body", scope: scope)
        }
        for refinement in spec.refinements {
            for mapping in refinement.mappings {
                try validateExpression(
                    mapping.source,
                    at: "refinements.\(refinement.name).mappings.\(mapping.target)",
                    scope: [:]
                )
            }
        }
        return CompiledBindingTable(
            operatorNames: operatorNames,
            binders: binders,
            localOperatorDependencies: localOperatorDependencies,
            references: references
        )
    }

    private mutating func validate(_ expression: TemporalExpr, at path: String) throws {
        switch expression {
        case .always(let predicate), .eventually(let predicate), .alwaysEventually(let predicate), .eventuallyAlways(let predicate):
            try validateExpression(predicate, at: "\(path).body", scope: [:])
        case .leadsTo(let from, let to):
            try validateExpression(from, at: "\(path).from", scope: [:])
            try validateExpression(to, at: "\(path).to", scope: [:])
        }
    }

    private mutating func validate(_ condition: FairnessCondition, at path: String) throws {
        let name: String
        switch condition {
        case .weakFairnessNext, .strongFairnessNext:
            return
        case .weakFairness(let value), .strongFairness(let value):
            name = value
        case .weakFairnessActionCall(let value), .strongFairnessActionCall(let value):
            name = value.name
            for (index, argument) in value.arguments.enumerated() {
                try validateValue(argument, at: "\(path).arguments[\(index)]")
            }
        }
        guard let id = layout.actionID(named: name) else {
            throw diagnostic(
                code: .unknownReference,
                path: path,
                expected: "a declared action",
                actual: "fairness references '\(name)'"
            )
        }
        references["\(path).action"] = .action(id)
    }

    private mutating func validateExpression(
        _ expression: StateExpr?,
        at path: String,
        scope: [String: BinderID]
    ) throws {
        guard let expression else { return }
        try validate([.expression(expression, path: path, scope: scope)])
    }

    private mutating func validateExpression(_ expression: StateExpr, at path: String, scope: [String: BinderID]) throws {
        try validate([.expression(expression, path: path, scope: scope)])
    }

    private mutating func validate(_ initial: [BindingValidationTask]) throws {
        var pending = initial
        while let task = pending.popLast() {
            switch task {
            case .expression(let expression, let path, let scope):
                try validateExpressionNode(expression, at: path, scope: scope, pending: &pending)
            case .action(let action, let path, let scope):
                try validateActionNode(action, at: path, scope: scope, pending: &pending)
            case .bindExpression(let names, let binderPath, let expression, let expressionPath, let scope):
                let bodyScope = try bind(names, at: binderPath, scope: scope)
                pending.append(.expression(expression, path: expressionPath, scope: bodyScope))
            case .bindAction(let name, let binderPath, let action, let actionPath, let scope):
                let bodyScope = try bind([name], at: binderPath, scope: scope)
                pending.append(.action(action, path: actionPath, scope: bodyScope))
            case .formalOperator(let operation, let path, let scope):
                try validateFormalOperator(operation, at: path, scope: scope, pending: &pending)
            case .formalArgument(let argument, let path, let scope):
                switch argument {
                case .value(let expression): pending.append(.expression(expression, path: path, scope: scope))
                case .operator(let operation): pending.append(.formalOperator(operation, path: path, scope: scope))
                }
            case .recordFields(let fields, let index, var seen, let path, let scope):
                guard fields.indices.contains(index) else { continue }
                let field = fields[index]
                guard seen.insert(field.name).inserted else {
                    throw CompilationDiagnostic(
                        code: .duplicateRecordField,
                        stage: .validation,
                        path: "\(path).fields[\(index)].declaration",
                        expected: "one declaration for each record field",
                        actual: "a repeated record field '\(field.name)'",
                        nextSafeAction: "Give each record field a distinct name."
                    )
                }
                let fieldPath = "\(path).fields[\(index)]"
                try bindField(field.name, at: "\(fieldPath).declaration")
                pending.append(.recordFields(fields, index: index + 1, seen: seen, path: path, scope: scope))
                pending.append(.expression(field.value, path: "\(fieldPath).value", scope: scope))
            case .bindField(let name, let path):
                try bindField(name, at: path)
            case .localOperators(let operations, let body, let path, let scope):
                try scheduleLocalOperators(operations, body: body, at: path, scope: scope, pending: &pending)
            case .localOperator(let operation, let id, let path, let scope):
                let referencePathsBeforeBody = Set(references.keys)
                pending.append(.finishLocalOperator(
                    id,
                    referencePathsBeforeBody: referencePathsBeforeBody,
                    declarationPath: "\(path).declaration"
                ))
                pending.append(.bindExpression(
                    names: operation.parameters,
                    binderPath: "\(path).parameters",
                    expression: operation.body,
                    expressionPath: "\(path).body",
                    scope: scope
                ))
                if let domain = operation.domain {
                    pending.append(.expression(domain, path: "\(path).domain", scope: scope))
                }
            case .finishLocalOperator(let id, let referencePathsBeforeBody, let declarationPath):
                localOperatorDependencies[id] = Set(references.compactMap { path, reference in
                    guard referencePathsBeforeBody.contains(path) == false,
                          case .operator(let target) = reference
                    else { return nil }
                    return target
                })
                references[declarationPath] = .operator(id)
            case .restoreOperators(let outer):
                operators = outer
            }
        }
    }

    private mutating func validateExpressionNode(
        _ expression: StateExpr,
        at path: String,
        scope: [String: BinderID],
        pending: inout [BindingValidationTask]
    ) throws {
        switch expression {
        case .sourceIssue(let issue):
            throw issue.compilationDiagnostic(stage: .validation, path: path)
        case .value(let value):
            try validateValue(value, at: path)
        case .currentProcess:
            throw diagnostic(
                code: .unknownReference,
                path: path,
                expected: "a process scope",
                actual: "current-process identity outside an algorithm process"
            )
        case .programCounter:
            guard let id = layout.programCounterID() else {
                throw diagnostic(
                    code: .unknownReference,
                    path: path,
                    expected: "a compiler-owned program counter",
                    actual: "this model has no program counter"
                )
            }
            references[path] = .variable(id)
        case .procedureStack:
            guard let id = layout.procedureStackID() else {
                throw diagnostic(
                    code: .unknownReference,
                    path: path,
                    expected: "a compiler-owned procedure stack",
                    actual: "this model has no procedure stack"
                )
            }
            references[path] = .variable(id)
        case .controlLocation(let reference):
            guard let id = layout.controlLocationID(for: reference) else {
                throw diagnostic(
                    code: .unknownControlLocation,
                    path: path,
                    expected: "a control location declared by the source algorithm",
                    actual: "unresolved control location '\(reference.sourceName)'"
                )
            }
            references[path] = .controlLocation(id)
        case .variable(let name):
            try resolveValue(name, at: path, scope: scope)
        case .processLocalFamily(let name):
            throw diagnostic(
                code: .unknownReference,
                path: path,
                expected: "a process-local declaration lowered from an algorithm",
                actual: "process-local family '\(name)' outside algorithm lowering"
            )
        case .enabledAction(let name):
            guard let id = layout.actionID(named: name) else {
                try unresolved(name, at: path, expected: "a declared action")
                return
            }
            references[path] = .action(id)
        case .negate(let value), .not(let value), .cardinality(let value), .powerSet(let value),
             .unionAll(let value), .tupleLength(let value), .tupleHead(let value), .tupleTail(let value),
             .domain(let value), .sequenceFromSet(let value):
            pending.append(.expression(value, path: path, scope: scope))
        case .add(let lhs, let rhs), .subtract(let lhs, let rhs), .multiply(let lhs, let rhs),
             .divide(let lhs, let rhs), .modulo(let lhs, let rhs), .integerDivide(let lhs, let rhs),
             .equal(let lhs, let rhs), .notEqual(let lhs, let rhs), .lessThan(let lhs, let rhs),
             .lessOrEqual(let lhs, let rhs), .greaterThan(let lhs, let rhs), .greaterOrEqual(let lhs, let rhs),
             .and(let lhs, let rhs), .or(let lhs, let rhs), .in(let lhs, let rhs), .subset(let lhs, let rhs),
             .union(let lhs, let rhs), .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs),
             .tupleDynamicAccess(let lhs, let rhs), .tupleAppend(let lhs, let rhs),
             .tupleConcatenate(let lhs, let rhs),
             .functionSet(let lhs, let rhs), .setSum(let lhs, let rhs):
            pending.append(.expression(rhs, path: "\(path).right", scope: scope))
            pending.append(.expression(lhs, path: "\(path).left", scope: scope))
        case .functionApply(.variable(let name), let argument)
            where scope[name] == nil && operators.keys.contains(name):
            guard let id = operators[name], let arity = operatorArities[id] else {
                throw diagnostic(
                    code: .invalidFormalOperatorApplication,
                    path: path,
                    expected: "a bound unary operator",
                    actual: "operator '\(name)' has no bound signature"
                )
            }
            guard arity == 1 else {
                throw diagnostic(
                    code: .invalidFormalOperatorApplication,
                    path: path,
                    expected: "a unary operator",
                    actual: "operator '\(name)' has arity \(arity)"
                )
            }
            references["\(path).left"] = .operator(id)
            pending.append(.expression(argument, path: "\(path).right", scope: scope))
        case .functionApply(let function, let argument):
            pending.append(.expression(argument, path: "\(path).right", scope: scope))
            pending.append(.expression(function, path: "\(path).left", scope: scope))
        case .ifThenElse(let condition, let then, let otherwise):
            pending.append(.expression(otherwise, path: "\(path).else", scope: scope))
            pending.append(.expression(then, path: "\(path).then", scope: scope))
            pending.append(.expression(condition, path: "\(path).condition", scope: scope))
        case .setLiteral(let values), .tupleLiteral(let values):
            for (index, value) in values.enumerated().reversed() {
                pending.append(.expression(value, path: "\(path)[\(index)]", scope: scope))
            }
        case .tupleAccess(let value, _):
            pending.append(.expression(value, path: path, scope: scope))
        case .recordAccess(let value, let field):
            pending.append(.bindField(field, path: "\(path).field"))
            pending.append(.expression(value, path: "\(path).value", scope: scope))
        case .recordLiteral(let values):
            pending.append(.recordFields(values.fields, index: 0, seen: [], path: path, scope: scope))
        case .except(let function, let key, let value):
            pending.append(.expression(value, path: "\(path).value", scope: scope))
            pending.append(.expression(key, path: "\(path).key", scope: scope))
            pending.append(.expression(function, path: "\(path).function", scope: scope))
        case .caseExpr(let pairs, let otherwise):
            guard pairs.isEmpty == false, pairs.count.isMultiple(of: 2) else {
                throw CompilationDiagnostic(
                    code: .invalidFormalDeclaration,
                    stage: .validation,
                    path: path,
                    expected: "at least one complete CASE condition and value pair",
                    actual: pairs.isEmpty ? "no CASE branches" : "an unmatched CASE branch",
                    nextSafeAction: "Provide complete condition and value pairs before an optional OTHER expression."
                )
            }
            if let otherwise {
                pending.append(.expression(otherwise, path: "\(path).otherwise", scope: scope))
            }
            for (index, pair) in pairs.enumerated().reversed() {
                pending.append(.expression(pair, path: "\(path).branch[\(index)]", scope: scope))
            }
        case .setFilter(let set, let name, let predicate), .functionLiteral(let set, let name, let predicate),
             .forAll(let set, let name, let predicate), .exists(let set, let name, let predicate),
             .choose(let set, let name, let predicate):
            pending.append(.bindExpression(
                names: [name],
                binderPath: "\(path).binder",
                expression: predicate,
                expressionPath: "\(path).body",
                scope: scope
            ))
            pending.append(.expression(set, path: "\(path).domain", scope: scope))
        case .setMap(let value, let name, let set):
            pending.append(.bindExpression(
                names: [name],
                binderPath: "\(path).binder",
                expression: value,
                expressionPath: "\(path).body",
                scope: scope
            ))
            pending.append(.expression(set, path: "\(path).domain", scope: scope))
        case .integerRange(let lower, let upper):
            pending.append(.expression(upper, path: "\(path).upper", scope: scope))
            pending.append(.expression(lower, path: "\(path).lower", scope: scope))
        case .foldFunction(let lambda, let initial, let sequence):
            let bodyScope = try bind(lambda.parameters, at: "\(path).parameters", scope: scope)
            pending.append(.expression(sequence, path: "\(path).sequence", scope: scope))
            pending.append(.expression(initial, path: "\(path).initial", scope: scope))
            pending.append(.expression(lambda.body, path: "\(path).body", scope: bodyScope))
        case .operatorApplication(let operation, let arguments):
            guard operation.arity == arguments.count else {
                throw diagnostic(
                    code: .invalidFormalOperatorApplication,
                    path: path,
                    expected: "\(operation.arity) formal operator arguments",
                    actual: "\(arguments.count) arguments"
                )
            }
            if case .lambda = operation,
               arguments.contains(where: {
                   if case .operator = $0 { return true }
                   return false
               }) {
                throw diagnostic(
                    code: .invalidFormalOperatorApplication,
                    path: path,
                    expected: "formal value arguments for a lambda",
                    actual: "a formal operator argument"
                )
            }
            for (index, argument) in arguments.enumerated().reversed() {
                pending.append(.formalArgument(
                    argument,
                    path: "\(path).arguments[\(index)]",
                    scope: scope
                ))
            }
            pending.append(.formalOperator(operation, path: "\(path).operator", scope: scope))
        case .recursiveCall(let name, let arguments):
            guard let id = operators[name] else {
                throw diagnostic(
                    code: .unresolvedImportedSymbol,
                    path: path,
                    expected: "a linked recursive or formal operator",
                    actual: "unresolved symbol '\(name)'"
                )
            }
            guard let declaredArity = operatorArities[id] else {
                throw diagnostic(
                    code: .invalidFormalOperatorApplication,
                    path: path,
                    expected: "a bound recursive operator signature",
                    actual: "recursive call '\(name)' has no bound signature"
                )
            }
            guard declaredArity == arguments.count else {
                throw diagnostic(
                    code: .invalidFormalOperatorApplication,
                    path: path,
                    expected: "\(declaredArity) formal operator arguments",
                    actual: "\(arguments.count) arguments"
                )
            }
            references[path] = .operator(id)
            for (index, argument) in arguments.enumerated().reversed() {
                pending.append(.expression(argument, path: "\(path).arguments[\(index)]", scope: scope))
            }
        case .letValue(let name, let value, let body):
            pending.append(.bindExpression(
                names: [name],
                binderPath: "\(path).binder",
                expression: body,
                expressionPath: "\(path).body",
                scope: scope
            ))
            pending.append(.expression(value, path: "\(path).value", scope: scope))
        case .letIn(let operators, let body):
            pending.append(.localOperators(operators, body: body, path: path, scope: scope))
        }
    }

    private func validateValue(_ value: TLAValue, at path: String) throws {
        guard let member = symmetricMembers.first(where: { valueContains(value, $0) }) else {
            return
        }
        throw diagnostic(
            code: .invalidSymmetricCollection,
            path: path,
            expected: "logic invariant under exchangeable member renaming",
            actual: "authored expression names compiler-owned symmetric member '\(member)'"
        )
    }

    private mutating func validateFormalOperator(
        _ operation: FormalOperator,
        at path: String,
        scope: [String: BinderID],
        pending: inout [BindingValidationTask]
    ) throws {
        switch operation {
        case .reference(let name, let arity):
            guard let id = operators[name] else {
                throw diagnostic(
                    code: .unresolvedImportedSymbol,
                    path: path,
                    expected: "a linked formal operator",
                    actual: "unresolved symbol '\(name)'"
                )
            }
            guard let declaredArity = operatorArities[id] else {
                throw diagnostic(
                    code: .invalidFormalOperatorApplication,
                    path: path,
                    expected: "a bound formal operator signature",
                    actual: "reference '\(name)' has no bound signature"
                )
            }
            guard declaredArity == arity else {
                throw diagnostic(
                    code: .invalidFormalOperatorApplication,
                    path: path,
                    expected: "\(declaredArity) formal operator arguments",
                    actual: "reference '\(name)' declares arity \(arity)"
                )
            }
            references[path] = .operator(id)
        case .lambda(let lambda):
            if let issue = lambda.sourceIssue {
                throw issue.compilationDiagnostic(stage: .binding, path: path)
            }
            let bodyScope = try bind(lambda.parameters, at: "\(path).parameters", scope: scope)
            pending.append(.expression(lambda.body, path: "\(path).body", scope: bodyScope))
        }
    }

    private mutating func scheduleLocalOperators(
        _ operators: [LocalOperator],
        body: StateExpr,
        at path: String,
        scope: [String: BinderID],
        pending: inout [BindingValidationTask]
    ) throws {
        for operation in operators {
            if let issue = operation.sourceIssue {
                throw issue.compilationDiagnostic(stage: .binding, path: "\(path).\(operation.name)")
            }
            try requireFormalDeclarationName(
                operation.name,
                kind: "local operator",
                at: "\(path).\(operation.name).declaration"
            )
        }
        try duplicate(operators.map(\.name), at: "\(path).operators")
        let outerOperators = self.operators
        let localOperators = operators.map { operation in
            (operation.name, OperatorID(ordinal: nextOperatorOrdinal))
        }
        nextOperatorOrdinal += localOperators.count
        for local in localOperators {
            self.operators[local.0] = local.1
            operatorNames[local.1] = local.0
        }
        for (operation, local) in zip(operators, localOperators) {
            operatorArities[local.1] = operation.parameters.count
        }
        for local in localOperators {
            references["\(path).operators.\(local.0)"] = .operator(local.1)
        }
        pending.append(.restoreOperators(outerOperators))
        pending.append(.expression(body, path: "\(path).body", scope: scope))
        for (operation, local) in zip(operators, localOperators).reversed() {
            pending.append(.localOperator(
                operation,
                id: local.1,
                path: "\(path).\(operation.name)",
                scope: scope
            ))
        }
    }

    private mutating func validateActionNode(
        _ action: ActionExpr,
        at path: String,
        scope: [String: BinderID],
        pending: inout [BindingValidationTask]
    ) throws {
        switch action {
        case .assign(let target, let value):
            try assignmentTarget(target, at: "\(path).assign", scope: scope)
            pending.append(.expression(value, path: "\(path).value", scope: scope))
        case .unchanged(let target):
            try assignmentTarget(target, at: "\(path).unchanged", scope: scope)
        case .guard_(let condition):
            pending.append(.expression(condition, path: "\(path).guard", scope: scope))
        case .chooseAction(let target, let set):
            try assignmentTarget(target, at: "\(path).choose", scope: scope)
            pending.append(.expression(set, path: "\(path).set", scope: scope))
        case .existsAction(let name, let set, let body):
            pending.append(.bindAction(
                name: name,
                binderPath: "\(path).binder",
                action: body,
                actionPath: "\(path).body",
                scope: scope
            ))
            pending.append(.expression(set, path: "\(path).set", scope: scope))
        case .define(let name, let value, let body):
            pending.append(.bindAction(
                name: name,
                binderPath: "\(path).binder",
                action: body,
                actionPath: "\(path).body",
                scope: scope
            ))
            pending.append(.expression(value, path: "\(path).value", scope: scope))
        case .ifElse(let condition, let then, let otherwise):
            pending.append(.action(otherwise, path: "\(path).else", scope: scope))
            pending.append(.action(then, path: "\(path).then", scope: scope))
            pending.append(.expression(condition, path: "\(path).condition", scope: scope))
        case .and(let lhs, let rhs), .or(let lhs, let rhs):
            pending.append(.action(rhs, path: "\(path).right", scope: scope))
            pending.append(.action(lhs, path: "\(path).left", scope: scope))
        }
    }

    private mutating func bindField(_ name: String, at path: String) throws {
        try requireFormalIdentifier(name, kind: "record field", at: path)
        guard let id = layout.fieldID(named: name) else {
            throw diagnostic(
                code: .unknownReference,
                path: path,
                expected: "a field declared by the compiled layout",
                actual: "unresolved field '\(name)'"
            )
        }
        references[path] = .field(id)
    }

    private mutating func resolveValue(_ name: String, at path: String, scope: [String: BinderID]) throws {
        if let id = scope[name] {
            references[path] = .binder(id)
            return
        }
        if let id = layout.variableID(named: name) {
            references[path] = .variable(id)
            return
        }
        if let value = constants.value(named: name) {
            references[path] = .constant(value)
            return
        }
        if formalParameters.contains(name) {
            references[path] = .constant(.constant(name))
            return
        }
        if incomingModuleParameters.contains(where: { $0.operatorName == name }) {
            references[path] = .constant(.constant(name))
            return
        }
        if let id = operators[name] {
            guard operatorArities[id] == 0 else {
                throw diagnostic(
                    code: .invalidFormalOperatorApplication,
                    path: path,
                    expected: "a zero-arity operator in value position",
                    actual: "operator '\(name)' requires \(operatorArities[id] ?? 0) arguments"
                )
            }
            references[path] = .operator(id)
            return
        }
        try unresolved(name, at: path, expected: "a declared variable, scoped binder, or linked symbol")
    }

    private mutating func assignmentTarget(_ target: ActionTarget, at path: String, scope: [String: BinderID]) throws {
        switch target {
        case .programCounter:
            guard let id = layout.programCounterID() else {
                throw diagnostic(
                    code: .unknownReference,
                    path: path,
                    expected: "a compiler-owned program counter",
                    actual: "this model has no program counter"
                )
            }
            references[path] = .variable(id)
            return
        case .procedureStack:
            guard let id = layout.procedureStackID() else {
                throw diagnostic(
                    code: .unknownReference,
                    path: path,
                    expected: "a compiler-owned procedure stack",
                    actual: "this model has no procedure stack"
                )
            }
            references[path] = .variable(id)
            return
        case .named(let name):
            try assignmentTarget(named: name, at: path, scope: scope)
        }
    }

    private mutating func assignmentTarget(named name: String, at path: String, scope: [String: BinderID]) throws {
        if scope[name] != nil || knownBinderNames.contains(name) {
            throw diagnostic(
                code: .assignmentToBinder,
                path: path,
                expected: "an assignable declared state variable",
                actual: "binder '\(name)'"
            )
        }
        guard let id = layout.variableID(named: name) else {
            try unresolved(name, at: path, expected: "an assignable declared state variable")
            return
        }
        references[path] = .variable(id)
    }

    private mutating func bind(_ names: [String], at path: String, scope: [String: BinderID]) throws -> [String: BinderID] {
        try duplicate(names, at: path)
        var nested = scope
        for name in names {
            try requireFormalIdentifier(name, kind: "binder", at: "\(path).\(name)")
            let id = allocateBinder()
            knownBinderNames.insert(name)
            nested[name] = id
            references["\(path).\(name)"] = .binder(id)
        }
        return nested
    }

    private mutating func bindFormalParameters(
        _ parameters: [FormalParameter],
        at path: String,
        scope: [String: BinderID]
    ) throws -> [String: BinderID] {
        try duplicate(parameters.map(\.name), at: path)
        var nested = scope
        for parameter in parameters {
            try requireFormalIdentifier(
                parameter.name,
                kind: "formal parameter",
                at: "\(path).\(parameter.name)"
            )
            switch parameter {
            case .value(let name):
                let id = allocateBinder()
                knownBinderNames.insert(name)
                nested[name] = id
                references["\(path).\(name)"] = .binder(id)
            case .operator(let name, let arity):
                let id = OperatorID(ordinal: nextOperatorOrdinal)
                nextOperatorOrdinal += 1
                operators[name] = id
                operatorNames[id] = name
                operatorArities[id] = arity
                references["\(path).\(name)"] = .operator(id)
            }
        }
        return nested
    }

    private mutating func allocateBinder() -> BinderID {
        let id = BinderID(ordinal: nextBinderOrdinal)
        nextBinderOrdinal += 1
        var declaredNames = reservedRenderedNames
        declaredNames.formUnion(operators.keys)
        declaredNames.formUnion(binders.values)
        var renderedName = "b\(id.ordinal)"
        while declaredNames.contains(renderedName) {
            renderedName = "_\(renderedName)"
        }
        binders[id] = renderedName
        return id
    }

    private func requireFormalDeclarationName(_ name: String, kind: String, at path: String) throws {
        guard isTLADeclarationName(name) else {
            throw diagnostic(
                code: .invalidFormalDeclaration,
                path: path,
                expected: "a formal identifier that is not a reserved word",
                actual: "invalid \(kind) name '\(name)'"
            )
        }
    }

    private func requireFormalIdentifier(_ name: String, kind: String, at path: String) throws {
        guard isFormalIdentifier(name) else {
            throw diagnostic(
                code: .invalidFormalDeclaration,
                path: path,
                expected: "a formal identifier beginning with an ASCII letter or underscore",
                actual: "invalid \(kind) name '\(name)'"
            )
        }
    }

    private func duplicate(_ names: [String], at path: String) throws {
        var seen: Set<String> = []
        for name in names where !seen.insert(name).inserted {
            throw diagnostic(
                code: .duplicateBinder,
                path: "\(path).\(name)",
                expected: "one binder named '\(name)' in this scope",
                actual: "multiple binders named '\(name)'"
            )
        }
    }

    private func unresolved(_ name: String, at path: String, expected: String) throws {
        throw diagnostic(
            code: knownBinderNames.contains(name) ? .outOfScopeReference : .unknownReference,
            path: path,
            expected: expected,
            actual: "unresolved name '\(name)'"
        )
    }

    private func diagnostic(
        code: CompilationDiagnostic.Code,
        path: String,
        expected: String,
        actual: String
    ) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: code,
            stage: .binding,
            path: path,
            expected: expected,
            actual: actual,
            nextSafeAction: "Declare the name in this scope or use a visible declaration, then compile again."
        )
    }
}
