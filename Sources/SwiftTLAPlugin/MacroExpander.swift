import SwiftCompilerPlugin
import Foundation
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
        let machineInitializerParameters = ([
            "storage: _GeneratedMachineStorage",
            "storageState: _GeneratedMachineStorage.State"
        ] + collectionParameters)
            .joined(separator: ", ")
        let collectionAssignments = plan.symmetricCollections.map {
            "_\($0.formalName)Members = \($0.formalName)"
        }
        let machineInitializerAssignments = ([
            "_storage = storage",
            "_storageState = storageState"
        ] + collectionAssignments + [
            "_state = try State(storage: storage, storageState: storageState\(collectionArguments))"
        ])
            .joined(separator: "\n            ")

        decls.append(DeclSyntax(stringLiteral: "private let _storage: _GeneratedMachineStorage"))
        decls.append(DeclSyntax(stringLiteral: "private var _storageState: _GeneratedMachineStorage.State"))
        decls.append(DeclSyntax(stringLiteral: "private var _state: State"))
        decls.append(contentsOf: plan.symmetricCollections.map { collection in
            DeclSyntax(stringLiteral: "private let _\(collection.formalName)Members: [\(collection.elementType).ID]")
        })
        decls.append(DeclSyntax(stringLiteral: """
        private init(\(machineInitializerParameters)) throws {
            \(machineInitializerAssignments)
        }
        """))

        decls.append(contentsOf: generateAction(actions: plan.actions))
        decls.append(DeclSyntax(generateStateStruct(
            variables: plan.variables,
            enumInfos: model.enumInfos
        )))
        decls.append(contentsOf: generateGeneratedMachineStorageMembers(
            actions: plan.actions,
            symmetricCollections: plan.symmetricCollections
        ))
        decls.append(contentsOf: generateActorMembers(model: model))
        decls.append(contentsOf: generateCompilationIdentityCheck(model: model))
        decls.append(DeclSyntax(stringLiteral: """
        public static func makeMachine(\(collectionParameters.joined(separator: ", "))) throws -> Self {
            let storage = _GeneratedMachineStorage(compilation: try _compiledSpecification())
            let initialStates = try storage.initialStates()
            guard initialStates.count == 1 else {
                if initialStates.isEmpty {
                    throw GeneratedMachineError.noInitialState
                }
                throw GeneratedMachineError.ambiguousInitialState
            }
            return try Self(
                storage: storage,
                storageState: initialStates[0]\(collectionArguments)
            )
        }
        public static func makeMachine(_ initial: State\(appendedCollectionParameters)) throws -> Self {
            let storage = _GeneratedMachineStorage(compilation: try _compiledSpecification())
            return try Self(
                storage: storage,
                storageState: try storage.initialState { candidate in
                    try State(storage: storage, storageState: candidate\(collectionArguments)) == initial
                }\(collectionArguments)
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
            if let collection = action.symmetricCollection {
                let formalMembers = collection.members.map(codegenTLAValue).joined(separator: ", ")
                return """
                case .\(action.swiftIdentifier)(member: let member):
                    guard let memberOrdinal = _\(collection.formalName)Members.firstIndex(of: member) else {
                        throw GeneratedMachineStateDiagnostic.typeMismatch(
                            path: "\(collection.formalName).member",
                            expected: "an application ID bound when the machine was created",
                            actual: String(describing: member)
                        )
                    }
                    let formalMembers: [TLAValue] = [\(formalMembers)]
                    return [formalMembers[memberOrdinal]]
                """
            }
            let publicBindings = action.bindings.filter(\.isPublic)
            let arguments = action.bindings.map { binding in
                binding.isPublic
                    ? "\(binding.formalName).tlaValue"
                    : codegenTLAValue(binding.domain[0])
            }.joined(separator: ", ")
            let pattern = publicBindings.isEmpty
                ? ".\(action.swiftIdentifier)"
                : ".\(action.swiftIdentifier)(\(publicBindings.map { "let \($0.formalName)" }.joined(separator: ", ")))"
            return "case \(pattern): return [\(arguments)]"
        }.joined(separator: "\n        ")

        let labelCases = actions.enumerated().map { ordinal, action -> String in
            if let collection = action.symmetricCollection {
                let formalMembers = collection.members.map(codegenTLAValue).joined(separator: ", ")
                return """
                case \(ordinal) where arguments.count == 1:
                    let formalMembers: [TLAValue] = [\(formalMembers)]
                    guard let memberOrdinal = formalMembers.firstIndex(where: {
                        arguments.matches($0, at: 0)
                    }), _\(collection.formalName)Members.indices.contains(memberOrdinal) else {
                        throw GeneratedMachineError.invalidGeneratedActionArguments
                    }
                    return .\(action.swiftIdentifier)(member: _\(collection.formalName)Members[memberOrdinal])
                """
            }
            let publicBindings = action.bindings.filter(\.isPublic)
            if action.bindings.isEmpty {
                return "case \(ordinal) where arguments.isEmpty: return .\(action.swiftIdentifier)"
            }
            let bindings = action.bindings.enumerated().compactMap { index, binding in
                binding.isPublic
                    ? "let \(binding.formalName) = try arguments.value(at: \(index), as: \(binding.swiftType).self)"
                    : nil
            }.joined(separator: "\n                    ")
            let fixedArguments = action.bindings.enumerated().compactMap { index, binding in
                binding.isPublic ? nil : "arguments.matches(\(codegenTLAValue(binding.domain[0])), at: \(index))"
            }
            let arguments = publicBindings.map { "\($0.formalName): \($0.formalName)" }.joined(separator: ", ")
            let guardFixedArguments = fixedArguments.isEmpty
                ? ""
                : "guard \(fixedArguments.joined(separator: ", ")) else { throw GeneratedMachineError.invalidGeneratedActionArguments }\n                    "
            return """
                case \(ordinal) where arguments.count == \(action.bindings.count):
                    \(bindings)
                    \(guardFixedArguments)return .\(action.swiftIdentifier)\(arguments.isEmpty ? "" : "(\(arguments))")
                """
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
        private func _actionArguments(for action: Action) throws -> [any TLAValueConvertible] {
            switch action {
            \(actionArgumentCases)
            }
        }
        """),
            DeclSyntax(stringLiteral: """
        private func _action(actionAt ordinal: Int, arguments: _GeneratedMachineStorage.ActionArguments) throws -> Action {
            switch ordinal {
            \(labelCases)
            default: throw GeneratedMachineError.invalidGeneratedActionOrdinal
            }
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
                                firstName: "storage",
                                type: TypeSyntax(stringLiteral: "_GeneratedMachineStorage")
                            )
                            FunctionParameterSyntax(
                                firstName: "storageState",
                                type: TypeSyntax(stringLiteral: "_GeneratedMachineStorage.State")
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
                let formalMembers = collection.members.map(codegenTLAValue).joined(separator: ", ")
                return """
                guard \(collection.formalName).count == \(collection.members.count),
                      Set(\(collection.formalName)).count == \(collection.formalName).count else {
                    throw GeneratedMachineStateDiagnostic.typeMismatch(
                        path: \(key),
                        expected: "\(collection.members.count) unique application IDs",
                        actual: "\\(\(collection.formalName).count) supplied IDs"
                    )
                }
                self.\(collection.formalName) = try Dictionary(uniqueKeysWithValues: zip(
                    \(collection.formalName),
                    [\(formalMembers)]
                ).map { id, formalMember in
                    guard let value: \(collection.valueType) = try storage.collectionValue(
                        at: \(variable.storageOrdinal),
                        for: formalMember,
                        as: \(collection.valueType).self,
                        in: storageState
                    ) else {
                        throw GeneratedMachineStateDiagnostic.missingRequiredValue(
                            path: \(key),
                            expected: "a compiled value for every symmetric member"
                        )
                    }
                    return (id, value)
                })
                """
            }
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

}
