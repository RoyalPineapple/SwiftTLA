import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

// MARK: - Shared parsing and verification

struct MacroCompilation {
    let typeName: String
    let api: GeneratedMachineAPI
    let program: CompiledProgram

    init(typeName: String, program: CompiledProgram) throws {
        self.typeName = typeName
        self.program = program
        api = try GeneratedMachineAPI(layout: program.layout, actions: program.behavior.actions)
    }
}

enum TLASpecVerifier {
    static func parseAndVerify(_ declaration: some DeclGroupSyntax) throws -> MacroCompilation {
        guard let declaration = declaration.as(StructDeclSyntax.self) else {
            throw ModelMacroError.invalidHost
        }
        let typeName = declaration.name.text
        let memberList = declaration.memberBlock.members

        guard let source = try Self.findSpec(in: memberList) else {
            throw ModelMacroError.missingSpecification(typeName: typeName)
        }

        let enumInfos = try Self.collectEnumVariables(from: memberList)
        let sourceMetadata = try sourceTypes(in: memberList, enums: enumInfos)
        let parser = ParserSession(sourceTypes: sourceMetadata)
        let parsed = parser.parseSpecClosure(named: source.name, source.closure)
        let compilation = try parsed.compile()
        if parsed.variables.isEmpty && parsed.sourceAlgorithms.isEmpty {
            throw ModelMacroError.emptyState
        }

        return try MacroCompilation(
            typeName: typeName,
            program: try CompiledProgram(inputs: parser.sourceTypeResolver.resolve(in: compilation))
        )
    }

    // MARK: - Helpers

    static func findSpec(in members: MemberBlockItemListSyntax) throws -> (name: String, closure: ClosureExprSyntax)? {
        let declarations = members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.filter {
            $0.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "spec" }
        }
        guard let declaration = declarations.first else { return nil }
        guard declarations.count == 1,
              declaration.modifiers.contains(where: { $0.name.text == "static" }),
              declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              binding.initializer == nil,
              let accessors = binding.accessorBlock?.accessors
        else { throw ModelMacroError.nonLiteralSpecification }

        let statements: CodeBlockItemListSyntax
        if let body = accessors.as(CodeBlockItemListSyntax.self) {
            statements = body
        } else if let getters = accessors.as(AccessorDeclListSyntax.self),
                  getters.count == 1,
                  let getter = getters.first,
                  getter.accessorSpecifier.tokenKind == .keyword(.get),
                  getter.effectSpecifiers == nil,
                  let body = getter.body {
            statements = body.statements
        } else {
            throw ModelMacroError.nonLiteralSpecification
        }
        guard statements.count == 1, let statement = statements.first else {
            throw ModelMacroError.nonLiteralSpecification
        }
        let expression: ExprSyntax?
        if case .expr(let value) = statement.item {
            expression = value
        } else {
            expression = statement.item.as(ReturnStmtSyntax.self)?.expression
        }
        guard let source = try specBuilderSource(from: expression) else {
            throw ModelMacroError.nonLiteralSpecification
        }
        return source
    }

    private static func specBuilderSource(from expression: ExprSyntax?) throws -> (name: String, closure: ClosureExprSyntax)? {
        guard let expression else { return nil }
        let arguments: LabeledExprListSyntax
        let trailingClosure: ClosureExprSyntax?
        let source: ModelMacroError.Source
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLASpec" {
            guard call.additionalTrailingClosures.isEmpty else {
                throw ModelMacroError.nonLiteralSpecification
            }
            arguments = call.arguments
            trailingClosure = call.trailingClosure
            source = .builder
        } else if let macro = expression.as(MacroExpansionExprSyntax.self),
                  macro.macroName.text == "spec" {
            guard macro.additionalTrailingClosures.isEmpty else {
                throw ModelMacroError.nonLiteralSpecification
            }
            arguments = macro.arguments
            trailingClosure = macro.trailingClosure
            source = .specMacro
        } else {
            return nil
        }
        guard let first = arguments.first,
              first.label == nil,
              let name = first.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
            throw ModelMacroError.dynamicModuleName(source)
        }
        if arguments.count == 1, let trailingClosure {
            return (name, trailingClosure)
        }
        if arguments.count == 2, trailingClosure == nil,
           let last = arguments.last,
           last.label == nil || last.label?.text == "scoped",
           let closure = last.expression.as(ClosureExprSyntax.self) {
            return (name, closure)
        }
        throw ModelMacroError.nonLiteralSpecification
    }

    /// Qualified spellings must name the module that owns the recognized type.
    static func inheritedTypeNames(in clause: InheritanceClauseSyntax?) -> Set<String> {
        Set(clause?.inheritedTypes.compactMap { inherited -> String? in
            if let type = inherited.type.as(IdentifierTypeSyntax.self), type.genericArgumentClause == nil {
                return type.name.sourceIdentifierName
            }
            guard let type = inherited.type.as(MemberTypeSyntax.self), type.genericArgumentClause == nil,
                  let module = type.baseType.as(IdentifierTypeSyntax.self), module.genericArgumentClause == nil
            else { return nil }
            let name = type.name.sourceIdentifierName
            switch (module.name.sourceIdentifierName, name) {
            case ("Swift", "Int"), ("Swift", "String"), ("Swift", "CaseIterable"),
                 ("SwiftTLA", "TLAValueType"), ("SwiftTLA", "FiniteTLAValueDomain"),
                 ("SwiftTLA", "TLARecordSchema"):
                return name
            default: return nil
            }
        } ?? [])
    }

    static func collectEnumVariables(from members: MemberBlockItemListSyntax) throws -> [SourceEnum] {
        var enums: [SourceEnum] = []
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self) else { continue }
            guard let inheritance = enumDecl.inheritanceClause else { continue }

            let inheritedNames = inheritedTypeNames(in: inheritance)
            let intBacked = inheritedNames.contains("Int")
            let stringBacked = inheritedNames.contains("String")
            guard intBacked || stringBacked else { continue }
            let formalValue = inheritedNames.contains("TLAValueType")
                || inheritedNames.contains("FiniteTLAValueDomain")
            guard formalValue || (stringBacked && inheritedNames.contains("CaseIterable")) else {
                continue
            }

            let encoding = try enumEncoding(in: enumDecl, intBacked: intBacked)
            var cases: [(name: String, value: TLAValue)] = []
            var caseNames = Set<String>()
            var caseValues = Set<TLAValue>()
            var nextInteger: Int? = 0
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else { continue }
                for element in caseDecl.elements {
                    let value: TLAValue
                    if let rawValue = element.rawValue?.value {
                        if intBacked,
                           let val = SourceIntegerLiteral.value(rawValue) {
                            value = .int(val)
                            let next = val.addingReportingOverflow(1)
                            nextInteger = next.overflow ? nil : next.partialValue
                        } else if stringBacked,
                                  let raw = rawValue.as(StringLiteralExprSyntax.self),
                                  let val = raw.representedLiteralValue {
                            value = .string(val)
                        } else {
                            throw ModelMacroError.invalidEnumRawValue(caseName: element.name.sourceIdentifierName)
                        }
                    } else if intBacked {
                        guard let integer = nextInteger else {
                            throw ModelMacroError.invalidEnumRawValue(caseName: element.name.sourceIdentifierName)
                        }
                        value = .int(integer)
                        let next = integer.addingReportingOverflow(1)
                        nextInteger = next.overflow ? nil : next.partialValue
                    } else {
                        value = .string(element.name.sourceIdentifierName)
                    }
                    let encoded: TLAValue
                    if encoding == "constant", case .string(let raw) = value {
                        encoded = .constant(raw)
                    } else {
                        encoded = value
                    }
                    let caseName = element.name.sourceIdentifierName
                    guard caseNames.insert(caseName).inserted else {
                        throw ModelMacroError.duplicateEnumCase(typeName: enumDecl.name.sourceIdentifierName, caseName: caseName)
                    }
                    guard caseValues.insert(encoded).inserted else {
                        throw ModelMacroError.duplicateEnumRawValue(typeName: enumDecl.name.sourceIdentifierName, caseName: caseName)
                    }
                    cases.append((caseName, encoded))
                }
            }

            enums.append(SourceEnum(
                typeName: enumDecl.name.text,
                cases: cases,
                finiteValues: try finiteValues(in: enumDecl, cases: cases),
                isFiniteDomain: inheritedNames.contains("FiniteTLAValueDomain")
            ))
        }
        return enums
    }

    private static func enumEncoding(in declaration: EnumDeclSyntax, intBacked: Bool) throws -> String {
        let encodings = declaration.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.filter {
            $0.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "tlaValue" }
        }
        guard let encoding = encodings.first else { return intBacked ? "int" : "string" }
        let failure = ModelMacroError.unsupportedEnumEncoding(typeName: declaration.name.text)
        guard encodings.count == 1, encoding.bindings.count == 1,
              !encoding.modifiers.contains(where: { $0.name.text == "static" }),
              let binding = encoding.bindings.first, binding.initializer == nil,
              let accessors = binding.accessorBlock?.accessors else { throw failure }
        let statements: CodeBlockItemListSyntax
        if let body = accessors.as(CodeBlockItemListSyntax.self) {
            statements = body
        } else if let getters = accessors.as(AccessorDeclListSyntax.self), getters.count == 1,
                  let getter = getters.first, getter.accessorSpecifier.tokenKind == .keyword(.get),
                  getter.effectSpecifiers == nil, let body = getter.body {
            statements = body.statements
        } else { throw failure }
        guard statements.count == 1, let statement = statements.first else { throw failure }
        let expression: ExprSyntax?
        if case .expr(let value) = statement.item { expression = value }
        else { expression = statement.item.as(ReturnStmtSyntax.self)?.expression }
        guard let call = expression?.as(FunctionCallExprSyntax.self),
              call.arguments.count == 1, call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let constructor = call.calledExpression.as(MemberAccessExprSyntax.self),
              constructor.base == nil || constructor.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLAValue",
              let argument = call.arguments.first, argument.label == nil else { throw failure }
        let isRawValue = argument.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "rawValue"
            || argument.expression.as(MemberAccessExprSyntax.self).map {
                $0.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self"
                    && $0.declName.baseName.text == "rawValue"
            } == true
        let name = constructor.declName.baseName.text
        guard isRawValue, (intBacked ? ["int"] : ["string", "constant"]).contains(name) else { throw failure }
        return name
    }

    private static func finiteValues(
        in enumDecl: EnumDeclSyntax,
        cases: [(name: String, value: TLAValue)]
    ) throws -> [TLAValue] {
        let declarations = enumDecl.memberBlock.members.compactMap {
            $0.decl.as(VariableDeclSyntax.self)
        }
        let bindings = declarations.filter {
            $0.modifiers.contains(where: { $0.name.text == "static" })
        }.flatMap { Array($0.bindings) }
        let domains = bindings.filter {
            $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "finiteValues"
        }
        guard let binding = domains.first else { return cases.map(\.value) }
        let failure = ModelMacroError.dynamicFiniteDomain(typeName: enumDecl.name.text)
        guard domains.count == 1,
              declarations.contains(where: {
                  $0.bindingSpecifier.tokenKind == .keyword(.let) && $0.bindings.contains(binding)
              }),
              binding.accessorBlock == nil,
              let initializer = binding.initializer?.value else { throw failure }

        func localName(_ expression: ExprSyntax) -> String? {
            if let reference = expression.as(DeclReferenceExprSyntax.self) {
                return reference.baseName.sourceIdentifierName
            }
            guard let member = expression.as(MemberAccessExprSyntax.self) else { return nil }
            if let base = member.base {
                guard let reference = base.as(DeclReferenceExprSyntax.self),
                      ["Self", enumDecl.name.text].contains(reference.baseName.text) else { return nil }
            }
            return member.declName.baseName.sourceIdentifierName
        }

        if localName(initializer) == "allCases" {
            guard !bindings.contains(where: {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "allCases"
            }) else { throw failure }
            return cases.map(\.value)
        }
        guard let array = initializer.as(ArrayExprSyntax.self) else { throw failure }
        return try array.elements.map { element in
            guard let name = localName(element.expression),
                  let value = cases.first(where: { $0.name == name })?.value else { throw failure }
            return value
        }
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
    case nonLiteralSpecification
    case dynamicFiniteDomain(typeName: String)
    case invalidEnumRawValue(caseName: String)
    case duplicateTypeDeclaration(typeName: String)
    case duplicateEnumCase(typeName: String, caseName: String)
    case duplicateEnumRawValue(typeName: String, caseName: String)
    case unsupportedEnumEncoding(typeName: String)
    case unsupportedRecordSchema(typeName: String)
    case emptyFiniteEnum
    case emptyValueEnum

    var description: String {
        switch self {
        case .invalidHost: "@TLAModel requires a struct"
        case .missingSpecification(let typeName): "\(typeName) must declare a static spec"
        case .emptyState: "The specification must declare at least one state variable"
        case .dynamicFiniteDomain(let typeName): "Enum \(typeName).finiteValues must be an array of its declared cases or synthesized allCases; dynamic or computed domains are not supported"
        case .nonLiteralSpecification: "The static spec getter must contain only a direct #spec or TLASpec declaration, optionally preceded by return, with a literal module name and an inline builder closure"
        case .dynamicModuleName(let source): "\(source.rawValue) requires a literal module name"
        case .unsupportedRecordSchema(let typeName): "Native type \(typeName) requires a literal alias or a record schema whose fieldName directly maps every declared key path to a unique string literal"
        case .unsupportedEnumEncoding(let typeName): "Enum \(typeName).tlaValue must directly encode rawValue as .string, .constant, or .int matching its raw type; dynamic encodings are not supported"
        case .duplicateTypeDeclaration(let typeName): "Type '\(typeName)' is declared more than once in the model"
        case .duplicateEnumCase(let typeName, let caseName): "Enum \(typeName) declares case '\(caseName)' more than once"
        case .duplicateEnumRawValue(let typeName, let caseName): "Enum \(typeName) case '\(caseName)' repeats an earlier case's raw value"
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
        let inheritedNames = TLASpecVerifier.inheritedTypeNames(in: inheritance)
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

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo _: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard diagnoseStoredInstanceState(in: declaration, context: context) == false else {
            return []
        }
        do {
            let model = try TLASpecVerifier.parseAndVerify(declaration)
            var emitter = NativeSwiftEmitter(model: model)
            return try emitter.machineMembers()
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
    }
}

public struct FiniteEnumMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
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
        conformingTo _: [TypeSyntax],
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

private struct ModelDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity = .error

    init(_ id: String, message: String) {
        self.message = message
        diagnosticID = MessageID(domain: "SwiftTLA", id: id)
    }
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
            message: ModelDiagnostic("model-instance-stored-state", message:
                "@TLAModel models cannot declare instance stored properties; model state belongs in the static specification")
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
        message: ModelDiagnostic("unsupported-spec-expression", message: diagnostic.renderedMessage)
    )
}

private func modelCompilationDiagnostic(
    _ diagnostic: CompilationDiagnostic,
    in declaration: some DeclGroupSyntax
) -> Diagnostic {
    Diagnostic(
        node: Syntax(declaration),
        message: ModelDiagnostic("model-compilation-failure", message:
            "What failed: compilation failed [\(diagnostic.code.rawValue)] at \(diagnostic.stage.rawValue) \(diagnostic.path). "
                + "Where: this @TLAModel declaration. Expected: \(diagnostic.expected). "
                + "Actual: \(diagnostic.actual). Next safe action: \(diagnostic.nextSafeAction)")
    )
}

private func modelMacroDiagnostic(
    _ error: ModelMacroError,
    in declaration: some DeclGroupSyntax
) -> Diagnostic {
    Diagnostic(
        node: Syntax(declaration),
        message: ModelDiagnostic("model-macro-failure", message: error.description)
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
