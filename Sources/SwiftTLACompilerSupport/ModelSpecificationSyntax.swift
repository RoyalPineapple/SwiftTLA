import SwiftParser
import SwiftSyntax

package enum ModelSpecificationSyntax {
    package enum Failure: Error {
        case nonLiteralSpecification, dynamicModuleName
    }

    package static func algorithmBody(_ call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        call.trailingClosure ?? call.arguments.first(where: { $0.label?.text == "scoped" })?.expression.as(ClosureExprSyntax.self)
    }

    package static func parameterNames(in closure: ClosureExprSyntax) -> [String] {
        func spelling(_ token: TokenSyntax) -> String { token.identifier?.name ?? token.text }
        switch closure.signature?.parameterClause {
        case .simpleInput(let list): return list.map { spelling($0.name) }
        case .parameterClause(let clause): return clause.parameters.map { spelling($0.secondName ?? $0.firstName) }
        case nil: return []
        }
    }

    package static func find(in members: MemberBlockItemListSyntax, defaultName: String? = nil) throws(Failure) -> (name: String, closure: ClosureExprSyntax)? {
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
        else { throw Failure.nonLiteralSpecification }

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
            throw Failure.nonLiteralSpecification
        }
        guard statements.count == 1, let statement = statements.first else {
            throw Failure.nonLiteralSpecification
        }
        let expression: ExprSyntax?
        if case .expr(let value) = statement.item {
            expression = value
        } else {
            expression = statement.item.as(ReturnStmtSyntax.self)?.expression
        }
        guard let source = try specMacroSource(from: expression, defaultName: defaultName) else {
            throw Failure.nonLiteralSpecification
        }
        return source
    }

    private static func specMacroSource(from expression: ExprSyntax?, defaultName: String?) throws(Failure) -> (name: String, closure: ClosureExprSyntax)? {
        guard let macro = expression?.as(MacroExpansionExprSyntax.self),
              macro.macroName.text == "spec" else { return nil }
        guard macro.additionalTrailingClosures.isEmpty else {
            throw Failure.nonLiteralSpecification
        }
        let arguments = macro.arguments
        let trailingClosure = macro.trailingClosure
        if arguments.isEmpty, let trailingClosure, let defaultName {
            return (defaultName, trailingClosure)
        }
        guard let first = arguments.first,
              first.label == nil,
              let name = first.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
            throw Failure.dynamicModuleName
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
        throw Failure.nonLiteralSpecification
    }
}
