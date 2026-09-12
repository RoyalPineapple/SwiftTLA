private enum StateRenderingTask {
    case expression(CompiledExpression)
    case checkedView(FormalValueShape, start: Int)
    case formalArgument(CompiledFormalCallArgument)
    case formalOperator(CompiledFormalOperator)
    case localOperator(CompiledOperatorDefinition)
    case text(String)
}

private enum ActionRenderingTask {
    case expression(CompiledActionExpr)
    case text(String)
}

struct CompiledTLARenderer {
    let layout: CompiledLayout
    let bindings: CompiledBindingTable
    let operators: CompiledOperators

    func action(
        _ expression: CompiledActionExpr
    ) throws -> String {
        var tasks = [ActionRenderingTask.expression(expression)]
        var parts: [String] = []
        func schedule(_ values: [ActionRenderingTask]) {
            tasks.append(contentsOf: values.reversed())
        }
        while let task = tasks.popLast() {
            switch task {
            case .text(let value):
                parts.append(value)
            case .expression(let action):
                switch action {
                case .assign(let variable, let value):
                    parts.append("\(try variableName(variable))' = \(try state(value))")
                case .unchanged(let variable):
                    parts.append("UNCHANGED \(try variableName(variable))")
                case .guard_(let condition):
                    parts.append(try state(condition))
                case .existsAction(let binder, let set, let body):
                    parts.append("\\E \(try binderName(binder)) \\in \(try state(set)): ")
                    tasks.append(.expression(body))
                case .ifElse(let condition, let then, let otherwise):
                    parts.append("IF \(try state(condition)) THEN (")
                    schedule([
                        .expression(then), .text(") ELSE ("), .expression(otherwise), .text(")")
                    ])
                case .define(let binder, let value, let body):
                    parts.append("LET \(try binderName(binder)) == \(try state(value)) IN ")
                    tasks.append(.expression(body))
                case .and(let lhs, let rhs):
                    parts.append("(")
                    schedule([.expression(lhs), .text(" /\\ "), .expression(rhs), .text(")")])
                case .or(let lhs, let rhs):
                    parts.append("(")
                    schedule([.expression(lhs), .text(" \\/ "), .expression(rhs), .text(")")])
                }
            }
        }
        return parts.joined()
    }

    func temporal(
        _ expression: CompiledTemporalExpr<CompiledStateQuery>
    ) throws -> String {
        switch expression {
        case .always(let predicate): return "[]\(try state(predicate.expression))"
        case .eventually(let predicate): return "<>\(try state(predicate.expression))"
        case .alwaysEventually(let predicate): return "[]<>\(try state(predicate.expression))"
        case .eventuallyAlways(let predicate): return "<>[]\(try state(predicate.expression))"
        case .leadsTo(let source, let target): return "(\(try state(source.expression)) ~> \(try state(target.expression)))"
        }
    }

    func formalDefinition(_ id: OperatorID) throws -> String {
        guard let definition = operators[id] else { throw missing("operator", id.ordinal) }
        let name = try operatorName(definition.id)
        let parameters = try definition.parameters.map(formalParameter).joined(separator: ", ")
        return "\(name)\(parameters.isEmpty ? "" : "(\(parameters))") == \(try state(definition.body))"
    }

    func recursiveFunction(_ id: OperatorID) throws -> (declaration: String, body: String) {
        guard let function = operators[id] else { throw missing("recursive function", id.ordinal) }
        let name = try operatorName(function.id)
        let parameters = try function.parameters.map(formalParameter)
        return (
            declaration: "RECURSIVE \(name)(\(parameters.map { _ in "_" }.joined(separator: ", ")))",
            body: "\(name)(\(parameters.joined(separator: ", "))) == \(try state(function.body))"
        )
    }

    func fairness(
        _ condition: CompiledFairnessCondition,
        vars: String,
        actionNames: [ActionID: String],
        actionCalls: [CompiledActionCall: String]
    ) throws -> String {
        let action: String
        switch condition.scope {
        case .next:
            action = "Next"
        case .action(let id):
            guard let name = actionNames[id] else { throw missing("action", id.ordinal) }
            action = name
        case .actionCall(let call):
            guard let name = actionCalls[call] else { throw missing("action", call.action.ordinal) }
            action = name
        }
        return "\(condition.isStrong ? "SF" : "WF")_\(vars)(\(action))"
    }

    func refinement(_ refinement: CompiledRefinement) throws -> String {
        guard let instance = layout.moduleInstances.first(where: { $0.id == refinement.instance }) else {
            throw missing("module instance", refinement.instance.ordinal)
        }
        let target: String
        switch refinement.operator {
        case .spec: target = "Spec"
        case .liveSpec: target = "LiveSpec"
        case .liveSpecEquals: target = "LiveSpecEquals"
        }
        return "\(refinement.name) == \(instance.namespace)!\(target)"
    }

    func formalModuleReplacement(_ replacement: CompiledFormalModuleReplacement) throws -> String {
        "\(replacement.definitionName) == \(try state(replacement.expression))"
    }

    func moduleInstance(_ instance: CompiledModuleInstance) throws -> String {
        guard let layout = layout.moduleInstances.first(where: { $0.id == instance.id }) else {
            throw missing("module instance", instance.id.ordinal)
        }
        let arguments = try instance.arguments.map {
            "\($0.parameter) <- \(try state($0.value))"
        }.joined(separator: ", ")
        let withClause = arguments.isEmpty ? "" : " WITH \(arguments)"
        return "\(layout.namespace) == INSTANCE \(layout.moduleName)\(withClause)"
    }

    func state(_ expression: CompiledExpression) throws -> String {
        var tasks = [StateRenderingTask.expression(expression)]
        var parts: [String] = []

        func schedule(_ operation: CompiledOperation, _ operands: [CompiledExpression]) throws {
            let syntax = try operation.tlaSyntax(operandCount: operands.count,
                binderName: binderName)
            for part in syntax.reversed() {
                switch part {
                case .text(let text): tasks.append(.text(text))
                case .operand(let index): tasks.append(.expression(operands[index]))
                }
            }
        }

        func schedule(_ scheduled: [StateRenderingTask]) {
            tasks.append(contentsOf: scheduled.reversed())
        }

        while let task = tasks.popLast() {
            switch task {
            case .text(let text):
                parts.append(text)
            case .formalArgument(let argument):
                switch argument {
                case .value(let value): tasks.append(.expression(value))
                case .operator(let operation): tasks.append(.formalOperator(operation))
                }
            case .formalOperator(let operation):
                switch operation {
                case .lambda(let id, _):
                    guard let lambda = operators[id] else { throw missing("lambda", id.ordinal) }
                    parts.append("LAMBDA \(try lambda.parameters.map(formalParameter).joined(separator: ", ")) : ")
                    tasks.append(.expression(lambda.body))
                case .reference(let id, _):
                    parts.append(try operatorName(id))
                }
            case .localOperator(let operation):
                let name = try operatorName(operation.id)
                let parameters = try operation.parameters.map(formalParameter).joined(separator: ", ")
                if let domain = operation.domain, case .value(let parameter, _) = operation.parameters.first {
                    parts.append("\(name)[\(try binderName(parameter)) \\in ")
                    schedule([.expression(domain), .text("] == "), .expression(operation.body)])
                } else {
                    parts.append("\(name)\(parameters.isEmpty ? "" : "(\(parameters))") == ")
                    tasks.append(.expression(operation.body))
                }
            case .checkedView(let shape, let start):
                let operand = parts[start...].joined()
                parts.removeSubrange(start...)
                var name = "_checkedValue"
                let shapeNames = String(describing: shape)
                while operand.contains(name) || shapeNames.contains(name) { name += "_" }
                parts.append("(LET \(name) == \(operand) IN CASE \(shape.predicate(for: name)) -> \(name))")
            case .expression(let expression):
                switch expression.operation {
                case .assertView(let shape):
                    let value = expression.children[0]

                    tasks.append(.checkedView(shape, start: parts.count))
                    tasks.append(.expression(value))
                case .value(let value): parts.append(try value.rendered(using: layout).description)
                case .stateVariable(let variable): parts.append(try variableName(variable))
                case .boundValue(let binder): parts.append(try binderName(binder))
                case .controlLocation(let location): parts.append(try controlLocationName(location))
                case .operatorReference(let operation): parts.append(try operatorName(operation))
                case .enabledAction(let action): parts.append("ENABLED \(try actionName(action))")
                case .convert:
                    tasks.append(.expression(expression.children[0]))
                case .call, .checkedCall:
                    throw missing("resolved function", 0)
                case .operatorApplication(.lambda(let id, _), let arguments):
                    guard let lambda = operators[id] else { throw missing("lambda", id.ordinal) }
                    var rendered: [StateRenderingTask] = []
                    for (parameter, argument) in zip(lambda.parameters, arguments) {
                        rendered.append(.text("LET \(try formalParameter(parameter)) == "))
                        rendered.append(.formalArgument(argument))
                        rendered.append(.text(" IN "))
                    }
                    parts.append("(")
                    rendered.append(.expression(lambda.body))
                    rendered.append(.text(")"))
                    schedule(rendered)
                case .operatorApplication(.reference(let operation, _), let arguments):
                    parts.append(try operatorName(operation))
                    if arguments.isEmpty == false {
                        var rendered: [StateRenderingTask] = []
                        for (index, argument) in arguments.enumerated() {
                            if index > 0 { rendered.append(.text(", ")) }
                            rendered.append(.formalArgument(argument))
                        }
                        parts.append("(")
                        rendered.append(.text(")"))
                        schedule(rendered)
                    }
                case .letIn(let ids):
                    let body = expression.children[0]

                    let operations = try ids.map { id in
                        guard let operation = operators[id] else {
                            throw missing("local operator", id.ordinal)
                        }
                        return operation
                    }
                    if operations.isEmpty {
                        tasks.append(.expression(body))
                        continue
                    }
                    let recursiveDeclarations = try operations
                        .filter { $0.isRecursive && $0.domain == nil }
                        .map { operation in
                            let name = try operatorName(operation.id)
                            let slots = Array(repeating: "_", count: operation.parameters.count).joined(separator: ", ")
                            return operation.parameters.isEmpty ? name : "\(name)(\(slots))"
                        }
                        .joined(separator: ", ")
                    parts.append("LET ")
                    if recursiveDeclarations.isEmpty == false {
                        parts.append("RECURSIVE \(recursiveDeclarations)\n    ")
                    }
                    var rendered: [StateRenderingTask] = []
                    for (index, operation) in operations.enumerated() {
                        if index > 0 { rendered.append(.text("\n    ")) }
                        rendered.append(.localOperator(operation))
                    }
                    rendered.append(.text("\nIN "))
                    rendered.append(.expression(body))
                    schedule(rendered)
                case .add, .subtract, .multiply, .divide, .integerDivide, .modulo, .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .and, .or, .in, .subset, .union, .intersection, .setDifference, .tupleDynamicAccess, .tupleAppend, .tupleConcatenate, .tupleRemoving, .sequenceSelect, .functionApply, .functionSet, .setSum, .integerRange, .negate, .not, .cardinality, .powerSet, .unionAll, .tupleLength, .tupleHead, .tupleTail, .domain, .sequenceFromSet, .ifThenElse, .setLiteral, .setFilter, .setMap, .tupleLiteral, .tupleAccess, .recordLiteral, .recordAccess, .functionLiteral, .except, .caseExpr, .forAll, .exists, .choose, .foldFunction, .letValue:
                    try schedule(expression.operation, expression.children)

                }
            }
        }
        return parts.joined()
    }

    private func formalParameter(_ parameter: CompiledFormalParameter) throws -> String {
        switch parameter {
        case .value(let binder, _): return try binderName(binder)
        case .operator(let operation, let arity):
            return "\(try operatorName(operation))(\(Array(repeating: "_", count: arity).joined(separator: ", ")))"
        }
    }

    func variableName(_ id: VariableID) throws -> String {
        guard layout.variables.indices.contains(id.ordinal) else { throw missing("variable", id.ordinal) }
        return layout.variables[id.ordinal].declaration.name
    }

    private func actionName(_ id: ActionID) throws -> String {
        guard layout.actions.indices.contains(id.ordinal) else { throw missing("action", id.ordinal) }
        return layout.actions[id.ordinal].declaration.name
    }

    func binderName(_ id: BinderID) throws -> String {
        guard let name = bindings.binderName(id) else { throw missing("binder", id.ordinal) }
        return name
    }

    func procedureName(_ id: ProcedureID) throws -> String {
        guard let procedure = layout.procedure(id) else { throw missing("procedure", id.ordinal) }
        return procedure.name
    }

    func controlLocationSourceName(_ id: ControlLocationID) throws -> String {
        guard let location = layout.controlLocation(id) else { throw missing("control location", id.ordinal) }
        return location.sourceName
    }

    private func operatorName(_ id: OperatorID) throws -> String {
        guard let name = bindings.operatorName(id) else { throw missing("operator", id.ordinal) }
        return name
    }

    private func controlLocationName(_ id: ControlLocationID) throws -> String {
        guard let location = layout.controlLocation(id) else { throw missing("control location", id.ordinal) }
        return "\"\(location.sourceName)\""
    }

    private func missing(_ kind: String, _ ordinal: Int) -> CompilationDiagnostic {
        .init(
            code: .unknownReference,
            stage: .rendering,
            path: "compiledRenderer.\(kind)[\(ordinal)]",
            expected: "a rendered declaration name",
            actual: "no declaration",
            nextSafeAction: "Compile the source model again before rendering."
        )
    }
}

/// Operand-delimited TLA+ syntax, independent of the expression representation.
extension CompiledOperation {
    private var tlaOperandSyntax: (prefix: String, separator: String, suffix: String)? {
        switch self {
        case .convert: ("(", "", ")")
        case .add: ("(", " + ", ")")
        case .subtract: ("(", " - ", ")")
        case .multiply: ("(", " * ", ")")
        case .modulo: ("(", " % ", ")")
        case .equal: ("(", " = ", ")")
        case .notEqual: ("(", " /= ", ")")
        case .lessThan: ("(", " < ", ")")
        case .lessOrEqual: ("(", " <= ", ")")
        case .greaterThan: ("(", " > ", ")")
        case .greaterOrEqual: ("(", " >= ", ")")
        case .and: ("(", " /\\ ", ")")
        case .or: ("(IF ", " THEN TRUE ELSE ", ")")
        case .in: ("(", " \\in ", ")")
        case .subset: ("(", " \\subseteq ", ")")
        case .union: ("(", " \\cup ", ")")
        case .intersection: ("(", " \\cap ", ")")
        case .setDifference: ("(", " \\ ", ")")
        case .tupleDynamicAccess: ("", "[", "]")
        case .tupleAppend: ("Append(", ", ", ")")
        case .tupleConcatenate: ("(", " \\o ", ")")
        case .functionApply: ("", "[", "]")
        case .functionSet: ("[", " -> ", "]")
        case .setSum: ("Sum(", ", ", ")")
        case .integerRange: ("", "..", "")
        case .negate: ("(-", "", ")")
        case .not: ("(~", "", ")")
        case .cardinality: ("Cardinality(", "", ")")
        case .powerSet: ("SUBSET ", "", "")
        case .unionAll: ("UNION ", "", "")
        case .tupleLength: ("Len(", "", ")")
        case .tupleHead: ("Head(", "", ")")
        case .tupleTail: ("Tail(", "", ")")
        case .domain: ("DOMAIN ", "", "")
        case .sequenceFromSet: ("SeqFromSet(", "", ")")
        case .setLiteral: ("{", ", ", "}")
        case .tupleLiteral: ("<<", ", ", ">>")
        case .divide, .integerDivide: ("(", " \\div ", ")")
        default: nil
        }
    }
}

/// A rendering instruction refers to an operand without owning another expression tree.
enum TLAExpressionPart: Equatable, Sendable {
    case text(String)
    case operand(Int)
}

extension CompiledOperation {
    func tlaSyntax(
        operandCount: Int,
        binderName: (BinderID) throws -> String
    ) throws -> [TLAExpressionPart] {
        if let syntax = tlaOperandSyntax {
            var parts: [TLAExpressionPart] = [.text(syntax.prefix)]
            for index in 0..<operandCount {
                if index > 0 { parts.append(.text(syntax.separator)) }
                parts.append(.operand(index))
            }
            parts.append(.text(syntax.suffix))
            return parts
        }
        let parts: [TLAExpressionPart]
        switch self {
        case .ifThenElse:
            parts = [.text("(IF "), .operand(0), .text(" THEN "), .operand(1),
                .text(" ELSE "), .operand(2), .text(")")]
        case .tupleRemoving:
            parts = [.text("(SubSeq("), .operand(0), .text(", 1, ("), .operand(1),
                .text(" - 1)) \\o SubSeq("), .operand(0), .text(", ("), .operand(1),
                .text(" + 1), Len("), .operand(0), .text(")))")]
        case .sequenceSelect(let binder):
            parts = [.text("SelectSeq("), .operand(0), .text(", LAMBDA \(try binderName(binder)): "),
                .operand(1), .text(")")]
        case .setFilter(let binder):
            parts = [.text("{\(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1), .text("}")]
        case .setMap(let binder):
            parts = [.text("{"), .operand(0), .text(" : \(try binderName(binder)) \\in "), .operand(1), .text("}")]
        case .tupleAccess(let index):
            parts = [.operand(0), .text("[\(index)]")]
        case .recordLiteral(let fields):
            guard fields.count == operandCount else {
                throw CompiledValueType.diagnostic("rendering.record", "each record field requires one operand")
            }
            var record: [TLAExpressionPart] = [.text("[")]
            for (index, field) in fields.enumerated() {
                if index > 0 { record.append(.text(", ")) }
                record += [.text("\(field) |-> "), .operand(index)]
            }
            record.append(.text("]"))
            parts = record
        case .recordAccess(let field):
            parts = [.text("("), .operand(0), .text(").\(field)")]
        case .functionLiteral(let binder):
            parts = [.text("[\(try binderName(binder)) \\in "), .operand(0), .text(" |-> "), .operand(1), .text("]")]
        case .except:
            parts = [.text("["), .operand(0), .text(" EXCEPT !["), .operand(1), .text("] = "), .operand(2), .text("]")]
        case .caseExpr(let hasOtherwise):
            let branchOperands = operandCount - (hasOtherwise ? 1 : 0)
            guard branchOperands >= 2, branchOperands.isMultiple(of: 2) else {
                throw CompiledValueType.diagnostic("rendering.case", "CASE requires condition/value pairs and an optional default")
            }
            var branches: [TLAExpressionPart] = [.text("CASE ")]
            for index in stride(from: 0, to: branchOperands, by: 2) {
                if index > 0 { branches.append(.text(" [] ")) }
                branches += [.operand(index), .text(" -> "), .operand(index + 1)]
            }
            if hasOtherwise { branches += [.text(" [] OTHER -> "), .operand(branchOperands)] }
            parts = branches
        case .forAll(let binder):
            parts = [.text("\\A \(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1)]
        case .exists(let binder):
            parts = [.text("\\E \(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1)]
        case .choose(let binder):
            parts = [.text("CHOOSE \(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1)]
        case .foldFunction(let binders):
            parts = [.text("FoldFunction(LAMBDA \(try binders.map(binderName).joined(separator: ", ")) : "),
                .operand(0), .text(", "), .operand(1), .text(", "), .operand(2), .text(")")]
        case .letValue(let binder):
            parts = [.text("LET \(try binderName(binder)) == "), .operand(0), .text(" IN "), .operand(1)]
        default:
            throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                path: "compiledRenderer.operation", expected: "an operand syntax template",
                actual: String(describing: self), nextSafeAction: "Check operation lowering before rendering.")
        }
        return parts
    }
}
