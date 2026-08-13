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
    let actions: [SpecParser.ParsedAction]
    let symmetricCollections: [SpecParser.ParsedSymmetricCollection]
    let collectionActions: [SpecParser.ParsedCollectionAction]
    let enumInfos: [ParsedEnumInfo]
    let hasInvariants: Bool
    let invariants: [(String, StateExpr)]
}

enum NestedAdapterModelRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var models: [String: ParsedMacroModel] = [:]

    static func record(_ model: ParsedMacroModel) {
        lock.lock()
        models[model.typeName] = model
        lock.unlock()
    }

    static func model(named typeName: String) -> ParsedMacroModel? {
        lock.lock()
        defer { lock.unlock() }
        return models[typeName]
    }
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
        let enumInfos = Self.collectEnumStateVars(from: memberList)
        let (enumPhases, caseToType) = collectEnumPhaseMap(from: memberList)
        let enumDomains = Dictionary(
            uniqueKeysWithValues: enumInfos.map { ($0.typeName, $0.cases.map(\.value)) }
        )
        let rewriter = EnumDotRewriter(caseToType: caseToType)
        let dotRewrittenSyntax = rewriter.rewrite(rewritten)
        let dotRewritten = dotRewrittenSyntax.as(ClosureExprSyntax.self) ?? rewritten
        if let unknown = rewriter.unknownDots.first, !caseToType.isEmpty {
            let allCases = caseToType.keys.sorted().joined(separator: ", ")
            throw SimpleError("Unknown enum case '.\(unknown)'. Available cases: [\(allCases)]")
        }
        var parsed = SpecParser.parseSpecClosure(
            dotRewritten,
            enumPhases: enumPhases,
            enumDomains: enumDomains
        )
        if let diagnostic = parsed.diagnostics.first {
            throw diagnostic
        }
        if parsed.variables.isEmpty { throw SimpleError("No variables in spec") }

        let varBindings = scanVarBindings(in: rewritten)
        for i in parsed.variables.indices {
            if let binding = varBindings.first(where: { $0.name == parsed.variables[i].name }),
               binding.typeName != "TLAValue" {
                if parsed.variables[i].swiftTypeName == nil {
                    parsed.variables[i].swiftTypeName = binding.typeName
                }
            }
        }

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
            actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body, bindings: $0.bindings) },
            invariants: allInvariants,
            temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) },
            fairness: parsed.fairness,
            symmetricCollections: parsed.symmetricCollections.map(\.declaration)
        )

        let hasComplexType = parsed.symmetricCollections.isEmpty && parsed.variables.contains { v in
            let typeName = v.swiftTypeName ?? MacroExpander.swiftType(for: v.initial)
            return !["Int", "Bool", "String"].contains(typeName)
                && !enumInfos.contains(where: { $0.typeName == typeName })
        }

        if hasComplexType {
            SpecRegistry.register(spec)
        } else {
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
        }

        let hasInvs = !allInvariants.isEmpty

        return ParsedMacroModel(
            typeName: typeName, variables: parsed.variables, actions: parsed.actions,
            symmetricCollections: parsed.symmetricCollections, collectionActions: parsed.collectionActions,
            enumInfos: enumInfos, hasInvariants: hasInvs, invariants: parsed.invariants
        )
    }

    // MARK: - Var bindings (scan pass)

    struct VarBinding {
        let name: String
        let typeName: String
    }

    static func typeNameFromAnnotation(_ typeAnn: TypeAnnotationSyntax?) -> String? {
        typeAnn?.type.as(IdentifierTypeSyntax.self)?.name.text
    }

    static func inferTypeFromExpr(_ expr: ExprSyntax) -> String? {
        if expr.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if expr.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        if expr.is(StringLiteralExprSyntax.self) { return "String" }
        if let memberAccess = expr.as(MemberAccessExprSyntax.self),
           let baseRef = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            return baseRef.baseName.text
        }
        return nil
    }

    static func scanVarBindings(in closure: ClosureExprSyntax) -> [VarBinding] {
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
                let genericType = fc.calledExpression.as(GenericSpecializationExprSyntax.self)?
                    .genericArgumentClause.arguments.first?.argument.as(IdentifierTypeSyntax.self)?.name.text
                let args = Array(fc.arguments)
                guard !args.isEmpty,
                      let firstArg = args[0].expression.as(StringLiteralExprSyntax.self),
                      let varName = firstArg.segments.first?.as(StringSegmentSyntax.self)?.content.text,
                      varName == patternName
                else { continue }
                let typeName = typeNameFromAnnotation(binding.typeAnnotation)
                    ?? genericType
                    ?? (args.count >= 2 ? inferTypeFromExpr(args[1].expression) : nil)
                    ?? "Int"
                bindings.append(VarBinding(name: patternName, typeName: typeName))
            }
        }
        return bindings
    }

    // MARK: - Var name injection

    static func rewriteVarNames(in closure: ClosureExprSyntax) -> ClosureExprSyntax {
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

    static func rewriteVarBinding(in item: CodeBlockItemSyntax) -> CodeBlockItemSyntax {
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
                    let expr: ExprSyntax? = {
                        if case .expr(let e) = stmt.item { return e }
                        if let returnStmt = stmt.item.as(ReturnStmtSyntax.self) { return returnStmt.expression }
                        return nil
                    }()
                    if let e = expr,
                       let fc = e.as(FunctionCallExprSyntax.self),
                       fc.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLASpec" {
                        return fc.trailingClosure ?? fc.arguments.last?.expression.as(ClosureExprSyntax.self)
                    }
                }
            }
            if let accessors = binding.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) {
                for acc in accessors where acc.accessorSpecifier.tokenKind == .keyword(.get) {
                    for stmt in acc.body?.statements ?? [] {
                        let expr: ExprSyntax? = {
                            if case .expr(let e) = stmt.item { return e }
                            if let returnStmt = stmt.item.as(ReturnStmtSyntax.self) { return returnStmt.expression }
                            return nil
                        }()
                        if let e = expr,
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

            guard inheritedNames.contains("TLAValueType") || inheritedNames.contains("FiniteTLAValueDomain") else { continue }

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
        "head", "tail", "stays", "zero", "max", "min", "default", "init", "value",
        "variable",
        "int", "bool", "string", "set", "tuple", "record", "function", "constant"
    ]
}

enum GenerationMode {
    case model
    case actor
    case observable
}

struct SimpleError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Macros

public struct ModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard let ext = ("""
            extension \(type.trimmed): @unchecked Sendable, TLAModelType, TLAMachineExecuting, TLAMachineAdapterCanonicalModel {}
            """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let parsed: ParsedMacroModel
        do {
            parsed = try TLASpecVerifier.parseAndVerify(declaration)
        } catch let diagnostic as SpecParser.SymmetricCollectionParseDiagnostic {
            context.diagnose(parserDiagnostic(diagnostic, in: declaration))
            return []
        }
        NestedAdapterModelRegistry.record(parsed)
        return MacroExpander.generate(mode: .model, model: parsed)
    }
}

public struct TLAActorMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        switch adapterNestingMode(for: declaration, at: node, in: context) {
        case .nested:
            guard let ext = ("""
                extension \(type.trimmed): TLAMachineAdapterAccess {}
                """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
            return [ext]
        case .invalid:
            return []
        case .standalone:
            break
        }
        guard let ext = ("""
            extension \(type.trimmed): TLAModelType {}
            """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        switch adapterNestingMode(for: declaration, at: node, in: context) {
        case .nested(let model):
            guard let parsed = NestedAdapterModelRegistry.model(named: model.name.text) else {
                context.diagnose(Diagnostic(
                    node: Syntax(node),
                    message: AdapterNestingDiagnostic(message: "Nested adapter could not resolve its enclosing @TLAModel")
                ))
                return []
            }
            return MacroExpander.generateNestedAdapterMembers(
                kind: .actor,
                canonicalModel: parsed
            )
        case .invalid:
            return []
        case .standalone:
            break
        }
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

public struct TLAObservableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard case .nested = adapterNestingMode(for: declaration, at: node, in: context),
              let ext = ("""
                @MainActor extension \(type.trimmed): Sendable, TLAMachineAdapterAccess {}
                """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        switch adapterNestingMode(for: declaration, at: node, in: context) {
        case .nested(let model):
            guard let parsed = NestedAdapterModelRegistry.model(named: model.name.text) else {
                context.diagnose(Diagnostic(
                    node: Syntax(node),
                    message: AdapterNestingDiagnostic(message: "Nested adapter could not resolve its enclosing @TLAModel")
                ))
                return []
            }
            return MacroExpander.generateNestedAdapterMembers(
                kind: .observable,
                canonicalModel: parsed
            )
        case .invalid:
            return []
        case .standalone:
            break
        }
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

private struct AdapterNestingDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "invalid-adapter-nesting")
    let severity: DiagnosticSeverity = .error
}

private enum AdapterNestingMode {
    case standalone
    case nested(StructDeclSyntax)
    case invalid
}

private func adapterNestingMode(
    for declaration: some DeclGroupSyntax,
    at attribute: AttributeSyntax,
    in context: some MacroExpansionContext
) -> AdapterNestingMode {
    let ancestors = enclosingModelDeclarations(in: context)
    if ancestors.count > 1 {
        context.diagnose(Diagnostic(
            node: Syntax(attribute),
            message: AdapterNestingDiagnostic(message: "Adapter must be enclosed by exactly one @TLAModel")
        ))
        return .invalid
    }
    if let model = ancestors.first {
        guard let structModel = model.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(attribute),
                message: AdapterNestingDiagnostic(message: "Nested adapters require an enclosing @TLAModel struct")
            ))
            return .invalid
        }
        return .nested(structModel)
    }
    if TLASpecVerifier.findSpec(in: declaration.memberBlock.members) == nil {
        context.diagnose(Diagnostic(
            node: Syntax(attribute),
            message: AdapterNestingDiagnostic(message: "Adapter without a spec must be enclosed by one @TLAModel")
        ))
        return .invalid
    }
    return .standalone
}

private func enclosingModelDeclarations(in context: some MacroExpansionContext) -> [DeclGroupSyntax] {
    var enclosing: [DeclGroupSyntax] = []
    for node in context.lexicalContext {
        if let candidate = node.as(StructDeclSyntax.self), hasTLAModelAttribute(candidate.attributes) {
            enclosing.append(candidate)
        } else if let candidate = node.as(ClassDeclSyntax.self), hasTLAModelAttribute(candidate.attributes) {
            enclosing.append(candidate)
        } else if let candidate = node.as(ActorDeclSyntax.self), hasTLAModelAttribute(candidate.attributes) {
            enclosing.append(candidate)
        }
    }
    return enclosing
}

private func hasTLAModelAttribute(_ attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else { return false }
        return attribute.attributeName.trimmedDescription == "TLAModel"
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
        node: finder.resolvedNode() ?? Syntax(declaration),
        message: ParserDiagnosticMessage(message: diagnostic.message)
    )
}

private final class ParserDiagnosticNodeFinder: SyntaxAnyVisitor {
    let source: String
    let offset: Int?
    var node: Syntax?
    private var sourceMatch: Syntax?

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
        if matchesSource, sourceMatch == nil {
            sourceMatch = candidate
        }
        if matchesOffset && matchesSource {
            node = candidate
            return .skipChildren
        }
        return .visitChildren
    }

    func resolvedNode() -> Syntax? {
        node ?? sourceMatch
    }
}
