import SwiftSyntax
import SwiftTLA

extension ParserSession {
    func parseGeneratedModelInstance(
        _ call: FunctionCallExprSyntax, named name: String, into components: inout TLASpec
    ) -> ParsedGeneratedModelInstance? {
        guard call.arguments.count == 1,
              let argument = call.arguments.first, argument.label?.text == "of",
              let metatype = argument.expression.as(MemberAccessExprSyntax.self),
              metatype.declName.baseName.sourceIdentifierName == "self",
              let type = metatype.base,
              let typePath = Self.sourceTypePath(type), !typePath.isEmpty,
              let body = call.trailingClosure, call.additionalTrailingClosures.isEmpty else {
            components.diagnostics.append(.init(
                message: "A generated-model Instance requires a static model type and Bind key paths.", source: call))
            return nil
        }
        var bindings: [GeneratedModelFieldBinding] = []
        var seen: Set<String> = []
        for statement in body.statements {
            guard case .expr(let expression) = statement.item,
                  let binding = expression.as(FunctionCallExprSyntax.self),
                  compilerGrammarName(in: binding.calledExpression) == "Bind",
                  binding.arguments.count == 2,
                  let target = binding.arguments.first,
                  let field = generatedFieldName(target.expression),
                  let value = binding.arguments.last,
                  value.label?.text == "to",
                  let source = decodeTypedFacadeValue(value.expression, scope: sourceScope),
                  seen.insert(field).inserted else {
                components.diagnostics.append(.init(
                    message: "Instance bindings require distinct Bind(\\.field, to: typedValue) entries.",
                    source: statement))
                return nil
            }
            bindings.append(.init(fieldName: field, source: source))
        }
        return .init(name: name, targetModelType: typePath.joined(separator: "."), fieldBindings: bindings)
    }

    func parseGeneratedModelRefinement(
        _ call: FunctionCallExprSyntax, named name: String, into components: inout TLASpec
    ) -> ParsedGeneratedModelRefinement? {
        let labels = call.arguments.filter { $0.label?.text == "label" }
        let label = labels.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        guard call.arguments.count == 1 + labels.count,
              labels.isEmpty || (labels.count == 1 && label?.isEmpty == false),
              let instanceArgument = call.arguments.first(where: { $0.label?.text == "instance" }),
              let reference = instanceArgument.expression.as(DeclReferenceExprSyntax.self),
              let instanceName = specBindings.generatedInstances[reference.baseName.sourceIdentifierName]?.name,
              let body = call.trailingClosure, call.additionalTrailingClosures.isEmpty else {
            components.diagnostics.append(.init(
                message: "A generated-model Refinement requires a declared Instance and Map key paths.",
                source: call))
            return nil
        }
        var mappings: [GeneratedModelFieldBinding] = []
        var seen: Set<String> = []
        for statement in body.statements {
            guard case .expr(let expression) = statement.item,
                  let mapping = expression.as(FunctionCallExprSyntax.self),
                  compilerGrammarName(in: mapping.calledExpression) == "Map",
                  mapping.arguments.count == 2,
                  let target = mapping.arguments.first,
                  let field = generatedFieldName(target.expression),
                  let value = mapping.arguments.last,
                  value.label?.text == "from",
                  let source = decodeTypedFacadeValue(value.expression, scope: sourceScope),
                  seen.insert(field).inserted else {
                components.diagnostics.append(.init(
                    message: "Refinement mappings require distinct Map(\\.field, from: typedValue) entries.",
                    source: statement))
                return nil
            }
            mappings.append(.init(fieldName: field, source: source))
        }
        return .init(name: name, reference: .init(name: name, displayLabel: label),
            instanceName: instanceName, fieldMappings: mappings)
    }

    private func generatedFieldName(_ expression: ExprSyntax) -> String? {
        guard let keyPath = expression.as(KeyPathExprSyntax.self),
              keyPath.root == nil, keyPath.components.count == 1,
              let field = keyPath.components.first?.component.as(KeyPathPropertyComponentSyntax.self),
              field.genericArgumentClause == nil else { return nil }
        return field.declName.baseName.sourceIdentifierName
    }
}
