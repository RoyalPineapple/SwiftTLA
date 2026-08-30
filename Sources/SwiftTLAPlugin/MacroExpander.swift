import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

enum MacroExpander {
    // MARK: - State machine code generation (model / actor)

    static func generateStateMachineMembers(model: MacroCompilation) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []
        let plan = model.compilation.machineSurfacePlan
        let collectionParameters = plan.symmetricCollections.map {
            "\($0.formalName): [\($0.elementType).ID]"
        }
        let appendedCollectionParameters = collectionParameters.isEmpty
            ? ""
            : ", \(collectionParameters.joined(separator: ", "))"
        let collectionArguments = plan.symmetricCollections.map {
            ", \($0.formalName): \($0.formalName)"
        }.joined()
        let stateDecoder = "{ values in try State(values: &values\(collectionArguments)) }"
        let actionDecoders = generateActionDecoders(actions: plan.actions)
        let actionValidator = generateActionValidator(actions: plan.actions)

        decls.append(DeclSyntax(stringLiteral: "private var _storage: _GeneratedMachineStorage<State, Action>"))
        decls.append(DeclSyntax(stringLiteral: """
        private init(storage: _GeneratedMachineStorage<State, Action>) {
            _storage = storage
        }
        """))

        decls.append(contentsOf: generateAction(actions: plan.actions))
        decls.append(DeclSyntax(generateStateStruct(
            variables: plan.variables,
            enumInfos: model.enumInfos
        )))
        decls.append(contentsOf: generateGeneratedMachineStorageMembers(
            actions: plan.actions
        ))
        decls.append(contentsOf: generateActorMembers(model: model))
        decls.append(contentsOf: generateCompilationIdentityCheck(model: model))
        decls.append(DeclSyntax(stringLiteral: """
        public static func makeMachine(\(collectionParameters.joined(separator: ", "))) throws -> Self {
            Self(storage: try _GeneratedMachineStorage(
                compilation: try _compiledSpecification(),
                initial: nil,
                stateDecoder: \(stateDecoder),
                actionDecoders: [\(actionDecoders)],
                actionValidator: \(actionValidator)
            ))
        }
        public static func makeMachine(_ initial: State\(appendedCollectionParameters)) throws -> Self {
            Self(storage: try _GeneratedMachineStorage(
                compilation: try _compiledSpecification(),
                initial: initial,
                stateDecoder: \(stateDecoder),
                actionDecoders: [\(actionDecoders)],
                actionValidator: \(actionValidator)
            ))
        }
        """))
        return decls
    }

    static func generateActionDecoders(actions: [MachineSurfacePlan.Action]) -> String {
        actions.map { action in
            if let collection = action.symmetricCollection {
                return """
                { values in
                    let member = try values.decodeMember(
                        applicationMembers: \(collection.formalName)
                    )
                    return .\(action.swiftIdentifier)(member: member)
                }
                """
            }
            let decoding = action.bindings.compactMap { binding in
                binding.isPublic
                    ? "let \(binding.formalName) = try values.decode(as: \(binding.swiftType).self)"
                    : nil
            }.joined(separator: "\n                    ")
            let publicBindings = action.bindings.filter(\.isPublic)
            let arguments = publicBindings.map {
                "\($0.formalName): \($0.formalName)"
            }.joined(separator: ", ")
            return """
            { values in
                \(decoding)
                return .\(action.swiftIdentifier)\(arguments.isEmpty ? "" : "(\(arguments))")
            }
            """
        }.joined(separator: ",\n                ")
    }

    static func generateActionValidator(actions: [MachineSurfacePlan.Action]) -> String {
        let cases = actions.map { action in
            if let collection = action.symmetricCollection {
                return """
                case .\(action.swiftIdentifier)(member: let member):
                    guard \(collection.formalName).contains(member) else {
                        throw GeneratedMachineStateDiagnostic.typeMismatch(
                            path: "\(collection.formalName).member",
                            expected: "an application ID bound when the machine was created",
                            actual: String(describing: member)
                        )
                    }
                """
            }
            return "case .\(action.swiftIdentifier): break"
        }.joined(separator: "\n                ")
        guard cases.isEmpty == false else { return "{ _ in }" }
        return """
        { action in
            switch action {
            \(cases)
            }
        }
        """
    }

    static func generateCompilationIdentityCheck(model: MacroCompilation) -> [DeclSyntax] {
        let expectedIdentity = model.compilation.identity.value
        let compilationSource = """
        private static let _expectedCompilationIdentity = \"\(expectedIdentity)\"
        private static func _compiledSpecification() throws -> CompiledSpecification {
            let compilation = try Self.spec.compile()
            guard compilation.identity.value == _expectedCompilationIdentity else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .lowering,
                    path: \"spec\",
                    expected: _expectedCompilationIdentity,
                    actual: compilation.identity.value,
                    nextSafeAction: \"Update the authored #spec declaration so every consumer compiles the same source model.\"
                )
            }
            return compilation
        }
        """
        return [DeclSyntax(stringLiteral: compilationSource)]
    }

    static func generateAction(actions: [MachineSurfacePlan.Action]) -> [DeclSyntax] {
        guard actions.isEmpty == false else {
            return [
                DeclSyntax(stringLiteral: "public enum Action: Hashable, Sendable {}")
            ]
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

        return [
            DeclSyntax(stringLiteral: """
        public enum Action: Hashable, Sendable {
            \(cases)
        }
        """)
        ]
    }

}

extension MacroExpander {
    static func generateStateStruct(
        variables: [MachineSurfacePlan.Variable],
        enumInfos: [ParsedEnum]
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
                                type: TypeSyntax(stringLiteral: v.swiftType)
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
                                    type: TypeSyntax(stringLiteral: v.swiftType)
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
                                firstName: "values",
                                type: TypeSyntax(stringLiteral: "inout _GeneratedMachineStorage<State, Action>.Decoder")
                            )
                            for collection in variables.compactMap(\.symmetricCollection) {
                                FunctionParameterSyntax(
                                    firstName: .identifier(collection.formalName),
                                    type: TypeSyntax(stringLiteral: "[\(collection.elementType).ID]")
                                )
                            }
                        },
                        effectSpecifiers: FunctionEffectSpecifiersSyntax(
                            throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
                        )
                    ),
                    body: CodeBlockSyntax {
                        ExprSyntax(stringLiteral: stateDecodingStatements(
                            variables: variables,
                            enumInfos: enumInfos
                        ))
                    }
                )
            }
        )
    }

    static func stateDecodingStatements(
        variables: [MachineSurfacePlan.Variable],
        enumInfos: [ParsedEnum]
    ) -> String {
        variables.map { variable in
            let key = String(reflecting: variable.formalName)
            let typeName = variable.swiftType
            if let collection = variable.symmetricCollection {
                return """
                self.\(collection.formalName) = try values.decodeCollection(
                    applicationMembers: \(collection.formalName),
                    as: \(collection.valueType).self
                )
                """
            }
            if let info = enumInfos.first(where: { $0.typeName == typeName }) {
                let cases = info.cases.map { "case \"\($0.name)\": self.\(variable.formalName) = \(typeName).\($0.name)" }
                    .joined(separator: "\n")
                return """
                do {
                let value = try values.decode(as: String.self)
                switch value {
                \(cases)
                default:
                    throw GeneratedMachineStateDiagnostic.typeMismatch(path: \(key), expected: "a declared \(typeName) case", actual: value)
                }
                }
                """
            }
            let type = typeName
            if ["Int", "Bool", "String"].contains(typeName) == false {
                return """
                self.\(variable.formalName) = try values.decode(as: \(typeName).self)
                """
            }
            return """
            self.\(variable.formalName) = try values.decode(as: \(type).self)
            """
        }.joined(separator: "\n")
    }

}
