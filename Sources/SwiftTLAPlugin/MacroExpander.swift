import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

enum MacroExpander {
    static func generate(mode: GenerationMode, model: ParsedMacroModel) -> [DeclSyntax] {
        switch mode {
        case .model, .actor:
            return generateStateMachineMembers(isActor: mode == .actor, model: model)
        case .observable:
            return generateObservableMembers(
                typeName: model.typeName,
                variables: model.variables,
                actions: model.actions,
                enumInfos: model.enumInfos
            )
        }
    }

    // MARK: - State machine code generation (model / actor)

    static func generateStateMachineMembers(isActor: Bool, model: ParsedMacroModel) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        decls.append(DeclSyntax(stringLiteral: """
        private var _machine = CanonicalMachine(
            runtime: \(model.typeName).runtime,
            initial: State(from: \(model.typeName).runtime.initialStates().first!),
            stateDictionary: { $0.asDictionary },
            snapshotFromDictionary: { State(from: $0) }
        )
        """))

        decls.append(DeclSyntax(generateVariablesEnum(variables: model.variables)))
        if !model.actions.isEmpty {
            decls.append(DeclSyntax(generateActionsEnum(actions: model.actions)))
            decls.append(DeclSyntax(generateActionLabel(actions: model.actions)))
        }
        decls.append(DeclSyntax(generateStateStruct(variables: model.variables, enumInfos: model.enumInfos)))
        decls.append(contentsOf: generateCanonicalMachineMembers(
            isActor: isActor,
            hasActions: !model.actions.isEmpty,
            symmetricCollections: model.symmetricCollections
        ))
        decls.append(contentsOf: generateCollectionRuntimeMembers(model.symmetricCollections))
        let ordinaryVariables = model.variables.filter { variable in
            !model.symmetricCollections.contains(where: { $0.name == variable.name })
        }
        decls.append(contentsOf: generateVariableProperties(variables: ordinaryVariables).map(DeclSyntax.init))
        let actionResult = generateActionMethods(
            isActor: isActor,
            actions: model.actions,
            collectionActions: model.collectionActions,
            symmetricCollections: model.symmetricCollections,
            variables: model.variables,
            enumInfos: model.enumInfos
        )
        decls.append(contentsOf: actionResult.methods.map(DeclSyntax.init))
        _ = actionResult.nativeActionNames
        decls.append(contentsOf: generateParserTreeCheck(model: model))
        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "runtime"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "SpecRuntime")),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "_checkParserTree(); return SpecRuntime(spec: spec)") }
                    ))
                )]
            )
        ))

        decls.append(contentsOf: generateSpecTest())
        if !isActor {
            decls.append(DeclSyntax(stringLiteral: """
            public static func generatedActionOutcome(
                actionName: String,
                in state: [String: TLAValue]
            ) -> SpecRuntime.RuntimeActionOutcome {
                Self.runtime.actionOutcome(named: actionName, in: state)
            }
            """))
            decls.append(DeclSyntax(stringLiteral: """
            public static func generatedPropertyOutcomes(
                in state: [String: TLAValue]
            ) -> [SpecRuntime.RuntimePropertyOutcome] {
                Self.runtime.propertyOutcomes(in: state)
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

    static func generateParserTreeCheck(model: ParsedMacroModel) -> [DeclSyntax] {
        let treeVars = model.variables.map { v in
            "(\"\(v.name)\", \(codegenTLAValue(v.initial)))"
        }.joined(separator: ", ")

        let treeActions = model.actions.map { a in
            let bindings = a.bindings.map {
                "ActionBinding(name: \"\($0.name)\", values: [\($0.values.map(codegenTLAValue).joined(separator: ", "))])"
            }.joined(separator: ", ")
            return "(\"\(a.name)\", \(codegenActionExpr(a.body)), [\(bindings)])"
        }.joined(separator: ", ")

        let treeInvs = model.invariants.map { i in
            "(\"\(i.0)\", \(codegenStateExpr(i.1)))"
        }.joined(separator: ", ")

        let parserTreeSource = """
        static let _parserTree: ParsedSpecModel = ParsedSpecModel(
            variables: [\(treeVars)],
            actions: [\(treeActions)],
            invariants: [\(treeInvs)]
        )
        """
        let checkerSource = """
        static func _checkParserTree() {
            let builtSpec = Self.spec
            let built = ParsedSpecModel(
                variables: builtSpec.variables.map { ($0.name, $0.initial) },
                actions: builtSpec.actions.map { ($0.name, $0.body, $0.bindings) },
                invariants: builtSpec.invariants.map { ($0.name, $0.body) }
            )
            if built != _parserTree {
                print("⚠ SpecParser tree mismatch")
            }
        }
        """
        return [DeclSyntax(stringLiteral: parserTreeSource), DeclSyntax(stringLiteral: checkerSource)]
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
        case .tupleLiteral(let es): return "StateExpr.tupleLiteral([\(es.map(cg).joined(separator: ", "))])"
        case .recordLiteral(let fs):
            let fields = fs.map { "\"\($0.key)\": \(cg($0.value))" }.joined(separator: ", ")
            return "StateExpr.recordLiteral([\(fields)])"
        case .setLiteral(let es): return "StateExpr.setLiteral([\(es.map(cg).joined(separator: ", "))])"
        case .functionLiteral(let d, let qv, let b): return "StateExpr.functionLiteral(\(cg(d)), \"\(qv)\", \(cg(b)))"
        case .caseExpr(let ps, let fb):
            let patterns = ps.map(cg).joined(separator: ", ")
            let fallback = fb.map { cg($0) } ?? "nil"
            return "StateExpr.caseExpr([\(patterns)], \(fallback))"
        case .forAll, .exists, .choose, .sequenceFromSet, .setSum, .functionSet,
             .recursiveCall, .enabledAction:
            return "StateExpr.value(.int(0))"
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

    static func generateVariablesEnum(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)]) -> EnumDeclSyntax {
        EnumDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: "Variables",
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeListSyntax {
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "String"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "CaseIterable"))
                }
            },
            memberBlock: MemberBlockSyntax {
                for v in variables {
                    EnumCaseDeclSyntax { EnumCaseElementSyntax(name: .identifier(v.name)) }
                }
            }
        )
    }

    static func generateActionsEnum(actions: [SpecParser.ParsedAction]) -> EnumDeclSyntax {
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
                for a in actions {
                    EnumCaseDeclSyntax {
                        EnumCaseElementSyntax(
                            name: .identifier(a.name),
                            rawValue: InitializerClauseSyntax(value: StringLiteralExprSyntax(content: a.name))
                        )
                    }
                }
            }
        )
    }

    static func generateActionLabel(actions: [SpecParser.ParsedAction]) -> DeclSyntax {
        func swiftType(for binding: ActionBinding) -> String {
            Self.swiftType(for: binding.values[0])
        }

        func argumentConstructor(for binding: ActionBinding) -> String {
            tlaValueConstructor(for: swiftType(for: binding), value: binding.name)
        }

        func invocationPattern(for binding: ActionBinding, index: Int) -> String {
            let argument = "invocation.arguments[\(index)]"
            switch swiftType(for: binding) {
            case "Int": return "case .int(let \(binding.name)) = \(argument)"
            case "Bool": return "case .bool(let \(binding.name)) = \(argument)"
            case "String": return "case .string(let \(binding.name)) = \(argument)"
            case "TLAValue": return "let \(binding.name) = \(argument)"
            default:
                return "case .string(let \(binding.name)Raw) = \(argument), "
                    + "let \(binding.name) = \(swiftType(for: binding))(rawValue: \(binding.name)Raw)"
            }
        }

        let cases = actions.map { action in
            guard !action.bindings.isEmpty else { return "case \(action.name)" }
            let parameters = action.bindings.map { "\($0.name): \(swiftType(for: $0))" }.joined(separator: ", ")
            return "case \(action.name)(\(parameters))"
        }.joined(separator: "\n    ")

        let toInvocationCases = actions.map { action in
            let arguments = action.bindings.map(argumentConstructor).joined(separator: ", ")
            let pattern = action.bindings.isEmpty
                ? ".\(action.name)"
                : ".\(action.name)(\(action.bindings.map { "let \($0.name)" }.joined(separator: ", ")))"
            return "case \(pattern): return .init(name: \"\(action.name)\", arguments: [\(arguments)])"
        }.joined(separator: "\n        ")

        let fromInvocationCases = actions.map { action in
            if action.bindings.isEmpty {
                return "case \"\(action.name)\" where invocation.arguments.isEmpty: self = .\(action.name)"
            }
            let patterns = action.bindings.enumerated().map { invocationPattern(for: $0.element, index: $0.offset) }.joined(separator: ", ")
            let arguments = action.bindings.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
            return "case \"\(action.name)\" where invocation.arguments.count == \(action.bindings.count): "
                + "guard \(patterns) else { return nil }; self = .\(action.name)(\(arguments))"
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
    static func generateStateStruct(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)], enumInfos: [ParsedEnumInfo] = []) -> StructDeclSyntax {
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
                                type: IdentifierTypeSyntax(name: .identifier(stateType(for: v, enumInfos: enumInfos)))
                            )
                        )]
                    )
                }
                InitializerDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax {
                            FunctionParameterSyntax(
                                firstName: "from", secondName: "dict",
                                type: TypeSyntax(stringLiteral: "[String: TLAValue]")
                            )
                        }
                    ),
                    body: CodeBlockSyntax {
                        for v in variables {
                if let typeName = v.swiftTypeName,
                   let info = enumInfos.first(where: { $0.typeName == typeName }) {
                    let caseLines = info.cases.map { c in
                        "case \"\(c.name)\": return \(typeName).\(c.name)"
                    }.joined(separator: "\n                    ")
                    ExprSyntax(stringLiteral: """
                    self.\(v.name) = {
                        guard case .string(let s) = dict[Variables.\(v.name).rawValue] else { fatalError("Invalid enum value for \(v.name)") }
                        switch s {
                        \(caseLines)
                        default: fatalError("Unknown \(typeName): \\(s)")
                        }
                    }()
                    """)
                } else if let typeName = v.swiftTypeName,
                          !["Int", "Bool", "String", "TLAValue"].contains(typeName) {
                    ExprSyntax(stringLiteral:
                        "self.\(v.name) = \(typeName)(rawValue: "
                            + "dict[Variables.\(v.name).rawValue]!.\(extractor(for: v.initial)))!"
                    )
                } else {
                    let st = stateType(for: v, enumInfos: enumInfos)
                    if st == "TLAValue" {
                        ExprSyntax(stringLiteral: "self.\(v.name) = dict[Variables.\(v.name).rawValue]!")
                    } else {
                        let extractor = v.swiftTypeName.map(extractor(forSwiftType:)) ?? extractor(for: v.initial)
                        ExprSyntax(stringLiteral: "self.\(v.name) = dict[Variables.\(v.name).rawValue]!.\(extractor)")
                    }
                }
                        }
                    }
                )
                VariableDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    bindingSpecifier: .keyword(.var),
                    bindings: [PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: "asDictionary"),
                        typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "[String: TLAValue]")),
                        accessorBlock: AccessorBlockSyntax(accessors: .getter(
                            CodeBlockItemListSyntax {
                                DeclSyntax(stringLiteral: "var d: [String: TLAValue] = [:]")
                                for v in variables {
                                    let st = stateType(for: v, enumInfos: enumInfos)
                                    if v.swiftTypeName != nil && enumInfos.contains(where: { $0.typeName == v.swiftTypeName }) {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = .string(String(describing: \(v.name)))")
                                    } else if st == "TLAValue" {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(v.name)")
                                    } else if ["Int", "Bool", "String"].contains(st) {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(constructor(forSwiftType: st, value: v.name))")
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

    static func generateVariableProperties(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)]) -> [VariableDeclSyntax] {
        variables.map { v in
            let inferred = v.swiftTypeName ?? swiftType(for: v.initial)
            let propType = ["Int", "Bool", "String"].contains(inferred) ? inferred : "TLAValue"
            return VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(propType))),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "_machine.snapshot.\(v.name)") }
                    ))
                )]
            )
        }
    }

    static func generateActionMethods(
        isActor: Bool = false,
        actions: [SpecParser.ParsedAction],
        collectionActions: [SpecParser.ParsedCollectionAction],
        symmetricCollections: [SpecParser.ParsedSymmetricCollection],
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> (methods: [FunctionDeclSyntax], nativeActionNames: Set<String>) {
        let methods = actions.map { action -> FunctionDeclSyntax in
            if action.bindings.isEmpty,
               let collectionAction = collectionActions.first(where: { $0.name == action.name }),
               let collection = symmetricCollections.first(where: { $0.name == collectionAction.collectionName }) {
               let liveBranches = collectionAction.runtimeBranches.map { branch in
                    let condition = branch.guardExpressions.isEmpty
                        ? "true"
                        : branch.guardExpressions.map {
                            "(\($0.replacingOccurrences(of: "_state.", with: "beforeState.")))"
                        }.joined(separator: " && ")
                    let update = branch.updateExpression.map { expression in
                        """
                        let projectedValue = \(expression)
                        let evidence = try _machine.apply(.init(name: \"\(action.name)\"), from: _stateWithLiveCollections()) { candidate in
                            guard case .function(let values) = candidate[Variables.\(collection.name).rawValue] else { return false }
                            return values[targetKey] == projectedValue.tlaValue
                        }
                        do {
                            try \(collection.name).update(id: id, to: projectedValue, action: \"\(action.name)\")
                        } catch {
                            throw GeneratedMachineError.unexpected(error)
                        }
                        return TransitionEvidence(
                            label: .\(action.name),
                            invocation: .init(name: "\(action.name)"),
                            before: evidence.before.asDictionary,
                            after: evidence.after.asDictionary
                        )
                        """
                    } ?? """
                    let evidence = try _machine.apply(.init(name: \"\(action.name)\"), from: _stateWithLiveCollections()) { _ in true }
                    return TransitionEvidence(
                        label: .\(action.name),
                        invocation: .init(name: "\(action.name)"),
                        before: evidence.before.asDictionary,
                        after: evidence.after.asDictionary
                    )
                    """
                    return """
                    if \(condition) {
                        \(update)
                    }
                    """
               }.joined(separator: "\n")
                let beforeState = collectionAction.runtimeBranches
                    .flatMap(\.guardExpressions)
                    .contains { $0.contains("_state.") }
                    ? "let beforeState = _machine.snapshot"
                    : ""
                let source = """
                @discardableResult
                \(isActor ? "fileprivate" : "public mutating") func \(action.name)(id: \(collection.elementType).ID) throws -> TransitionEvidence {
                    let projection = \(collection.name).projection()
                    let targetKey: TLAValue
                    do {
                        targetKey = try projection.key(for: id, collection: "\(collection.name)", action: "\(action.name)")
                    } catch {
                        throw GeneratedMachineError.unexpected(error)
                    }
                    let entry: IdentifiedModelCollection<\(collection.elementType), \(collection.valueType)>.Entry
                    do {
                        entry = try \(collection.name).entry(for: id, action: "\(action.name)")
                    } catch {
                        throw GeneratedMachineError.unexpected(error)
                    }
                    \(beforeState)
                    \(liveBranches)
                    throw GeneratedMachineError.runtime(.actionNotEnabled(.init(name: "\(action.name)"), available: []))
                }
                """
                return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
            }
            let parameters = action.bindings.map { binding in
                "\(binding.name): \(swiftType(for: binding.values[0]))"
            }.joined(separator: ", ")
            let labels = action.bindings.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
            let methodName = isActor ? "_\(action.name)" : "apply\(action.name)"
            if action.bindings.isEmpty {
                let source = """
                \(isActor ? "fileprivate" : "public mutating") func \(methodName)() throws -> TransitionEvidence {
                    try apply(.\(action.name))
                }
                """
                return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
            }
            let modifier = isActor ? "fileprivate" : "public mutating"
            let source = """
            \(modifier) func \(methodName)(\(parameters)) throws -> TransitionEvidence {
                try apply(.\(action.name)\(labels.isEmpty ? "" : "(\(labels))"))
            }
            """
            return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
        }
        return (methods, [])
    }

    static func generateCollectionRuntimeMembers(
        _ collections: [SpecParser.ParsedSymmetricCollection]
    ) -> [DeclSyntax] {
        var declarations = collections.map { collection in
            DeclSyntax(stringLiteral: """
            public var \(collection.name) = IdentifiedModelCollection<\(collection.elementType), \(collection.valueType)>(
                name: \"\(collection.name)\",
                verificationScope: \(collection.verificationScope),
                initial: \(literalExpr(for: collection.declaration.initial))
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
