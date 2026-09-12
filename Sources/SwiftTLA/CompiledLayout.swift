package struct VariableID: Hashable, Sendable {
    package let ordinal: Int
}

package struct BinderID: Hashable, Sendable {
    package let ordinal: Int
}

package struct ActionID: Hashable, Sendable {
    package let ordinal: Int
}

package struct PropertyID: Hashable, Sendable {
    package let ordinal: Int
}

package struct ControlLocationID: Hashable, Sendable {
    package let ordinal: Int
}



package struct OperatorID: Hashable, Sendable {
    package let ordinal: Int
}

struct ProcedureID: Hashable, Sendable {
    let ordinal: Int
}

struct ModuleInstanceID: Hashable, Sendable {
    let ordinal: Int
}

package struct CompiledDeclaration: Hashable, Sendable {
    package enum Kind: String, Hashable, Sendable {
        case variable
        case action
        case invariant
        case temporalProperty
    }

    package let kind: Kind
    package let name: String
    package let sourceOffset: Int?
    package let origin: VariableOrigin

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

package struct CompiledVariableLayout: Hashable, Sendable {
    package let id: VariableID
    package let declaration: CompiledDeclaration
    package let generatedSwiftType: String?
    package let collection: CompiledModelCollectionLayout?
}

package struct CompiledModelCollectionLayout: Hashable, Sendable {
    package let members: [CompiledValue]
    package let elementType: String?
    package let valueType: String?
}

package struct CompiledActionLayout: Hashable, Sendable {
    package let id: ActionID
    package let declaration: CompiledDeclaration
    package let renderedName: String
    package let isTermination: Bool
}

struct CompiledPropertyLayout: Hashable, Sendable {
    let id: PropertyID
    let declaration: CompiledDeclaration
}

struct CompiledProcedureLayout: Hashable, Sendable {
    let id: ProcedureID
    let algorithm: String
    let name: String
    let sourceOffset: Int?
}

package enum ControlOwner: Hashable, Sendable {
    case sequential(algorithm: String)
    case process(algorithm: String, ordinal: Int, typeName: String)
    case procedure(algorithm: String, name: String)
    case generated(algorithm: String, purpose: String)

    package var canonicalEncoding: String {
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

    package static let done = Self(CompilerControlSymbol.done.rawValue)

    package init(_ sourceName: String) {
        self.owner = nil
        self.sourceName = sourceName
    }

    package init(owner: ControlOwner, sourceName: String) {
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

package struct CompiledControlLocation: Hashable, Sendable {
    package let id: ControlLocationID
    package let owner: ControlOwner
    package let sourceName: String
    package let renderedName: String
}

struct CompiledModuleInstanceLayout: Hashable, Sendable {
    let id: ModuleInstanceID
    let namespace: String
    let moduleName: String
}

package struct CompiledLayout: Hashable, Sendable {
    package let variables: [CompiledVariableLayout]
    package let actions: [CompiledActionLayout]
    let stateProperties: [CompiledPropertyLayout]
    let temporalProperties: [CompiledPropertyLayout]
    let procedures: [CompiledProcedureLayout]
    package let controlLocations: [CompiledControlLocation]
    let moduleInstances: [CompiledModuleInstanceLayout]
    let declarations: [CompiledDeclaration]

    init(source spec: TLASpec) {
        variables = spec.variables.enumerated().map { ordinal, variable in
            let collection = spec.collections.first { $0.name == variable.name }
            return CompiledVariableLayout(
                id: VariableID(ordinal: ordinal),
                declaration: .init(
                    kind: .variable,
                    name: variable.name,
                    sourceOffset: nil,
                    origin: variable.origin
                ),
                generatedSwiftType: variable.generatedSwiftType,
                collection: collection.map {
                    .init(
                        members: $0.metadata.members.map(CompiledValue.init(formal:)),
                        elementType: $0.generatedElementType,
                        valueType: $0.generatedValueType
                    )
                }
            )
        }
        let controlLocations = Self.controlLocations(
            in: spec.sourceAlgorithms,
            actions: spec.actions,
            hasProgramCounter: spec.variables.contains { $0.origin == .programCounter }
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

    func moduleInstanceID(named namespace: String) -> ModuleInstanceID? {
        moduleInstances.first { $0.namespace == namespace }?.id
    }

    func procedure(_ id: ProcedureID) -> CompiledProcedureLayout? {
        guard procedures.indices.contains(id.ordinal) else { return nil }
        return procedures[id.ordinal]
    }

    func controlLocation(_ id: ControlLocationID) -> CompiledControlLocation? {
        controlLocations.first { $0.id == id }
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
            "\(action.id.ordinal):\(action.renderedName.utf8.count):\(action.renderedName):\(action.isTermination)"
        }.joined(separator: "|")
        let procedureEncoding = procedures.map { procedure in
            "\(procedure.algorithm.utf8.count):\(procedure.algorithm)\(procedure.name.utf8.count):\(procedure.name)"
        }.joined(separator: "|")
        let instanceEncoding = moduleInstances.map {
            "\($0.id.ordinal):\($0.namespace.utf8.count):\($0.namespace)\($0.moduleName.utf8.count):\($0.moduleName)"
        }.joined(separator: "|")
        return "declarations[\(declarationEncoding)]actions[\(actionEncoding)]procedures[\(procedureEncoding)]controls[\(controlEncoding)]instances[\(instanceEncoding)]"
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
        for action in actions where !action.isTermination && knownActionNames.contains(action.name) == false {
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
                renderedName: renderedName,
                isTermination: action.isTermination
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
