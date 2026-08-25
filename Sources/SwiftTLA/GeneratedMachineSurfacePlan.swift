import Foundation

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

    init(
        identity: CompilationIdentity,
        spec: TLASpec,
        layout: CompiledLayout
    ) throws {
        let variablesByID = try Dictionary(uniqueKeysWithValues: spec.variables.map { variable in
            guard let id = layout.variableID(named: variable.name) else {
                throw Self.missingDeclaration("variable", named: variable.name)
            }
            return (id, variable)
        })
        let actionsByID = try Dictionary(uniqueKeysWithValues: spec.actions.map { action in
            guard let id = layout.actionID(named: action.name) else {
                throw Self.missingDeclaration("action", named: action.name)
            }
            return (id, action)
        })
        let collectionPairs = try spec.symmetricCollections.map { declaration in
            guard let id = layout.variableID(named: declaration.name) else {
                throw Self.missingDeclaration("symmetric collection", named: declaration.name)
            }
            guard let elementType = declaration.generatedElementType,
                  let valueType = declaration.generatedValueType
            else {
                throw CompilationDiagnostic(
                    code: .unsupportedGeneratedValueShape,
                    stage: .validation,
                    path: "variables.\(declaration.name)",
                    expected: "declared Swift element and value types for the generated API",
                    actual: "no Swift surface types",
                    nextSafeAction: "Declare the collection through typed Swift source, then compile again."
                )
            }
            return (
                id,
                SymmetricCollection(
                    formalName: declaration.name,
                    storageOrdinal: id.ordinal,
                    verificationScope: declaration.verificationScope,
                    initial: declaration.initial,
                    elementType: elementType,
                    valueType: valueType
                )
            )
        }
        let symmetricCollectionsByVariableID = Dictionary(uniqueKeysWithValues: collectionPairs)

        let variables = try layout.variables.filter {
            $0.declaration.origin == .source
        }.map { layout in
            guard let variable = variablesByID[layout.id] else {
                throw Self.missingDeclaration("variable", named: layout.declaration.name)
            }
            let collection = symmetricCollectionsByVariableID[layout.id]
            let swiftType = try Self.generatedSwiftType(
                explicit: variable.generatedSwiftType,
                fallback: variable.initial,
                path: "variables.\(layout.declaration.name)"
            )
            return Variable(
                formalName: layout.declaration.name,
                storageOrdinal: layout.id.ordinal,
                swiftType: swiftType,
                valueShape: .init(variable.initial),
                collectionType: variable.collectionType,
                isSymmetricCollection: collection != nil
            )
        }
        let symmetricCollections = collectionPairs.map(\.1)
        let executableActions = layout.actions.filter {
            $0.declaration.name != CompilerControlSymbol.terminatingAction.rawValue
        }
        let actionIdentifiers = Self.generatedActionIdentifiers(executableActions.map(\.declaration.name))
        let actions = try zip(executableActions, actionIdentifiers).map { actionLayout, identifier in
            guard let action = actionsByID[actionLayout.id] else {
                throw Self.missingDeclaration("action", named: actionLayout.declaration.name)
            }
            return Action(
                id: actionLayout.id,
                formalName: actionLayout.declaration.name,
                swiftIdentifier: identifier,
                bindings: try action.bindings.map { binding in
                    Binding(
                        formalName: binding.name,
                        swiftType: try Self.generatedSwiftType(
                            explicit: action.generatedBindingSwiftTypes[binding.name],
                            fallback: binding.values[0],
                            path: "actions.\(action.name).bindings.\(binding.name)"
                        ),
                        domain: binding.values,
                        isPublic: binding.values.count > 1
                    )
                },
                symmetricCollection: try action.generatedSymmetricCollectionName.map { name in
                    guard let id = layout.variableID(named: name),
                          let collection = symmetricCollectionsByVariableID[id]
                    else {
                        throw Self.missingDeclaration("symmetric collection", named: name)
                    }
                    return collection
                }
            )
        }

        self.compilationIdentity = identity
        self.variables = variables
        self.actions = actions
        self.symmetricCollections = symmetricCollections
    }

    private static func missingDeclaration(_ kind: String, named name: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .compilationIdentityMismatch,
            stage: .lowering,
            path: "machineSurfacePlan.\(kind).\(name)",
            expected: "a declaration in the compiled layout",
            actual: "no matching declaration identity",
            nextSafeAction: "Compile the model again from its current source."
        )
    }

    private static func generatedSwiftType(
        explicit: String?,
        fallback: TLAValue,
        path: String
    ) throws -> String {
        if explicit == "TLAValue" {
            throw CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape,
                stage: .validation,
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
            throw CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape,
                stage: .validation,
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
