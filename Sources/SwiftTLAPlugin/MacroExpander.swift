import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

enum MacroExpander {
    static func generatedActionIdentifiers(actions: [NamedAction]) -> [String] {
        let reserved: Set<String> = ["init", "deinit", "subscript", "rawValue"]
        var used: Set<String> = []
        return actions.map { action in
            let scalars = action.name.unicodeScalars.map { scalar -> Character in
                switch scalar.value {
                case 65...90, 97...122, 48...57, 95: return Character(String(scalar))
                default: return "_"
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

    static func swiftType(
        for action: NamedAction,
        binding: ActionBinding,
        facts: MachineSurfaceSwiftFacts
    ) -> String {
        facts.actionBindingTypes[action.name]?[binding.name] ?? swiftType(for: binding.values[0])
    }

    /// A finite binding with one possible value is a scheduler detail, not a
    /// useful public argument. Keep it in the formal invocation while hiding
    /// it from the generated Swift surface.
    static func publicBindings(for action: NamedAction) -> [ActionBinding] {
        action.bindings.filter { $0.values.count > 1 }
    }

    static func generate(model: MacroCompilation) -> [DeclSyntax] {
        generateStateMachineMembers(isActor: false, model: model)
    }

    // MARK: - State machine code generation (model / actor)

    static func generateStateMachineMembers(
        isActor: Bool,
        model: MacroCompilation
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []
        let plan = model.machineSurface
        let collectionParameters = plan.symmetricCollections.map {
            "\($0.formalName): IdentifiedModelCollection<\($0.elementType), \($0.valueType)>"
        }
        let machineInitializerParameters = (["machine: CanonicalMachine<State, ActionLabel>"] + collectionParameters)
            .joined(separator: ", ")
        let collectionAssignments = plan.symmetricCollections.map {
            "self.\($0.formalName) = \($0.formalName)"
        }
        let machineInitializerAssignments = (["_machine = machine"] + collectionAssignments)
            .joined(separator: "\n            ")
        let collectionInitializers = plan.symmetricCollections.map { collection in
            """,
                \(collection.formalName): try IdentifiedModelCollection<\(collection.elementType), \(collection.valueType)>(
                    name: \"\(collection.formalName)\",
                    verificationScope: \(collection.verificationScope),
                    initial: \(literalExpr(for: collection.initial))
                )"""
        }.joined()

        decls.append(DeclSyntax(stringLiteral: "private var _machine: CanonicalMachine<State, ActionLabel>"))
        decls.append(DeclSyntax(stringLiteral: """
        private init(\(machineInitializerParameters)) {
            \(machineInitializerAssignments)
        }
        """))

        decls.append(contentsOf: generateActionLabel(actions: plan.actions))
        decls.append(DeclSyntax(generateStateStruct(variables: plan.variables, enumInfos: model.enumInfos)))
        decls.append(DeclSyntax(stringLiteral: generateMachineSchema(model: model)))
        decls.append(contentsOf: generateCanonicalMachineMembers(
            isActor: isActor,
            hasActions: !plan.actions.isEmpty,
            actions: plan.actions,
            symmetricCollections: plan.symmetricCollections,
            identityRoutedActions: Set(plan.collectionActions.keys)
        ))
        if model.hasNestedLiveAdapter {
            decls.append(contentsOf: generateLiveMachineMembers(model: model))
        }
        decls.append(contentsOf: generateCollectionRuntimeMembers(plan.symmetricCollections))
        let symmetricCollectionNames = Set(plan.symmetricCollections.map(\.formalName))
        let ordinaryVariables = plan.variables.filter { !symmetricCollectionNames.contains($0.formalName) }
        decls.append(contentsOf: generateVariableProperties(
            variables: ordinaryVariables,
            enumInfos: model.enumInfos
        ).map(DeclSyntax.init))
        decls.append(contentsOf: generateActionMethods(
            isActor: isActor,
            actions: plan.actions,
            collectionActions: plan.collectionActions,
            symmetricCollections: Dictionary(uniqueKeysWithValues: plan.symmetricCollections.map { ($0.formalName, $0) })
        ))
        decls.append(contentsOf: generateCompilationIdentityCheck(model: model))
        decls.append(DeclSyntax(stringLiteral: """
        private static func _matchingInitialState(
            for initial: State,
            compilation: CompiledSpecification
        ) throws -> TLAStateProjection {
            let requested = try initial.formalProjection()
            let candidates = try compilation.initialStateProjections()
            let matches = candidates.filter { candidate in
                requested.entries.allSatisfy { entry in
                    candidate.value(for: entry.token) == entry.value
                }
            }
            guard matches.count == 1 else {
                if matches.isEmpty {
                    throw GeneratedMachineError.invalidInitialState
                }
                throw GeneratedMachineError.ambiguousInitialState
            }
            return matches[0]
        }
        private static func _makeMachine(
            compilation: CompiledSpecification,
            formalState: TLAStateProjection
        ) throws -> Self {
            let initial = try State(projection: formalState)
            return Self(machine: CanonicalMachine(
                compilation: compilation,
                initial: initial,
                formalState: formalState,
                snapshotFromProjection: { try State(projection: $0) },
                actionRequest: {
                    try compilation.actionRequest(
                        ordinal: Self._actionOrdinal(for: $0),
                        formalArguments: Self._formalArguments(for: $0)
                    )
                },
                labelFromRequest: { request in
                    let input = try compilation.generatedActionLabelInput(for: request)
                    return Self._actionLabel(
                        actionAt: input.ordinal,
                        arguments: input.formalArguments
                    )
                }
            )\(collectionInitializers))
        }
        public static func makeMachine() throws -> Self {
            let compilation = try compiledSpecification()
            let initialStates = try compilation.initialStateProjections()
            guard initialStates.count == 1 else {
                if initialStates.isEmpty {
                    throw GeneratedMachineError.noInitialState
                }
                throw GeneratedMachineError.ambiguousInitialState
            }
            return try _makeMachine(
                compilation: compilation,
                formalState: initialStates[0]
            )
        }
        public static func makeMachine(_ initial: State) throws -> Self {
            let compilation = try compiledSpecification()
            return try _makeMachine(
                compilation: compilation,
                formalState: try _matchingInitialState(for: initial, compilation: compilation)
            )
        }
        """))
        decls.append(contentsOf: generateSpecTest())
        decls.append(contentsOf: generateTransitionsTest(hasActions: !plan.actions.isEmpty))
        if model.hasInvariants && !plan.actions.isEmpty {
            decls.append(contentsOf: generateInvariantsTest())
        }

        return decls
    }

    static func generateCompilationIdentityCheck(model: MacroCompilation) -> [DeclSyntax] {
        let expectedIdentity = model.compilation.identity.value
        let facts = machineSurfaceSwiftFactsSource(model.swiftFacts)
        let metadata = generatedMachineMetadataSource(model.machineSurface)
        let behaviorSource: String
        if model.machineSurface.actions.isEmpty {
            behaviorSource = """
            private static let _generatedMachineBehavior = GeneratedMachineBehavior(
                initialStates: {
                    try Self.compiledSpecification().initialStateProjections().map { projection in
                        _ = try State(projection: projection)
                        return projection
                    }
                },
                actions: []
            )
            """
        } else {
            let actionEntries = generatedBehaviorActionEntries(model.machineSurface.actions)
            behaviorSource = """
            private static let _generatedMachineBehavior = GeneratedMachineBehavior(
                initialStates: {
                    try Self.compiledSpecification().initialStateProjections().map { projection in
                        _ = try State(projection: projection)
                        return projection
                    }
                },
                actions: [
                    \(actionEntries)
                ]
            )
            private static func _generatedSuccessors(
                for action: ActionLabel,
                from projection: TLAStateProjection
            ) throws -> [TLAStateProjection] {
                _ = try State(projection: projection)
                let machine = try Self.makeMachine()
                return try machine._machine.successors(for: action, from: projection).map { target in
                    _ = try State(projection: target)
                    return target
                }
            }
            """
        }
        let compilationSource = """
        static let _expectedCompilationIdentity = \"\(expectedIdentity)\"
        public static let generatedMachineMetadata: GeneratedMachineMetadata = \(metadata)
        private static func _machineSurfacePlan(
            _ compilation: CompiledSpecification
        ) throws -> MachineSurfacePlan {
            let plan = try MachineSurfacePlan(compilation: compilation, swiftFacts: \(facts))
            guard plan.metadata == generatedMachineMetadata else {
                throw GeneratedMachineContractDiagnostic(
                    code: .metadataDomainMismatch,
                    path: "generatedMachineMetadata",
                    expected: "metadata derived from the compiled specification",
                    actual: "a differing generated-machine metadata surface",
                    nextSafeAction: "Compile the model from its current source."
                )
            }
            return plan
        }
        \(behaviorSource)
        public static func compiledSpecification() throws -> CompiledSpecification {
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
            _ = try _machineSurfacePlan(compilation)
            return compilation
        }
        public static func verifyGeneratedMachineContract(
            metadata: GeneratedMachineMetadata? = nil,
            configuration: FiniteExplorationConfiguration
        ) -> GeneratedMachineContractReport {
            do {
                let compilation = try compiledSpecification()
                return GeneratedMachineContractVerifier.verify(
                    compilation: compilation,
                    plan: try _machineSurfacePlan(compilation),
                    metadata: metadata ?? generatedMachineMetadata,
                    maximumStateLimit: configuration.maximumStateLimit,
                    decodeState: { projection in
                        _ = try State(projection: projection)
                    },
                    behavior: _generatedMachineBehavior
                )
            } catch let diagnostic as GeneratedMachineContractDiagnostic {
                return .init(status: .difference, initialStateCount: 0, transitionCount: 0, diagnostic: diagnostic)
            } catch {
                return .init(
                    status: .unavailable,
                    initialStateCount: 0,
                    transitionCount: 0,
                    diagnostic: .init(
                        code: .evaluationUnavailable,
                        path: \"compiledSpecification\",
                        expected: \"a compiled specification\",
                        actual: String(describing: error),
                        nextSafeAction: \"Correct the compilation failure, then rerun generated contract verification.\"
                    )
                )
            }
        }
        private static func _verifiedGeneratedMachineContract(
            configuration: FiniteExplorationConfiguration
        ) throws -> GeneratedMachineContractReport {
            let report = verifyGeneratedMachineContract(configuration: configuration)
            guard report.status == .exact else {
                throw VerificationError(report.diagnostic?.description ?? "Generated-machine verification did not complete.")
            }
            return report
        }
        """
        return [DeclSyntax(stringLiteral: compilationSource)]
    }

    private static func generatedBehaviorActionEntries(
        _ actions: [MachineSurfacePlan.Action]
    ) -> String {
        actions.enumerated().flatMap { ordinal, action in
            let argumentLists = action.bindings.reduce([[]]) { partial, binding in
                partial.flatMap { arguments in
                    binding.domain.map { arguments + [$0] }
                }
            }
            return argumentLists.map { values in
                let arguments = values.map(codegenTLAValue).joined(separator: ", ")
                return """
                .init(successors: { projection in
                    guard let action = Self._actionLabel(actionAt: \(ordinal), arguments: [\(arguments)]) else {
                        throw GeneratedMachineContractDiagnostic(
                            code: .actionLabelRoundTripMismatch,
                            path: "generatedBehavior.actions.\(ordinal)",
                            expected: "a generated action label",
                            actual: "an action outside the generated label domain",
                            nextSafeAction: "Regenerate the model from its current source."
                        )
                    }
                    return try Self._generatedSuccessors(for: action, from: projection)
                })
                """
            }
        }.joined(separator: ",\n                    ")
    }

    static func machineSurfaceSwiftFactsSource(_ facts: MachineSurfaceSwiftFacts) -> String {
        func quoted(_ value: String) -> String { String(reflecting: value) }
        func dictionary(_ values: [String: String]) -> String {
            guard !values.isEmpty else { return "[:]" }
            return "[" + values.sorted { $0.key < $1.key }
                .map { "\(quoted($0.key)): \(quoted($0.value))" }
                .joined(separator: ", ") + "]"
        }
        let actionBindings = facts.actionBindingTypes.isEmpty ? "[:]" : "[" + facts.actionBindingTypes.sorted { $0.key < $1.key }.map { action in
            "\(quoted(action.key)): \(dictionary(action.value))"
        }.joined(separator: ", ") + "]"
        let collections = facts.symmetricCollections.isEmpty ? "[:]" : "[" + facts.symmetricCollections.sorted { $0.key < $1.key }.map { collection in
            "\(quoted(collection.key)): .init(elementType: \(quoted(collection.value.elementType)), valueType: \(quoted(collection.value.valueType)))"
        }.joined(separator: ", ") + "]"
        return "MachineSurfaceSwiftFacts(variableTypes: \(dictionary(facts.variableTypes)), actionBindingTypes: \(actionBindings), symmetricCollections: \(collections), collectionActions: \(dictionary(facts.collectionActions)))"
    }

    static func generatedMachineMetadataSource(_ plan: MachineSurfacePlan) -> String {
        func quoted(_ value: String) -> String { String(reflecting: value) }
        func collectionType(_ value: CollectionVarType) -> String {
            switch value {
            case .scalar: ".scalar"
            case .set: ".set"
            case .array(let scope): ".array(\(scope))"
            case .dictionary(let scope): ".dictionary(\(scope))"
            }
        }
        let variables = plan.variables.map {
            ".init(formalName: \(quoted($0.formalName)), swiftType: \(quoted($0.swiftType)), valueShape: .\($0.valueShape.rawValue), collectionType: \(collectionType($0.collectionType)))"
        }.joined(separator: ", ")
        let actions = plan.actions.map { action in
            let bindings = action.bindings.map {
                ".init(formalName: \(quoted($0.formalName)), swiftType: \(quoted($0.swiftType)), domain: [\($0.domain.map(codegenTLAValue).joined(separator: ", "))], isPublic: \($0.isPublic))"
            }.joined(separator: ", ")
            return ".init(formalName: \(quoted(action.formalName)), swiftIdentifier: \(quoted(action.swiftIdentifier)), bindings: [\(bindings)])"
        }.joined(separator: ", ")
        let symmetricCollections = plan.symmetricCollections.map {
            ".init(formalName: \(quoted($0.formalName)), verificationScope: \($0.verificationScope), initial: \(codegenTLAValue($0.initial)), elementType: \(quoted($0.elementType)), valueType: \(quoted($0.valueType)))"
        }.joined(separator: ", ")
        let collectionActions = plan.collectionActions.isEmpty ? "[:]" : "[" + plan.collectionActions.sorted { $0.key < $1.key }
            .map { "\(quoted($0.key)): \(quoted($0.value))" }
            .joined(separator: ", ") + "]"
        return ".init(compilationIdentity: .init(value: \(quoted(plan.compilationIdentity.value))), variables: [\(variables)], actions: [\(actions)], symmetricCollections: [\(symmetricCollections)], collectionActions: \(collectionActions))"
    }

    static func codegenTLAValue(_ value: TLAValue) -> String {
        switch value {
        case .int(let n): return ".int(\(n))"
        case .bool(let b): return ".bool(\(b))"
        case .string(let s): return ".string(\"\(s)\")"
        case .set(let s): return ".set([\(s.map(codegenTLAValue).joined(separator: ", "))])"
        case .tuple(let t): return ".tuple([\(t.map(codegenTLAValue).joined(separator: ", "))])"
        case .record(let r):
            let fields = r.fields.map { "\"\($0.name)\": \(codegenTLAValue($0.value))" }.joined(separator: ", ")
            return fields.isEmpty ? ".record([:])" : ".record([\(fields)])"
        case .function(let f):
            let entries = f.map { "\(codegenTLAValue($0.key)): \(codegenTLAValue($0.value))" }.joined(separator: ", ")
            return entries.isEmpty ? ".function([:])" : ".function([\(entries)])"
        case .constant(let c): return ".constant(\"\(c)\")"
        }
    }

    static func generateActionLabel(actions: [MachineSurfacePlan.Action]) -> [DeclSyntax] {
        guard actions.isEmpty == false else {
            return [
                DeclSyntax(stringLiteral: "public enum ActionLabel: Hashable, Sendable {}"),
                DeclSyntax(stringLiteral: "private static func _actionOrdinal(for action: ActionLabel) -> Int { switch action {} }"),
                DeclSyntax(stringLiteral: "private static func _formalArguments(for action: ActionLabel) -> [TLAValue] { switch action {} }"),
                DeclSyntax(stringLiteral: "private static func _actionLabel(actionAt ordinal: Int, arguments: [TLAValue]) -> ActionLabel? { nil }")
            ]
        }
        func argumentConstructor(for binding: MachineSurfacePlan.Binding) -> String {
            switch binding.swiftType {
            case "Int": return ".int(\(binding.formalName))"
            case "Bool": return ".bool(\(binding.formalName))"
            case "String": return ".string(\(binding.formalName))"
            case "TLAValue": return binding.formalName
            default: return "\(binding.formalName).tlaValue"
            }
        }

        func fixedArgument(_ binding: MachineSurfacePlan.Binding) -> String {
            codegenTLAValue(binding.domain[0])
        }

        func actionArgumentPattern(
            for binding: MachineSurfacePlan.Binding,
            index: Int,
            in arguments: String
        ) -> String {
            let argument = "\(arguments)[\(index)]"
            switch binding.swiftType {
            case "Int": return "case .int(let \(binding.formalName)) = \(argument)"
            case "Bool": return "case .bool(let \(binding.formalName)) = \(argument)"
            case "String": return "case .string(let \(binding.formalName)) = \(argument)"
            case "TLAValue": return "let \(binding.formalName) = \(argument)"
            default:
                return "let \(binding.formalName) = \(binding.swiftType)(formalValue: \(argument))"
            }
        }

        let cases = actions.map { action in
            let bindings = action.bindings.filter(\.isPublic)
            guard !bindings.isEmpty else { return "case \(action.swiftIdentifier)" }
            let parameters = bindings.map { "\($0.formalName): \($0.swiftType)" }.joined(separator: ", ")
            return "case \(action.swiftIdentifier)(\(parameters))"
        }.joined(separator: "\n    ")

        let actionOrdinalCases = actions.enumerated().map { ordinal, action in
            "case .\(action.swiftIdentifier): return \(ordinal)"
        }.joined(separator: "\n        ")

        let actionArgumentCases = actions.map { action in
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

        let labelCases = actions.enumerated().map { ordinal, action in
            let publicBindings = action.bindings.filter(\.isPublic)
            if action.bindings.isEmpty {
                return "case \(ordinal) where arguments.isEmpty: return .\(action.swiftIdentifier)"
            }
            let patterns = action.bindings.enumerated().map { index, binding -> String in
                if binding.isPublic {
                    return actionArgumentPattern(for: binding, index: index, in: "arguments")
                }
                return "\(codegenTLAValue(binding.domain[0])) == arguments[\(index)]"
            }.joined(separator: ", ")
            let arguments = publicBindings.map { "\($0.formalName): \($0.formalName)" }.joined(separator: ", ")
            return "case \(ordinal) where arguments.count == \(action.bindings.count): "
                + "guard \(patterns) else { return nil }; return .\(action.swiftIdentifier)\(arguments.isEmpty ? "" : "(\(arguments))")"
        }.joined(separator: "\n        ")

        return [
            DeclSyntax(stringLiteral: """
        public enum ActionLabel: Hashable, Sendable {
            \(cases)
        }
        """),
            DeclSyntax(stringLiteral: """
        private static func _actionOrdinal(for action: ActionLabel) -> Int {
            switch action {
            \(actionOrdinalCases)
            }
        }
        """),
            DeclSyntax(stringLiteral: """
        private static func _formalArguments(for action: ActionLabel) -> [TLAValue] {
            switch action {
            \(actionArgumentCases)
            }
        }
        """),
            DeclSyntax(stringLiteral: """
        private static func _actionLabel(actionAt ordinal: Int, arguments: [TLAValue]) -> ActionLabel? {
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
                        bindingSpecifier: .keyword(.var),
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
                                firstName: "projection",
                                type: TypeSyntax(stringLiteral: "TLAStateProjection")
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
                DeclSyntax(stringLiteral: stateProjectionFunction(variables: variables, enumInfos: enumInfos))
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
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "_machine.snapshot.\(v.formalName)") }
                    ))
                )]
            )
        }
    }

    static func stateDecodingStatements(
        variables: [MachineSurfacePlan.Variable],
        enumInfos: [ParsedEnumInfo]
    ) -> String {
        variables.enumerated().map { index, variable in
            let key = String(reflecting: variable.formalName)
            let token = "token\(index)"
            let rawValue = "projection.value(for: \(token))"
            let typeName = stateType(for: variable, enumInfos: enumInfos)
            let tokenDeclaration = """
            guard let \(token) = TLAStateProjection.Token(validating: \(key)) else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: \(key))
            }
            """
            if let info = enumInfos.first(where: { $0.typeName == typeName }) {
                let cases = info.cases.map { "case \"\($0.name)\": self.\(variable.formalName) = \(typeName).\($0.name)" }
                    .joined(separator: "\n")
                return """
                \(tokenDeclaration)
                guard let rawValue = \(rawValue) else {
                    throw TLAStateProjectionDiagnostic.missingRequiredValue(path: \(key), expected: "\(typeName)")
                }
                guard case .string(let value) = rawValue else {
                    throw TLAStateProjectionDiagnostic.typeMismatch(path: \(key), expected: "\(typeName) encoded as a formal string", actual: rawValue)
                }
                switch value {
                \(cases)
                default:
                    throw TLAStateProjectionDiagnostic.typeMismatch(path: \(key), expected: "a declared \(typeName) case", actual: rawValue)
                }
                """
            }
            let type = typeName
            if type == "TLAValue" {
                return """
                \(tokenDeclaration)
                guard let value = \(rawValue) else {
                    throw TLAStateProjectionDiagnostic.missingRequiredValue(path: \(key), expected: "\(type)")
                }
                self.\(variable.formalName) = value
                """
            }
            if !["Int", "Bool", "String", "TLAValue"].contains(typeName) {
                return """
                \(tokenDeclaration)
                guard let rawValue = \(rawValue) else {
                    throw TLAStateProjectionDiagnostic.missingRequiredValue(path: \(key), expected: "\(typeName)")
                }
                guard let value = \(typeName)(formalValue: rawValue) else {
                    throw TLAStateProjectionDiagnostic.typeMismatch(path: \(key), expected: "\(typeName)", actual: rawValue)
                }
                self.\(variable.formalName) = value
                """
            }
            let pattern = tlaValuePattern(forSwiftType: type, binding: "value")
            return """
            \(tokenDeclaration)
            guard let rawValue = \(rawValue) else {
                throw TLAStateProjectionDiagnostic.missingRequiredValue(path: \(key), expected: "\(type)")
            }
            guard \(pattern) else {
                throw TLAStateProjectionDiagnostic.typeMismatch(path: \(key), expected: "\(type)", actual: rawValue)
            }
            self.\(variable.formalName) = value
            """
        }.joined(separator: "\n")
    }

    static func stateProjectionFunction(
        variables: [MachineSurfacePlan.Variable],
        enumInfos: [ParsedEnumInfo]
    ) -> String {
        let entries = variables.map { variable -> String in
            let typeName = stateType(for: variable, enumInfos: enumInfos)
            let value: String
            if enumInfos.contains(where: { $0.typeName == typeName }) {
                value = ".string(String(describing: \(variable.formalName)) )"
            } else if typeName == "TLAValue" {
                value = variable.formalName
            } else if ["Int", "Bool", "String"].contains(typeName) {
                value = constructor(forSwiftType: typeName, value: variable.formalName)
            } else {
                value = "\(variable.formalName).tlaValue"
            }
            return """
            guard let token = TLAStateProjection.Token(validating: \(String(reflecting: variable.formalName))) else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: \(String(reflecting: variable.formalName)))
            }
            entries.append(.init(token: token, value: \(value)))
            """
        }.joined(separator: "\n")
        return """
        fileprivate func formalProjection() throws -> TLAStateProjection {
            var entries: [TLAStateProjection.Entry] = []
            \(entries)
            return try TLAStateProjection(validating: entries)
        }
        """
    }

    static func tlaValuePattern(forSwiftType swiftType: String, binding: String) -> String {
        switch swiftType {
        case "Int": "case .int(let \(binding)) = rawValue"
        case "Bool": "case .bool(let \(binding)) = rawValue"
        case "String": "case .string(let \(binding)) = rawValue"
        default: "let \(binding) = rawValue"
        }
    }

    static func generateActionMethods(
        isActor: Bool = false,
        actions: [MachineSurfacePlan.Action],
        collectionActions: [String: String],
        symmetricCollections: [String: MachineSurfacePlan.SymmetricCollection]
    ) -> [DeclSyntax] {
        let methods = actions.map { action -> DeclSyntax in
            if action.bindings.isEmpty,
               let collectionName = collectionActions[action.formalName],
               let collection = symmetricCollections[collectionName] {
                let source = """
                @discardableResult
                \(isActor ? "fileprivate" : "public mutating") func \(action.swiftIdentifier)(id: \(collection.elementType).ID) throws -> TransitionResult {
                    let projection = \(collection.formalName).projection()
                    let targetKey: TLAValue
                    do {
                        targetKey = try projection.key(for: id, collection: "\(collection.formalName)", action: "\(action.formalName)")
                    } catch {
                        throw error
                    }
                    let formalState = try _stateWithLiveCollections()
                    guard let token = TLAStateProjection.Token(validating: \(String(reflecting: collection.formalName))),
                          case .function(let originalValues) = formalState.value(for: token) else {
                        throw TLAStateProjectionDiagnostic.missingRequiredValue(
                            path: \(String(reflecting: collection.formalName)),
                            expected: "a formal collection function"
                        ))
                    }
                    let evidence = try _machine.apply(
                        .\(action.swiftIdentifier),
                        from: formalState
                    ) { candidate in
                        guard case .function(let candidateValues) = candidate.\(collection.formalName),
                              candidateValues[targetKey] != nil else { return false }
                        return candidateValues.allSatisfy { key, value in
                            key == targetKey || originalValues[key] == value
                        }
                    }
                    guard case .function(let nextValues) = evidence.after.\(collection.formalName),
                          let nextFormalValue = nextValues[targetKey],
                          let nextValue = \(collection.valueType)(formalValue: nextFormalValue) else {
                        throw TLAStateProjectionDiagnostic.typeMismatch(
                            path: \(String(reflecting: collection.formalName)),
                            expected: "\(collection.valueType)",
                            actual: evidence.after.\(collection.formalName)
                        ))
                    }
                    try \(collection.formalName).update(id: id, to: nextValue)
                    return TransitionResult(
                        action: .\(action.swiftIdentifier),
                        before: evidence.before,
                        after: evidence.after
                    )
                }
                """
                return DeclSyntax(stringLiteral: source)
            }
            let bindings = action.bindings.filter(\.isPublic)
            let parameters = bindings.map { binding in
                "\(binding.formalName): \(binding.swiftType)"
            }.joined(separator: ", ")
            let labels = bindings.map { "\($0.formalName): \($0.formalName)" }.joined(separator: ", ")
            let methodName = isActor ? "_\(action.swiftIdentifier)" : "apply\(action.swiftIdentifier)"
            if bindings.isEmpty {
                let source = """
                \(isActor ? "fileprivate" : "public mutating") func \(methodName)() throws -> TransitionResult {
                    try apply(.\(action.swiftIdentifier))
                }
                """
                return DeclSyntax(stringLiteral: source)
            }
            let modifier = isActor ? "fileprivate" : "public mutating"
            let source = """
            \(modifier) func \(methodName)(\(parameters)) throws -> TransitionResult {
                try apply(.\(action.swiftIdentifier)\(labels.isEmpty ? "" : "(\(labels))"))
            }
            """
            return DeclSyntax(stringLiteral: source)
        }
        return methods
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
