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
    /// The values that belong to the formal domain. This is intentionally
    /// separate from all Swift cases: a useful formal type can include a
    /// sentinel such as `.none` without making it a process or map key.
    let formalDomain: [TLAValue]

    init(typeName: String, cases: [(String, TLAValue)], formalDomain: [TLAValue]? = nil) {
        self.typeName = typeName
        self.cases = cases
        self.formalDomain = formalDomain ?? cases.map(\.1)
    }
    var domain: Set<TLAValue> { Set(cases.map(\.value)) }
}

struct MacroCompilation {
    let typeName: String
    let compilation: CompiledSpecification
    let machineSurface: MachineSurfacePlan
    let swiftFacts: MacroSwiftFacts
    let enumInfos: [ParsedEnumInfo]

    var hasInvariants: Bool { !compilation.spec.invariants.isEmpty }
}

typealias MacroSwiftFacts = MachineSurfaceSwiftFacts

enum NestedAdapterModelRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var models: [String: MacroCompilation] = [:]

    static func record(_ model: MacroCompilation) {
        lock.lock()
        models[model.typeName] = model
        lock.unlock()
    }

    static func model(named typeName: String) -> MacroCompilation? {
        lock.lock()
        defer { lock.unlock() }
        return models[typeName]
    }
}

enum TLASpecVerifier {
    typealias EnumPhaseMap = [String: [String: TLAValue]]

    static func parseAndVerify(_ declaration: some DeclGroupSyntax) throws -> MacroCompilation {
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

        guard let source = try Self.findSpec(in: memberList) else {
            throw SimpleError("Could not find 'TLASpec' builder in '\(typeName)'")
        }

        let rewritten = rewriteVarNames(in: source.closure)
        let enumInfos = Self.collectEnumVariables(from: memberList)
        let (enumPhases, caseToType) = collectEnumMetadata(from: memberList)
        let enumDomains = Dictionary(
            uniqueKeysWithValues: enumInfos.map { ($0.typeName, $0.formalDomain) }
        )
        let rewriter = EnumDotRewriter(caseToType: caseToType)
        let dotRewrittenSyntax = rewriter.rewrite(rewritten)
        let dotRewritten = dotRewrittenSyntax.as(ClosureExprSyntax.self) ?? rewritten
        if let unknown = rewriter.unknownDots.first, !caseToType.isEmpty {
            throw SpecParser.SymmetricCollectionParseDiagnostic(
                message: "Unknown enum case '.\(unknown)'.",
                source: dotRewritten.description,
                expected: "a declared enum case or a recognized formal operator spelling",
                actual: ".\(unknown); available cases: [\(caseToType.keys.sorted().joined(separator: ", "))]",
                nextSafeAction: "Qualify the intended enum case, or use FormalOperator and FormalCallArgument spellings for formal operator syntax."
            )
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

        let compilation = try parsed.compile(
            specificationName: source.name,
            additionalInvariants: allInvariants.dropFirst(parsed.invariants.count).map { $0 }
        )
        let spec = compilation.spec

        let hasComplexType = parsed.symmetricCollections.isEmpty && parsed.variables.contains { v in
            let typeName = v.swiftTypeName ?? MacroExpander.swiftType(for: v.initial)
            return !["Int", "Bool", "String"].contains(typeName)
                && !enumInfos.contains(where: { $0.typeName == typeName })
        }

        if hasComplexType {
            SpecRegistry.register(spec)
        } else {
            let result = try ModelChecker(compilation: compilation, maxStates: 1_000_000).check()
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

        let swiftFacts = MacroSwiftFacts(
            variableTypes: Dictionary(
                uniqueKeysWithValues: parsed.variables.compactMap { variable in
                    variable.swiftTypeName.map { (variable.name, $0) }
                }
            ),
            actionBindingTypes: Dictionary(
                uniqueKeysWithValues: parsed.actions.map { ($0.name, $0.bindingSwiftTypes) }
            ),
            symmetricCollections: Dictionary(
                uniqueKeysWithValues: parsed.symmetricCollections.map {
                    ($0.name, .init(elementType: $0.elementType, valueType: $0.valueType))
                }
            ),
            collectionActions: Dictionary(
                uniqueKeysWithValues: parsed.collectionActions.map { ($0.name, $0.collectionName) }
            )
        )
        return MacroCompilation(
            typeName: typeName,
            compilation: compilation,
            machineSurface: try MachineSurfacePlan(compilation: compilation, swiftFacts: swiftFacts),
            swiftFacts: swiftFacts,
            enumInfos: enumInfos
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
            if isVar {
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

    static func findSpec(in members: MemberBlockItemListSyntax) throws -> (name: String, closure: ClosureExprSyntax)? {
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
                    if let source = try specBuilderSource(from: expr) { return source }
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
                        if let source = try specBuilderSource(from: expr) { return source }
                    }
                }
            }
        }
        return nil
    }

    private static func specBuilderSource(from expression: ExprSyntax?) throws -> (name: String, closure: ClosureExprSyntax)? {
        guard let expression else { return nil }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLASpec" {
            guard let name = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
                throw SimpleError("The formal module name in TLASpec must be a string literal; dynamic names cannot form a stable compilation identity.")
            }
            guard let closure = call.trailingClosure ?? call.arguments.last?.expression.as(ClosureExprSyntax.self) else {
                return nil
            }
            return (name, closure)
        }
        if let macro = expression.as(MacroExpansionExprSyntax.self),
           macro.macroName.text == "spec" {
            guard let name = macro.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
                throw SimpleError("The formal module name in #spec must be a string literal; dynamic names cannot form a stable compilation identity.")
            }
            guard let closure = macro.trailingClosure else { return nil }
            return (name, closure)
        }
        return nil
    }

    static func collectEnumVariables(from members: MemberBlockItemListSyntax) -> [ParsedEnumInfo] {
        var result: [ParsedEnumInfo] = []
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self) else { continue }
            guard let inheritance = enumDecl.inheritanceClause else { continue }

            let inheritedNames = inheritance.inheritedTypes.compactMap {
                $0.type.as(IdentifierTypeSyntax.self)?.name.text
            }

            guard inheritedNames.contains("TLAValueType")
                || inheritedNames.contains("FiniteTLAValueDomain")
                || inheritedNames.contains("FiniteDomainKey")
            else { continue }

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
                cases: cases,
                formalDomain: formalDomain(in: enumDecl, cases: cases)
            ))
        }
        return result
    }

    /// Reads the finite domain declaration from source so macro parsing has
    /// the same process/key members as the runtime builder. The Swift enum
    /// may have additional values for optional fields or sentinels.
    private static func formalDomain(
        in enumDecl: EnumDeclSyntax,
        cases: [(name: String, value: TLAValue)]
    ) -> [TLAValue] {
        guard let binding = enumDecl.memberBlock.members.lazy.compactMap({ member -> PatternBindingSyntax? in
            guard let declaration = member.decl.as(VariableDeclSyntax.self),
                  declaration.modifiers.contains(where: { $0.name.text == "static" })
            else { return nil }
            return declaration.bindings.first { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "formalDomain"
            }
        }).first,
        let initializer = binding.initializer?.value
        else { return cases.map(\.value) }

        if initializer.as(DeclReferenceExprSyntax.self)?.baseName.text == "allCases"
            || initializer.description.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasSuffix(".allCases") {
            return cases.map(\.value)
        }

        guard let array = initializer.as(ArrayExprSyntax.self) else {
            return cases.map(\.value)
        }
        let values = array.elements.compactMap { element -> TLAValue? in
            let name = element.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
                ?? element.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
            return cases.first { $0.name == name }?.value
        }
        return values.isEmpty ? cases.map(\.value) : values
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
        if caseName == "define",
           node.parent?.as(LabeledExprSyntax.self)?.label?.text == "plusCalPhase" {
            return super.visit(node)
        }
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
        "int", "bool", "string", "set", "tuple", "record", "function", "constant",
        // Formal operator syntax is expression data, not an application enum
        // case. Keep these members unqualified so SpecParser's existing
        // formal-expression decoder can preserve their AST structure.
        "lambda", "reference", "operator",
        // A FormalLambda body is authored with StateExpr cases. The enum-dot
        // pass runs before source parsing, so it must not mistake any of
        // those formal AST members for an application enum case.
        "add", "subtract", "multiply", "divide", "modulo", "negate", "integerDivide",
        "equal", "notEqual", "lessThan", "lessOrEqual", "greaterThan", "greaterOrEqual",
        "and", "or", "not", "ifThenElse",
        "setLiteral", "in", "subset", "union", "intersection", "setDifference",
        "setFilter", "setMap", "powerSet", "unionAll", "integerRange",
        "tupleLiteral", "tupleAccess", "tupleDynamicAccess", "tupleLength", "tupleAppend",
        "tupleHead", "tupleTail", "tupleConcatenate",
        "recordLiteral", "recordAccess", "functionLiteral", "functionApply", "except",
        "caseExpr", "forAll", "exists", "choose", "enabledAction", "sequenceFromSet",
        "setSum", "functionSet", "foldFunction", "operatorApplication", "recursiveCall",
        "letValue", "letIn",
        // These are DSL enum cases, not user-state enum cases. They remain
        // unqualified so Algorithm's parser can recognize its public syntax.
        "none", "weak", "strong"
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

private func hasZeroArgumentInitializer(in declaration: some DeclGroupSyntax) -> Bool {
    declaration.memberBlock.members.contains { member in
        guard let initializer = member.decl.as(InitializerDeclSyntax.self) else { return false }
        return initializer.signature.parameterClause.parameters.isEmpty
    }
}

public struct ModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard diagnoseStoredInstanceState(in: declaration, context: context) == false else {
            return []
        }
        guard let ext = ("""
            extension \(type.trimmed): TLAModelType, TLAMachineExecuting, TLAMachineAdapterCanonicalModel, TLAMachineSchemaProviding, TLAGeneratedLiveModel {}
            """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let parsed: MacroCompilation
        do {
            parsed = try TLASpecVerifier.parseAndVerify(declaration)
        } catch let diagnostic as SpecParser.SymmetricCollectionParseDiagnostic {
            context.diagnose(parserDiagnostic(diagnostic, in: declaration))
            return []
        } catch {
            context.diagnose(modelCompilationDiagnostic(error, in: declaration))
            return []
        }
        NestedAdapterModelRegistry.record(parsed)
        return MacroExpander.generate(
            mode: .model,
            model: parsed,
            needsPublicInitializer: !hasZeroArgumentInitializer(in: declaration)
        )
    }
}

public struct TLAActorMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        switch adapterNestingMode(for: declaration, at: node, in: context) {
        case .nested:
            guard let ext = ("""
                extension \(type.trimmed): TLAMachineAdapterAccess, TLAMachineSchemaProviding {}
                """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
            return [ext]
        case .invalid:
            return []
        }
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
                canonicalModel: parsed,
                needsPublicInitializer: !hasZeroArgumentInitializer(in: declaration)
            )
        case .invalid:
            return []
        }
    }
}

public struct TLAObservableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        switch adapterNestingMode(for: declaration, at: node, in: context) {
        case .nested:
            guard let ext = ("""
                @MainActor extension \(type.trimmed): Sendable, TLAMachineAdapterAccess, TLAMachineSchemaProviding {}
                """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
            return [ext]
        case .invalid:
            return []
        }
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
                canonicalModel: parsed,
                needsPublicInitializer: !hasZeroArgumentInitializer(in: declaration)
            )
        case .invalid:
            return []
        }
    }
}

private struct AdapterNestingDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "invalid-adapter-nesting")
    let severity: DiagnosticSeverity = .error
}

private struct ModelStoredStateDiagnostic: DiagnosticMessage {
    let message = "@TLAModel models cannot declare instance stored properties; model state belongs in the static specification"
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "model-instance-stored-state")
    let severity: DiagnosticSeverity = .error
}

private func diagnoseStoredInstanceState(
    in declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext
) -> Bool {
    for member in declaration.memberBlock.members {
        guard let variable = member.decl.as(VariableDeclSyntax.self),
              !variable.modifiers.contains(where: { $0.name.text == "static" || $0.name.text == "class" }),
              let binding = variable.bindings.first(where: isInstanceStoredBinding) else {
            continue
        }
        context.diagnose(Diagnostic(
            node: Syntax(binding.pattern),
            message: ModelStoredStateDiagnostic()
        ))
        return true
    }
    return false
}

private func isInstanceStoredBinding(_ binding: PatternBindingSyntax) -> Bool {
    guard let accessorBlock = binding.accessorBlock else { return true }
    guard case .accessors(let accessors) = accessorBlock.accessors else { return false }
    return accessors.contains { accessor in
        accessor.accessorSpecifier.text == "willSet" || accessor.accessorSpecifier.text == "didSet"
    }
}

private enum AdapterNestingMode {
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
    context.diagnose(Diagnostic(
        node: Syntax(attribute),
        message: AdapterNestingDiagnostic(message: "@TLAActor and @TLAObservable require an enclosing @TLAModel; put the formal spec on that model")
    ))
    return .invalid
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

/// SwiftDiagnostics only transports a rendered message, while the parser
/// retains the structured diagnostic separately. Keep this rendering explicit
/// so an error at the compiler boundary still answers the next useful question.
private struct ModelCompilationDiagnosticMessage: DiagnosticMessage {
    let whatFailed: String
    let expected: String
    let actual: String
    let nextSafeAction: String

    let diagnosticID = MessageID(domain: "SwiftTLA", id: "model-compilation-failure")
    let severity: DiagnosticSeverity = .error

    var message: String {
        "What failed: \(whatFailed). Where: this @TLAModel declaration. "
            + "Expected: \(expected). Actual: \(actual). "
            + "Change status: no generated model was emitted. "
            + "Next safe action: \(nextSafeAction)"
    }
}

private func parserDiagnostic(
    _ diagnostic: SpecParser.SymmetricCollectionParseDiagnostic,
    in declaration: some DeclGroupSyntax
) -> Diagnostic {
    let finder = ParserDiagnosticNodeFinder(
        source: diagnostic.source,
        location: diagnostic.sourceSpan.location
    )
    finder.walk(Syntax(declaration))
    return Diagnostic(
        node: finder.resolvedNode() ?? Syntax(declaration),
        message: ParserDiagnosticMessage(message: diagnostic.message)
    )
}

private func modelCompilationDiagnostic(
    _ error: Error,
    in declaration: some DeclGroupSyntax
) -> Diagnostic {
    Diagnostic(
        node: Syntax(declaration),
        message: ModelCompilationDiagnosticMessage(
            whatFailed: "the formal model could not be parsed or verified",
            expected: "a bounded @TLAModel specification whose declarations, imports, and properties are valid",
            actual: String(describing: error),
            nextSafeAction: "Inspect the reported formal construct, correct the model, and compile again; no generated state machine is available until this succeeds."
        )
    )
}

private final class ParserDiagnosticNodeFinder: SyntaxAnyVisitor {
    let source: String
    let location: SpecParser.SymmetricCollectionParseDiagnostic.SourceSpan.Location
    var node: Syntax?
    private var sourceMatch: Syntax?

    init(
        source: String,
        location: SpecParser.SymmetricCollectionParseDiagnostic.SourceSpan.Location
    ) {
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.location = location
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ candidate: Syntax) -> SyntaxVisitorContinueKind {
        guard node == nil else { return .skipChildren }
        let matchesOffset: Bool
        switch location {
        case .utf8Offset(let offset):
            matchesOffset = candidate.positionAfterSkippingLeadingTrivia.utf8Offset == offset
        case .unavailable:
            matchesOffset = false
        }
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
