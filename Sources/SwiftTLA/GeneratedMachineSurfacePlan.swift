import Foundation

/// Swift field and collection facts for generated machine code.
package struct MachineSurfaceSwiftFacts: Sendable, Equatable {
    package struct SymmetricCollection: Sendable, Equatable {
        package let elementType: String
        package let valueType: String

        package init(elementType: String, valueType: String) {
            self.elementType = elementType
            self.valueType = valueType
        }
    }

    package let variableTypes: [String: String]
    package let actionBindingTypes: [String: [String: String]]
    package let symmetricCollections: [String: SymmetricCollection]
    package let collectionActions: [String: String]

    package init(
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

/// Reports an invalid generated machine surface.
package struct GeneratedMachineSurfaceDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    package enum Code: String, Sendable, Equatable {
        case unknownSwiftFact
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

        package init(
            formalName: String,
            storageOrdinal: Int,
            swiftType: String,
            valueShape: FormalValueShape,
            collectionType: CollectionVarType
        ) {
            self.formalName = formalName
            self.storageOrdinal = storageOrdinal
            self.swiftType = swiftType
            self.valueShape = valueShape
            self.collectionType = collectionType
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
        package let formalName: String
        package let swiftIdentifier: String
        package let bindings: [Binding]

        package init(formalName: String, swiftIdentifier: String, bindings: [Binding]) {
            self.formalName = formalName
            self.swiftIdentifier = swiftIdentifier
            self.bindings = bindings
        }
    }

    package struct SymmetricCollection: Sendable, Equatable {
        package let formalName: String
        package let verificationScope: Int
        package let initial: TLAValue
        package let elementType: String
        package let valueType: String

        package init(
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

    package let compilationIdentity: CompilationIdentity
    package let variables: [Variable]
    package let actions: [Action]
    package let symmetricCollections: [SymmetricCollection]
    package let collectionActions: [String: String]

    package init(
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
        let variables = try compilation.layout.variables.filter {
            $0.declaration.origin == .source
        }.map { layout in
            guard let variable = variablesByName[layout.declaration.name] else {
                throw Self.unknownFact("compiledLayout.variables.\(layout.declaration.name)")
            }
            let swiftType: String
            if let collection = swiftFacts.symmetricCollections[layout.declaration.name] {
                swiftType = "IdentifiedModelCollection<\(collection.elementType), \(collection.valueType)>"
            } else {
                swiftType = try Self.generatedSwiftType(
                    explicit: swiftFacts.variableTypes[layout.declaration.name],
                    fallback: variable.initial,
                    path: "variables.\(layout.declaration.name)"
                )
            }
            return Variable(
                formalName: layout.declaration.name,
                storageOrdinal: layout.id.ordinal,
                swiftType: swiftType,
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
                bindings: try action.bindings.map { binding in
                    Binding(
                        formalName: binding.name,
                        swiftType: try Self.generatedSwiftType(
                            explicit: swiftFacts.actionBindingTypes[action.name]?[binding.name],
                            fallback: binding.values[0],
                            path: "actions.\(action.name).bindings.\(binding.name)"
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
    }

    private static func unknownFact(_ path: String) -> GeneratedMachineSurfaceDiagnostic {
        .init(
            code: .unknownSwiftFact,
            path: path,
            expected: "a declaration in the compiled specification",
            actual: "no matching declaration",
            nextSafeAction: "Correct the source-only fact key, then compile the model again."
        )
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
