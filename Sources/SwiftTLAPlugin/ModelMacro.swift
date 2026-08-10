import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

// MARK: - Shared parsing and verification

struct ParsedEnumInfo {
    let typeName: String
    let cases: [(name: String, value: TLAValue)]
    init(typeName: String, cases: [(String, TLAValue)]) {
        self.typeName = typeName
        self.cases = cases
    }
    var domain: Set<TLAValue> { Set(cases.map(\.value)) }
}

struct ParsedMacroModel {
    let typeName: String
    let variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)]
    let actions: [(String, ActionExpr)]
    let symmetricCollections: [SpecParser.ParsedSymmetricCollection]
    let collectionActions: [SpecParser.ParsedCollectionAction]
    let enumInfos: [ParsedEnumInfo]
    let hasInvariants: Bool
}

enum TLASpecVerifier {
    typealias EnumPhaseMap = [String: [String: TLAValue]]

    static func parseAndVerify(_ declaration: some DeclGroupSyntax) throws -> ParsedMacroModel {
        let typeName: String
        let memberList: MemberBlockItemListSyntax

        if let s = declaration.as(StructDeclSyntax.self) {
            typeName = s.name.text; memberList = s.memberBlock.members
        } else if let c = declaration.as(ClassDeclSyntax.self) {
            typeName = c.name.text; memberList = c.memberBlock.members
        } else if let a = declaration.as(ActorDeclSyntax.self) {
            typeName = a.name.text; memberList = a.memberBlock.members
        } else {
            throw SimpleError("Must be applied to a struct, class, or actor")
        }

        guard let closure = Self.findSpec(in: memberList) else {
            throw SimpleError("Could not find 'TLASpec' builder in '\(typeName)'")
        }

        let rewritten = rewriteVarNames(in: closure)
        let (enumPhases, caseToType) = collectEnumPhaseMap(from: memberList)
        let rewriter = EnumDotRewriter(caseToType: caseToType)
        let dotRewrittenSyntax = rewriter.rewrite(rewritten)
        let dotRewritten = dotRewrittenSyntax.as(ClosureExprSyntax.self) ?? rewritten
        if let unknown = rewriter.unknownDots.first {
            let allCases = caseToType.keys.sorted().joined(separator: ", ")
            throw SimpleError("Unknown enum case '.\(unknown)'. Available cases: [\(allCases)]")
        }
        let parsed = SpecParser.parseSpecClosure(dotRewritten, enumPhases: enumPhases)
        if let diagnostic = parsed.diagnostics.first {
            throw diagnostic
        }
        if parsed.variables.isEmpty { throw SimpleError("No variables in spec") }

        let enumInfos = Self.collectEnumStateVars(from: memberList)

        var allInvariants = parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) }
        for variable in parsed.variables {
            if let swiftTypeName = variable.swiftTypeName,
               let enumInfo = enumInfos.first(where: { $0.typeName == swiftTypeName }) {
                let domainValues = TLAValue.sorted(enumInfo.domain)
                let invariantName = "\(variable.name)InDomain"
                let body = StateExpr.in(.variable(variable.name),
                                         .setLiteral(domainValues.map { .value($0) }))
                allInvariants.append(NamedInvariant(name: invariantName, body: body))
            }
        }

        let spec = TLASpec(
            name: typeName,
            variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
            constants: parsed.constants,
            actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body) },
            invariants: allInvariants,
            temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) },
            fairness: parsed.fairness,
            symmetricCollections: parsed.symmetricCollections.map(\.declaration)
        )

        let result = try ModelChecker(spec: spec, maxStates: 1_000_000).check()
        switch result {
        case .invariantViolated(let inv, _, let trace):
            throw SimpleError("Invariant '\(inv)' violated:\n\(trace.map(String.init(describing:)).joined(separator: "\n"))")
        case .error(let msg): throw SimpleError("Checker error: \(msg)")
        case .deadlocked(let s): throw SimpleError("Deadlock at: \(s)")
        case .depthExceeded(let c, let l): throw SimpleError("Depth exceeded: \(c)/\(l)")
        case .livenessViolated(let msg): throw SimpleError("Liveness violated: \(msg)")
        case .ok: SpecRegistry.register(spec)
        case .bounded(_, let outcome):
            guard case .ok = outcome else {
                throw SimpleError("Checker error: \(outcome)")
            }
            SpecRegistry.register(spec)
        }

        let hasInvs = !allInvariants.isEmpty

        return ParsedMacroModel(
            typeName: typeName,
            variables: parsed.variables,
            actions: parsed.actions,
            symmetricCollections: parsed.symmetricCollections,
            collectionActions: parsed.collectionActions,
            enumInfos: enumInfos,
            hasInvariants: hasInvs
        )
    }

    // MARK: - Var name injection

    private static func rewriteVarNames(in closure: ClosureExprSyntax) -> ClosureExprSyntax {
        var newStatements: [CodeBlockItemSyntax] = []
        for item in closure.statements {
            newStatements.append(rewriteVarBinding(in: item))
        }
        return closure.with(\.statements, CodeBlockItemListSyntax(newStatements))
    }

    private static func rewriteVarBinding(in item: CodeBlockItemSyntax) -> CodeBlockItemSyntax {
        guard case .decl(let decl) = item.item,
              let varDecl = decl.as(VariableDeclSyntax.self)
        else { return item }

        var bindingsChanged = false
        var newBindings: [PatternBindingSyntax] = []
        for binding in varDecl.bindings {
            guard let patternName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let initializer = binding.initializer,
                  let fc = initializer.value.as(FunctionCallExprSyntax.self)
            else { newBindings.append(binding); continue }

            let callee = fc.calledExpression
            let baseName = callee.as(DeclReferenceExprSyntax.self)?.baseName.text
                ?? callee.as(GenericSpecializationExprSyntax.self)?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
            let isVar = baseName == "Var"
            let isValue = baseName == "Value"
            let isStateVar = baseName == "StateVar"

            if isStateVar || isVar {
                if let firstArg = fc.arguments.first,
                   let label = firstArg.label?.text,
                   label == "in" || label == "values" {
                    let hasNameArg = fc.arguments.contains { $0.label?.text == "name" }
                    if hasNameArg { newBindings.append(binding); continue }

                    var newArgs = fc.arguments
                    newArgs.append(LabeledExprSyntax(
                        label: "name",
                        colon: .colonToken(),
                        expression: StringLiteralExprSyntax(content: patternName)
                    ))
                    let newFC = fc.with(\.arguments, newArgs)
                    let newInit = initializer.with(\.value, ExprSyntax(newFC))
                    let newBinding = binding.with(\.initializer, newInit)
                    newBindings.append(newBinding)
                    bindingsChanged = true
                } else {
                    let hasStringArg = fc.arguments.contains { arg in
                        arg.label == nil && arg.expression.is(StringLiteralExprSyntax.self)
                    }
                    if hasStringArg { newBindings.append(binding); continue }

                    var newArgs = fc.arguments
                    newArgs.insert(LabeledExprSyntax(
                        expression: StringLiteralExprSyntax(content: patternName)
                    ), at: newArgs.startIndex)
                    let newFC = fc.with(\.arguments, newArgs)
                    let newInit = initializer.with(\.value, ExprSyntax(newFC))
                    let newBinding = binding.with(\.initializer, newInit)
                    newBindings.append(newBinding)
                    bindingsChanged = true
                }
                continue
            }

            guard isVar || isValue
            else { newBindings.append(binding); continue }

            let hasStringArg = fc.arguments.contains { arg in
                arg.label == nil && arg.expression.is(StringLiteralExprSyntax.self)
            }
            if hasStringArg { newBindings.append(binding); continue }

            let nameArg = LabeledExprSyntax(
                expression: StringLiteralExprSyntax(content: patternName)
            )
            var newArgs = fc.arguments
            if let firstArg = newArgs.first, firstArg.label?.text == "value" {
                newArgs.insert(nameArg, at: newArgs.startIndex)
            } else {
                newArgs.insert(nameArg, at: newArgs.startIndex)
            }

            let newFC = fc.with(\.arguments, newArgs)
            let newInit = initializer.with(\.value, ExprSyntax(newFC))
            let newBinding = binding.with(\.initializer, newInit)
            newBindings.append(newBinding)
            bindingsChanged = true
        }

        guard bindingsChanged else { return item }
        let newDecl = varDecl.with(\.bindings, PatternBindingListSyntax(newBindings))
        return item.with(\.item, .decl(DeclSyntax(newDecl)))
    }

    // MARK: - Helpers

    static func findSpec(in members: MemberBlockItemListSyntax) -> ClosureExprSyntax? {
        for member in members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "spec"
            else { continue }

            if let closure = binding.accessorBlock?.accessors.as(CodeBlockItemListSyntax.self) {
                for stmt in closure {
                    if case .expr(let e) = stmt.item,
                       let fc = e.as(FunctionCallExprSyntax.self),
                       fc.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLASpec" {
                        return fc.trailingClosure ?? fc.arguments.last?.expression.as(ClosureExprSyntax.self)
                    }
                }
            }
            if let accessors = binding.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) {
                for acc in accessors where acc.accessorSpecifier.tokenKind == .keyword(.get) {
                    for stmt in acc.body?.statements ?? [] {
                        if case .expr(let e) = stmt.item,
                           let fc = e.as(FunctionCallExprSyntax.self),
                           fc.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLASpec" {
                            return fc.trailingClosure ?? fc.arguments.last?.expression.as(ClosureExprSyntax.self)
                        }
                    }
                }
            }
        }
        return nil
    }

    static func collectEnumPhases(from members: MemberBlockItemListSyntax) -> [String: Int] {
        var result: [String: Int] = [:]
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self) else { continue }
            guard let inheritance = enumDecl.inheritanceClause,
                  inheritance.inheritedTypes.count == 1,
                  inheritance.inheritedTypes.first?.type.as(IdentifierTypeSyntax.self)?.name.text == "Int"
            else { continue }

            var idx = 0
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else { continue }
                for element in caseDecl.elements {
                    if let raw = element.rawValue?.value.as(IntegerLiteralExprSyntax.self),
                       let val = Int(raw.literal.text) {
                        result[element.name.text] = val
                        idx = val + 1
                    } else {
                        result[element.name.text] = idx
                        idx += 1
                    }
                }
            }
        }
        return result
    }

    static func collectEnumStateVars(from members: MemberBlockItemListSyntax) -> [ParsedEnumInfo] {
        var result: [ParsedEnumInfo] = []
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self) else { continue }
            guard let inheritance = enumDecl.inheritanceClause else { continue }

            let inheritedNames = inheritance.inheritedTypes.compactMap {
                $0.type.as(IdentifierTypeSyntax.self)?.name.text
            }

            guard inheritedNames.contains("TLAValueType") else { continue }

            let intBacked = inheritedNames.contains("Int")
            let stringBacked = inheritedNames.contains("String")
            guard intBacked || stringBacked else { continue }

            var cases: [(name: String, value: TLAValue)] = []
            var idx = 0
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else { continue }
                for element in caseDecl.elements {
                    let value: TLAValue
                    if let raw = element.rawValue?.value.as(IntegerLiteralExprSyntax.self),
                       let val = Int(raw.literal.text) {
                        value = .int(val)
                        idx = val + 1
                    } else if let raw = element.rawValue?.value.as(StringLiteralExprSyntax.self) {
                        value = .string(raw.representedLiteralValue ?? raw.segments.description)
                    } else if intBacked {
                        value = .int(idx)
                        idx += 1
                    } else {
                        value = .string(element.name.text)
                    }
                    cases.append((element.name.text, value))
                }
            }

            result.append(ParsedEnumInfo(
                typeName: enumDecl.name.text,
                cases: cases
            ))
        }
        return result
    }

    static func collectEnumPhaseMap(from members: MemberBlockItemListSyntax) -> (phases: EnumPhaseMap, caseToType: [String: String]) {
        let infos = collectEnumStateVars(from: members)
        var phases: EnumPhaseMap = [:]
        var caseToType: [String: String] = [:]
        for info in infos {
            var caseMap: [String: TLAValue] = [:]
            for (caseName, value) in info.cases {
                caseMap[caseName] = value
                caseToType[caseName] = info.typeName
            }
            phases[info.typeName] = caseMap
        }
        return (phases, caseToType)
    }
}

private final class EnumDotRewriter: SyntaxRewriter {
    let caseToType: [String: String]
    var unknownDots: [String] = []

    init(caseToType: [String: String]) {
        self.caseToType = caseToType
    }

    override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
        guard node.base == nil else { return super.visit(node) }
        let caseName = node.declName.baseName.text
        guard let enumType = caseToType[caseName] else {
            if isEnumCaseName(caseName) {
                unknownDots.append(caseName)
            }
            return super.visit(node)
        }
        let qualified = MemberAccessExprSyntax(
            base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(enumType))),
            period: node.period,
            declName: node.declName
        )
        return ExprSyntax(qualified)
    }

    private func isEnumCaseName(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        return first.isLowercase && !knownPropertyNames.contains(name)
    }

    private let knownPropertyNames: Set<String> = [
        "cardinality", "count", "isEmpty", "flattened", "subsets", "domain",
        "head", "tail", "stays", "zero", "max", "min", "default"
    ]
}

enum GenerationMode {
    case model
    case actor
    case observable
}

enum MacroExpander {
    static func generate(mode: GenerationMode, model: ParsedMacroModel) -> [DeclSyntax] {
        switch mode {
        case .model, .actor:
            return generateStateMachineMembers(isActor: mode == .actor, model: model)
        case .observable:
            return generateObservableMembers(
                variables: model.variables,
                actions: model.actions,
                enumInfos: model.enumInfos
            )
        }
    }

    // MARK: - State machine code generation (model / actor)

    private static func generateStateMachineMembers(isActor: Bool, model: ParsedMacroModel) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.private))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "_state"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "State")),
                    initializer: InitializerClauseSyntax(value: ExprSyntax(stringLiteral: "State(from: runtime.initialStates().first!)"))
                )]
            )
        ))

        decls.append(DeclSyntax(generateVariablesEnum(variables: model.variables)))
        decls.append(DeclSyntax(generateActionsEnum(actions: model.actions)))
        decls.append(DeclSyntax(generateStateStruct(variables: model.variables, enumInfos: model.enumInfos)))
        decls.append(contentsOf: generateCollectionRuntimeMembers(model.symmetricCollections))
        let ordinaryVariables = model.variables.filter { variable in
            !model.symmetricCollections.contains(where: { $0.name == variable.name })
        }
        decls.append(contentsOf: generateVariableProperties(variables: ordinaryVariables).map(DeclSyntax.init))
        decls.append(contentsOf: generateActionMethods(
            isActor: isActor,
            actions: model.actions,
            collectionActions: model.collectionActions,
            symmetricCollections: model.symmetricCollections
        ).map(DeclSyntax.init))
        decls.append(DeclSyntax(generateApplyHelper(symmetricCollections: model.symmetricCollections)))
        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "runtime"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "SpecRuntime")),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "SpecRuntime(spec: spec)") }
                    ))
                )]
            )
        ))

        decls.append(contentsOf: generateSpecTest())
        decls.append(contentsOf: generateTransitionMatrix())
        decls.append(contentsOf: generateTransitionsTest())
        if model.hasInvariants {
            decls.append(contentsOf: generateInvariantsTest())
        }

        return decls
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

    static func generateActionsEnum(actions: [(name: String, body: ActionExpr)]) -> EnumDeclSyntax {
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

    static func generateStateStruct(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)], enumInfos: [ParsedEnumInfo] = []) -> StructDeclSyntax {
        StructDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: "State",
            memberBlock: MemberBlockSyntax {
                for v in variables {
                    VariableDeclSyntax(
                        modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                        bindingSpecifier: .keyword(.var),
                        bindings: [PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                            typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(v.swiftTypeName ?? swiftType(for: v.initial))))
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
                            } else if let typeName = v.swiftTypeName {
                                ExprSyntax(stringLiteral: "self.\(v.name) = \(typeName)(rawValue: dict[Variables.\(v.name).rawValue]!.\(extractor(for: v.initial)))!")
                            } else {
                                ExprSyntax(stringLiteral: "self.\(v.name) = dict[Variables.\(v.name).rawValue]!.\(extractor(for: v.initial))")
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
                                    if v.swiftTypeName != nil && enumInfos.contains(where: { $0.typeName == v.swiftTypeName }) {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = .string(String(describing: \(v.name)))")
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
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(v.swiftTypeName ?? swiftType(for: v.initial)))),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "_state.\(v.name)") }
                    ))
                )]
            )
        }
    }

    static func generateActionMethods(
        isActor: Bool = false,
        actions: [(name: String, body: ActionExpr)],
        collectionActions: [SpecParser.ParsedCollectionAction],
        symmetricCollections: [SpecParser.ParsedSymmetricCollection]
    ) -> [FunctionDeclSyntax] {
        let visibility = isActor ? TokenSyntax.keyword(.fileprivate) : TokenSyntax.keyword(.public)
        return actions.map { a in
            if let collectionAction = collectionActions.first(where: { $0.name == a.name }),
               let collection = symmetricCollections.first(where: { $0.name == collectionAction.collectionName }) {
                let actionNotEnabled = "SymmetricCollectionRuntimeError.actionNotEnabled(collection: \"\(collection.name)\", action: \"\(a.name)\")"
                let liveBranches = collectionAction.runtimeBranches.map { branch in
                    let condition = branch.guardExpressions.isEmpty
                        ? "true"
                        : branch.guardExpressions.map { "(\($0))" }.joined(separator: " && ")
                    let update = branch.updateExpression.map {
                        "try \(collection.name).update(id: id, action: \"\(a.name)\") { entry in \($0) }"
                    } ?? ""
                    return """
                    if \(condition) {
                        \(update)
                        return
                    }
                    """
                }.joined(separator: "\n")
                let source = """
                \(isActor ? "fileprivate" : "public mutating") func \(a.name)(id: \(collection.elementType).ID) throws {
                    let entry = try \(collection.name).entry(for: id, action: "\(a.name)")
                    \(liveBranches)
                    throw \(actionNotEnabled)
                }
                """
                return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
            }
            return FunctionDeclSyntax(
                modifiers: isActor
                    ? [DeclModifierSyntax(name: visibility)]
                    : [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.mutating))],
                name: isActor ? .identifier("_\(a.name)") : .identifier("apply\(a.name)"),
                signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: [])),
                body: CodeBlockSyntax { ExprSyntax(stringLiteral: "_state = _apply(.\(a.name))") }
            )
        }
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

    static func generateApplyHelper(
        symmetricCollections: [SpecParser.ParsedSymmetricCollection] = []
    ) -> FunctionDeclSyntax {
        if symmetricCollections.isEmpty {
            return FunctionDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.private))],
                name: "_apply",
                signature: FunctionSignatureSyntax(
                    parameterClause: FunctionParameterClauseSyntax {
                        FunctionParameterSyntax(
                            firstName: "_", secondName: "action",
                            type: IdentifierTypeSyntax(name: "Actions")
                        )
                    },
                    returnClause: ReturnClauseSyntax(type: IdentifierTypeSyntax(name: "State"))
                ),
                body: CodeBlockSyntax {
                    ExprSyntax(stringLiteral: """
                    guard let next = try? Self.runtime.apply(
                        actionName: action.rawValue,
                        to: _state.asDictionary
                    ) else { return _state }
                    """)
                    StmtSyntax(stringLiteral: "return State(from: next)")
                }
            )
        }
        let liveStateProjection = symmetricCollections.map { collection in
            """
            liveState[Variables.\(collection.name).rawValue] = \(collection.name).projectedModelValue(
                preserving: boundedState[Variables.\(collection.name).rawValue]!.functionValue.keys.sorted()
            )
            """
        }.joined(separator: "\n")
        let boundedStateRestoration = symmetricCollections.map { collection in
            "next[Variables.\(collection.name).rawValue] = boundedState[Variables.\(collection.name).rawValue]"
        }.joined(separator: "\n")
        return FunctionDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.private))],
            name: "_apply",
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax {
                    FunctionParameterSyntax(
                        firstName: "_", secondName: "action",
                        type: IdentifierTypeSyntax(name: "Actions")
                    )
                },
                returnClause: ReturnClauseSyntax(type: IdentifierTypeSyntax(name: "State"))
            ),
            body: CodeBlockSyntax {
                ExprSyntax(stringLiteral: """
                let boundedState = _state.asDictionary
                var liveState = boundedState
                \(liveStateProjection)
                guard var next = try? Self.runtime.apply(
                    actionName: action.rawValue,
                    to: liveState
                ) else { return _state }
                \(boundedStateRestoration)
                """)
                StmtSyntax(stringLiteral: "return State(from: next)")
            }
        )
    }

    // MARK: - Spec verification code generation

    static func generateSpecTest() -> [DeclSyntax] {
        [DeclSyntax(stringLiteral: """
        public struct _VerificationError: Error, CustomStringConvertible {
            public let description: String
            public init(_ description: String) { self.description = description }
        }
        """),
        DeclSyntax(stringLiteral: """
        public static func verifySpec() throws {
            let result = try ModelChecker(spec: Self.spec, maxStates: 100_000).check()
            switch result {
            case .ok(let count):
                guard count > 0 else { throw _VerificationError("No states found") }
            case .bounded(_, let outcome):
                switch outcome {
                case .ok(let count):
                    guard count > 0 else { throw _VerificationError("No states found") }
                default:
                    throw _VerificationError("Spec verification failed: \\(result)")
                }
            default:
                throw _VerificationError("Spec verification failed: \\(result)")
            }
        }
        """)]
    }

    static func generateTransitionMatrix() -> [DeclSyntax] {
        [DeclSyntax(stringLiteral: """
        public static func transitionMatrix() throws -> [(from: [String: TLAValue], action: String, to: [String: TLAValue])] {
            let graph = try ModelChecker(spec: Self.spec, maxStates: 100_000).exploreGraph()
            var matrix: [(from: [String: TLAValue], action: String, to: [String: TLAValue])] = []
            for (fromID, transitions) in graph.transitions {
                guard let fromState = graph.states[fromID] else { continue }
                for t in transitions {
                    guard let toState = graph.states[t.target] else { continue }
                    matrix.append((from: fromState, action: t.action, to: toState))
                }
            }
            return matrix
        }
        """)]
    }

    static func generateTransitionsTest() -> [DeclSyntax] {
        [DeclSyntax(stringLiteral: """
        public static func verifyTransitions() throws {
            let matrix = try Self.transitionMatrix()
            let runtime = Self.runtime
            for entry in matrix {
                let nextState = try runtime.apply(actionName: entry.action, to: entry.from)
                guard nextState == entry.to else {
                    throw _VerificationError("Transition mismatch on action '\\(entry.action)': expected \\(entry.to), got \\(nextState)")
                }
                for inv in runtime.spec.invariants {
                    guard try inv.body.evaluateBool(in: nextState, runtimeFuncs: runtime.spec.runtimeFuncs, recursiveFuncs: runtime.spec.recursiveFuncs) else {
                        throw _VerificationError("Invariant '\\(inv.name)' violated by action '\\(entry.action)'")
                    }
                }
            }
        }
        """)]
    }

    static func generateInvariantsTest() -> [DeclSyntax] {
        [DeclSyntax(stringLiteral: """
        public static func verifyInvariants() throws {
            let matrix = try Self.transitionMatrix()
            let runtime = Self.runtime
            for entry in matrix {
                let nextState = try runtime.apply(actionName: entry.action, to: entry.from)
                for inv in runtime.spec.invariants {
                    guard try inv.body.evaluateBool(in: nextState, runtimeFuncs: runtime.spec.runtimeFuncs, recursiveFuncs: runtime.spec.recursiveFuncs) else {
                        throw _VerificationError("Invariant '\\(inv.name)' violated by action '\\(entry.action)' on transition from \\(entry.from) to \\(nextState)")
                    }
                }
            }
        }
        """)]
    }

    // MARK: - Observable code generation

    static func generateObservableMembers(
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        actions: [(name: String, body: ActionExpr)],
        enumInfos: [ParsedEnumInfo] = []
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        for v in variables {
            let typeStr = v.swiftTypeName ?? Self.swiftType(for: v.initial)
            let initStr: String
            if let swiftType = v.swiftTypeName,
               let info = enumInfos.first(where: { $0.typeName == swiftType }),
               let caseName = info.cases.first(where: { $0.value == v.initial })?.name {
                initStr = ".\(caseName)"
            } else if v.swiftTypeName != nil {
                initStr = "\(typeStr)(rawValue: \(literalExpr(for: v.initial)))!"
            } else {
                initStr = literalExpr(for: v.initial)
            }
            let storedVar: DeclSyntax = DeclSyntax(
                VariableDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    bindingSpecifier: .keyword(.var),
                    bindings: [PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                        typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(typeStr))),
                        initializer: InitializerClauseSyntax(value: ExprSyntax(stringLiteral: initStr))
                    )]
                )
            )
            decls.append(storedVar)
        }

        for a in actions {
            let callbackName = "on" + a.0.prefix(1).capitalized + a.0.dropFirst()
            let callbackVar: DeclSyntax = DeclSyntax(
                VariableDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    bindingSpecifier: .keyword(.var),
                    bindings: [PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(callbackName)),
                        typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "((State, State) async -> Void)?"))
                    )]
                )
            )
            decls.append(callbackVar)
        }

        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.private))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "_state"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "State")),
                    initializer: InitializerClauseSyntax(value: ExprSyntax(stringLiteral: "State(from: runtime.initialStates().first!)"))
                )]
            )
        ))

        decls.append(DeclSyntax(generateVariablesEnum(variables: variables)))
        decls.append(DeclSyntax(generateActionsEnum(actions: actions)))
        decls.append(DeclSyntax(generateStateStruct(variables: variables, enumInfos: enumInfos)))
        decls.append(contentsOf: generateObservableActionMethods(variables: variables, actions: actions).map(DeclSyntax.init))
        decls.append(DeclSyntax(generateApplyHelper()))
        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "runtime"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "SpecRuntime")),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "SpecRuntime(spec: spec)") }
                    ))
                )]
            )
        ))

        return decls
    }

    static func generateObservableActionMethods(
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        actions: [(name: String, body: ActionExpr)]
    ) -> [FunctionDeclSyntax] {
        actions.map { a in
            let callbackName = "on" + a.0.prefix(1).capitalized + a.0.dropFirst()
            var bodyExprs: [ExprSyntax] = [
                ExprSyntax(stringLiteral: "let from = _state"),
                ExprSyntax(stringLiteral: "_state = _apply(.\(a.0))")
            ]
            for v in variables {
                bodyExprs.append(ExprSyntax(stringLiteral: "\(v.name) = _state.\(v.name)"))
            }
            bodyExprs.append(ExprSyntax(stringLiteral: "if let h = \(callbackName) { Task { await h(from, _state) } }"))
            return FunctionDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                name: .identifier("_\(a.0)"),
                signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: [])),
                body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(bodyExprs.map {
                    CodeBlockItemSyntax(item: .expr($0))
                }))
            )
        }
    }

    static func literalExpr(for initial: TLAValue) -> String {
        switch initial {
        case .int(let v): "\(v)"
        case .bool(let v): "\(v)"
        case .string(let v): "\"\(v)\""
        case .set(let v): "[\(v.map(String.init).joined(separator: ", "))]"
        default: "0"
        }
    }

    static func generateCallbackProtocol(typeName: String, actions: [(String, ActionExpr)]) throws -> [DeclSyntax] {
        let protoName = "\(typeName)Actions"
        var callbackDecls: [String] = []
        var defaultDecls: [String] = []

        for a in actions {
            let callbackName = "on" + a.0.prefix(1).capitalized + a.0.dropFirst()
            callbackDecls.append("func \(callbackName)()")
            defaultDecls.append("""
                func \(callbackName)() {
                    runtimeWarning("\(typeName).\(callbackName)() not overridden")
                }
                """)
        }

        let protoCode = """
            protocol \(protoName) {
                \(callbackDecls.joined(separator: "\n    "))
            }
            """
        let extCode = """
            extension \(protoName) {
                \(defaultDecls.joined(separator: "\n    "))
            }
            """

        let conformanceCode = """
            extension \(typeName): \(protoName) {}
            """

        return [
            DeclSyntax(stringLiteral: protoCode),
            DeclSyntax(stringLiteral: extCode),
            DeclSyntax(stringLiteral: conformanceCode)
        ]
    }

    // MARK: - Helpers

    static func swiftType(for initial: TLAValue) -> String {
        switch initial {
        case .int: "Int"; case .bool: "Bool"; case .string: "String"
        case .set: "Set<Int>"; case .tuple: "[TLAValue]"
        case .record: "[String: TLAValue]"; case .function: "[TLAValue: TLAValue]"
        case .constant: "String"
        }
    }

    static func extractor(for initial: TLAValue) -> String {
        switch initial {
        case .int: "intValue"; case .bool: "boolValue"; case .string: "stringValue"
        case .set: "intSetValue"; case .tuple: "tupleValue"
        case .record: "recordValue"; case .function: "functionValue"
        case .constant: "stringValue"
        }
    }

    static func constructor(for initial: TLAValue, value: String) -> String {
        switch initial {
        case .int: ".int(\(value))"; case .bool: ".bool(\(value))"; case .string: ".string(\(value))"
        case .set: ".set(Set(\(value).map { .int($0) }))"; case .tuple: ".tuple(\(value))"
        case .record: ".record(\(value))"; case .function: ".function(\(value))"
        case .constant: ".constant(\(value))"
        }
    }
}

struct SimpleError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Macros

public struct ModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                  providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                  in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard let ext = ("""
            extension \(type.trimmed): TLAModelType {}
            """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                  in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let parsed: ParsedMacroModel
        do {
            parsed = try TLASpecVerifier.parseAndVerify(declaration)
        } catch let diagnostic as SpecParser.SymmetricCollectionParseDiagnostic {
            context.diagnose(parserDiagnostic(diagnostic, in: declaration))
            return []
        }
        return MacroExpander.generate(mode: .model, model: parsed)
    }
}

public struct TLAActorMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                  providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                  in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard let ext = ("""
            extension \(type.trimmed): TLAModelType {}
            """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                  in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let parsed: ParsedMacroModel
        do {
            parsed = try TLASpecVerifier.parseAndVerify(declaration)
        } catch let diagnostic as SpecParser.SymmetricCollectionParseDiagnostic {
            context.diagnose(parserDiagnostic(diagnostic, in: declaration))
            return []
        }
        return MacroExpander.generate(mode: .actor, model: parsed)
    }
}

public struct TLAObservableMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                  in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let parsed: ParsedMacroModel
        do {
            parsed = try TLASpecVerifier.parseAndVerify(declaration)
        } catch let diagnostic as SpecParser.SymmetricCollectionParseDiagnostic {
            context.diagnose(parserDiagnostic(diagnostic, in: declaration))
            return []
        }
        return MacroExpander.generate(mode: .observable, model: parsed)
    }
}

private struct ParserDiagnosticMessage: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "unsupported-spec-expression")
    let severity: DiagnosticSeverity = .error
}

private func parserDiagnostic(
    _ diagnostic: SpecParser.SymmetricCollectionParseDiagnostic,
    in declaration: some DeclGroupSyntax
) -> Diagnostic {
    let finder = ParserDiagnosticNodeFinder(
        source: diagnostic.source,
        offset: diagnostic.sourceOffset
    )
    finder.walk(Syntax(declaration))
    return Diagnostic(
        node: finder.node ?? Syntax(declaration),
        message: ParserDiagnosticMessage(message: diagnostic.message)
    )
}

private final class ParserDiagnosticNodeFinder: SyntaxAnyVisitor {
    let source: String
    let offset: Int?
    var node: Syntax?

    init(source: String, offset: Int?) {
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.offset = offset
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ candidate: Syntax) -> SyntaxVisitorContinueKind {
        guard node == nil else { return .skipChildren }
        let matchesOffset = offset.map {
            candidate.positionAfterSkippingLeadingTrivia.utf8Offset == $0
        } ?? false
        let matchesSource = candidate.description.trimmingCharacters(in: .whitespacesAndNewlines) == source
        if matchesOffset && matchesSource {
            node = candidate
            return .skipChildren
        }
        return .visitChildren
    }
}
