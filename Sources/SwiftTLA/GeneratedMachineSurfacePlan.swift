import Foundation

/// Swift field and collection facts for generated machine code.
package struct MachineSurfaceSwiftFacts: Sendable, Equatable {
    package struct SymmetricCollection: Sendable, Equatable {
        package let elementType: String
        package let valueType: String
        package let verificationScope: Int
        package let initial: TLAValue

        package init(
            elementType: String,
            valueType: String,
            verificationScope: Int,
            initial: TLAValue
        ) {
            self.elementType = elementType
            self.valueType = valueType
            self.verificationScope = verificationScope
            self.initial = initial
        }
    }

    let variableTypes: [VariableID: String]
    let actionBindingTypes: [ActionID: [String?]]
    let symmetricCollections: [VariableID: SymmetricCollection]
    let collectionActions: [ActionID: VariableID]

    init(
        variableTypes: [VariableID: String] = [:],
        actionBindingTypes: [ActionID: [String?]] = [:],
        symmetricCollections: [VariableID: SymmetricCollection] = [:],
        collectionActions: [ActionID: VariableID] = [:]
    ) {
        self.variableTypes = variableTypes
        self.actionBindingTypes = actionBindingTypes
        self.symmetricCollections = symmetricCollections
        self.collectionActions = collectionActions
    }
}

/// Reports an invalid generated machine surface.
package struct GeneratedMachineSurfaceDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    package enum Code: String, Sendable, Equatable {
        case compilationIdentityMismatch
        case unsupportedGeneratedValueShape
    }

    package let code: Code
    package let path: String
    package let expected: String
    package let actual: String
    package let nextSafeAction: String

    package init(
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

    package var description: String {
        "Generated-machine contract failed [\(code.rawValue)] at \(path). "
            + "Expected: \(expected). Actual: \(actual). "
            + "Next safe action: \(nextSafeAction)"
    }
}

/// The emitted-machine view of one compiled specification.
package struct MachineSurfacePlan: Sendable, Equatable {
    package enum FormalValueShape: String, Sendable, Equatable {
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

    package struct Variable: Sendable, Equatable {
        package let formalName: String
        package let storageOrdinal: Int
        package let swiftType: String
        package let valueShape: FormalValueShape
        package let collectionType: CollectionVarType
        package let isSymmetricCollection: Bool

        package init(
            formalName: String,
            storageOrdinal: Int,
            swiftType: String,
            valueShape: FormalValueShape,
            collectionType: CollectionVarType,
            isSymmetricCollection: Bool
        ) {
            self.formalName = formalName
            self.storageOrdinal = storageOrdinal
            self.swiftType = swiftType
            self.valueShape = valueShape
            self.collectionType = collectionType
            self.isSymmetricCollection = isSymmetricCollection
        }
    }

    package struct Binding: Sendable, Equatable {
        package let formalName: String
        package let swiftType: String
        package let domain: [TLAValue]
        package let isPublic: Bool

        package init(formalName: String, swiftType: String, domain: [TLAValue], isPublic: Bool) {
            self.formalName = formalName
            self.swiftType = swiftType
            self.domain = domain
            self.isPublic = isPublic
        }
    }

    package struct Action: Sendable, Equatable {
        package let id: ActionID
        package let formalName: String
        package let swiftIdentifier: String
        package let bindings: [Binding]
        package let symmetricCollection: SymmetricCollection?

        package init(
            id: ActionID,
            formalName: String,
            swiftIdentifier: String,
            bindings: [Binding],
            symmetricCollection: SymmetricCollection?
        ) {
            self.id = id
            self.formalName = formalName
            self.swiftIdentifier = swiftIdentifier
            self.bindings = bindings
            self.symmetricCollection = symmetricCollection
        }
    }

    package struct SymmetricCollection: Sendable, Equatable {
        package let formalName: String
        package let storageOrdinal: Int
        package let verificationScope: Int
        package let initial: TLAValue
        package let elementType: String
        package let valueType: String

        package init(
            formalName: String,
            storageOrdinal: Int,
            verificationScope: Int,
            initial: TLAValue,
            elementType: String,
            valueType: String
        ) {
            self.formalName = formalName
            self.storageOrdinal = storageOrdinal
            self.verificationScope = verificationScope
            self.initial = initial
            self.elementType = elementType
            self.valueType = valueType
        }
    }

    package let compilationIdentity: CompilationIdentity
    package let variables: [Variable]
    package let actions: [Action]
    package let symmetricCollections: [SymmetricCollection]

    package init(
        compilation: CompiledSpecification,
        swiftFacts: MachineSurfaceSwiftFacts = .init()
    ) throws {
        let variables = try compilation.layout.variables.filter {
            $0.declaration.origin == .source
        }.map { layout in
            let variable = compilation.spec.variables[layout.id.ordinal]
            let swiftType: String
            if let collection = swiftFacts.symmetricCollections[layout.id] {
                swiftType = "IdentifiedModelCollection<\(collection.elementType), \(collection.valueType)>"
            } else {
                swiftType = try Self.generatedSwiftType(
                    explicit: swiftFacts.variableTypes[layout.id],
                    fallback: variable.initial,
                    path: "variables.\(layout.declaration.name)"
                )
            }
            return Variable(
                formalName: layout.declaration.name,
                storageOrdinal: layout.id.ordinal,
                swiftType: swiftType,
                valueShape: .init(variable.initial),
                collectionType: variable.collectionType,
                isSymmetricCollection: swiftFacts.symmetricCollections[layout.id]
                    .map { _ in true } ?? false
            )
        }
        let symmetricCollectionPairs = compilation.layout.variables.compactMap {
            layout -> (VariableID, SymmetricCollection)? in
            guard let fact = swiftFacts.symmetricCollections[layout.id] else {
                return nil
            }
            return (
                layout.id,
                SymmetricCollection(
                    formalName: layout.declaration.name,
                    storageOrdinal: layout.id.ordinal,
                    verificationScope: fact.verificationScope,
                    initial: fact.initial,
                    elementType: fact.elementType,
                    valueType: fact.valueType
                )
            )
        }
        let symmetricCollections = symmetricCollectionPairs.map(\.1)
        let symmetricCollectionsByVariableID = Dictionary(
            uniqueKeysWithValues: symmetricCollectionPairs
        )
        let executableActions = compilation.layout.actions.filter {
            $0.declaration.name != CompilerControlSymbol.terminatingAction.rawValue
        }
        let actionIdentifiers = Self.generatedActionIdentifiers(executableActions.map(\.declaration.name))
        let actions = try zip(executableActions, actionIdentifiers).map { layout, identifier in
            let action = compilation.spec.actions[layout.id.ordinal]
            let bindingTypes = swiftFacts.actionBindingTypes[layout.id] ?? []
            return Action(
                id: layout.id,
                formalName: layout.declaration.name,
                swiftIdentifier: identifier,
                bindings: try action.bindings.enumerated().map { index, binding in
                    Binding(
                        formalName: binding.name,
                        swiftType: try Self.generatedSwiftType(
                            explicit: bindingTypes.indices.contains(index) ? bindingTypes[index] : nil,
                            fallback: binding.values[0],
                            path: "actions.\(action.name).bindings.\(binding.name)"
                        ),
                        domain: binding.values,
                        isPublic: binding.values.count > 1
                    )
                },
                symmetricCollection: swiftFacts.collectionActions[layout.id]
                    .flatMap { symmetricCollectionsByVariableID[$0] }
            )
        }

        self.compilationIdentity = compilation.identity
        self.variables = variables
        self.actions = actions
        self.symmetricCollections = symmetricCollections
    }

    private static func generatedSwiftType(
        explicit: String?,
        fallback: TLAValue,
        path: String
    ) throws -> String {
        if explicit == "TLAValue" {
            throw GeneratedMachineSurfaceDiagnostic(
                code: .unsupportedGeneratedValueShape,
                path: path,
                expected: "a declared Swift value type for the generated API",
                actual: "TLAValue",
                nextSafeAction: "Declare a Swift value type that converts to and from this formal value, then compile again."
            )
        }
        if let explicit {
            return explicit
        }
        switch fallback {
        case .int: return "Int"
        case .bool: return "Bool"
        case .string, .constant: return "String"
        case .set, .tuple, .record, .function:
            throw GeneratedMachineSurfaceDiagnostic(
                code: .unsupportedGeneratedValueShape,
                path: path,
                expected: "a declared Swift value type for the generated API",
                actual: String(describing: fallback),
                nextSafeAction: "Declare a Swift value type that converts to and from this formal value, then compile again."
            )
        }
    }

    private static func generatedActionIdentifiers(_ names: [String]) -> [String] {
        let reserved: Set<String> = ["init", "deinit", "subscript", "rawValue"]
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
}
