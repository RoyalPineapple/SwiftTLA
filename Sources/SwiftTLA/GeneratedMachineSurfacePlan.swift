import Foundation
import SwiftParser
import SwiftSyntax

/// The emitted-machine view of one compiled specification.
package struct MachineSurfacePlan: Sendable, Equatable {
    package struct Variable: Sendable, Equatable {
        package let formalName: String
        package let swiftIdentifier: String
        package let storageOrdinal: Int
        package let swiftType: String
        package let collection: SymmetricCollection?

        init(
            formalName: String,
            storageOrdinal: Int,
            swiftType: String,
            collection: SymmetricCollection?
        ) throws {
            self.formalName = formalName
            self.swiftIdentifier = try MachineSurfacePlan.sourceIdentifier(formalName)
            self.storageOrdinal = storageOrdinal
            self.swiftType = swiftType
            self.collection = collection
        }
    }

    package struct Binding: Sendable, Equatable {
        package let formalName: String
        package let swiftIdentifier: String
        package let swiftType: String
        package let domain: [TLAValue]
        package var isPublic: Bool { domain.count > 1 }

        init(formalName: String, swiftType: String, domain: [TLAValue]) throws {
            self.formalName = formalName
            self.swiftIdentifier = try MachineSurfacePlan.sourceIdentifier(formalName)
            self.swiftType = swiftType
            self.domain = domain
        }
    }

    package struct Action: Sendable, Equatable {
        package let compiledAction: ActionID
        package let swiftIdentifier: String
        package let bindings: [Binding]
        package let collection: SymmetricCollection?

        init(
            compiledAction: ActionID,
            swiftIdentifier: String,
            bindings: [Binding],
            collection: SymmetricCollection?
        ) {
            self.compiledAction = compiledAction
            self.swiftIdentifier = swiftIdentifier
            self.bindings = bindings
            self.collection = collection
        }
    }

    package struct SymmetricCollection: Sendable, Equatable {
        package let formalName: String
        package let swiftIdentifier: String
        package let members: [TLAValue]
        package let elementType: String
        package let valueType: String

        init(
            formalName: String,
            members: [TLAValue],
            elementType: String,
            valueType: String
        ) throws {
            self.formalName = formalName
            self.swiftIdentifier = try MachineSurfacePlan.sourceIdentifier(formalName)
            self.members = members
            self.elementType = elementType
            self.valueType = valueType
        }
    }

    package let variables: [Variable]
    package let actions: [Action]
    package var symmetricCollections: [SymmetricCollection] {
        variables.compactMap(\.collection)
    }

    init(layout: CompiledLayout, semantics: CompiledSemantics) throws {
        let symmetricCollectionsByVariableID: [VariableID: SymmetricCollection] = try Dictionary(
            uniqueKeysWithValues: layout.variables.compactMap { variable in
                guard let declaration = variable.collection else { return nil }
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
                    try SymmetricCollection(
                        formalName: variable.declaration.name,
                        members: try declaration.members.map { try $0.rendered(using: layout) },
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
            return try Variable(
                formalName: variable.declaration.name,
                storageOrdinal: variable.id.ordinal,
                swiftType: swiftType,
                collection: collection
            )
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
            let collection = action.collection.flatMap {
                symmetricCollectionsByVariableID[$0]
            }
            if action.collection != nil, collection == nil {
                throw Self.missingDeclaration(
                    "symmetric collection",
                    named: layoutAction.declaration.name
                )
            }
            if let collection {
                guard let collectionVariable = action.collection,
                      layout.variables.indices.contains(collectionVariable.ordinal),
                      let compiledMembers = layout.variables[collectionVariable.ordinal]
                        .collection?.members else {
                    throw Self.missingDeclaration(
                        "symmetric collection layout",
                        named: layoutAction.declaration.name
                    )
                }
                guard action.bindings.count == 1,
                      action.bindings[0].values == compiledMembers else {
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
                compiledAction: layoutAction.id,
                swiftIdentifier: identifier,
                bindings: try action.bindings.map { binding in
                    try Binding(
                        formalName: collection == nil ? binding.sourceName : "member",
                        swiftType: try Self.generatedSwiftType(
                            explicit: binding.generatedSwiftType,
                            fallback: try binding.values[0].rendered(using: layout),
                            path: "actions.\(layoutAction.declaration.name).bindings.\(binding.sourceName)"
                        ),
                        domain: try binding.values.map { try $0.rendered(using: layout) }
                    )
                },
                collection: collection
            )
        }

        self.variables = variables
        self.actions = actions
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

    private static func sourceIdentifier(_ name: String) throws -> String {
        let tokens = Parser.parse(source: name).tokens(viewMode: .sourceAccurate).filter {
            $0.tokenKind != .endOfFile
        }
        guard tokens.count == 1, let token = tokens.first, token.text == name, name != "_" else {
            throw invalidSourceIdentifier(name)
        }
        switch token.tokenKind {
        case .identifier: return name
        case .keyword: return "`\(name)`"
        default: throw invalidSourceIdentifier(name)
        }
    }

    private static func invalidSourceIdentifier(_ name: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape,
            stage: .validation,
            path: "machineSurfacePlan.identifiers.\(name)",
            expected: "one named Swift identifier for a generated state field or action parameter",
            actual: name,
            nextSafeAction: "Choose a named Swift identifier; formal action labels may use arbitrary names."
        )
    }

    private static func generatedActionIdentifiers(_ names: [String]) -> [String] {
        let reserved: Set<String> = ["_", "init", "deinit", "subscript", "rawValue"]
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
            if let token = Parser.parse(source: identifier).firstToken(viewMode: .sourceAccurate),
               case .keyword = token.tokenKind {
                return "`\(identifier)`"
            }
            return identifier
        }
    }
}
