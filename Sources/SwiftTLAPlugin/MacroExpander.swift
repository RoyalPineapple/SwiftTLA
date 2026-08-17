import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

enum MacroExpander {
    /// The formal action label is external specification data and is kept
    /// verbatim in `TLAActionInvocation`. Generated Swift declarations need a
    /// separate, collision-safe identifier surface.
    static func generatedActionIdentifiers(actions: [NamedAction]) -> [String] {
        let reserved: Set<String> = ["init", "deinit", "subscript", "toInvocation", "rawValue"]
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
        facts: MacroSwiftFacts
    ) -> String {
        facts.actionBindingTypes[action.name]?[binding.name] ?? swiftType(for: binding.values[0])
    }

    /// A finite binding with one possible value is a scheduler detail, not a
    /// useful public argument. Keep it in the formal invocation while hiding
    /// it from the generated Swift surface.
    static func publicBindings(for action: NamedAction) -> [ActionBinding] {
        action.bindings.filter { $0.values.count > 1 }
    }

    static func generate(
        mode: GenerationMode,
        model: MacroCompilation,
        needsPublicInitializer: Bool = true
    ) -> [DeclSyntax] {
        switch mode {
        case .model, .actor:
            return generateStateMachineMembers(
                isActor: mode == .actor,
                model: model,
                needsPublicInitializer: needsPublicInitializer
            )
        case .observable:
            return generateObservableMembers(
                typeName: model.typeName,
                variables: model.variables,
                actions: model.actions,
                facts: model.swiftFacts,
                enumInfos: model.enumInfos
            )
        }
    }

    // MARK: - State machine code generation (model / actor)

    static func generateStateMachineMembers(
        isActor: Bool,
        model: MacroCompilation,
        needsPublicInitializer: Bool
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        // A generated machine is a public value surface. Swift only
        // synthesizes an internal memberwise initializer for a public type,
        // so emit the zero-argument construction API explicitly.
        if needsPublicInitializer {
            decls.append(DeclSyntax(stringLiteral: "public init() {}"))
        }

        decls.append(DeclSyntax(stringLiteral: """
        private var _machine = CanonicalMachine(
            runtime: \(model.typeName).runtime,
            initial: try! State(formalDictionary: \(model.typeName).runtime.initialStates().first!),
            stateDictionary: { $0.asDictionary },
            snapshotFromDictionary: { try State(formalDictionary: $0) }
        )
        """))

        decls.append(DeclSyntax(generateVariablesEnum(variables: model.variables)))
        if !model.actions.isEmpty {
            decls.append(DeclSyntax(generateActionsEnum(actions: model.actions)))
            decls.append(DeclSyntax(generateActionLabel(actions: model.actions, facts: model.swiftFacts)))
        }
        decls.append(DeclSyntax(generateStateStruct(variables: model.variables, facts: model.swiftFacts, enumInfos: model.enumInfos)))
        decls.append(contentsOf: generateCanonicalMachineMembers(
            isActor: isActor,
            hasActions: !model.actions.isEmpty,
            symmetricCollections: model.symmetricCollections
        ))
        decls.append(contentsOf: generateCollectionRuntimeMembers(
            model.symmetricCollections,
            facts: model.swiftFacts
        ))
        let symmetricCollectionNames = Set(model.symmetricCollections.map(\.name))
        let ordinaryVariables = model.variables.filter { !symmetricCollectionNames.contains($0.name) }
        decls.append(contentsOf: generateVariableProperties(
            variables: ordinaryVariables,
            facts: model.swiftFacts,
            enumInfos: model.enumInfos
        ).map(DeclSyntax.init))
        decls.append(contentsOf: generateActionMethods(
            isActor: isActor,
            actions: model.actions,
            collectionActions: model.collectionActions,
            symmetricCollections: model.symmetricCollectionsByName,
            facts: model.swiftFacts
        ).map(DeclSyntax.init))
        decls.append(contentsOf: generateCompilationIdentityCheck(model: model))
        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "runtime"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "SpecRuntime")),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "do { return try SpecRuntime(compilation: compiledSpecification()) } catch { fatalError(String(describing: error)) }") }
                    ))
                )]
            )
        ))

        decls.append(contentsOf: generateSpecTest())
        if !isActor {
            decls.append(DeclSyntax(stringLiteral: """
            public static func generatedActionOutcome(
                actionName: String,
                in state: State
            ) -> SpecRuntime.RuntimeActionOutcome {
                Self.runtime.actionOutcome(named: actionName, in: state.asDictionary)
            }
            """))
            decls.append(DeclSyntax(stringLiteral: """
            public static func generatedPropertyOutcomes(
                in state: State
            ) -> [SpecRuntime.RuntimePropertyOutcome] {
                Self.runtime.propertyOutcomes(in: state.asDictionary)
            }
            """))
        }
        if !model.actions.isEmpty {
            decls.append(contentsOf: generateTransitionMatrix())
        }
        decls.append(contentsOf: generateTransitionsTest(model.actions))
        if model.hasInvariants && !model.actions.isEmpty {
            decls.append(contentsOf: generateInvariantsTest())
        }

        return decls
    }

    static func generateCompilationIdentityCheck(model: MacroCompilation) -> [DeclSyntax] {
        let expectedIdentity = model.compilation.identity.value
        let compilationSource = """
        static let _expectedCompilationIdentity = \"\(expectedIdentity)\"
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
            return compilation
        }
        """
        return [DeclSyntax(stringLiteral: compilationSource)]
    }

    static func codegenTemporalExpr(_ expression: TemporalExpr) -> String {
        switch expression {
        case .always(let state): return ".always(\(codegenStateExpr(state)))"
        case .eventually(let state): return ".eventually(\(codegenStateExpr(state)))"
        case .alwaysEventually(let state): return ".alwaysEventually(\(codegenStateExpr(state)))"
        case .eventuallyAlways(let state): return ".eventuallyAlways(\(codegenStateExpr(state)))"
        case .leadsTo(let from, let to): return ".leadsTo(\(codegenStateExpr(from)), \(codegenStateExpr(to)))"
        }
    }

    static func codegenFairness(_ fairness: FairnessCondition) -> String {
        switch fairness {
        case .weakFairness(let action): return ".weakFairness(\"\(action)\")"
        case .strongFairness(let action): return ".strongFairness(\"\(action)\")"
        case .weakFairnessInvocation(let invocation):
            return ".weakFairnessInvocation(\(codegenInvocation(invocation)))"
        case .strongFairnessInvocation(let invocation):
            return ".strongFairnessInvocation(\(codegenInvocation(invocation)))"
        }
    }

    static func codegenInvocation(_ invocation: TLAActionInvocation) -> String {
        ".init(name: \"\(invocation.name)\", arguments: [\(invocation.arguments.map(codegenTLAValue).joined(separator: ", "))])"
    }

    static func codegenTLAValue(_ value: TLAValue) -> String {
        switch value {
        case .int(let n): return ".int(\(n))"
        case .bool(let b): return ".bool(\(b))"
        case .string(let s): return ".string(\"\(s)\")"
        case .set(let s): return ".set([\(s.map(codegenTLAValue).joined(separator: ", "))])"
        case .tuple(let t): return ".tuple([\(t.map(codegenTLAValue).joined(separator: ", "))])"
        case .record(let r):
            let fields = r.map { "\"\($0.key)\": \(codegenTLAValue($0.value))" }.joined(separator: ", ")
            return fields.isEmpty ? ".record([:])" : ".record([\(fields)])"
        case .function(let f):
            let entries = f.map { "\(codegenTLAValue($0.key)): \(codegenTLAValue($0.value))" }.joined(separator: ", ")
            return entries.isEmpty ? ".function([:])" : ".function([\(entries)])"
        case .constant(let c): return ".constant(\"\(c)\")"
        }
    }

    static func codegenStateExpr(_ expr: StateExpr) -> String {
        func cg(_ e: StateExpr) -> String { codegenStateExpr(e) }
        switch expr {
        case .variable(let v): return "StateExpr.variable(\"\(v)\")"
        case .value(let v): return "StateExpr.value(\(codegenTLAValue(v)))"
        case .add(let a, let b): return "StateExpr.add(\(cg(a)), \(cg(b)))"
        case .subtract(let a, let b): return "StateExpr.subtract(\(cg(a)), \(cg(b)))"
        case .multiply(let a, let b): return "StateExpr.multiply(\(cg(a)), \(cg(b)))"
        case .divide(let a, let b): return "StateExpr.divide(\(cg(a)), \(cg(b)))"
        case .modulo(let a, let b): return "StateExpr.modulo(\(cg(a)), \(cg(b)))"
        case .negate(let a): return "StateExpr.negate(\(cg(a)))"
        case .integerDivide(let a, let b): return "StateExpr.integerDivide(\(cg(a)), \(cg(b)))"
        case .equal(let a, let b): return "StateExpr.equal(\(cg(a)), \(cg(b)))"
        case .notEqual(let a, let b): return "StateExpr.notEqual(\(cg(a)), \(cg(b)))"
        case .lessThan(let a, let b): return "StateExpr.lessThan(\(cg(a)), \(cg(b)))"
        case .lessOrEqual(let a, let b): return "StateExpr.lessOrEqual(\(cg(a)), \(cg(b)))"
        case .greaterThan(let a, let b): return "StateExpr.greaterThan(\(cg(a)), \(cg(b)))"
        case .greaterOrEqual(let a, let b): return "StateExpr.greaterOrEqual(\(cg(a)), \(cg(b)))"
        case .and(let a, let b): return "StateExpr.and(\(cg(a)), \(cg(b)))"
        case .or(let a, let b): return "StateExpr.or(\(cg(a)), \(cg(b)))"
        case .not(let a): return "StateExpr.not(\(cg(a)))"
        case .ifThenElse(let c, let t, let f): return "StateExpr.ifThenElse(\(cg(c)), \(cg(t)), \(cg(f)))"
        case .cardinality(let s): return "StateExpr.cardinality(\(cg(s)))"
        case .functionApply(let f, let x): return "StateExpr.functionApply(\(cg(f)), \(cg(x)))"
        case .recordAccess(let r, let f): return "StateExpr.recordAccess(\(cg(r)), \"\(f)\")"
        case .in(let e, let s): return "StateExpr.in(\(cg(e)), \(cg(s)))"
        case .union(let a, let b): return "StateExpr.union(\(cg(a)), \(cg(b)))"
        case .intersection(let a, let b): return "StateExpr.intersection(\(cg(a)), \(cg(b)))"
        case .setDifference(let a, let b): return "StateExpr.setDifference(\(cg(a)), \(cg(b)))"
        case .subset(let a, let b): return "StateExpr.subset(\(cg(a)), \(cg(b)))"
        case .tupleAccess(let t, let i): return "StateExpr.tupleAccess(\(cg(t)), \(i))"
        case .tupleDynamicAccess(let tuple, let index): return "StateExpr.tupleDynamicAccess(\(cg(tuple)), \(cg(index)))"
        case .tupleAppend(let t, let e): return "StateExpr.tupleAppend(\(cg(t)), \(cg(e)))"
        case .tupleHead(let t): return "StateExpr.tupleHead(\(cg(t)))"
        case .tupleTail(let t): return "StateExpr.tupleTail(\(cg(t)))"
        case .tupleLength(let t): return "StateExpr.tupleLength(\(cg(t)))"
        case .tupleConcatenate(let a, let b): return "StateExpr.tupleConcatenate(\(cg(a)), \(cg(b)))"
        case .except(let f, let k, let v): return "StateExpr.except(\(cg(f)), \(cg(k)), \(cg(v)))"
        case .domain(let f): return "StateExpr.domain(\(cg(f)))"
        case .setFilter(let s, let qv, let p): return "StateExpr.setFilter(\(cg(s)), \"\(qv)\", \(cg(p)))"
        case .setMap(let e, let qv, let s): return "StateExpr.setMap(\(cg(e)), \"\(qv)\", \(cg(s)))"
        case .powerSet(let s): return "StateExpr.powerSet(\(cg(s)))"
        case .unionAll(let s): return "StateExpr.unionAll(\(cg(s)))"
        case .integerRange(let lower, let upper): return "StateExpr.integerRange(\(cg(lower)), \(cg(upper)))"
        case .tupleLiteral(let es): return "StateExpr.tupleLiteral([\(es.map(cg).joined(separator: ", "))])"
        case .recordLiteral(let fs):
            let fields = fs.map { "\"\($0.key)\": \(cg($0.value))" }.joined(separator: ", ")
            return "StateExpr.recordLiteral([\(fields)])"
        case .setLiteral(let es): return "StateExpr.setLiteral([\(es.map(cg).joined(separator: ", "))])"
        case .functionLiteral(let d, let qv, let b): return "StateExpr.functionLiteral(\(cg(d)), \"\(qv)\", \(cg(b)))"
        case .functionSet(let domain, let range):
            return "StateExpr.functionSet(\(cg(domain)), \(cg(range)))"
        case .caseExpr(let ps, let fb):
            let patterns = ps.map(cg).joined(separator: ", ")
            let fallback = fb.map { cg($0) } ?? "nil"
            return "StateExpr.caseExpr([\(patterns)], \(fallback))"
        case .forAll(let set, let variable, let predicate):
            return "StateExpr.forAll(\(cg(set)), \"\(variable)\", \(cg(predicate)))"
        case .exists(let set, let variable, let predicate):
            return "StateExpr.exists(\(cg(set)), \"\(variable)\", \(cg(predicate)))"
        case .choose(let set, let variable, let predicate):
            return "StateExpr.choose(\(cg(set)), \"\(variable)\", \(cg(predicate)))"
        case .enabledAction(let name): return "StateExpr.enabled(\"\(name)\")"
        case .sequenceFromSet(let values): return "StateExpr.sequenceFromSet(\(cg(values)))"
        case .setSum(let function, let values): return "StateExpr.setSum(\(cg(function)), \(cg(values)))"
        case .foldFunction(let operation, let initial, let sequence):
            let parameters = operation.parameters.map { "\"\($0)\"" }.joined(separator: ", ")
            return "StateExpr.foldFunction(FormalLambda(parameters: [\(parameters)], body: \(cg(operation.body))), initial: \(cg(initial)), sequence: \(cg(sequence)))"
        case .operatorApplication(let operation, let arguments):
            let operatorSource: String
            switch operation {
            case .lambda(let lambda):
                let parameters = lambda.parameters.map { "\"\($0)\"" }.joined(separator: ", ")
                operatorSource = ".lambda(FormalLambda(parameters: [\(parameters)], body: \(cg(lambda.body))))"
            case .reference(let name, let arity):
                operatorSource = ".reference(\"\(name)\", arity: \(arity))"
            }
            let argumentSource = arguments.map { argument -> String in
                switch argument {
                case .value(let expression): return ".value(\(cg(expression)))"
                case .operator(.reference(let name, let arity)):
                    return ".operator(.reference(\"\(name)\", arity: \(arity)))"
                case .operator(.lambda(let lambda)):
                    let parameters = lambda.parameters.map { "\"\($0)\"" }.joined(separator: ", ")
                    return ".operator(.lambda(FormalLambda(parameters: [\(parameters)], body: \(cg(lambda.body)))))"
                }
            }.joined(separator: ", ")
            return "StateExpr.operatorApplication(\(operatorSource), [\(argumentSource)])"
        case .recursiveCall(let name, let arguments):
            return "StateExpr.recursiveCall(\"\(name)\", [\(arguments.map(cg).joined(separator: ", "))])"
        case .letValue(let name, let value, let body):
            return "StateExpr.letValue(\"\(name)\", \(cg(value)), \(cg(body)))"
        case .letIn(let operators, let body):
            let definitions = operators.map { operation in
                let parameters = operation.parameters.map { "\"\($0)\"" }.joined(separator: ", ")
                let domain = operation.domain.map { ", domain: \(cg($0))" } ?? ""
                return "LocalOperator(\"\(operation.name)\", parameters: [\(parameters)]\(domain), body: \(cg(operation.body)))"
            }.joined(separator: ", ")
            return "StateExpr.letIn([\(definitions)], \(cg(body)))"
        }
    }

    static func codegenActionExpr(_ action: ActionExpr) -> String {
        func cg(_ a: ActionExpr) -> String { codegenActionExpr(a) }
        func sg(_ e: StateExpr) -> String { codegenStateExpr(e) }
        switch action {
        case .assign(let v, let e): return "ActionExpr.assign(\"\(v)\", \(sg(e)))"
        case .unchanged(let v): return "ActionExpr.unchanged(\"\(v)\")"
        case .guard_(let e): return "ActionExpr.guard_(\(sg(e)))"
        case .chooseAction(let v, let s): return "ActionExpr.chooseAction(\"\(v)\", \(sg(s)))"
        case .existsAction(let v, let s, let b): return "ActionExpr.existsAction(\"\(v)\", \(sg(s)), \(cg(b)))"
        case .ifElse(let c, let t, let e): return "ActionExpr.ifElse(\(sg(c)), \(cg(t)), \(cg(e)))"
        case .define(let v, let e, let b): return "ActionExpr.define(\"\(v)\", \(sg(e)), \(cg(b)))"
        case .and(let a, let b): return "ActionExpr.and(\(cg(a)), \(cg(b)))"
        case .or(let a, let b): return "ActionExpr.or(\(cg(a)), \(cg(b)))"
        }
    }

    static func generateVariablesEnum(variables: [NamedVar]) -> EnumDeclSyntax {
        EnumDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: "Variables",
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeListSyntax {
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "String"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "CaseIterable"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "Sendable"))
                }
            },
            memberBlock: MemberBlockSyntax {
                for v in variables {
                    EnumCaseDeclSyntax { EnumCaseElementSyntax(name: .identifier(v.name)) }
                }
            }
        )
    }

    static func generateActionsEnum(actions: [NamedAction]) -> EnumDeclSyntax {
        EnumDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: "Actions",
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeListSyntax {
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "String"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "CaseIterable"))
                }
            },
            memberBlock: MemberBlockSyntax {
                for (a, identifier) in zip(actions, generatedActionIdentifiers(actions: actions)) {
                    EnumCaseDeclSyntax {
                        EnumCaseElementSyntax(
                            name: .identifier(identifier),
                            rawValue: InitializerClauseSyntax(value: StringLiteralExprSyntax(content: a.name))
                        )
                    }
                }
            }
        )
    }

    static func generateActionLabel(actions: [NamedAction], facts: MacroSwiftFacts) -> DeclSyntax {
        let identifiers = generatedActionIdentifiers(actions: actions)
        func swiftType(for action: NamedAction, binding: ActionBinding) -> String {
            Self.swiftType(for: action, binding: binding, facts: facts)
        }

        func argumentConstructor(for action: NamedAction, binding: ActionBinding) -> String {
            switch swiftType(for: action, binding: binding) {
            case "Int": return ".int(\(binding.name))"
            case "Bool": return ".bool(\(binding.name))"
            case "String": return ".string(\(binding.name))"
            case "TLAValue": return binding.name
            default: return "\(binding.name).tlaValue"
            }
        }

        func fixedArgument(_ binding: ActionBinding) -> String {
            codegenTLAValue(binding.values[0])
        }

        func invocationPattern(for action: NamedAction, binding: ActionBinding, index: Int) -> String {
            let argument = "invocation.arguments[\(index)]"
            switch swiftType(for: action, binding: binding) {
            case "Int": return "case .int(let \(binding.name)) = \(argument)"
            case "Bool": return "case .bool(let \(binding.name)) = \(argument)"
            case "String": return "case .string(let \(binding.name)) = \(argument)"
            case "TLAValue": return "let \(binding.name) = \(argument)"
            default:
                return "let \(binding.name) = \(swiftType(for: action, binding: binding))(formalValue: \(argument))"
            }
        }

        let cases = zip(actions, identifiers).map { action, identifier in
            let bindings = publicBindings(for: action)
            guard !bindings.isEmpty else { return "case \(identifier)" }
            let parameters = bindings.map { "\($0.name): \(swiftType(for: action, binding: $0))" }.joined(separator: ", ")
            return "case \(identifier)(\(parameters))"
        }.joined(separator: "\n    ")

        let toInvocationCases = zip(actions, identifiers).map { action, identifier in
            let publicBindings = publicBindings(for: action)
            let arguments = action.bindings.map { binding in
                publicBindings.contains(where: { $0.name == binding.name })
                    ? argumentConstructor(for: action, binding: binding)
                    : fixedArgument(binding)
            }.joined(separator: ", ")
            let pattern = publicBindings.isEmpty
                ? ".\(identifier)"
                : ".\(identifier)(\(publicBindings.map { "let \($0.name)" }.joined(separator: ", ")))"
            return "case \(pattern): return .init(name: \"\(action.name)\", arguments: [\(arguments)])"
        }.joined(separator: "\n        ")

        let fromInvocationCases = zip(actions, identifiers).map { action, identifier in
            let publicBindings = publicBindings(for: action)
            if action.bindings.isEmpty {
                return "case \"\(action.name)\" where invocation.arguments.isEmpty: self = .\(identifier)"
            }
            let patterns = action.bindings.enumerated().map { index, binding -> String in
                if publicBindings.contains(where: { $0.name == binding.name }) {
                    return invocationPattern(for: action, binding: binding, index: index)
                }
                return "\(codegenTLAValue(binding.values[0])) == invocation.arguments[\(index)]"
            }.joined(separator: ", ")
            let arguments = publicBindings.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
            return "case \"\(action.name)\" where invocation.arguments.count == \(action.bindings.count): "
                + "guard \(patterns) else { return nil }; self = .\(identifier)\(arguments.isEmpty ? "" : "(\(arguments))")"
        }.joined(separator: "\n        ")

        return DeclSyntax(stringLiteral: """
        public enum ActionLabel: Hashable, Sendable {
            \(cases)

            public func toInvocation() -> TLAActionInvocation {
                switch self {
                \(toInvocationCases)
                }
            }

            public init?(invocation: TLAActionInvocation) {
                switch invocation.name {
                \(fromInvocationCases)
                default: return nil
                }
            }
        }
        """)
    }

}

extension MacroExpander {
    static func generateStateStruct(
        variables: [NamedVar],
        facts: MacroSwiftFacts,
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
                            pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                            typeAnnotation: TypeAnnotationSyntax(
                                type: TypeSyntax(stringLiteral: stateType(for: v, facts: facts, enumInfos: enumInfos))
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
                                    firstName: .identifier(v.name),
                                    type: TypeSyntax(stringLiteral: stateType(for: v, facts: facts, enumInfos: enumInfos))
                                )
                            }
                        }
                    ),
                    body: CodeBlockSyntax {
                        for v in variables {
                            ExprSyntax(stringLiteral: "self.\(v.name) = \(v.name)")
                        }
                    }
                )
                InitializerDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.fileprivate))],
                    signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax {
                            FunctionParameterSyntax(
                                firstName: "formalDictionary", secondName: "dict",
                                type: TypeSyntax(stringLiteral: "[String: TLAValue]")
                            )
                        },
                        effectSpecifiers: FunctionEffectSpecifiersSyntax(
                            throwsClause: ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
                        )
                    ),
                    body: CodeBlockSyntax {
                        ExprSyntax(stringLiteral: stateDecodingStatements(variables: variables, facts: facts, enumInfos: enumInfos))
                    }
                )
                VariableDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.fileprivate))],
                    bindingSpecifier: .keyword(.var),
                    bindings: [PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: "asDictionary"),
                        typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "[String: TLAValue]")),
                        accessorBlock: AccessorBlockSyntax(accessors: .getter(
                            CodeBlockItemListSyntax {
                                DeclSyntax(stringLiteral: "var d: [String: TLAValue] = [:]")
                                for v in variables {
                                    let st = stateType(for: v, facts: facts, enumInfos: enumInfos)
                                    if let swiftTypeName = facts.variableTypes[v.name],
                                       enumInfos.contains(where: { $0.typeName == swiftTypeName }) {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = .string(String(describing: \(v.name)))")
                                    } else if st == "TLAValue" {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(v.name)")
                                    } else if ["Int", "Bool", "String"].contains(st) {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(constructor(forSwiftType: st, value: v.name))")
                                    } else if facts.variableTypes[v.name] != nil {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(v.name).tlaValue")
                                    } else {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(constructor(for: v.initial, value: v.name))")
                                    }
                                }
                                StmtSyntax(stringLiteral: "return d")
                            }
                        ))
                    )]
                )
            }
        )
    }

    static func generateVariableProperties(
        variables: [NamedVar],
        facts: MacroSwiftFacts,
        enumInfos: [ParsedEnumInfo] = []
    ) -> [VariableDeclSyntax] {
        variables.map { v in
            let propType = stateType(for: v, facts: facts, enumInfos: enumInfos)
            return VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                    typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: propType)),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "_machine.snapshot.\(v.name)") }
                    ))
                )]
            )
        }
    }

    static func tlaValuePattern(for initial: TLAValue, binding: String) -> String {
        switch initial {
        case .int: "case .int(let \(binding)) = rawValue"
        case .bool: "case .bool(let \(binding)) = rawValue"
        case .string, .constant: "case .string(let \(binding)) = rawValue"
        case .set: "case .set(let \(binding)) = rawValue"
        case .tuple: "case .tuple(let \(binding)) = rawValue"
        case .record: "case .record(let \(binding)) = rawValue"
        case .function: "case .function(let \(binding)) = rawValue"
        }
    }

    static func stateDecodingStatements(
        variables: [NamedVar],
        facts: MacroSwiftFacts,
        enumInfos: [ParsedEnumInfo]
    ) -> String {
        variables.map { variable in
            let key = "Variables.\(variable.name).rawValue"
            if let typeName = facts.variableTypes[variable.name],
               let info = enumInfos.first(where: { $0.typeName == typeName }) {
                let cases = info.cases.map { "case \"\($0.name)\": self.\(variable.name) = \(typeName).\($0.name)" }
                    .joined(separator: "\n")
                return """
                guard let rawValue = dict[\(key)] else {
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
            let type = stateType(for: variable, facts: facts, enumInfos: enumInfos)
            if type == "TLAValue" {
                return """
                guard let value = dict[\(key)] else {
                    throw TLAStateProjectionDiagnostic.missingRequiredValue(path: \(key), expected: "\(type)")
                }
                self.\(variable.name) = value
                """
            }
            if let typeName = facts.variableTypes[variable.name],
               !["Int", "Bool", "String", "TLAValue"].contains(typeName) {
                return """
                guard let rawValue = dict[\(key)] else {
                    throw TLAStateProjectionDiagnostic.missingRequiredValue(path: \(key), expected: "\(typeName)")
                }
                guard let value = \(typeName)(formalValue: rawValue) else {
                    throw TLAStateProjectionDiagnostic.typeMismatch(path: \(key), expected: "\(typeName)", actual: rawValue)
                }
                self.\(variable.name) = value
                """
            }
            let pattern = tlaValuePattern(forSwiftType: type, binding: "value")
            return """
            guard let rawValue = dict[\(key)] else {
                throw TLAStateProjectionDiagnostic.missingRequiredValue(path: \(key), expected: "\(type)")
            }
            guard \(pattern) else {
                throw TLAStateProjectionDiagnostic.typeMismatch(path: \(key), expected: "\(type)", actual: rawValue)
            }
            self.\(variable.name) = value
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
        actions: [NamedAction],
        collectionActions: [String: MacroCompilation.CollectionActionFact],
        symmetricCollections: [String: SymmetricCollectionDecl],
        facts: MacroSwiftFacts
    ) -> [FunctionDeclSyntax] {
        let identifiers = generatedActionIdentifiers(actions: actions)
        let methods = zip(actions, identifiers).map { action, identifier -> FunctionDeclSyntax in
            if action.bindings.isEmpty,
               let collectionAction = collectionActions[action.name],
               let collection = symmetricCollections[collectionAction.collectionName],
               let collectionFact = facts.symmetricCollections[collection.name] {
                let source = """
                @discardableResult
                \(isActor ? "fileprivate" : "public mutating") func \(identifier)(id: \(collectionFact.elementType).ID) throws -> TransitionResult {
                    let projection = \(collection.name).projection()
                    let targetKey: TLAValue
                    do {
                        targetKey = try projection.key(for: id, collection: "\(collection.name)", action: "\(action.name)")
                    } catch {
                        throw GeneratedMachineError.unexpected(error)
                    }
                    let formalState = try _stateWithLiveCollections()
                    guard let token = TLAStateProjection.Token(validating: Variables.\(collection.name).rawValue),
                          case .function(let originalValues) = formalState.value(for: token) else {
                        throw GeneratedMachineError.stateDecodingFailed(.missingRequiredValue(
                            path: Variables.\(collection.name).rawValue,
                            expected: "a formal collection function"
                        ))
                    }
                    let evidence = try _machine.apply(.init(name: "\(action.name)"), from: formalState) { candidate in
                        guard case .function(let candidateValues) = candidate.value(for: token),
                              candidateValues[targetKey] != nil else { return false }
                        return candidateValues.allSatisfy { key, value in
                            key == targetKey || originalValues[key] == value
                        }
                    }
                    guard case .function(let nextValues) = evidence.after.\(collection.name),
                          let nextFormalValue = nextValues[targetKey],
                          let nextValue = \(collectionFact.valueType)(formalValue: nextFormalValue) else {
                        throw GeneratedMachineError.stateDecodingFailed(.typeMismatch(
                            path: Variables.\(collection.name).rawValue,
                            expected: "\(collectionFact.valueType)",
                            actual: evidence.after.\(collection.name)
                        ))
                    }
                    do {
                        try \(collection.name).update(id: id, to: nextValue, action: "\(action.name)")
                    } catch {
                        throw GeneratedMachineError.unexpected(error)
                    }
                    return TransitionResult(
                        action: .\(identifier),
                        before: evidence.before,
                        after: evidence.after
                    )
                }
                """
                return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
            }
            let bindings = publicBindings(for: action)
            let parameters = bindings.map { binding in
                "\(binding.name): \(swiftType(for: action, binding: binding, facts: facts))"
            }.joined(separator: ", ")
            let labels = bindings.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
            let methodName = isActor ? "_\(identifier)" : "apply\(identifier)"
            if bindings.isEmpty {
                let source = """
                \(isActor ? "fileprivate" : "public mutating") func \(methodName)() throws -> TransitionResult {
                    try apply(.\(identifier))
                }
                """
                return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
            }
            let modifier = isActor ? "fileprivate" : "public mutating"
            let source = """
            \(modifier) func \(methodName)(\(parameters)) throws -> TransitionResult {
                try apply(.\(identifier)\(labels.isEmpty ? "" : "(\(labels))"))
            }
            """
            return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
        }
        return methods
    }

    static func generateCollectionRuntimeMembers(
        _ collections: [SymmetricCollectionDecl],
        facts: MacroSwiftFacts
    ) -> [DeclSyntax] {
        var declarations = collections.compactMap { collection -> DeclSyntax? in
            guard let fact = facts.symmetricCollections[collection.name] else { return nil }
            DeclSyntax(stringLiteral: """
            public var \(collection.name) = IdentifiedModelCollection<\(fact.elementType), \(fact.valueType)>(
                name: \"\(collection.name)\",
                verificationScope: \(collection.verificationScope),
                initial: \(literalExpr(for: collection.initial))
            )
            """)
        }
        guard !collections.isEmpty else { return declarations }
        let scopes = collections.map {
            "SymmetricCollectionScope(collectionName: \"\($0.name)\", verificationScope: \($0.verificationScope))"
        }.joined(separator: ", ")
        declarations.append(DeclSyntax(stringLiteral: """
        public static let symmetricCollectionScopes: [SymmetricCollectionScope] = [\(scopes)]
        """))
        return declarations
    }

}
