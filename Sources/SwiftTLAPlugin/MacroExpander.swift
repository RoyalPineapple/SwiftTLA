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

        decls.append(contentsOf: generateActionLabel(actions: plan.actions))
        decls.append(DeclSyntax(generateStateStruct(variables: plan.variables, enumInfos: model.enumInfos)))
        decls.append(contentsOf: generateGeneratedMachineStorageMembers(
            isActor: isActor,
            hasActions: !plan.actions.isEmpty,
            actions: plan.actions,
            variables: plan.variables,
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
            symmetricCollections: Dictionary(uniqueKeysWithValues: plan.symmetricCollections.map { ($0.formalName, $0) }),
            variableOrdinals: Dictionary(uniqueKeysWithValues: plan.variables.enumerated().map { ($0.element.formalName, $0.offset) })
        ))
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
        variables.enumerated().map { index, variable in
            let key = String(reflecting: variable.formalName)
            let rawValue = "try storage.formalValue(at: \(index), in: storageState)"
            let typeName = stateType(for: variable, enumInfos: enumInfos)
            if let info = enumInfos.first(where: { $0.typeName == typeName }) {
                let cases = info.cases.map { "case \"\($0.name)\": self.\(variable.formalName) = \(typeName).\($0.name)" }
                    .joined(separator: "\n")
                return """
                let rawValue = \(rawValue)
                guard case .string(let value) = rawValue else {
                    throw GeneratedMachineStateDiagnostic.typeMismatch(path: \(key), expected: "\(typeName) encoded as a formal string", actual: String(describing: rawValue))
                }
                switch value {
                \(cases)
                default:
                    throw GeneratedMachineStateDiagnostic.typeMismatch(path: \(key), expected: "a declared \(typeName) case", actual: String(describing: rawValue))
                }
                """
            }
            let type = typeName
            if type == "TLAValue" {
                return """
                let value = \(rawValue)
                self.\(variable.formalName) = value
                """
            }
            if !["Int", "Bool", "String", "TLAValue"].contains(typeName) {
                return """
                let rawValue = \(rawValue)
                guard let value = \(typeName)(formalValue: rawValue) else {
                    throw GeneratedMachineStateDiagnostic.typeMismatch(path: \(key), expected: "\(typeName)", actual: String(describing: rawValue))
                }
                self.\(variable.formalName) = value
                """
            }
            let pattern = tlaValuePattern(forSwiftType: type, binding: "value")
            return """
            let rawValue = \(rawValue)
            guard \(pattern) else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(path: \(key), expected: "\(type)", actual: String(describing: rawValue))
            }
            self.\(variable.formalName) = value
            """
        }.joined(separator: "\n")
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
        symmetricCollections: [String: MachineSurfacePlan.SymmetricCollection],
        variableOrdinals: [String: Int]
    ) -> [DeclSyntax] {
        let methods = actions.map { action -> DeclSyntax in
            if action.bindings.isEmpty,
               let collectionName = collectionActions[action.formalName],
               let collection = symmetricCollections[collectionName],
               let variableOrdinal = variableOrdinals[collectionName] {
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
                    let storageState = try _stateWithLiveCollections()
                    guard case .function(let originalValues) = try _storage.formalValue(
                        at: \(variableOrdinal),
                        in: storageState
                    ) else {
                        throw GeneratedMachineStateDiagnostic.missingRequiredValue(
                            path: \(String(reflecting: collection.formalName)),
                            expected: "a formal collection function"
                        ))
                    }
                    let before = _state
                    let afterStorageState = try _storage.apply(
                        actionOrdinal: Self._actionOrdinal(for: .\(action.swiftIdentifier)),
                        formalArguments: Self._formalArguments(for: .\(action.swiftIdentifier)),
                        from: storageState
                    ) { candidate in
                        let candidate = try State(storage: _storage, storageState: candidate)
                        guard case .function(let candidateValues) = candidate.\(collection.formalName),
                              candidateValues[targetKey] != nil else { return false }
                        return candidateValues.allSatisfy { key, value in
                            key == targetKey || originalValues[key] == value
                        }
                    }
                    let after = try State(storage: _storage, storageState: afterStorageState)
                    let afterValue = try _storage.formalValue(at: \(variableOrdinal), in: afterStorageState)
                    guard case .function(let nextValues) = afterValue,
                          let nextFormalValue = nextValues[targetKey],
                          let nextValue = \(collection.valueType)(formalValue: nextFormalValue) else {
                        throw GeneratedMachineStateDiagnostic.typeMismatch(
                            path: \(String(reflecting: collection.formalName)),
                            expected: "\(collection.valueType)",
                            actual: String(describing: afterValue)
                        ))
                    }
                    try \(collection.formalName).update(id: id, to: nextValue)
                    _storageState = afterStorageState
                    _state = after
                    return TransitionResult(
                        action: .\(action.swiftIdentifier),
                        before: before,
                        after: after
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
