import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct StateExprStructuralMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDeclaration = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: StructuralMacroDiagnostic(
                "What failed: StateExpr structural generation. Where: @StateExprStructural. "
                    + "Expected an enum declaration; found a non-enum declaration. What changed: no members were generated. "
                    + "Next safe action: attach this internal macro only to StateExpr."
            )))
            return []
        }

        let cases = enumDeclaration.memberBlock.members.flatMap { member -> [EnumCaseElementSyntax] in
            member.decl.as(EnumCaseDeclSyntax.self).map { Array($0.elements) } ?? []
        }
        guard !cases.isEmpty else {
            context.diagnose(Diagnostic(node: Syntax(enumDeclaration), message: StructuralMacroDiagnostic(
                "What failed: StateExpr structural generation. Where: StateExpr. Expected at least one enum case; found none. "
                    + "What changed: no members were generated. Next safe action: declare the StateExpr cases before applying the macro."
            )))
            return []
        }

        do {
            let specifications = try cases.map(StructuralCase.init)
            return [
                DeclSyntax(stringLiteral: tagDeclaration(for: specifications)),
                DeclSyntax(stringLiteral: tagProperty(for: specifications)),
                DeclSyntax(stringLiteral: childVisitor(for: specifications)),
                DeclSyntax(stringLiteral: childMapper(for: specifications))
            ]
        } catch let error as StructuralMacroError {
            context.diagnose(Diagnostic(node: Syntax(error.node), message: StructuralMacroDiagnostic(error.message)))
            return []
        }
    }
}

private struct StructuralCase {
    let name: String
    let parameters: [StructuralParameter]

    init(_ element: EnumCaseElementSyntax) throws {
        name = element.name.text
        parameters = try (element.parameterClause?.parameters ?? []).enumerated().map { index, parameter in
            try StructuralParameter(parameter, index: index)
        }
    }
}

private struct StructuralParameter {
    let kind: StructuralParameterKind
    let argumentLabel: String?

    init(_ parameter: EnumCaseParameterSyntax, index: Int) throws {
        let spelling = parameter.type.trimmedDescription.filter { !$0.isWhitespace }
        guard let kind = StructuralParameterKind(spelling: spelling) else {
            throw StructuralMacroError(
                node: Syntax(parameter),
                message: "What failed: StateExpr structural generation. Where: case payload \(index + 1). "
                    + "Expected a supported structural payload; found '\(parameter.type.trimmedDescription)'. "
                    + "What changed: no members were generated. Next safe action: add this payload shape to the internal structural macro before adding the case."
            )
        }
        self.kind = kind
        argumentLabel = parameter.firstName.map(\.text).flatMap { $0 == "_" ? nil : $0 }
    }
}

private enum StructuralParameterKind {
    case scalar
    case expression
    case expressionArray
    case expressionDictionary
    case optionalExpression
    case lambda
    case formalOperator
    case formalCallArgumentArray
    case localOperatorArray

    init?(spelling: String) {
        switch spelling {
        case "StateExpr": self = .expression
        case "[StateExpr]": self = .expressionArray
        case "[String:StateExpr]": self = .expressionDictionary
        case "StateExpr?": self = .optionalExpression
        case "FormalLambda": self = .lambda
        case "FormalOperator": self = .formalOperator
        case "[FormalCallArgument]": self = .formalCallArgumentArray
        case "[LocalOperator]": self = .localOperatorArray
        case "TLAValue", "String", "Int", "Bool": self = .scalar
        default: return nil
        }
    }
}

private struct StructuralMacroError: Error {
    let node: Syntax
    let message: String
}

private struct StructuralMacroDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "stateexpr-structural-generation")
    let severity: DiagnosticSeverity = .error

    init(_ message: String) {
        self.message = message
    }
}

private func tagDeclaration(for cases: [StructuralCase]) -> String {
    let entries = cases.map { "case \(escapedIdentifier($0.name))" }.joined(separator: "\n        ")
    return """
    package enum StructuralTag: String, Sendable {
        \(entries)
    }
    """
}

private func tagProperty(for cases: [StructuralCase]) -> String {
    let entries = cases.map { specification in
        "case .\(specification.name): return .\(specification.name)"
    }.joined(separator: "\n        ")
    return """
    package var structuralTag: StructuralTag {
        switch self {
        \(entries)
        }
    }
    """
}

private func childVisitor(for cases: [StructuralCase]) -> String {
    let entries = cases.map(visitorCase).joined(separator: "\n        ")
    return """
    package func forEachStructuralChild(_ body: (String, StateExpr) -> Void) {
        func visitLambda(_ lambda: FormalLambda, at path: String) {
            body(path + ".body", lambda.body)
        }
        func visitOperator(_ formalOperator: FormalOperator, at path: String) {
            if case .lambda(let lambda) = formalOperator {
                visitLambda(lambda, at: path)
            }
        }
        func visitArgument(_ argument: FormalCallArgument, at path: String) {
            switch argument {
            case .value(let expression): body(path + ".value", expression)
            case .operator(let formalOperator): visitOperator(formalOperator, at: path + ".operator")
            }
        }
        func visitLocalOperator(_ localOperator: LocalOperator, at path: String) {
            body(path + ".body", localOperator.body)
        }
        switch self {
        \(entries)
        }
    }
    """
}

private func childMapper(for cases: [StructuralCase]) -> String {
    let entries = cases.map(mapperCase).joined(separator: "\n        ")
    return """
    package func mapStructuralChildren(_ transform: (String, StateExpr) -> StateExpr) -> StateExpr {
        func mapLambda(_ lambda: FormalLambda, at path: String) -> FormalLambda {
            FormalLambda(parameters: lambda.parameters, body: transform(path + ".body", lambda.body))
        }
        func mapOperator(_ formalOperator: FormalOperator, at path: String) -> FormalOperator {
            switch formalOperator {
            case .lambda(let lambda): return .lambda(mapLambda(lambda, at: path))
            case .reference: return formalOperator
            }
        }
        func mapArgument(_ argument: FormalCallArgument, at path: String) -> FormalCallArgument {
            switch argument {
            case .value(let expression): return .value(transform(path + ".value", expression))
            case .operator(let formalOperator): return .operator(mapOperator(formalOperator, at: path + ".operator"))
            }
        }
        func mapLocalOperator(_ localOperator: LocalOperator, at path: String) -> LocalOperator {
            LocalOperator(
                localOperator.name,
                parameters: localOperator.parameters,
                body: transform(path + ".body", localOperator.body)
            )
        }
        switch self {
        \(entries)
        }
    }
    """
}

private func visitorCase(_ specification: StructuralCase) -> String {
    let bindings = specification.parameters.enumerated().map { index, parameter in
        let binding = "let value\(index)"
        return parameter.argumentLabel.map { "\($0): \(binding)" } ?? binding
    }.joined(separator: ", ")
    let statements = specification.parameters.enumerated().compactMap { index, parameter in
        visitorStatements(for: parameter.kind, value: "value\(index)", path: "\(index)")
    }.joined(separator: "\n            ")
    let body = statements.isEmpty ? "break" : statements
    return "case .\(specification.name)(\(bindings)):\n            \(body)"
}

private func mapperCase(_ specification: StructuralCase) -> String {
    let bindings = specification.parameters.enumerated().map { index, parameter in
        let binding = "let value\(index)"
        return parameter.argumentLabel.map { "\($0): \(binding)" } ?? binding
    }.joined(separator: ", ")
    let arguments = specification.parameters.enumerated().map { index, parameter in
        let expression = mapperExpression(for: parameter.kind, value: "value\(index)", path: "\(index)")
        return parameter.argumentLabel.map { "\($0): \(expression)" } ?? expression
    }.joined(separator: ", ")
    return "case .\(specification.name)(\(bindings)):\n            return .\(specification.name)(\(arguments))"
}

private func visitorStatements(for kind: StructuralParameterKind, value: String, path: String) -> String? {
    switch kind {
    case .scalar:
        nil
    case .expression:
        "body(\"\(path)\", \(value))"
    case .expressionArray:
        "\(value).enumerated().forEach { index, child in body(\"\(path)[\\(index)]\", child) }"
    case .expressionDictionary:
        "\(value).keys.sorted().forEach { key in body(\"\(path)[\\(key)]\", \(value)[key]!) }"
    case .optionalExpression:
        "\(value).map { body(\"\(path)\", $0) }"
    case .lambda:
        "visitLambda(\(value), at: \"\(path)\")"
    case .formalOperator:
        "visitOperator(\(value), at: \"\(path)\")"
    case .formalCallArgumentArray:
        "\(value).enumerated().forEach { index, argument in visitArgument(argument, at: \"\(path)[\\(index)]\") }"
    case .localOperatorArray:
        "\(value).enumerated().forEach { index, localOperator in visitLocalOperator(localOperator, at: \"\(path)[\\(index)]\") }"
    }
}

private func mapperExpression(for kind: StructuralParameterKind, value: String, path: String) -> String {
    switch kind {
    case .scalar:
        value
    case .expression:
        "transform(\"\(path)\", \(value))"
    case .expressionArray:
        "\(value).enumerated().map { index, child in transform(\"\(path)[\\(index)]\", child) }"
    case .expressionDictionary:
        "Dictionary(uniqueKeysWithValues: \(value).keys.sorted().map { key in (key, transform(\"\(path)[\\(key)]\", \(value)[key]!)) })"
    case .optionalExpression:
        "\(value).map { transform(\"\(path)\", $0) }"
    case .lambda:
        "mapLambda(\(value), at: \"\(path)\")"
    case .formalOperator:
        "mapOperator(\(value), at: \"\(path)\")"
    case .formalCallArgumentArray:
        "\(value).enumerated().map { index, argument in mapArgument(argument, at: \"\(path)[\\(index)]\") }"
    case .localOperatorArray:
        "\(value).enumerated().map { index, localOperator in mapLocalOperator(localOperator, at: \"\(path)[\\(index)]\") }"
    }
}

private func escapedIdentifier(_ identifier: String) -> String {
    ["as", "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "guard", "if", "import", "in", "indirect", "init", "inout", "internal", "is", "let", "nil", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while"].contains(identifier)
        ? "`\(identifier)`"
        : identifier
}
