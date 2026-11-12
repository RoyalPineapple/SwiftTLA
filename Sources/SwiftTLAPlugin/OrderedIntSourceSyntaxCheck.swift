import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

enum OrderedIntSourceSyntaxCheck {
    private typealias Component = _OrderedIntSourceComponent

    static func verify(_ syntax: ClosureExprSyntax, parsed: TLASpec, enums: [SourceEnum],
                       sourceTypes: SourceTypeMetadata? = nil) throws {
        let registered = Set(syntax.statements.compactMap { item -> String? in
            guard case .expr(let expression) = item.item else { return nil }
            return expression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName
        })
        let primitiveNames = ["Int", "Swift", "SwiftTLA", "Expr"]
        let unshadowed = !primitiveNames.contains { name in
            enums.contains { $0.typeName == name }
                || sourceTypes?.structs[name] != nil || sourceTypes?.aliases[name] != nil
        }
        if unshadowed, let expected = intInitializers(in: syntax) {
            try verifyInitializers(expected, actual: parsed.variables.map { ($0.name, $0.initialization) },
                path: "variables.authoredIntInitializers")
        }
        for item in syntax.statements {
            guard case .decl(let declaration) = item.item,
                  let variable = declaration.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.text == "let", variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                  registered.contains(name),
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == "Algorithm" else { continue }
            let matches = parsed.sourceAlgorithms.filter { $0.model.name == name }
            if unshadowed,
               let body = call.arguments.first(where: { $0.label?.text == "scoped" })?
                .expression.as(ClosureExprSyntax.self), let expected = intInitializers(in: body) {
                guard matches.count == 1 else { throw drift(name) }
                let actual = matches[0].model.components.compactMap { component -> (String, VariableInitialization)? in
                    guard case .shared(let state) = component else { return nil }
                    return (state.root, state.initialization)
                }
                try verifyInitializers(expected, actual: actual,
                    path: "algorithms.\(name).authoredSyntax")
            }
            guard let expected = components(of: call, enums: enums) else { continue }
            guard matches.count == 1, matches[0].model.matchesOrderedIntSource(expected) else {
                throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape,
                    stage: .validation, path: "algorithms.\(name).authoredSyntax",
                    expected: "the Int initializers and ordered Do assignments in the authored #spec",
                    actual: "the parsed source model changes an initial value, label, target, read, or addition",
                    nextSafeAction: "Report this #spec syntax-to-source-model translation failure.")
            }
        }
    }

    private static func verifyInitializers(_ expected: [Component],
                                          actual: [(String, VariableInitialization)], path: String) throws {
        guard expected.count == actual.count, zip(expected, actual).allSatisfy({ source, actual in
            guard case .variable(let root, let initialization) = source else { return false }
            return root == actual.0 && initialization == actual.1
        }) else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation, path: path,
                expected: "the authored deterministic Int initializers in declaration and operand order",
                actual: "the parsed initializers change a declaration, value, read, or checked addition",
                nextSafeAction: "Report this #spec initialization translation failure.")
        }
    }

    private static func intInitializers(in syntax: ClosureExprSyntax) -> [Component]? {
        guard let scope = scopeName(of: syntax) else { return nil }
        var roots: [[UInt8]: String] = [:]
        var result: [Component] = []
        for item in syntax.statements {
            if case .expr(let expression) = item.item,
               let call = expression.as(FunctionCallExprSyntax.self),
               let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName,
               ["Do", "Invariant"].contains(name) { continue }
            guard case .decl(let declaration) = item.item,
                  let variable = declaration.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.text == "let", variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  member.base?.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == scope,
                  member.declName.baseName.sourceIdentifierName == "sharedVar",
                  call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
                  call.arguments.allSatisfy({ ["_name", "label", "initial"].contains($0.label?.text ?? "") }),
                  call.arguments.filter({ $0.label?.text == "initial" }).count == 1,
                  let initial = call.arguments.first(where: { $0.label?.text == "initial" }),
                  let value = initializerValue(initial.expression, roots: roots)?.value else { return nil }
            let root: String
            if let argument = call.arguments.first(where: { $0.label?.text == "_name" }) {
                guard let name = argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else { return nil }
                root = name
            } else { root = name }
            guard roots.updateValue(root, forKey: Array(name.utf8)) == nil else { return nil }
            let initialization: VariableInitialization
            if case .value(.int(let number)) = value { initialization = .value(.int(number)) }
            else { initialization = .expression(value) }
            result.append(.variable(root: root, initialization: initialization))
        }
        return result
    }

    private static func initializerValue(_ syntax: ExprSyntax, roots: [[UInt8]: String])
        -> (value: StateExpr, formal: Bool)? {
        if let number = integer(syntax) { return (.value(.int(number)), false) }
        if let name = syntax.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName,
           let root = roots[Array(name.utf8)] {
            return (.variable(root), true)
        }
        if let prefix = syntax.as(PrefixOperatorExprSyntax.self),
           ["+", "-"].contains(prefix.operator.text),
           let operand = initializerValue(prefix.expression, roots: roots), !operand.formal,
           case .value(.int(let number)) = operand.value {
            if prefix.operator.text == "+" { return operand }
            let negative = 0.subtractingReportingOverflow(number)
            return negative.overflow ? nil : (.value(.int(negative.partialValue)), false)
        }
        if let member = syntax.as(MemberAccessExprSyntax.self),
           ["Int", "Swift.Int"].contains(member.base?.tokens(viewMode: .sourceAccurate)
                .map(\.sourceIdentifierName).joined() ?? "") {
            switch member.declName.baseName.sourceIdentifierName {
            case "min": return (.value(.int(Int.min)), false)
            case "max": return (.value(.int(Int.max)), false)
            default: return nil
            }
        }
        if let group = syntax.as(TupleExprSyntax.self), group.elements.count == 1,
           let element = group.elements.first, element.label == nil {
            return initializerValue(element.expression, roots: roots)
        }
        if let call = syntax.as(FunctionCallExprSyntax.self),
           ["Expr", "SwiftTLA.Expr", "Expr<Int>", "SwiftTLA.Expr<Int>",
            "Expr<Swift.Int>", "SwiftTLA.Expr<Swift.Int>"].contains(call.calledExpression
                .tokens(viewMode: .sourceAccurate).map(\.sourceIdentifierName).joined()),
           call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
           call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
           let operand = initializerValue(argument.expression, roots: roots), !operand.formal {
            return (operand.value, true)
        }
        let operands: [ExprSyntax]
        if let infix = syntax.as(InfixOperatorExprSyntax.self) {
            operands = [infix.leftOperand, infix.operator, infix.rightOperand]
        } else if let sequence = syntax.as(SequenceExprSyntax.self) {
            operands = Array(sequence.elements)
        } else { return nil }
        guard operands.count >= 3, operands.count % 2 == 1,
              stride(from: 1, to: operands.count, by: 2).allSatisfy({
                  operands[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "+"
              }) else { return nil }
        let split = operands.count - 2
        let left = ExprSyntax(SequenceExprSyntax(elements: ExprListSyntax(operands[..<split])))
        let leftSyntax = split == 1 ? operands[0] : left
        guard let lhs = initializerValue(leftSyntax, roots: roots),
              let rhs = initializerValue(operands[split + 1], roots: roots) else { return nil }
        if lhs.formal || rhs.formal { return (.add(lhs.value, rhs.value), true) }
        guard case .value(.int(let first)) = lhs.value,
              case .value(.int(let second)) = rhs.value else { return nil }
        let sum = first.addingReportingOverflow(second)
        return sum.overflow ? nil : (.value(.int(sum.partialValue)), false)
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
                  call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == "Algorithm",
                  components(of: call, enums: nil) != nil else { continue }
            guard case .decl(let outputDeclaration) = expanded.item,
                  let output = outputDeclaration.as(VariableDeclSyntax.self),
                  output.bindings.count == 1,
                  let outputBinding = output.bindings.first,
                  let outputName = outputBinding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                  outputName.utf8.elementsEqual(name.utf8),
                  var outputCall = outputBinding.initializer?.value.as(FunctionCallExprSyntax.self),
                  let identity = outputCall.arguments.first,
                  identity.label?.text == "_name",
                  let identityName = identity.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
                  identityName.utf8.elementsEqual(name.utf8),
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
                   let addedName = added.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
                   addedName.utf8.elementsEqual(root.utf8) {
                    outputVariableCall.arguments = LabeledExprListSyntax(outputVariableCall.arguments.dropFirst())
                    outputInitializer.value = ExprSyntax(outputVariableCall)
                    outputBinding.initializer = outputInitializer
                    outputVar.bindings = PatternBindingListSyntax([outputBinding])
                    normalized.item = .decl(DeclSyntax(outputVar))
                }
                guard sameTokens(sourceItem, normalized) else { throw drift(name) }
                normalizedStatements.append(normalized)
            }
            outputBody.statements = CodeBlockItemListSyntax(normalizedStatements)
            guard sameTokens(sourceBody, outputBody) else { throw drift(name) }
            outputCall.arguments = LabeledExprListSyntax(outputCall.arguments.dropFirst().map { argument in
                guard argument.label?.text == "scoped" else { return argument }
                var result = argument
                result.expression = ExprSyntax(outputBody)
                return result
            })
            guard sameTokens(call, outputCall) else { throw drift(name) }
            for (sourceItem, outputItem) in zip(source.statements, rewritten.statements) {
                guard case .expr(let expression) = sourceItem.item,
                      expression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == name
                else { continue }
                guard sameTokens(sourceItem, outputItem) else { throw drift(name) }
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
                  call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == "Algorithm",
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
            case .memberOf(let expression): value = ".memberOf(\(try render(expression)))"
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
        case .equal(let lhs, let rhs): return ".equal(\(try render(lhs)), \(try render(rhs)))"
        case .integerRange(let lhs, let rhs): return ".integerRange(\(try render(lhs)), \(try render(rhs)))"
        case .setLiteral(let members):
            return ".setLiteral([\(try members.map(render).joined(separator: ", "))])"
        case .ifThenElse(let condition, let yes, let no):
            return ".ifThenElse(\(try render(condition)), \(try render(yes)), \(try render(no)))"
        default: throw drift("ordered Int expression")
        }
    }

    private static func sameTokens(_ lhs: some SyntaxProtocol, _ rhs: some SyntaxProtocol) -> Bool {
        let first = Array(lhs.tokens(viewMode: .sourceAccurate))
        let second = Array(rhs.tokens(viewMode: .sourceAccurate))
        return first.count == second.count && zip(first, second).allSatisfy { left, right in
            left.tokenKind == right.tokenKind && left.text.utf8.elementsEqual(right.text.utf8)
        }
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
        var roots: [[UInt8]: String] = [:]
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
               member.declName.baseName.sourceIdentifierName == "sharedVar",
               initializer.arguments.allSatisfy({
                   $0.label?.text == "_name" || $0.label?.text == "label"
                       || $0.label?.text == "initial" || $0.label?.text == "in"
               }),
               let initial = initializer.arguments.first(where: {
                   $0.label?.text == "initial" || $0.label?.text == "in"
               }),
               let initialValue = value(initial.expression, roots: roots,
                   type: initial.label?.text == "in" ? .set(.int) : .int) {
                let root = initializer.arguments.first(where: { $0.label?.text == "_name" })?
                    .expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? sourceName
                guard roots.updateValue(root, forKey: Array(sourceName.utf8)) == nil else { return nil }
                let initialization: VariableInitialization
                if initial.label?.text == "in" {
                    initialization = .memberOf(initialValue)
                } else if case .value(.int(let number)) = initialValue {
                    initialization = .value(.int(number))
                } else {
                    initialization = .expression(initialValue)
                }
                result.append(.variable(root: root, initialization: initialization))
                continue
            }
            guard case .expr(let expression) = item.item,
                  let step = expression.as(FunctionCallExprSyntax.self),
                  step.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == "Do",
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
                      assignment.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == "Assign",
                      assignment.arguments.count == 2,
                      assignment.arguments.first?.label == nil,
                      assignment.arguments.last?.label?.text == "to",
                      let targetName = assignment.arguments.first?.expression
                        .as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName,
                      let target = roots[Array(targetName.utf8)],
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
        let literal: IntegerLiteralExprSyntax
        let sign: String
        if let prefix = syntax.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "-",
           let operand = prefix.expression.as(IntegerLiteralExprSyntax.self) {
            literal = operand
            sign = "-"
        } else if let operand = syntax.as(IntegerLiteralExprSyntax.self) {
            literal = operand
            sign = ""
        } else { return nil }
        let text = literal.literal.text.replacingOccurrences(of: "_", with: "")
        let radix: Int
        switch text.prefix(2) {
        case "0b": radix = 2
        case "0o": radix = 8
        case "0x": radix = 16
        default: radix = 10
        }
        let digits = radix == 10 ? text : String(text.dropFirst(2))
        return Int(sign + digits, radix: radix)
    }

    private static func value(_ syntax: ExprSyntax, roots: [[UInt8]: String],
                              type: CompiledValueType = .int) -> StateExpr? {
        if type == .int, let integer = integer(syntax) { return .value(.int(integer)) }
        if type == .int, let name = syntax.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName,
           let root = roots[Array(name.utf8)] { return .variable(root) }
        if let group = syntax.as(TupleExprSyntax.self), group.elements.count == 1,
           let element = group.elements.first { return value(element.expression, roots: roots, type: type) }
        if type == .int, let prefix = syntax.as(PrefixOperatorExprSyntax.self),
           ["+", "-"].contains(prefix.operator.text),
           let operand = value(prefix.expression, roots: roots),
           case .value(.int(let number)) = operand {
            if prefix.operator.text == "+" { return operand }
            let result = 0.subtractingReportingOverflow(number)
            return result.overflow ? nil : .value(.int(result.partialValue))
        }
        if type == .set(.int), let call = syntax.as(FunctionCallExprSyntax.self),
           call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty {
            if call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "If",
               call.arguments.count == 3,
               call.arguments.first?.label == nil,
               call.arguments.dropFirst().first?.label?.text == "then",
               call.arguments.last?.label?.text == "else" {
                let arguments = Array(call.arguments)
                guard let condition = value(arguments[0].expression, roots: roots, type: .bool),
                      let yes = value(arguments[1].expression, roots: roots, type: type),
                      let no = value(arguments[2].expression, roots: roots, type: type) else { return nil }
                return .ifThenElse(condition, yes, no)
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "literal",
               let generic = member.base?.as(GenericSpecializationExprSyntax.self),
               generic.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "SetExpr",
               generic.genericArgumentClause.arguments.count == 1,
               generic.genericArgumentClause.arguments.first?.argument.as(IdentifierTypeSyntax.self)?.name.text == "Int",
               call.arguments.allSatisfy({ $0.label == nil }) {
                let members = call.arguments.compactMap { value($0.expression, roots: roots) }
                guard members.count == call.arguments.count, members.allSatisfy(initialDomainMember) else { return nil }
                return .setLiteral(members)
            }
        }
        let operands: [ExprSyntax]
        if let infix = syntax.as(InfixOperatorExprSyntax.self) {
            operands = [infix.leftOperand, infix.operator, infix.rightOperand]
        } else if let sequence = syntax.as(SequenceExprSyntax.self) {
            operands = Array(sequence.elements)
        } else { return nil }
        if type != .int, operands.count == 3,
           let operation = operands[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
           let lhs = value(operands[0], roots: roots), let rhs = value(operands[2], roots: roots),
           initialLeaf(lhs), initialLeaf(rhs) {
            if type == .set(.int), operation == "...",
               case .value = lhs, case .value = rhs { return .integerRange(lhs, rhs) }
            if type == .bool, operation == "==" {
                // shortcut: raw Swift comparisons and fallible children need typed source evaluation before widening.
                if case .variable = lhs { return .equal(lhs, rhs) }
                if case .variable = rhs { return .equal(lhs, rhs) }
            }
            return nil
        }
        guard type == .int, operands.count >= 3, operands.count % 2 == 1 else { return nil }
        let operations = stride(from: 1, to: operands.count, by: 2).compactMap { index -> (Int, String, Int)? in
            guard let operation = operands[index].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  ["+", "-", "*", "/", "%"].contains(operation) else { return nil }
            return (index, operation, operation == "+" || operation == "-" ? 0 : 1)
        }
        guard operations.count == (operands.count - 1) / 2,
              let split = operations.min(by: { $0.2 == $1.2 ? $0.0 > $1.0 : $0.2 < $1.2 }) else { return nil }
        func operand(_ elements: ArraySlice<ExprSyntax>) -> StateExpr? {
            guard let first = elements.first else { return nil }
            let expression = elements.count == 1 ? first
                : ExprSyntax(SequenceExprSyntax(elements: ExprListSyntax(elements)))
            return value(expression, roots: roots)
        }
        guard let lhs = operand(operands[..<split.0]),
              let rhs = operand(operands[(split.0 + 1)...]) else { return nil }
        if case .value(.int(let left)) = lhs, case .value(.int(let right)) = rhs {
            let result: (partialValue: Int, overflow: Bool)
            switch split.1 {
            case "+": result = left.addingReportingOverflow(right)
            case "-": result = left.subtractingReportingOverflow(right)
            case "*": result = left.multipliedReportingOverflow(by: right)
            case "/":
                guard right != 0 else { return nil }
                result = left.dividedReportingOverflow(by: right)
            case "%":
                guard right != 0 else { return nil }
                result = left.remainderReportingOverflow(dividingBy: right)
            default: return nil
            }
            return result.overflow ? nil : .value(.int(result.partialValue))
        }
        return split.1 == "+" ? .add(lhs, rhs) : nil
    }

    private static func initialDomainMember(_ expression: StateExpr) -> Bool {
        if case .add(let lhs, let rhs) = expression {
            // Literal-only Swift additions evaluate before the DSL constructs its members.
            return !expression.freeVariableNames.isEmpty
                && initialDomainMember(lhs) && initialDomainMember(rhs)
        }
        return initialLeaf(expression)
    }

    private static func initialLeaf(_ expression: StateExpr) -> Bool {
        switch expression {
        case .value(.int), .variable: return true
        default: return false
        }
    }
}
