import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

enum MacroExpander {
    static func literalExpr(for value: TLAValue) -> String {
        switch value {
        case .int(let value): "\(value)"
        case .bool(let value): "\(value)"
        case .string(let value): "\"\(value)\""
        case .set, .tuple, .record, .function, .constant: codegenTLAValue(value)
        }
    }

    static func publicBindings(for action: NamedAction) -> [ActionBinding] {
        action.bindings.filter { $0.values.count > 1 }
    }

    static func generate(model: MacroCompilation) -> [DeclSyntax] {
        generateStateMachineMembers(model: model)
    }

    // MARK: - State machine code generation (model / actor)

    static func generateStateMachineMembers(model: MacroCompilation) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []
        let plan = model.machineSurface
        let collectionParameters = plan.symmetricCollections.map {
            "\($0.formalName): IdentifiedModelCollection<\($0.elementType), \($0.valueType)>"
        }
        let machineInitializerParameters = ([
            "storage: _GeneratedMachineStorage",
            "storageState: _GeneratedMachineStorage.State"
        ] + collectionParameters)
            .joined(separator: ", ")
        let collectionAssignments = plan.symmetricCollections.map {
            "self.\($0.formalName) = \($0.formalName)"
        }
        let machineInitializerAssignments = ([
            "_storage = storage",
            "_storageState = storageState",
            "_state = try State(storage: storage, storageState: storageState)"
        ] + collectionAssignments)
            .joined(separator: "\n            ")
        let collectionInitializers = plan.symmetricCollections.map { collection in
            """
            ,
                \(collection.formalName): try IdentifiedModelCollection<\(collection.elementType), \(collection.valueType)>(
                    name: \"\(collection.formalName)\",
                    verificationScope: \(collection.verificationScope),
                    initial: \(literalExpr(for: collection.initial))
                )
            """
        }.joined()

        decls.append(DeclSyntax(stringLiteral: "private let _storage: _GeneratedMachineStorage"))
        decls.append(DeclSyntax(stringLiteral: "private var _storageState: _GeneratedMachineStorage.State"))
        decls.append(DeclSyntax(stringLiteral: "private var _state: State"))
        decls.append(DeclSyntax(stringLiteral: """
        private init(\(machineInitializerParameters)) throws {
            \(machineInitializerAssignments)
        }
        """))

        let ordinaryVariables = plan.variables.filter { $0.isSymmetricCollection == false }

        decls.append(contentsOf: generateAction(actions: plan.actions))
        decls.append(DeclSyntax(generateStateStruct(variables: ordinaryVariables, enumInfos: model.enumInfos)))
        decls.append(contentsOf: generateGeneratedMachineStorageMembers(
            hasActions: !plan.actions.isEmpty,
            actions: plan.actions,
            variables: plan.variables,
            symmetricCollections: plan.symmetricCollections
        ))
        decls.append(contentsOf: generateActorMembers(model: model))
        decls.append(contentsOf: generateCollectionRuntimeMembers(plan.symmetricCollections))
        decls.append(contentsOf: generateVariableProperties(
            variables: ordinaryVariables,
            enumInfos: model.enumInfos
        ).map(DeclSyntax.init))
        decls.append(contentsOf: generateCompilationIdentityCheck(model: model))
        decls.append(DeclSyntax(stringLiteral: """
        private static func _makeMachine(
            storage: _GeneratedMachineStorage,
            storageState: _GeneratedMachineStorage.State
        ) throws -> Self {
            try Self(storage: storage, storageState: storageState\(collectionInitializers))
        }
        public static func makeMachine() throws -> Self {
            let storage = _GeneratedMachineStorage(compilation: try _compiledSpecification())
            let initialStates = try storage.initialStates()
            guard initialStates.count == 1 else {
                if initialStates.isEmpty {
                    throw GeneratedMachineError.noInitialState
                }
                throw GeneratedMachineError.ambiguousInitialState
            }
            return try _makeMachine(
                storage: storage,
                storageState: initialStates[0]
            )
        }
        public static func makeMachine(_ initial: State) throws -> Self {
            let storage = _GeneratedMachineStorage(compilation: try _compiledSpecification())
            return try _makeMachine(
                storage: storage,
                storageState: try storage.initialState { candidate in
                    try State(storage: storage, storageState: candidate) == initial
                }
            )
        }
        """))
        return decls
    }

    static func generateCompilationIdentityCheck(model: MacroCompilation) -> [DeclSyntax] {
        let expectedIdentity = model.compilation.identity.value
        let compilationSource = """
        static let _expectedCompilationIdentity = \"\(expectedIdentity)\"
        private static func _compiledSpecification() throws -> CompiledSpecification {
            let compilation = try Self.spec.compile()
            guard compilation.identity.value == _expectedCompilationIdentity else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .lowering,
                    path: \"spec\",
                    expected: _expectedCompilationIdentity,
                    actual: compilation.identity.value,
                    nextSafeAction: \"Update the authored #spec declaration so every consumer compiles the same formal model.\"
                )
            }
            return compilation
        }
        """
        return [DeclSyntax(stringLiteral: compilationSource)]
    }

    static func codegenTLAValue(_ value: TLAValue) -> String {
        switch value {
        case .int(let n): return "TLAValue.int(\(n))"
        case .bool(let b): return "TLAValue.bool(\(b))"
        case .string(let s): return "TLAValue.string(\"\(s)\")"
        case .set(let s): return "TLAValue.set([\(s.map(codegenTLAValue).joined(separator: ", "))])"
        case .tuple(let t): return "TLAValue.tuple([\(t.map(codegenTLAValue).joined(separator: ", "))])"
        case .record(let r):
            let fields = r.fields.map { "\"\($0.name)\": \(codegenTLAValue($0.value))" }.joined(separator: ", ")
            return fields.isEmpty ? "TLAValue.record([:])" : "TLAValue.record([\(fields)])"
        case .function(let f):
            let entries = f.map { "\(codegenTLAValue($0.key)): \(codegenTLAValue($0.value))" }.joined(separator: ", ")
            return entries.isEmpty ? "TLAValue.function([:])" : "TLAValue.function([\(entries)])"
        case .constant(let c): return "TLAValue.constant(\"\(c)\")"
        }
    }

    static func generateAction(actions: [MachineSurfacePlan.Action]) -> [DeclSyntax] {
        guard actions.isEmpty == false else {
            return [
                DeclSyntax(stringLiteral: "public enum Action: Hashable, Sendable {}")
            ]
        }
        func argumentConstructor(for binding: MachineSurfacePlan.Binding) -> String {
            "\(binding.formalName).tlaValue"
        }

        func fixedArgument(_ binding: MachineSurfacePlan.Binding) -> String {
            codegenTLAValue(binding.domain[0])
        }

        func actionArgumentBinding(
            for binding: MachineSurfacePlan.Binding,
            index: Int,
            in arguments: String
        ) -> String {
            switch binding.swiftType {
            case "Int": return "let \(binding.formalName) = try? \(arguments).value(at: \(index), as: Int.self)"
            case "Bool": return "let \(binding.formalName) = try? \(arguments).value(at: \(index), as: Bool.self)"
            case "String": return "let \(binding.formalName) = try? \(arguments).value(at: \(index), as: String.self)"
            case "TLAValue": return "let \(binding.formalName) = try? \(arguments).value(at: \(index), as: TLAValue.self)"
            default:
                return "let \(binding.formalName) = try? \(arguments).value(at: \(index), as: \(binding.swiftType).self)"
            }
        }

        let cases = actions.map { action in
            if let collection = action.symmetricCollection {
                return "case \(action.swiftIdentifier)(member: \(collection.elementType).ID)"
            }
            let bindings = action.bindings.filter(\.isPublic)
            guard !bindings.isEmpty else { return "case \(action.swiftIdentifier)" }
            let parameters = bindings.map { "\($0.formalName): \($0.swiftType)" }.joined(separator: ", ")
            return "case \(action.swiftIdentifier)(\(parameters))"
        }.joined(separator: "\n    ")

        let actionOrdinalCases = actions.enumerated().map { ordinal, action in
            let pattern = action.symmetricCollection == nil
                ? ".\(action.swiftIdentifier)"
                : ".\(action.swiftIdentifier)(member: _)"
            return "case \(pattern): return \(ordinal)"
        }.joined(separator: "\n        ")

        let actionArgumentCases = actions.map { action in
            if action.symmetricCollection != nil {
                return "case .\(action.swiftIdentifier)(member: _): return []"
            }
            let publicBindings = action.bindings.filter(\.isPublic)
            let arguments = action.bindings.map { binding in
                binding.isPublic
                    ? argumentConstructor(for: binding)
                    : fixedArgument(binding)
            }.joined(separator: ", ")
            let pattern = publicBindings.isEmpty
                ? ".\(action.swiftIdentifier)"
                : ".\(action.swiftIdentifier)(\(publicBindings.map { "let \($0.formalName)" }.joined(separator: ", ")))"
            return "case \(pattern): return [\(arguments)]"
        }.joined(separator: "\n        ")

        let labelCases = actions.enumerated().compactMap { ordinal, action -> String? in
            guard action.symmetricCollection == nil else { return nil }
            let publicBindings = action.bindings.filter(\.isPublic)
            if action.bindings.isEmpty {
                return "case \(ordinal) where arguments.isEmpty: return .\(action.swiftIdentifier)"
            }
            let patterns = action.bindings.enumerated().map { index, binding -> String in
                if binding.isPublic {
                    return actionArgumentBinding(for: binding, index: index, in: "arguments")
                }
                return "arguments.matches(\(codegenTLAValue(binding.domain[0])), at: \(index))"
            }.joined(separator: ", ")
            let arguments = publicBindings.map { "\($0.formalName): \($0.formalName)" }.joined(separator: ", ")
            return "case \(ordinal) where arguments.count == \(action.bindings.count): "
                + "guard \(patterns) else { return nil }; return .\(action.swiftIdentifier)\(arguments.isEmpty ? "" : "(\(arguments))")"
        }.joined(separator: "\n        ")

        return [
            DeclSyntax(stringLiteral: """
        public enum Action: Hashable, Sendable {
            \(cases)
        }
        """),
            DeclSyntax(stringLiteral: """
        private static func _actionOrdinal(for action: Action) -> Int {
            switch action {
            \(actionOrdinalCases)
            }
        }
        """),
            DeclSyntax(stringLiteral: """
        private static func _actionArguments(for action: Action) -> [any TLAValueConvertible] {
            switch action {
            \(actionArgumentCases)
            }
        }
        """),
            DeclSyntax(stringLiteral: """
        private static func _action(actionAt ordinal: Int, arguments: _GeneratedMachineStorage.ActionArguments) -> Action? {
            switch ordinal {
            \(labelCases)
            default: return nil
            }
        }
        """)
        ]
    }

}

extension MacroExpander {
    static func stateType(
        for variable: MachineSurfacePlan.Variable,
        enumInfos _: [ParsedEnumInfo]
    ) -> String {
        variable.swiftType
    }

    static func generateStateStruct(
        variables: [MachineSurfacePlan.Variable],
        enumInfos: [ParsedEnumInfo] = []
    ) -> StructDeclSyntax {
        StructDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: "State",
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Equatable"))
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Sendable"))
            },
            memberBlock: MemberBlockSyntax {
                for v in variables {
                    VariableDeclSyntax(
                        modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                        bindingSpecifier: .keyword(.let),
                        bindings: [PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(v.formalName)),
                            typeAnnotation: TypeAnnotationSyntax(
                                type: TypeSyntax(stringLiteral: stateType(for: v, enumInfos: enumInfos))
                            )
                        )]
                    )
                }
                InitializerDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax {
                            for v in variables {
                                FunctionParameterSyntax(
                                    firstName: .identifier(v.formalName),
                                    type: TypeSyntax(stringLiteral: stateType(for: v, enumInfos: enumInfos))
                                )
                            }
                        }
                    ),
                    body: CodeBlockSyntax {
                        for v in variables {
                            ExprSyntax(stringLiteral: "self.\(v.formalName) = \(v.formalName)")
                        }
                    }
                )
                InitializerDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.fileprivate))],
                    signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax {
                            FunctionParameterSyntax(
                                firstName: "storage",
                                type: TypeSyntax(stringLiteral: "_GeneratedMachineStorage")
                            )
                            FunctionParameterSyntax(
                                firstName: "storageState",
                                type: TypeSyntax(stringLiteral: "_GeneratedMachineStorage.State")
                            )
                        },
                        effectSpecifiers: FunctionEffectSpecifiersSyntax(
                            throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
                        )
                    ),
                    body: CodeBlockSyntax {
                        ExprSyntax(stringLiteral: stateDecodingStatements(variables: variables, enumInfos: enumInfos))
                    }
                )
            }
        )
    }

    static func generateVariableProperties(
        variables: [MachineSurfacePlan.Variable],
        enumInfos: [ParsedEnumInfo] = []
    ) -> [VariableDeclSyntax] {
        variables.map { v in
            let propType = stateType(for: v, enumInfos: enumInfos)
            return VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(v.formalName)),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: propType)),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "_state.\(v.formalName)") }
                    ))
                )]
            )
        }
    }

    static func stateDecodingStatements(
        variables: [MachineSurfacePlan.Variable],
        enumInfos: [ParsedEnumInfo]
    ) -> String {
        variables.map { variable in
            let key = String(reflecting: variable.formalName)
            let typeName = stateType(for: variable, enumInfos: enumInfos)
            if let info = enumInfos.first(where: { $0.typeName == typeName }) {
                let cases = info.cases.map { "case \"\($0.name)\": self.\(variable.formalName) = \(typeName).\($0.name)" }
                    .joined(separator: "\n")
                return """
                do {
                let value = try storage.value(at: \(variable.storageOrdinal), as: String.self, in: storageState)
                switch value {
                \(cases)
                default:
                    throw GeneratedMachineStateDiagnostic.typeMismatch(path: \(key), expected: "a declared \(typeName) case", actual: value)
                }
                }
                """
            }
            let type = typeName
            if type == "TLAValue" {
                return """
                self.\(variable.formalName) = try storage.value(at: \(variable.storageOrdinal), as: TLAValue.self, in: storageState)
                """
            }
            if !["Int", "Bool", "String", "TLAValue"].contains(typeName) {
                return """
                self.\(variable.formalName) = try storage.value(at: \(variable.storageOrdinal), as: \(typeName).self, in: storageState)
                """
            }
            return """
            self.\(variable.formalName) = try storage.value(at: \(variable.storageOrdinal), as: \(type).self, in: storageState)
            """
        }.joined(separator: "\n")
    }

    static func generateCollectionRuntimeMembers(
        _ collections: [MachineSurfacePlan.SymmetricCollection]
    ) -> [DeclSyntax] {
        var declarations = collections.map { collection -> DeclSyntax in
            DeclSyntax(stringLiteral: """
            public var \(collection.formalName): IdentifiedModelCollection<\(collection.elementType), \(collection.valueType)>
            """)
        }
        guard !collections.isEmpty else { return declarations }
        let scopes = collections.map {
            "SymmetricCollectionScope(collectionName: \"\($0.formalName)\", verificationScope: \($0.verificationScope))"
        }.joined(separator: ", ")
        declarations.append(DeclSyntax(stringLiteral: """
        public static let symmetricCollectionScopes: [SymmetricCollectionScope] = [\(scopes)]
        """))
        return declarations
    }

}
