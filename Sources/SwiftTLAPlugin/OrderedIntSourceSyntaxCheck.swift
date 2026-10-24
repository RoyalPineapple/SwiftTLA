import Foundation
import SwiftSyntax
import SwiftTLA

enum OrderedIntSourceSyntaxCheck {
    private enum Component {
        case variable(root: String, initialization: VariableInitialization)
        case step(label: String, assignments: [(root: String, value: StateExpr)])
    }

    static func verify(_ syntax: ClosureExprSyntax, parsed: TLASpec, enums: [SourceEnum]) throws {
        let registered = Set(syntax.statements.compactMap { item -> String? in
            guard case .expr(let expression) = item.item else { return nil }
            return expression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName
        })
        for item in syntax.statements {
            guard case .decl(let declaration) = item.item,
                  let variable = declaration.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.text == "let", variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                  registered.contains(name),
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Algorithm",
                  let expected = components(of: call, enums: enums) else { continue }
            let matches = parsed.sourceAlgorithms.filter { $0.model.name == name }
            guard matches.count == 1, agrees(expected, with: matches[0].model) else {
                throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape,
                    stage: .validation, path: "algorithms.\(name).authoredSyntax",
                    expected: "the Int initializers and ordered Do assignments in the authored #spec",
                    actual: "the parsed source model changes an initial value, label, target, read, or addition",
                    nextSafeAction: "Report this #spec syntax-to-source-model translation failure.")
            }
        }
    }

    private static func components(of call: FunctionCallExprSyntax, enums: [SourceEnum]) -> [Component]? {
        guard call.arguments.allSatisfy({ $0.label?.text == "label" || $0.label?.text == "scoped" }),
              let closure = call.arguments.first(where: { $0.label?.text == "scoped" })?
                .expression.as(ClosureExprSyntax.self),
              let scope = scopeName(of: closure) else { return nil }
        var roots: [String: String] = [:]
        var result: [Component] = []
        for item in closure.statements {
            if case .decl(let declaration) = item.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               variable.bindingSpecifier.text == "let", variable.bindings.count == 1,
               let binding = variable.bindings.first,
               let sourceName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
               let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
               let member = initializer.calledExpression.as(MemberAccessExprSyntax.self),
               member.base?.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == scope,
               member.declName.baseName.text == "sharedVar",
               initializer.arguments.allSatisfy({ $0.label?.text == "_name" || $0.label?.text == "initial" }),
               let initial = initializer.arguments.first(where: { $0.label?.text == "initial" })?.expression,
               let initialValue = value(initial, roots: roots) {
                let root = initializer.arguments.first(where: { $0.label?.text == "_name" })?
                    .expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? sourceName
                guard roots.updateValue(root, forKey: sourceName) == nil else { return nil }
                let initialization: VariableInitialization
                if case .value(.int(let number)) = initialValue {
                    initialization = .value(.int(number))
                } else {
                    initialization = .expression(initialValue)
                }
                result.append(.variable(root: root, initialization: initialization))
                continue
            }
            guard case .expr(let expression) = item.item,
                  let step = expression.as(FunctionCallExprSyntax.self),
                  step.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Do",
                  step.arguments.count == 1, step.arguments.first?.label == nil,
                  let labelExpression = step.arguments.first?.expression,
                  let labelAccess = labelExpression.as(MemberAccessExprSyntax.self),
                  let enumName = labelAccess.base?.as(DeclReferenceExprSyntax.self)?
                    .baseName.sourceIdentifierName,
                  case .string(let label) = enums.first(where: { $0.typeName == enumName })?
                    .value(named: labelAccess.declName.baseName.sourceIdentifierName),
                  let body = step.trailingClosure, !body.statements.isEmpty else { return nil }
            var assignments: [(root: String, value: StateExpr)] = []
            for statement in body.statements {
                guard case .expr(let expression) = statement.item,
                      let assignment = expression.as(FunctionCallExprSyntax.self),
                      assignment.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Assign",
                      assignment.arguments.count == 2,
                      assignment.arguments.first?.label == nil,
                      assignment.arguments.last?.label?.text == "to",
                      let targetName = assignment.arguments.first?.expression
                        .as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName,
                      let target = roots[targetName],
                      let valueSyntax = assignment.arguments.first(where: { $0.label?.text == "to" })?.expression,
                      let value = value(valueSyntax, roots: roots) else { return nil }
                assignments.append((target, value))
            }
            result.append(.step(label: label, assignments: assignments))
        }
        guard result.contains(where: { if case .step = $0 { return true }; return false }) else { return nil }
        return result
    }

    private static func scopeName(of closure: ClosureExprSyntax) -> String? {
        switch closure.signature?.parameterClause {
        case .simpleInput(let list): return list.count == 1 ? list.first?.name.sourceIdentifierName : nil
        case .parameterClause(let clause):
            guard clause.parameters.count == 1, let parameter = clause.parameters.first else { return nil }
            return (parameter.secondName ?? parameter.firstName).sourceIdentifierName
        case nil: return nil
        }
    }

    private static func integer(_ syntax: ExprSyntax) -> Int? {
        if let literal = syntax.as(IntegerLiteralExprSyntax.self) {
            return Int(literal.literal.text.replacingOccurrences(of: "_", with: ""))
        }
        if let prefix = syntax.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "-",
           let literal = prefix.expression.as(IntegerLiteralExprSyntax.self) {
            return Int("-" + literal.literal.text.replacingOccurrences(of: "_", with: ""))
        }
        return nil
    }

    private static func value(_ syntax: ExprSyntax, roots: [String: String]) -> StateExpr? {
        if let integer = integer(syntax) { return .value(.int(integer)) }
        if let name = syntax.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName,
           let root = roots[name] { return .variable(root) }
        if let group = syntax.as(TupleExprSyntax.self), group.elements.count == 1,
           let element = group.elements.first { return value(element.expression, roots: roots) }
        if let infix = syntax.as(InfixOperatorExprSyntax.self),
           infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+",
           let lhs = value(infix.leftOperand, roots: roots),
           let rhs = value(infix.rightOperand, roots: roots) { return .add(lhs, rhs) }
        if let sequence = syntax.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count >= 3, elements.count % 2 == 1,
                  let first = value(elements[0], roots: roots) else { return nil }
            var result = first
            for index in stride(from: 1, to: elements.count, by: 2) {
                guard elements[index].as(BinaryOperatorExprSyntax.self)?.operator.text == "+",
                      let rhs = value(elements[index + 1], roots: roots) else { return nil }
                result = .add(result, rhs)
            }
            return result
        }
        return nil
    }

    private static func agrees(_ expected: [Component], with parsed: AlgorithmModel) -> Bool {
        guard parsed.components.count == expected.count else { return false }
        for (source, actual) in zip(expected, parsed.components) {
            switch (source, actual) {
            case (.variable(let root, let initialization), .shared(let state)):
                guard state.root == root, state.initialization == initialization else { return false }
                if case .value = initialization {
                    guard state.swiftTypeName == "Int" else { return false }
                } else {
                    guard state.swiftTypeName == nil || state.swiftTypeName == "Int" else { return false }
                }
            case (.step(let label, let assignments), .step(let step)):
                guard step.label.name == label, step.loopCondition == nil,
                      step.statements.count == assignments.count else { return false }
                for (source, actual) in zip(assignments, step.statements) {
                    guard case .set(.root(let root), let value) = actual,
                          root == source.root, value == source.value else { return false }
                }
            default: return false
            }
        }
        return true
    }
}
