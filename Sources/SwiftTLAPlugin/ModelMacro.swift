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
    let invariants: [(String, StateExpr)]
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
        var parsed = SpecParser.parseSpecClosure(dotRewritten, enumPhases: enumPhases)
        if let diagnostic = parsed.diagnostics.first {
            throw diagnostic
        }
        if parsed.variables.isEmpty { throw SimpleError("No variables in spec") }

        let varBindings = scanVarBindings(in: rewritten)
        for i in parsed.variables.indices {
            if parsed.variables[i].swiftTypeName == nil,
               let binding = varBindings.first(where: { $0.name == parsed.variables[i].name }) {
                parsed.variables[i].swiftTypeName = binding.typeName
            }
        }

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
            hasInvariants: hasInvs,
            invariants: parsed.invariants
        )
    }

    // MARK: - Var bindings (scan pass)

    struct VarBinding {
        let name: String
        let typeName: String
    }

    private static func typeNameFromAnnotation(_ typeAnn: TypeAnnotationSyntax?) -> String? {
        typeAnn?.type.as(IdentifierTypeSyntax.self)?.name.text
    }

    private static func inferTypeFromExpr(_ expr: ExprSyntax) -> String? {
        if expr.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if expr.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        if expr.is(StringLiteralExprSyntax.self) { return "String" }
        if let memberAccess = expr.as(MemberAccessExprSyntax.self),
           let baseRef = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            return baseRef.baseName.text
        }
        return nil
    }

    private static func scanVarBindings(in closure: ClosureExprSyntax) -> [VarBinding] {
        var bindings: [VarBinding] = []
        for item in closure.statements {
            guard case .decl(let decl) = item.item,
                  let varDecl = decl.as(VariableDeclSyntax.self)
            else { continue }
            for binding in varDecl.bindings {
                guard let patternName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let initializer = binding.initializer,
                      let fc = initializer.value.as(FunctionCallExprSyntax.self)
                else { continue }
                let baseName = fc.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
                    ?? fc.calledExpression.as(GenericSpecializationExprSyntax.self)?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
                guard baseName == "Var" else { continue }
                let args = Array(fc.arguments)
                guard !args.isEmpty,
                      let firstArg = args[0].expression.as(StringLiteralExprSyntax.self),
                      let varName = firstArg.segments.first?.as(StringSegmentSyntax.self)?.content.text,
                      varName == patternName
                else { continue }
                let typeName = typeNameFromAnnotation(binding.typeAnnotation)
                    ?? (args.count >= 2 ? inferTypeFromExpr(args[1].expression) : nil)
                    ?? "Int"
                bindings.append(VarBinding(name: patternName, typeName: typeName))
            }
        }
        return bindings
    }

    // MARK: - Var name injection

    private static func rewriteVarNames(in closure: ClosureExprSyntax) -> ClosureExprSyntax {
        var newStatements: [CodeBlockItemSyntax] = []
        for item in closure.statements {
            newStatements.append(rewriteVarBinding(in: item))
        }
        let nameInjected = closure.with(\.statements, CodeBlockItemListSyntax(newStatements))
        let bindings = scanVarBindings(in: nameInjected)
        guard !bindings.isEmpty else { return nameInjected }
        let rebinder = ClosureRebinder(bindings: bindings)
        let rebound = rebinder.rewrite(Syntax(nameInjected))
        return rebound.as(ClosureExprSyntax.self) ?? nameInjected
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

    // MARK: - Closure re-binding

    private final class ClosureRebinder: SyntaxRewriter {
        let bindingMap: [String: VarBinding]
        private let bindingNames: Set<String>

        init(bindings: [VarBinding]) {
            self.bindingMap = Dictionary(uniqueKeysWithValues: bindings.map { ($0.name, $0) })
            self.bindingNames = Set(bindings.map(\.name))
        }

        override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
            guard let callName = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
                  callName == "Action" || callName == "Invariant",
                  let closure = node.trailingClosure
            else { return super.visit(node) }

            let scanner = ReferencedVarScanner(bindingNames: bindingNames)
            scanner.walk(closure)
            guard !scanner.referencedNames.isEmpty else { return super.visit(node) }

            var rebindStatements: [CodeBlockItemSyntax] = []
            for name in scanner.referencedNames.sorted() {
                guard let binding = bindingMap[name] else { continue }
                let source = "let \(name) = Var<\(binding.typeName)>(\"\(name)\")"
                let parsed = Parser.parse(source: source)
                rebindStatements.append(contentsOf: parsed.statements)
            }

            let newBody = CodeBlockItemListSyntax(rebindStatements + Array(closure.statements))
            let newClosure = closure.with(\.statements, newBody)
            return ExprSyntax(node.with(\.trailingClosure, newClosure))
        }
    }

    private final class ReferencedVarScanner: SyntaxVisitor {
        let bindingNames: Set<String>
        var referencedNames = Set<String>()

        init(bindingNames: Set<String>) {
            self.bindingNames = bindingNames
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            let name = node.baseName.text
            if bindingNames.contains(name) { referencedNames.insert(name) }
            return .visitChildren
        }
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
        if !model.actions.isEmpty {
            decls.append(DeclSyntax(generateActionsEnum(actions: model.actions)))
        }
        decls.append(DeclSyntax(generateStateStruct(variables: model.variables, enumInfos: model.enumInfos)))
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
        if !model.actions.isEmpty {
            decls.append(DeclSyntax(generateApplyHelper(symmetricCollections: model.symmetricCollections)))
            decls.append(DeclSyntax(generateApplyDispatcher(
                actions: model.actions,
                nativeNames: actionResult.nativeActionNames,
                isActor: isActor
            )))
        }
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
        if !model.actions.isEmpty {
            decls.append(contentsOf: generateTransitionMatrix())
        }
        decls.append(contentsOf: generateTransitionsTest(model.actions))
        if model.hasInvariants && !model.actions.isEmpty {
            decls.append(contentsOf: generateInvariantsTest())
        }

        decls.append(contentsOf: generateParserTreeCheck(model: model))

        return decls
    }

    static func generateParserTreeCheck(model: ParsedMacroModel) -> [DeclSyntax] {
        guard !model.actions.isEmpty else { return [] }

        let treeVars = model.variables.map { v in
            "(\"\(v.name)\", \(codegenTLAValue(v.initial)))"
        }.joined(separator: ", ")

        let treeActions = model.actions.map { a in
            "(\"\(a.0)\", \(codegenActionExpr(a.1)))"
        }.joined(separator: ", ")

        let treeInvs = model.invariants.map { i in
            "(\"\(i.0)\", \(codegenStateExpr(i.1)))"
        }.joined(separator: ", ")

        let source = """
        private static let _parserTree: ParsedSpecModel = ParsedSpecModel(
            variables: [\(treeVars)],
            actions: [\(treeActions)],
            invariants: [\(treeInvs)]
        )

        private static func _checkParserTree() {
            let builtSpec = Self.spec
            let built = ParsedSpecModel(
                variables: builtSpec.variables.map { ($0.name, $0.initial) },
                actions: builtSpec.actions.map { ($0.name, $0.body) },
                invariants: builtSpec.invariants.map { ($0.name, $0.body) }
            )
            if built != _parserTree {
                print("⚠ SpecParser tree mismatch")
            }
        }
        """
        return [DeclSyntax(stringLiteral: source)]
    }

    private static func codegenTLAValue(_ value: TLAValue) -> String {
        switch value {
        case .int(let n): return ".int(\(n))"
        case .bool(let b): return ".bool(\(b))"
        case .string(let s): return ".string(\"\(s)\")"
        case .set(let s): return ".set([\(s.map(codegenTLAValue).joined(separator: ", "))])"
        case .tuple(let t): return ".tuple([\(t.map(codegenTLAValue).joined(separator: ", "))])"
        case .record(let r):
            let fields = r.map { "\"\($0.key)\": \(codegenTLAValue($0.value))" }.joined(separator: ", ")
            return ".record([\(fields)])"
        case .function(let f):
            let entries = f.map { "\(codegenTLAValue($0.key)): \(codegenTLAValue($0.value))" }.joined(separator: ", ")
            return ".function([\(entries)])"
        case .constant(let c): return ".constant(\"\(c)\")"
        }
    }

    private static func codegenStateExpr(_ expr: StateExpr) -> String {
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
        case .setFilter(let s, let qv, let p): return "StateExpr.setFilter(\(cg(s)), QuantVar(name: \"\(qv.name)\"), \(cg(p)))"
        case .setMap(let e, let qv, let s): return "StateExpr.setMap(\(cg(e)), QuantVar(name: \"\(qv.name)\"), \(cg(s)))"
        case .powerSet(let s): return "StateExpr.powerSet(\(cg(s)))"
        case .unionAll(let s): return "StateExpr.unionAll(\(cg(s)))"
        case .tupleLiteral(let es): return "StateExpr.tupleLiteral([\(es.map(cg).joined(separator: ", "))])"
        case .recordLiteral(let fs):
            let fields = fs.map { "\"\($0.key)\": \(cg($0.value))" }.joined(separator: ", ")
            return "StateExpr.recordLiteral([\(fields)])"
        case .setLiteral(let es): return "StateExpr.setLiteral([\(es.map(cg).joined(separator: ", "))])"
        case .functionLiteral(let d, let qv, let b): return "StateExpr.functionLiteral(\(cg(d)), QuantVar(name: \"\(qv.name)\"), \(cg(b)))"
        case .caseExpr(let ps, let fb):
            let patterns = ps.map(cg).joined(separator: ", ")
            let fallback = fb.map { cg($0) } ?? "nil"
            return "StateExpr.caseExpr([\(patterns)], \(fallback))"
        case .forAll, .exists, .choose, .sequenceFromSet, .setSum, .functionSet,
             .recursiveCall, .enabledAction:
            return "StateExpr.value(.int(0))"
        }
    }

    private static func codegenActionExpr(_ action: ActionExpr) -> String {
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
                } else if let typeName = v.swiftTypeName,
                          !["Int", "Bool", "String", "TLAValue"].contains(typeName) {
                    ExprSyntax(stringLiteral: "self.\(v.name) = \(typeName)(rawValue: dict[Variables.\(v.name).rawValue]!.\(extractor(for: v.initial)))!")
                } else {
                    ExprSyntax(stringLiteral: "self.\(v.name) = dict[Variables.\(v.name).rawValue]!.\(v.swiftTypeName.map(extractor(forSwiftType:)) ?? extractor(for: v.initial))")
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
                                    let swiftType = v.swiftTypeName ?? swiftType(for: v.initial)
                                    if v.swiftTypeName != nil && enumInfos.contains(where: { $0.typeName == v.swiftTypeName }) {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = .string(String(describing: \(v.name)))")
                                    } else if ["Int", "Bool", "String"].contains(swiftType) {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(constructor(forSwiftType: swiftType, value: v.name))")
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
        symmetricCollections: [SpecParser.ParsedSymmetricCollection],
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> (methods: [FunctionDeclSyntax], nativeActionNames: Set<String>) {
        let visibility = isActor ? TokenSyntax.keyword(.fileprivate) : TokenSyntax.keyword(.public)
        var nativeNames = Set<String>()
        var methods: [FunctionDeclSyntax] = []

        for a in actions {
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
                methods.append(DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!)
                continue
            }

            let methodName = isActor ? "_\(a.name)" : "apply\(a.name)"
            if let body = codegenActionBody(a.body, variables: variables, enumInfos: enumInfos) {
                nativeNames.insert(a.name)
                let bodyLines = body.components(separatedBy: "\n").map { "        \($0)" }.joined(separator: "\n")
                let source = """
                \(isActor ? "fileprivate" : "public mutating") func \(methodName)() {
                \(bodyLines)
                }
                """
                methods.append(DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!)
            } else {
                methods.append(FunctionDeclSyntax(
                    modifiers: isActor
                        ? [DeclModifierSyntax(name: visibility)]
                        : [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.mutating))],
                    name: .identifier(methodName),
                    signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: [])),
                    body: CodeBlockSyntax { ExprSyntax(stringLiteral: "_state = _apply(.\(a.name))") }
                ))
            }
        }
        return (methods, nativeNames)
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
        public struct VerificationError: Error, CustomStringConvertible {
            public let description: String
            public init(_ description: String) { self.description = description }
        }
        """),
        DeclSyntax(stringLiteral: """
        public static func verifySpec() throws {
            let result = try ModelChecker(spec: Self.spec, maxStates: 100_000).check()
            switch result {
            case .ok(let count):
                guard count > 0 else { throw VerificationError("No states found") }
            case .bounded(_, let outcome):
                switch outcome {
                case .ok(let count):
                    guard count > 0 else { throw VerificationError("No states found") }
                default:
                    throw VerificationError("Spec verification failed: \\(result)")
                }
            default:
                throw VerificationError("Spec verification failed: \\(result)")
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

    static func generateTransitionsTest(_ actions: [(name: String, body: ActionExpr)]) -> [DeclSyntax] {
        if actions.isEmpty { return [] }
        return [DeclSyntax(stringLiteral: """
        public static func verifyTransitions() throws {
            let matrix = try Self.transitionMatrix()
            var instance = Self()
            for (from, actionName, expected) in matrix {
                guard let action = Actions(rawValue: actionName) else { continue }
                instance._state = State(from: from)
                instance._applyAction(action)
                let result = instance._state.asDictionary
                guard result == expected else {
                    throw VerificationError("\\(actionName): expected \\(expected), got \\(result)")
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
            var instance = Self()
            for (from, actionName, _) in matrix {
                guard let action = Actions(rawValue: actionName) else { continue }
                instance._state = State(from: from)
                instance._applyAction(action)
                for inv in runtime.spec.invariants {
                    guard try inv.body.evaluateBool(in: instance._state.asDictionary, runtimeFuncs: runtime.spec.runtimeFuncs, recursiveFuncs: runtime.spec.recursiveFuncs) else {
                        throw VerificationError("\\(inv.name) violated by \\(actionName)")
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

    static func extractor(forSwiftType swiftType: String) -> String {
        switch swiftType {
        case "Int": "intValue"; case "Bool": "boolValue"; case "String": "stringValue"
        default: "intValue"
        }
    }

    static func constructor(forSwiftType swiftType: String, value: String) -> String {
        switch swiftType {
        case "Int": ".int(\(value))"
        case "Bool": ".bool(\(value))"
        case "String": ".string(\(value))"
        default: ".int(0)"
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

    // MARK: - Native action codegen

    static func codegenExpr(
        _ expr: StateExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo],
        boundVarName: String? = nil
    ) -> String {
        let forceTLAValue = containsTLAValueField(expr, variables: variables, enumInfos: enumInfos, boundVarName: boundVarName)
        return codegenExprInner(expr, variables: variables, enumInfos: enumInfos, forceTLAValue: forceTLAValue, boundVarName: boundVarName)
    }

    private static func codegenExprInner(
        _ expr: StateExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo],
        forceTLAValue: Bool,
        boundVarName: String? = nil
    ) -> String {
        let cg: (StateExpr) -> String = { codegenExprInner($0, variables: variables, enumInfos: enumInfos, forceTLAValue: forceTLAValue, boundVarName: boundVarName) }

        switch expr {
        case .variable(let name):
            if name == boundVarName { return name }
            return "_state.\(name)"

        case .value(let val):
            return valueLiteral(val, forceTLAValue: forceTLAValue, enumInfos: enumInfos)

        case .add(let a, let b): return "(\(cg(a)) + \(cg(b)))"
        case .subtract(let a, let b): return "(\(cg(a)) - \(cg(b)))"
        case .multiply(let a, let b): return "(\(cg(a)) * \(cg(b)))"
        case .divide(let a, let b): return "(\(cg(a)) / \(cg(b)))"
        case .modulo(let a, let b): return "(\(cg(a)) % \(cg(b)))"
        case .negate(let a): return "(-\(cg(a)))"
        case .integerDivide(let a, let b): return "(\(cg(a)) / \(cg(b)))"

        case .equal(let a, let b): return "(\(cg(a)) == \(cg(b)))"
        case .notEqual(let a, let b): return "(\(cg(a)) != \(cg(b)))"
        case .lessThan(let a, let b): return "(\(cg(a)) < \(cg(b)))"
        case .lessOrEqual(let a, let b): return "(\(cg(a)) <= \(cg(b)))"
        case .greaterThan(let a, let b): return "(\(cg(a)) > \(cg(b)))"
        case .greaterOrEqual(let a, let b): return "(\(cg(a)) >= \(cg(b)))"

        case .and(let a, let b): return "(\(cg(a)) && \(cg(b)))"
        case .or(let a, let b): return "(\(cg(a)) || \(cg(b)))"
        case .not(let a): return "(!\(cg(a)))"

        case .ifThenElse(let c, let t, let f):
            if forceTLAValue {
                return "TLAValue.ternary(condition: \(cg(c)), then: \(cg(t)), else: \(cg(f)))"
            }
            return "(\(cg(c)) ? \(cg(t)) : \(cg(f)))"

        case .cardinality(let s): return "\(cg(s)).cardinality"
        case .functionApply(let f, let x): return "\(cg(f))[\(cg(x))]"
        case .recordAccess(let r, let field): return "\(cg(r))[\"\(field)\"]"

        case .in(let e, let s): return "\(cg(s)).contains(\(cg(e)))"
        case .union(let a, let b): return "\(cg(a)).union(\(cg(b)))"
        case .intersection(let a, let b): return "\(cg(a)).intersection(\(cg(b)))"
        case .setDifference(let a, let b): return "\(cg(a)).subtracting(\(cg(b)))"
        case .subset(let a, let b): return "\(cg(a)).isSubset(of: \(cg(b)))"

        case .tupleAccess(let t, let i): return "(\(cg(t)))[\(i)]"
        case .tupleAppend(let t, let e): return "(\(cg(t)) + [\(cg(e))])"
        case .tupleHead(let t): return "(\(cg(t))).first!"
        case .tupleTail(let t): return "Array((\(cg(t))).dropFirst())"

        case .except(let f, let k, let v): return "\(cg(f)).updating(\(cg(k)), to: \(cg(v)))"
        case .domain(let f): return "\(cg(f)).keys"

        case .setFilter(let s, let qv, let p):
            return "\(cg(s)).filter { \(qv.name) in \(codegenExprInner(p, variables: variables, enumInfos: enumInfos, forceTLAValue: forceTLAValue, boundVarName: qv.name)) }"
        case .setMap(let e, let qv, let s):
            return "\(cg(s)).map { \(qv.name) in \(codegenExprInner(e, variables: variables, enumInfos: enumInfos, forceTLAValue: forceTLAValue, boundVarName: qv.name)) }"
        case .powerSet(let s): return "\(cg(s)).powerSet"
        case .unionAll(let s): return "\(cg(s)).flattened"

        case .tupleLiteral(let es):
            return "[\(es.map { cg($0) }.joined(separator: ", "))]"
        case .recordLiteral(let fs):
            return "[\(fs.map { "\"\($0.key)\": \(cg($0.value))" }.joined(separator: ", "))]"
        case .setLiteral(let es):
            return "Set([\(es.map { cg($0) }.joined(separator: ", "))])"
        case .functionLiteral(let d, let qv, let b):
            return "\(cg(d)).asFunctionLiteral { \(qv.name) in \(codegenExprInner(b, variables: variables, enumInfos: enumInfos, forceTLAValue: forceTLAValue, boundVarName: qv.name)) }"
        case .caseExpr:
            return "StateExpr.caseExpr([], nil)"

        case .forAll, .exists, .choose, .sequenceFromSet, .setSum, .functionSet, .recursiveCall, .enabledAction:
            return "Self.runtime.evaluateExpr(\(expr.description), in: _state.asDictionary)"

        case .tupleLength(let t):
            return "TLAValue.int((\(cg(t)).tupleValue.count))"
        case .tupleConcatenate(let a, let b):
            return "(\(cg(a)) + \(cg(b)))"
        }
    }

    private static func containsTLAValueField(
        _ expr: StateExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo],
        boundVarName: String? = nil
    ) -> Bool {
        var found = false
        walkStateExpr(expr) { e in
            if case .variable(let name) = e, name != boundVarName {
                if isTLAValueField(name, variables: variables, enumInfos: enumInfos) {
                    found = true; return true
                }
            }
            return false
        }
        return found
    }

    private static func walkStateExpr(_ expr: StateExpr, visitor: (StateExpr) -> Bool) {
        if visitor(expr) { return }
        switch expr {
        case .variable, .value: break
        case .add(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .subtract(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .multiply(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .divide(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .modulo(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .negate(let a): walkStateExpr(a, visitor: visitor)
        case .integerDivide(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .equal(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .notEqual(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .lessThan(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .lessOrEqual(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .greaterThan(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .greaterOrEqual(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .and(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .or(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .not(let a): walkStateExpr(a, visitor: visitor)
        case .ifThenElse(let c, let t, let f): walkStateExpr(c, visitor: visitor); walkStateExpr(t, visitor: visitor); walkStateExpr(f, visitor: visitor)
        case .cardinality(let s): walkStateExpr(s, visitor: visitor)
        case .functionApply(let f, let x): walkStateExpr(f, visitor: visitor); walkStateExpr(x, visitor: visitor)
        case .recordAccess(let r, _): walkStateExpr(r, visitor: visitor)
        case .in(let e, let s): walkStateExpr(e, visitor: visitor); walkStateExpr(s, visitor: visitor)
        case .union(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .intersection(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .setDifference(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .subset(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .tupleAccess(let t, _): walkStateExpr(t, visitor: visitor)
        case .tupleAppend(let t, let e): walkStateExpr(t, visitor: visitor); walkStateExpr(e, visitor: visitor)
        case .tupleHead(let t): walkStateExpr(t, visitor: visitor)
        case .tupleTail(let t): walkStateExpr(t, visitor: visitor)
        case .tupleLength(let t): walkStateExpr(t, visitor: visitor)
        case .tupleConcatenate(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .except(let f, let k, let v): walkStateExpr(f, visitor: visitor); walkStateExpr(k, visitor: visitor); walkStateExpr(v, visitor: visitor)
        case .domain(let f): walkStateExpr(f, visitor: visitor)
        case .setFilter(let s, _, let p): walkStateExpr(s, visitor: visitor); walkStateExpr(p, visitor: visitor)
        case .setMap(let e, _, let s): walkStateExpr(e, visitor: visitor); walkStateExpr(s, visitor: visitor)
        case .powerSet(let s): walkStateExpr(s, visitor: visitor)
        case .unionAll(let s): walkStateExpr(s, visitor: visitor)
        case .tupleLiteral(let es): es.forEach { walkStateExpr($0, visitor: visitor) }
        case .recordLiteral(let fs): fs.values.forEach { walkStateExpr($0, visitor: visitor) }
        case .setLiteral(let es): es.forEach { walkStateExpr($0, visitor: visitor) }
        case .functionLiteral(let d, _, let b): walkStateExpr(d, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .caseExpr(let ps, let fb): ps.forEach { walkStateExpr($0, visitor: visitor) }; fb.map { walkStateExpr($0, visitor: visitor) }
        case .forAll, .exists, .choose, .sequenceFromSet, .setSum, .functionSet, .recursiveCall, .enabledAction: break
        }
    }

    private static func isTLAValueField(
        _ name: String,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> Bool {
        guard let v = variables.first(where: { $0.name == name }) else { return false }
        let typeName = v.swiftTypeName ?? swiftType(for: v.initial)
        if ["Int", "Bool", "String"].contains(typeName) { return false }
        if enumInfos.contains(where: { $0.typeName == typeName }) { return false }
        return true
    }

    private static func valueLiteral(_ value: TLAValue, forceTLAValue: Bool, enumInfos: [ParsedEnumInfo]) -> String {
        if forceTLAValue {
            switch value {
            case .int(let n): return ".int(\(n))"
            case .bool(let b): return ".bool(\(b))"
            case .string(let s): return ".string(\"\(s)\")"
            default: return ".int(0)"
            }
        }
        for info in enumInfos {
            for (caseName, caseValue) in info.cases where caseValue == value {
                return ".\(caseName)"
            }
        }
        switch value {
        case .int(let n): return "\(n)"
        case .bool(let b): return "\(b)"
        case .string(let s): return "\"\(s)\""
        default: return "0"
        }
    }

    // MARK: - Action body codegen (T2)

    static func codegenActionBody(
        _ action: ActionExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> String? {
        let expanded = inlineDefines(in: action)
        guard !containsNondeterministic(expanded) else { return nil }
        guard !containsRuntimeOnlyExpr(expanded) else { return nil }
        let disjuncts = distributeOr(expanded)
        if disjuncts.isEmpty { return nil }
        if disjuncts.count == 1 {
            return codegenSingleDisjunct(disjuncts[0], variables: variables, enumInfos: enumInfos)
        }
        return codegenMultiDisjunct(disjuncts, variables: variables, enumInfos: enumInfos)
    }

    private static func containsRuntimeOnlyExpr(_ action: ActionExpr) -> Bool {
        var found = false
        walkActionExpr(action) { a in
            let exprNodes: [StateExpr] = {
                switch a {
                case .assign(_, let e): return [e]
                case .guard_(let e): return [e]
                case .chooseAction(_, let s): return [s]
                case .existsAction(_, let s, _): return [s]
                case .ifElse(let c, _, _): return [c]
                case .define(_, let e, _): return [e]
                default: return []
                }
            }()
            for e in exprNodes {
                if containsRuntimeOnlyStateExpr(e) { found = true; return true }
            }
            return false
        }
        return found
    }

    private static func containsRuntimeOnlyStateExpr(_ expr: StateExpr) -> Bool {
        var found = false
        walkStateExpr(expr) { e in
            switch e {
            case .forAll, .exists, .choose, .sequenceFromSet, .setSum,
                 .functionSet, .recursiveCall, .enabledAction:
                found = true; return true
            case .caseExpr:
                found = true; return true
            default: return false
            }
        }
        return found
    }

    private static func containsNondeterministic(_ action: ActionExpr) -> Bool {
        var found = false
        walkActionExpr(action) { a in
            switch a {
            case .chooseAction, .existsAction:
                found = true; return true
            default: return false
            }
        }
        return found
    }

    private static func walkActionExpr(_ action: ActionExpr, visitor: (ActionExpr) -> Bool) {
        if visitor(action) { return }
        switch action {
        case .assign: break
        case .unchanged: break
        case .guard_: break
        case .ifElse(_, let t, let e):
            walkActionExpr(t, visitor: visitor); walkActionExpr(e, visitor: visitor)
        case .define(_, _, let b):
            walkActionExpr(b, visitor: visitor)
        case .and(let a, let b):
            walkActionExpr(a, visitor: visitor); walkActionExpr(b, visitor: visitor)
        case .or(let a, let b):
            walkActionExpr(a, visitor: visitor); walkActionExpr(b, visitor: visitor)
        case .existsAction(_, _, let b):
            walkActionExpr(b, visitor: visitor)
        case .chooseAction: break
        }
    }

    private static func inlineDefines(in action: ActionExpr) -> ActionExpr {
        switch action {
        case .define(let name, let expr, let body):
            let inlined = substituteActionVar(name, with: expr, in: body)
            return inlineDefines(in: inlined)
        case .and(let a, let b):
            return .and(inlineDefines(in: a), inlineDefines(in: b))
        case .or(let a, let b):
            return .or(inlineDefines(in: a), inlineDefines(in: b))
        case .ifElse(let c, let t, let e):
            return .ifElse(c, inlineDefines(in: t), inlineDefines(in: e))
        case .existsAction(let v, let s, let b):
            return .existsAction(v, s, inlineDefines(in: b))
        default:
            return action
        }
    }

    private static func substituteActionVar(_ name: String, with expr: StateExpr, in action: ActionExpr) -> ActionExpr {
        switch action {
        case .assign(let v, let e):
            return .assign(v, substituteInStateExpr(name, with: expr, in: e))
        case .unchanged(let v):
            if v == name { return .unchanged(v) }
            return action
        case .guard_(let e):
            return .guard_(substituteInStateExpr(name, with: expr, in: e))
        case .chooseAction(let v, let s):
            return .chooseAction(v, substituteInStateExpr(name, with: expr, in: s))
        case .existsAction(let v, let s, let b):
            return .existsAction(v, substituteInStateExpr(name, with: expr, in: s),
                                 substituteActionVar(name, with: expr, in: b))
        case .ifElse(let c, let t, let e):
            return .ifElse(substituteInStateExpr(name, with: expr, in: c),
                           substituteActionVar(name, with: expr, in: t),
                           substituteActionVar(name, with: expr, in: e))
        case .define(let v, let e, let b):
            if v == name { return action }
            return .define(v, substituteInStateExpr(name, with: expr, in: e),
                           substituteActionVar(name, with: expr, in: b))
        case .and(let a, let b):
            return .and(substituteActionVar(name, with: expr, in: a),
                        substituteActionVar(name, with: expr, in: b))
        case .or(let a, let b):
            return .or(substituteActionVar(name, with: expr, in: a),
                       substituteActionVar(name, with: expr, in: b))
        }
    }

    private static func substituteInStateExpr(_ name: String, with expr: StateExpr, in state: StateExpr) -> StateExpr {
        if case .variable(let v) = state, v == name { return expr }
        func sub(_ s: StateExpr) -> StateExpr { substituteInStateExpr(name, with: expr, in: s) }
        switch state {
        case .variable, .value: break
        case .add(let a, let b): return .add(sub(a), sub(b))
        case .subtract(let a, let b): return .subtract(sub(a), sub(b))
        case .multiply(let a, let b): return .multiply(sub(a), sub(b))
        case .divide(let a, let b): return .divide(sub(a), sub(b))
        case .modulo(let a, let b): return .modulo(sub(a), sub(b))
        case .negate(let a): return .negate(sub(a))
        case .integerDivide(let a, let b): return .integerDivide(sub(a), sub(b))
        case .equal(let a, let b): return .equal(sub(a), sub(b))
        case .notEqual(let a, let b): return .notEqual(sub(a), sub(b))
        case .lessThan(let a, let b): return .lessThan(sub(a), sub(b))
        case .lessOrEqual(let a, let b): return .lessOrEqual(sub(a), sub(b))
        case .greaterThan(let a, let b): return .greaterThan(sub(a), sub(b))
        case .greaterOrEqual(let a, let b): return .greaterOrEqual(sub(a), sub(b))
        case .and(let a, let b): return .and(sub(a), sub(b))
        case .or(let a, let b): return .or(sub(a), sub(b))
        case .not(let a): return .not(sub(a))
        case .ifThenElse(let c, let t, let f): return .ifThenElse(sub(c), sub(t), sub(f))
        case .cardinality(let s): return .cardinality(sub(s))
        case .functionApply(let f, let x): return .functionApply(sub(f), sub(x))
        case .recordAccess(let r, let f): return .recordAccess(sub(r), f)
        case .in(let e, let s): return .in(sub(e), sub(s))
        case .union(let a, let b): return .union(sub(a), sub(b))
        case .intersection(let a, let b): return .intersection(sub(a), sub(b))
        case .setDifference(let a, let b): return .setDifference(sub(a), sub(b))
        case .subset(let a, let b): return .subset(sub(a), sub(b))
        case .tupleAccess(let t, let i): return .tupleAccess(sub(t), i)
        case .tupleAppend(let t, let e): return .tupleAppend(sub(t), sub(e))
        case .tupleHead(let t): return .tupleHead(sub(t))
        case .tupleTail(let t): return .tupleTail(sub(t))
        case .tupleLength(let t): return .tupleLength(sub(t))
        case .tupleConcatenate(let a, let b): return .tupleConcatenate(sub(a), sub(b))
        case .except(let f, let k, let v): return .except(sub(f), sub(k), sub(v))
        case .domain(let f): return .domain(sub(f))
        case .setFilter(let s, let qv, let p): return .setFilter(sub(s), qv, sub(p))
        case .setMap(let e, let qv, let s): return .setMap(sub(e), qv, sub(s))
        case .powerSet(let s): return .powerSet(sub(s))
        case .unionAll(let s): return .unionAll(sub(s))
        case .tupleLiteral(let es): return .tupleLiteral(es.map(sub))
        case .recordLiteral(let fs): return .recordLiteral(fs.mapValues(sub))
        case .setLiteral(let es): return .setLiteral(es.map(sub))
        case .functionLiteral(let d, let qv, let b): return .functionLiteral(sub(d), qv, sub(b))
        case .caseExpr(let ps, let fb): return .caseExpr(ps.map(sub), fb.map(sub))
        case .forAll, .exists, .choose, .sequenceFromSet, .setSum, .functionSet,
             .recursiveCall, .enabledAction: break
        }
        return state
    }

    private static func codegenSingleDisjunct(
        _ disjunct: ActionExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> String {
        guard let extracted = try? ActionEnumerator.extractAssignments(disjunct) else {
            return "return"
        }
        let guardExprs = extracted.guards.map { codegenExpr($0, variables: variables, enumInfos: enumInfos) }
        let guardBlock = guardExprs.isEmpty ? "" : "guard \(guardExprs.joined(separator: ", ")) else { return }"
        let assignments = extracted.assignments.compactMap { (name, expr) -> String? in
            if case .variable(let refName) = expr, refName == name { return nil }
            return "_state.\(name) = \(codegenExpr(expr, variables: variables, enumInfos: enumInfos))"
        }
        let body = [guardBlock].filter { !$0.isEmpty } + assignments
        return body.filter { !$0.isEmpty }.joined(separator: "\n        ")
    }

    private static func codegenMultiDisjunct(
        _ disjuncts: [ActionExpr],
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> String {
        let parts = disjuncts.map { disjunct -> String in
            guard let extracted = try? ActionEnumerator.extractAssignments(disjunct) else { return "" }
            let guardExprs = extracted.guards.map { codegenExpr($0, variables: variables, enumInfos: enumInfos) }
            let condition = guardExprs.isEmpty ? "true" : guardExprs.joined(separator: " && ")
            let assignments = extracted.assignments.compactMap { (name, expr) -> String? in
                if case .variable(let refName) = expr, refName == name { return nil }
                return "_state.\(name) = \(codegenExpr(expr, variables: variables, enumInfos: enumInfos))"
            }
            return "if \(condition) {\n            \(assignments.joined(separator: "\n            "))\n            return\n        }"
        }
        var result = "let _saved = _state\n        "
        for (i, part) in parts.enumerated() {
            if !part.isEmpty {
                if i > 0 { result += "\n        _state = _saved\n        " }
                result += part
            }
        }
        return result
    }

    // MARK: - Apply dispatcher generation (T3)

    static func generateApplyDispatcher(
        actions: [(name: String, body: ActionExpr)],
        nativeNames: Set<String>,
        isActor: Bool = false
    ) -> FunctionDeclSyntax {
        let switchCases = actions.map { a in
            if nativeNames.contains(a.name) {
                let methodName = isActor ? "_\(a.name)" : "apply\(a.name)"
                return "case .\(a.name): \(methodName)()"
            } else {
                return "case .\(a.name): _state = _apply(action)"
            }
        }.joined(separator: "\n        ")
        let source = """
        \(isActor ? "fileprivate" : "private mutating") func _applyAction(_ action: Actions) {
            switch action {
            \(switchCases)
            }
        }
        """
        return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
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
