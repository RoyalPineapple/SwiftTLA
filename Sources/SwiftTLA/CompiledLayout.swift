private enum FieldDiscoveryTask {
    case value(TLAValue)
    case expression(StateExpr)
    case operation(FormalOperator)
    case argument(FormalCallArgument)
    case action(ActionExpr)
    case name(String)
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

struct ProcedureID: Hashable, Sendable {
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
    let id: ProcedureID
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
    let moduleName: String
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
            algorithm.model.procedures.enumerated().map { ordinal, procedure in
                .init(
                    id: .init(ordinal: ordinal),
                    algorithm: algorithm.model.name,
                    name: procedure.name,
                    sourceOffset: nil
                )
            }
        }
        self.controlLocations = controlLocations
        moduleInstances = spec.moduleInstances.enumerated().map {
            .init(
                id: .init(ordinal: $0.offset),
                namespace: $0.element.name,
                moduleName: $0.element.module.name
            )
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

    func procedureID(named name: String) -> ProcedureID? {
        procedures.first { $0.name == name }?.id
    }

    func procedure(_ id: ProcedureID) -> CompiledProcedureLayout? {
        guard procedures.indices.contains(id.ordinal) else { return nil }
        return procedures[id.ordinal]
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
        let instanceEncoding = moduleInstances.map {
            "\($0.id.ordinal):\($0.namespace.utf8.count):\($0.namespace)\($0.moduleName.utf8.count):\($0.moduleName)"
        }.joined(separator: "|")
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

struct CompiledBindingTable: Sendable {
    let binders: [BinderID: String]
    let operatorNames: [OperatorID: String]

    init(
        operatorNames: [OperatorID: String] = [:],
        binders: [BinderID: String] = [:]
    ) {
        self.binders = binders
        self.operatorNames = operatorNames
    }

    func binderName(_ id: BinderID) -> String? { binders[id] }

    func operatorName(_ id: OperatorID) -> String? { operatorNames[id] }
}
