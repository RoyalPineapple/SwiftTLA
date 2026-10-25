import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

enum OrderedIntSourceSyntaxCheck {
    private typealias Component = _OrderedIntSourceComponent

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
            guard matches.count == 1, matches[0].model.matchesOrderedIntSource(expected) else {
                throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape,
                    stage: .validation, path: "algorithms.\(name).authoredSyntax",
                    expected: "the Int initializers and ordered Do assignments in the authored #spec",
                    actual: "the parsed source model changes an initial value, label, target, read, or addition",
                    nextSafeAction: "Report this #spec syntax-to-source-model translation failure.")
            }
        }
    }

    static func verifyRewrite(_ source: ClosureExprSyntax, rewritten: ClosureExprSyntax) throws {
        guard source.statements.count == rewritten.statements.count else {
            throw drift("specification")
        }
        for (original, expanded) in zip(source.statements, rewritten.statements) {
            guard case .decl(let declaration) = original.item,
                  let variable = declaration.as(VariableDeclSyntax.self),
                  variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Algorithm",
                  components(of: call, enums: nil) != nil else { continue }
            guard case .decl(let outputDeclaration) = expanded.item,
                  let output = outputDeclaration.as(VariableDeclSyntax.self),
                  output.bindings.count == 1,
                  let outputBinding = output.bindings.first,
                  outputBinding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName == name,
                  var outputCall = outputBinding.initializer?.value.as(FunctionCallExprSyntax.self),
                  let identity = outputCall.arguments.first,
                  identity.label?.text == "_name",
                  identity.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue == name,
                  let sourceBody = call.arguments.first(where: { $0.label?.text == "scoped" })?
                    .expression.as(ClosureExprSyntax.self),
                  var outputBody = outputCall.arguments.first(where: { $0.label?.text == "scoped" })?
                    .expression.as(ClosureExprSyntax.self),
                  sourceBody.statements.count == outputBody.statements.count else {
                throw drift(name)
            }

            var normalizedStatements: [CodeBlockItemSyntax] = []
            for (sourceItem, outputItem) in zip(sourceBody.statements, outputBody.statements) {
                var normalized = outputItem
                if case .decl(let sourceDecl) = sourceItem.item,
                   let sourceVar = sourceDecl.as(VariableDeclSyntax.self),
                   let sourceBinding = sourceVar.bindings.first,
                   sourceVar.bindings.count == 1,
                   let root = sourceBinding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                   let sourceCall = sourceBinding.initializer?.value.as(FunctionCallExprSyntax.self),
                   sourceCall.arguments.contains(where: { $0.label?.text == "_name" }) == false,
                   case .decl(let outputDecl) = outputItem.item,
                   var outputVar = outputDecl.as(VariableDeclSyntax.self),
                   var outputBinding = outputVar.bindings.first,
                   var outputInitializer = outputBinding.initializer,
                   var outputVariableCall = outputInitializer.value.as(FunctionCallExprSyntax.self),
                   let added = outputVariableCall.arguments.first,
                   added.label?.text == "_name",
                   added.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue == root {
                    outputVariableCall.arguments = LabeledExprListSyntax(outputVariableCall.arguments.dropFirst())
                    outputInitializer.value = ExprSyntax(outputVariableCall)
                    outputBinding.initializer = outputInitializer
                    outputVar.bindings = PatternBindingListSyntax([outputBinding])
                    normalized.item = .decl(DeclSyntax(outputVar))
                }
                guard tokens(sourceItem) == tokens(normalized) else { throw drift(name) }
                normalizedStatements.append(normalized)
            }
            outputBody.statements = CodeBlockItemListSyntax(normalizedStatements)
            guard tokens(sourceBody) == tokens(outputBody) else { throw drift(name) }
            outputCall.arguments = LabeledExprListSyntax(outputCall.arguments.dropFirst().map { argument in
                guard argument.label?.text == "scoped" else { return argument }
                var result = argument
                result.expression = ExprSyntax(outputBody)
                return result
            })
            guard tokens(call) == tokens(outputCall) else { throw drift(name) }
            for (sourceItem, outputItem) in zip(source.statements, rewritten.statements) {
                guard case .expr(let expression) = sourceItem.item,
                      expression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == name
                else { continue }
                guard tokens(sourceItem) == tokens(outputItem) else { throw drift(name) }
            }
        }
    }

    static func checkingBuilderOutput(_ source: ClosureExprSyntax, built: ExprSyntax) throws -> ExprSyntax {
        let registered = Set(source.statements.compactMap { item -> String? in
            guard case .expr(let expression) = item.item else { return nil }
            return expression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName
        })
        var witnessCalls: [String] = []
        for item in source.statements {
            guard case .decl(let declaration) = item.item,
                  let variable = declaration.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.text == "let", variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                  registered.contains(name),
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Algorithm",
                  let expected = components(of: call, enums: nil) else { continue }
            let rendered = try expected.map(render).joined(separator: ", ")
            witnessCalls.append("._checkingOrderedIntSource(algorithm: \(String(reflecting: name)), components: [\(rendered)])")
        }
        guard !witnessCalls.isEmpty else { return built }
        return ExprSyntax(stringLiteral: built.trimmedDescription + witnessCalls.joined())
    }

    private static func render(_ component: Component) throws -> String {
        switch component {
        case .variable(let root, let initialization):
            let value: String
            switch initialization {
            case .value(.int(let number)): value = ".value(.int(\(number)))"
            case .expression(let expression): value = ".expression(\(try render(expression)))"
            default: throw drift(root)
            }
            return ".variable(root: \(String(reflecting: root)), initialization: \(value))"
        case .step(let label, let assignments):
            let identifiers = label.split(separator: ".", omittingEmptySubsequences: false)
            guard identifiers.count == 2 else { throw drift(label) }
            let qualifiedLabel = identifiers.map { "`\($0)`" }.joined(separator: ".")
            let writes = try assignments.map { assignment in
                "(root: \(String(reflecting: assignment.root)), value: \(try render(assignment.value)))"
            }.joined(separator: ", ")
            return ".step(label: \(qualifiedLabel).rawValue, assignments: [\(writes)])"
        }
    }

    private static func render(_ expression: StateExpr) throws -> String {
        switch expression {
        case .value(.int(let number)): return ".value(.int(\(number)))"
        case .variable(let root): return ".variable(\(String(reflecting: root)))"
        case .add(let lhs, let rhs): return ".add(\(try render(lhs)), \(try render(rhs)))"
        default: throw drift("ordered Int expression")
        }
    }

    private static func tokens(_ syntax: some SyntaxProtocol) -> [String] {
        syntax.tokens(viewMode: .sourceAccurate).map(\.text)
    }

    private static func drift(_ name: String) -> CompilationDiagnostic {
        CompilationDiagnostic(code: .unsupportedGeneratedValueShape,
            stage: .validation, path: "algorithms.\(name).macroRewrite",
            expected: "the same ordered Int algorithm with only bound identity arguments added",
            actual: "the expanded #spec changes an identity, initializer, step, or assignment",
            nextSafeAction: "Report this #spec expansion failure.")
    }

    private static func components(of call: FunctionCallExprSyntax, enums: [SourceEnum]?) -> [Component]? {
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
               initializer.arguments.allSatisfy({
                   $0.label?.text == "_name" || $0.label?.text == "label" || $0.label?.text == "initial"
               }),
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
                  let body = step.trailingClosure, !body.statements.isEmpty else { return nil }
            let label: String
            if let enums {
                guard case .string(let value) = enums.first(where: { $0.typeName == enumName })?
                    .value(named: labelAccess.declName.baseName.sourceIdentifierName) else { return nil }
                label = value
            } else {
                label = "\(enumName).\(labelAccess.declName.baseName.sourceIdentifierName)"
            }
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
}
