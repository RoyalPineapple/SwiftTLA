import Foundation

/// The emitted-machine view of one compiled specification.
package struct MachineSurfacePlan: Sendable, Equatable {
    package struct Variable: Sendable, Equatable {
        package let formalName: String
        package let storageOrdinal: Int
        package let swiftType: String

        package init(
            formalName: String,
            storageOrdinal: Int,
            swiftType: String
        ) {
            self.formalName = formalName
            self.storageOrdinal = storageOrdinal
            self.swiftType = swiftType
        }
    }

    package struct Binding: Sendable, Equatable {
        package let formalName: String
        package let swiftType: String
        package let domain: [TLAValue]
        package var isPublic: Bool { domain.count > 1 }

        package init(formalName: String, swiftType: String, domain: [TLAValue]) {
            self.formalName = formalName
            self.swiftType = swiftType
            self.domain = domain
        }
    }

    package struct Action: Sendable, Equatable {
        package let swiftIdentifier: String
        package let bindings: [Binding]
        package let symmetricCollection: SymmetricCollection?

        package init(
            swiftIdentifier: String,
            bindings: [Binding],
            symmetricCollection: SymmetricCollection?
        ) {
            self.swiftIdentifier = swiftIdentifier
            self.bindings = bindings
            self.symmetricCollection = symmetricCollection
        }
    }

    package struct SymmetricCollection: Sendable, Equatable {
        package let formalName: String
        package let storageOrdinal: Int
        package let members: [TLAValue]
        package let elementType: String
        package let valueType: String

        package init(
            formalName: String,
            storageOrdinal: Int,
            members: [TLAValue],
            elementType: String,
            valueType: String
        ) {
            self.formalName = formalName
            self.storageOrdinal = storageOrdinal
            self.members = members
            self.elementType = elementType
            self.valueType = valueType
        }
    }

    package let variables: [Variable]
    package let actions: [Action]
    package let symmetricCollections: [SymmetricCollection]

    init(layout: CompiledLayout, semantics: CompiledSemantics) throws {
        let symmetricCollectionsByVariableID: [VariableID: SymmetricCollection] = try Dictionary(
            uniqueKeysWithValues: layout.variables.compactMap { variable in
                guard let declaration = variable.symmetricCollection else { return nil }
                guard let elementType = declaration.elementType,
                      let valueType = declaration.valueType
                else {
                    throw CompilationDiagnostic(
                        code: .unsupportedGeneratedValueShape,
                        stage: .validation,
                        path: "variables.\(variable.declaration.name)",
                        expected: "declared Swift element and value types for the generated API",
                        actual: "no Swift surface types",
                        nextSafeAction: "Declare the collection through typed Swift source, then compile again."
                    )
                }
                return (
                    variable.id,
                    SymmetricCollection(
                        formalName: variable.declaration.name,
                        storageOrdinal: variable.id.ordinal,
                        members: declaration.members,
                        elementType: elementType,
                        valueType: valueType
                    )
                )
            }
        )
        let initializations = Dictionary(
            uniqueKeysWithValues: semantics.variableInitializations.map {
                ($0.variable, $0.initialization)
            }
        )

        let variables = try layout.variables.filter {
            $0.declaration.origin == .source
        }.map { variable in
            let collection = symmetricCollectionsByVariableID[variable.id]
            let fallback: TLAValue?
            if case .value(let value) = initializations[variable.id] {
                fallback = try value.rendered(using: layout)
            } else {
                fallback = nil
            }
            let swiftType = if let collection {
                "[\(collection.elementType).ID: \(collection.valueType)]"
            } else {
                try Self.generatedSwiftType(
                    explicit: variable.generatedSwiftType,
                    fallback: fallback,
                    path: "variables.\(variable.declaration.name)"
                )
            }
            return Variable(
                formalName: variable.declaration.name,
                storageOrdinal: variable.id.ordinal,
                swiftType: swiftType
            )
        }
        let symmetricCollections = layout.variables.compactMap {
            symmetricCollectionsByVariableID[$0.id]
        }
        let executableActions = layout.actions.filter {
            $0.declaration.name != CompilerControlSymbol.terminatingAction.rawValue
        }
        let actionIdentifiers = Self.generatedActionIdentifiers(executableActions.map(\.declaration.name))
        let compiledActions = Dictionary(uniqueKeysWithValues: semantics.actions.map { ($0.id, $0) })
        let actions = try zip(executableActions, actionIdentifiers).map { layoutAction, identifier in
            guard let action = compiledActions[layoutAction.id] else {
                throw Self.missingDeclaration("action", named: layoutAction.declaration.name)
            }
            let collection = action.symmetricCollection.flatMap {
                symmetricCollectionsByVariableID[$0]
            }
            if action.symmetricCollection != nil, collection == nil {
                throw Self.missingDeclaration(
                    "symmetric collection",
                    named: layoutAction.declaration.name
                )
            }
            if let collection {
                guard action.bindings.count == 1,
                      action.bindings[0].values == collection.members else {
                    throw CompilationDiagnostic(
                        code: .compilationIdentityMismatch,
                        stage: .lowering,
                        path: "machineSurfacePlan.actions.\(layoutAction.declaration.name)",
                        expected: "one compiled member binding for symmetric collection '\(collection.formalName)'",
                        actual: "\(action.bindings.count) binding(s) with domains \(action.bindings.map(\.values))",
                        nextSafeAction: "Compile the collection action from its declared symmetric collection."
                    )
                }
            }
            return Action(
                swiftIdentifier: identifier,
                bindings: try action.bindings.map { binding in
                    Binding(
                        formalName: collection == nil ? binding.sourceName : "member",
                        swiftType: try Self.generatedSwiftType(
                            explicit: binding.generatedSwiftType,
                            fallback: binding.values[0],
                            path: "actions.\(layoutAction.declaration.name).bindings.\(binding.sourceName)"
                        ),
                        domain: binding.values
                    )
                },
                symmetricCollection: collection
            )
        }

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
        fallback: TLAValue?,
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
        case .int?: return "Int"
        case .bool?: return "Bool"
        case .string?, .constant?: return "String"
        case .set?, .tuple?, .record?, .function?, nil:
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
