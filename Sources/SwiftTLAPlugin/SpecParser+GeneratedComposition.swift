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
            propertyDeclarationOffsets["generatedModelInstances.\(name).bindings.\(field)", default: []].append(
                value.expression.positionAfterSkippingLeadingTrivia.utf8Offset)
            bindings.append(.init(fieldName: field, source: source))
        }
        return .init(name: name, targetModelType: typePath.joined(separator: "."), fieldBindings: bindings)
    }

    func parseGeneratedModelRefinement(
        _ call: FunctionCallExprSyntax, named name: String, into components: inout TLASpec
    ) -> ParsedGeneratedModelRefinement? {
        let labels = call.arguments.filter { $0.label?.text == "label" }
        let label = labels.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        let behaviors = call.arguments.filter { $0.label?.text == "behavior" }
        let behavior = behaviors.first?.expression.as(MemberAccessExprSyntax.self)
            .flatMap { ModelBehavior(rawValue: $0.declName.baseName.sourceIdentifierName) }
        guard call.arguments.count == 1 + labels.count + behaviors.count,
              labels.isEmpty || (labels.count == 1 && label?.isEmpty == false),
              behaviors.isEmpty || (behaviors.count == 1 && behavior != nil),
              let instanceArgument = call.arguments.first(where: { $0.label?.text == "instance" }),
              let reference = instanceArgument.expression.as(DeclReferenceExprSyntax.self),
              let instance = specBindings.generatedInstances[reference.baseName.sourceIdentifierName],
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
                  mapping.arguments.count == 2 || mapping.arguments.count == 3,
                  let target = mapping.arguments.first,
                  let field = generatedFieldName(target.expression),
                  let value = mapping.arguments.first(where: { $0.label?.text == "from" }),
                  value.label?.text == "from",
                  let source = decodeTypedFacadeValue(value.expression, scope: sourceScope) else {
                components.diagnostics.append(.init(
                    message: "Refinement mappings require distinct Map(\\.field, from: typedValue) entries.",
                    source: statement))
                return nil
            }
            let projection = mapping.arguments.first(where: { $0.label?.text == "projecting" })
            guard
                  (projection == nil && mapping.arguments.count == 2)
                    || (projection != nil && mapping.arguments.count == 3),
                  projection == nil || projection?.expression.as(MemberAccessExprSyntax.self)?
                    .declName.baseName.sourceIdentifierName == "self",
                  seen.insert(field).inserted else {
                components.diagnostics.append(.init(
                    message: "Refinement mappings require distinct Map(\\.field, from: typedValue) entries.",
                    source: statement))
                return nil
            }
            propertyDeclarationOffsets["generatedRefinements.\(name).mappings.\(field)", default: []].append(
                value.expression.positionAfterSkippingLeadingTrivia.utf8Offset)
            mappings.append(.init(fieldName: field, source: source, projected: projection != nil))
        }
        propertyDeclarationOffsets["generatedRefinements.\(name)", default: []].append(
            call.positionAfterSkippingLeadingTrivia.utf8Offset)
        return .init(name: name, reference: .init(name: name, displayLabel: label),
            instanceName: instance.name, behavior: behavior ?? .specification, fieldMappings: mappings)
    }

    private func generatedFieldName(_ expression: ExprSyntax) -> String? {
        guard let keyPath = expression.as(KeyPathExprSyntax.self),
              keyPath.root == nil, keyPath.components.count == 1,
              let field = keyPath.components.first?.component.as(KeyPathPropertyComponentSyntax.self),
              field.genericArgumentClause == nil else { return nil }
        return field.declName.baseName.sourceIdentifierName
    }
}
