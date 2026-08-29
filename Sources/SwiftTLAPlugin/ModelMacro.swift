import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

// MARK: - Shared parsing and verification

struct ParsedEnum {
    let typeName: String
    let cases: [(name: String, value: TLAValue)]
    let formalDomainValues: [TLAValue]
}

struct MacroCompilation {
    let typeName: String
    let compilation: CompiledSpecification
    let enumInfos: [ParsedEnum]
}

enum TLASpecVerifier {
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
            throw ModelMacroError.invalidHost
        }

        guard let source = try Self.findSpec(in: memberList) else {
            throw ModelMacroError.missingSpecification(typeName: typeName)
        }

        let enumInfos = try Self.collectEnumVariables(from: memberList)
        let enumDefinitions = enumInfos.map {
            ParserEnumDefinition(
                typeName: $0.typeName,
                cases: TLARecord($0.cases.map { .init($0.name, $0.value) }),
                finiteValues: $0.formalDomainValues
            )
        }
        let parsed = SpecParser.parseSpecClosure(
            source.closure,
            enumDefinitions: enumDefinitions
        )
        let compilation = try parsed.compile(specificationName: source.name)
        if parsed.hasStateDeclarations == false {
            throw ModelMacroError.emptyState
        }

        return MacroCompilation(
            typeName: typeName,
            compilation: compilation,
            enumInfos: enumInfos
        )
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
                throw ModelMacroError.dynamicModuleName(.builder)
            }
            guard let closure = call.trailingClosure ?? call.arguments.last?.expression.as(ClosureExprSyntax.self) else {
                return nil
            }
            return (name, closure)
        }
        if let macro = expression.as(MacroExpansionExprSyntax.self),
           macro.macroName.text == "spec" {
            guard let name = macro.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
                throw ModelMacroError.dynamicModuleName(.specMacro)
            }
            guard let closure = macro.trailingClosure else { return nil }
            return (name, closure)
        }
        return nil
    }

    static func collectEnumVariables(from members: MemberBlockItemListSyntax) throws -> [ParsedEnum] {
        var result: [ParsedEnum] = []
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self) else { continue }
            guard let inheritance = enumDecl.inheritanceClause else { continue }

            let inheritedNames = inheritance.inheritedTypes.compactMap {
                $0.type.as(IdentifierTypeSyntax.self)?.name.text
            }
            let intBacked = inheritedNames.contains("Int")
            let stringBacked = inheritedNames.contains("String")
            guard intBacked || stringBacked else { continue }
            let formalValue = inheritedNames.contains("TLAValueType")
                || inheritedNames.contains("FiniteTLAValueDomain")
            guard formalValue || (stringBacked && inheritedNames.contains("CaseIterable")) else {
                continue
            }

            var cases: [(name: String, value: TLAValue)] = []
            var idx = 0
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else { continue }
                for element in caseDecl.elements {
                    let value: TLAValue
                    if let rawValue = element.rawValue?.value {
                        if intBacked,
                           let raw = rawValue.as(IntegerLiteralExprSyntax.self),
                           let val = Int(raw.literal.text.filter { $0 != "_" }) {
                            value = .int(val)
                            idx = val + 1
                        } else if stringBacked,
                                  let raw = rawValue.as(StringLiteralExprSyntax.self),
                                  let val = raw.representedLiteralValue {
                            value = .string(val)
                        } else {
                            throw ModelMacroError.invalidEnumRawValue(caseName: element.name.text)
                        }
                    } else if intBacked {
                        value = .int(idx)
                        idx += 1
                    } else {
                        value = .string(element.name.text)
                    }
                    cases.append((element.name.text, value))
                }
            }

            result.append(ParsedEnum(
                typeName: enumDecl.name.text,
                cases: cases,
                formalDomainValues: finiteValues(in: enumDecl, cases: cases)
            ))
        }
        return result
    }

    private static func finiteValues(
        in enumDecl: EnumDeclSyntax,
        cases: [(name: String, value: TLAValue)]
    ) -> [TLAValue] {
        guard let binding = enumDecl.memberBlock.members.lazy.compactMap({ member -> PatternBindingSyntax? in
            guard let declaration = member.decl.as(VariableDeclSyntax.self),
                  declaration.modifiers.contains(where: { $0.name.text == "static" })
            else { return nil }
            return declaration.bindings.first { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "finiteValues"
            }
        }).first,
        let initializer = binding.initializer?.value
        else { return cases.map(\.value) }

        if initializer.as(DeclReferenceExprSyntax.self)?.baseName.text == "allCases"
            || initializer.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "allCases" {
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

enum ModelMacroError: Error, CustomStringConvertible, Equatable {
    enum Source: String, Equatable {
        case builder = "TLASpec"
        case specMacro = "#spec"
    }

    case invalidHost
    case missingSpecification(typeName: String)
    case emptyState
    case dynamicModuleName(Source)
    case invalidEnumRawValue(caseName: String)
    case emptyFiniteEnum
    case emptyValueEnum

    var description: String {
        switch self {
        case .invalidHost: "@TLAModel requires a struct, class, or actor"
        case .missingSpecification(let typeName): "\(typeName) must declare a static spec"
        case .emptyState: "The specification must declare at least one state variable"
        case .dynamicModuleName(let source): "\(source.rawValue) requires a literal module name"
        case .invalidEnumRawValue(let caseName): "Enum case '\(caseName)' requires an integer or string literal raw value"
        case .emptyFiniteEnum: "A SwiftTLA finite enum must declare at least one case"
        case .emptyValueEnum: "A SwiftTLA value enum must declare at least one case"
        }
    }
}

// MARK: - Macros

public struct ModelMacro: MemberMacro, MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let enumDeclaration = member.as(EnumDeclSyntax.self),
              let inheritance = enumDeclaration.inheritanceClause
        else { return [] }
        let inheritedNames = Set(inheritance.inheritedTypes.compactMap {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text
        })
        let memberNames = Set(enumDeclaration.memberBlock.members.compactMap {
            if let variable = $0.decl.as(VariableDeclSyntax.self) {
                return variable.bindings.compactMap {
                    $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                }.first
            }
            return nil
        })
        if inheritedNames.contains("FiniteTLAValueDomain"),
           !memberNames.contains("defaultValue"),
           !memberNames.contains("finiteValues") {
            return ["@_TLAFiniteEnum"]
        }
        if inheritedNames.contains("TLAValueType"), !memberNames.contains("defaultValue") {
            return ["@_TLAValueEnum"]
        }
        return []
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard diagnoseStoredInstanceState(in: declaration, context: context) == false else {
            return []
        }
        let parsed: MacroCompilation
        do {
            parsed = try TLASpecVerifier.parseAndVerify(declaration)
        } catch let diagnostic as SourceParseDiagnostic {
            context.diagnose(parserDiagnostic(diagnostic, in: declaration))
            return []
        } catch let diagnostic as CompilationDiagnostic {
            context.diagnose(modelCompilationDiagnostic(diagnostic, in: declaration))
            return []
        } catch let diagnostic as ModelMacroError {
            context.diagnose(modelMacroDiagnostic(diagnostic, in: declaration))
            return []
        } catch {
            throw error
        }
        return MacroExpander.generateStateMachineMembers(model: parsed)
    }
}

public struct FiniteEnumMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDeclaration = declaration.as(EnumDeclSyntax.self) else {
            throw ModelMacroError.emptyFiniteEnum
        }
        let cases = enumDeclaration.memberBlock.members.flatMap {
            $0.decl.as(EnumCaseDeclSyntax.self)?.elements.map(\.name.text) ?? []
        }
        guard let firstCase = cases.first else {
            throw ModelMacroError.emptyFiniteEnum
        }
        let finiteValues = cases.map { ".\($0)" }.joined(separator: ", ")
        return [
            "public static var defaultValue: Self { .\(raw: firstCase) }",
            "public static var finiteValues: [Self] { [\(raw: finiteValues)] }"
        ]
    }

}

public struct ValueEnumMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDeclaration = declaration.as(EnumDeclSyntax.self),
              let firstCase = enumDeclaration.memberBlock.members.lazy.compactMap({
                  $0.decl.as(EnumCaseDeclSyntax.self)?.elements.first?.name.text
              }).first
        else {
            throw ModelMacroError.emptyValueEnum
        }
        return ["public static var defaultValue: Self { .\(raw: firstCase) }"]
    }
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


private struct ParserDiagnosticMessage: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "unsupported-spec-expression")
    let severity: DiagnosticSeverity = .error
}

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
            + "Next safe action: \(nextSafeAction)"
    }
}

private struct ModelMacroDiagnosticMessage: DiagnosticMessage {
    let error: ModelMacroError
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "model-macro-failure")
    let severity: DiagnosticSeverity = .error
    var message: String { error.description }
}

package func parserDiagnostic(
    _ diagnostic: SourceParseDiagnostic,
    in declaration: some DeclGroupSyntax
) -> Diagnostic {
    let finder = ParserDiagnosticNodeFinder(
        location: diagnostic.sourceSpan.location
    )
    finder.walk(Syntax(declaration))
    return Diagnostic(
        node: finder.resolvedNode() ?? Syntax(declaration),
        message: ParserDiagnosticMessage(message: diagnostic.renderedMessage)
    )
}

private func modelCompilationDiagnostic(
    _ diagnostic: CompilationDiagnostic,
    in declaration: some DeclGroupSyntax
) -> Diagnostic {
    Diagnostic(
        node: Syntax(declaration),
        message: ModelCompilationDiagnosticMessage(
            whatFailed: "compilation failed [\(diagnostic.code.rawValue)] at \(diagnostic.stage.rawValue) \(diagnostic.path)",
            expected: diagnostic.expected,
            actual: diagnostic.actual,
            nextSafeAction: diagnostic.nextSafeAction
        )
    )
}

private func modelMacroDiagnostic(
    _ error: ModelMacroError,
    in declaration: some DeclGroupSyntax
) -> Diagnostic {
    Diagnostic(
        node: Syntax(declaration),
        message: ModelMacroDiagnosticMessage(error: error)
    )
}

private final class ParserDiagnosticNodeFinder: SyntaxAnyVisitor {
    let location: CompilerSourceSpan.Location
    var node: Syntax?

    init(
        location: CompilerSourceSpan.Location
    ) {
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
        if matchesOffset {
            node = candidate
            return .skipChildren
        }
        return .visitChildren
    }

    func resolvedNode() -> Syntax? {
        node
    }
}
