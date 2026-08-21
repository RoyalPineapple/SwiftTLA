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

        decls.append(DeclSyntax(stringLiteral: "public typealias Simulation = Self"))

        decls.append(DeclSyntax(stringLiteral: "private var _machine: CanonicalMachine<State>"))
        decls.append(DeclSyntax(stringLiteral: """
        private init(machine: CanonicalMachine<State>) {
            _machine = machine
        }
        """))

        if !plan.actions.isEmpty {
            decls.append(contentsOf: generateActionLabel(actions: plan.actions))
            decls.append(DeclSyntax(stringLiteral: """
            private func _actionExecutor() -> CompiledActionExecutor<ActionLabel> {
                .init(
                    compilation: _machine.compilation,
                    actionOrdinal: { Self._actionOrdinal(for: $0) },
                    arguments: { Self._actionArguments(for: $0) },
                    label: { Self._actionLabel(actionAt: $0, arguments: $1) }
                )
            }
            """))
        }
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
                snapshotFromProjection: { try State(projection: $0) }
            ))
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
        let expectedSchema = model.machineSurface.schemaIdentifier
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
                let executor = CompiledActionExecutor(
                    compilation: try Self.compiledSpecification(),
                    actionOrdinal: { Self._actionOrdinal(for: $0) },
                    arguments: { Self._actionArguments(for: $0) },
                    label: { Self._actionLabel(actionAt: $0, arguments: $1) }
                )
                return try executor.successors(for: action, from: projection).map { target in
                    _ = try State(projection: target)
                    return target
                }
            }
            """
        }
        let compilationSource = """
        static let _expectedCompilationIdentity = \"\(expectedIdentity)\"
        static let _expectedMachineSchemaIdentifier = \"\(expectedSchema)\"
        public static let generatedMachineMetadata: GeneratedMachineMetadata = \(metadata)
        private static func _machineSurfacePlan(
            _ compilation: CompiledSpecification
        ) throws -> MachineSurfacePlan {
            let plan = try MachineSurfacePlan(compilation: compilation, swiftFacts: \(facts))
            guard plan.schemaIdentifier == _expectedMachineSchemaIdentifier,
                  plan.metadata == generatedMachineMetadata else {
                throw GeneratedMachineContractDiagnostic(
                    code: .schemaMismatch,
                    path: "generatedMachineMetadata",
                    expected: _expectedMachineSchemaIdentifier,
                    actual: plan.schemaIdentifier,
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
            let plan = try _machineSurfacePlan(compilation)
            guard compilation.identity == plan.compilationIdentity,
                  plan.schemaIdentifier == _expectedMachineSchemaIdentifier,
                  generatedMachineMetadata.compilationIdentity.value == _expectedCompilationIdentity,
                  generatedMachineMetadata.schemaIdentifier == _expectedMachineSchemaIdentifier else {
                throw GeneratedMachineContractDiagnostic(
                    code: .schemaMismatch,
                    path: \"generatedMachineMetadata\",
                    expected: _expectedMachineSchemaIdentifier,
                    actual: plan.schemaIdentifier,
                    nextSafeAction: \"Compile the model from its current source.\"
                )
            }
            return compilation
        }
        public static func verifyGeneratedMachineContract(
            metadata: GeneratedMachineMetadata? = nil,
            verificationStateLimit: Int? = nil
        ) -> GeneratedMachineContractReport {
            do {
                let compilation = try compiledSpecification()
                return GeneratedMachineContractVerifier.verify(
                    compilation: compilation,
                    plan: try _machineSurfacePlan(compilation),
                    metadata: metadata ?? generatedMachineMetadata,
                    expectedSchemaIdentifier: _expectedMachineSchemaIdentifier,
                    verificationStateLimit: verificationStateLimit ?? Self.verificationStateLimit,
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
        private static func _verifiedGeneratedMachineContract() throws -> GeneratedMachineContractReport {
            let report = verifyGeneratedMachineContract()
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
        return ".init(compilationIdentity: .init(value: \(quoted(plan.compilationIdentity.value))), schemaIdentifier: \(quoted(plan.schemaIdentifier)), variables: [\(variables)], actions: [\(actions)])"
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
        case .weakFairnessNext: return ".weakFairnessNext"
        case .strongFairnessNext: return ".strongFairnessNext"
        case .weakFairnessActionCall(let action):
            return ".weakFairnessActionCall(\(codegenActionCall(action)))"
        case .strongFairnessActionCall(let action):
            return ".strongFairnessActionCall(\(codegenActionCall(action)))"
        }
    }

    static func codegenActionCall(_ action: FormalActionCall) -> String {
        ".init(name: \"\(action.name)\", arguments: [\(action.arguments.map(codegenTLAValue).joined(separator: ", "))])"
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

    static func codegenStateExpr(_ expr: StateExpr) -> String {
        func cg(_ e: StateExpr) -> String { codegenStateExpr(e) }
        switch expr {
        case .variable(let v): return "StateExpr.variable(\"\(v)\")"
        case .value(let v): return "StateExpr.value(\(codegenTLAValue(v)))"
        case .programCounter: return "StateExpr.programCounter"
        case .controlLocation(let reference): return "StateExpr.controlLocation(.init(\(String(reflecting: reference.sourceName))))"
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
            let fields = fs.fields.map { "\"\($0.name)\": \(cg($0.value))" }.joined(separator: ", ")
            return "StateExpr.record([\(fields)])"
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

    static func generateActionLabel(actions: [MachineSurfacePlan.Action]) -> [DeclSyntax] {
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

        func invocationPattern(for binding: MachineSurfacePlan.Binding, index: Int) -> String {
            let argument = "invocation.arguments[\(index)]"
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
                    return invocationPattern(for: binding, index: index)
                        .replacingOccurrences(of: "invocation.arguments", with: "arguments")
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
        private static func _actionArguments(for action: ActionLabel) -> [TLAValue] {
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
                        using: _actionExecutor(),
                        from: formalState
                    ) { candidate in
                        guard case .function(let candidateValues) = candidate.value(for: token),
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
                    do {
                        try \(collection.formalName).update(id: id, to: nextValue, action: "\(action.formalName)")
                    } catch {
                        throw error
                    }
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
            public var \(collection.formalName) = IdentifiedModelCollection<\(collection.elementType), \(collection.valueType)>(
                name: \"\(collection.formalName)\",
                verificationScope: \(collection.verificationScope),
                initial: \(literalExpr(for: collection.initial))
            )
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
