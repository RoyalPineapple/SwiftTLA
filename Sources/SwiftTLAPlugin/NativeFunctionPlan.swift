import SwiftTLA

/// Evaluation order and recursive-call lowering over the checked function graph.
enum NativeFunctionPlan {
    indirect enum Body {
        case result(NativeExpressionID)
        case condition(NativeExpressionID, Body, Body)
        case binding(BinderID, NativeExpressionID, Body)
        case call(NativeFunctionID, [NativeExpressionID], Body)
        case repeatCall([NativeExpressionID])
        /// Freeze earlier operands, then continue evaluation when this operand returns.
        case resume(operand: NativeExpressionID, before: [NativeExpressionID], evaluate: Body, then: Body)

        var hasPendingReturns: Bool {
            var pending = [self]
            while let body = pending.popLast() {
                switch body {
                case .resume: return true
                case .condition(_, let yes, let no): pending.append(contentsOf: [yes, no])
                case .binding(_, _, let body), .call(_, _, let body): pending.append(body)
                case .result, .repeatCall: break
                }
            }
            return false
        }
    }

    case ordinary(parameterOrder: [BinderID])
    case loop(parameterOrder: [BinderID], body: Body)

    var parameterOrder: [BinderID] {
        switch self {
        case .ordinary(let order), .loop(let order, _): order
        }
    }

    init(function: NativeFunctionID, program: NativeResolvedProgram) {
        let resolved = program[function]
        guard resolved.callbacks.isEmpty, resolved.domainGuard == nil else {
            self = .ordinary(parameterOrder: [])
            return
        }
        let parameters = Set(resolved.parameters)
        let prefix = Self.entryReads(resolved.body, parameters: parameters, program: program)
        var seen: Set<BinderID> = []
        let order = prefix.bindings.filter { seen.insert($0).inserted }
        // Forcing these arguments preserves the original first-use order. Once
        // forced, a tail argument captures values instead of a chain of thunks.
        guard seen == parameters,
              let body = Self.lower(resolved.body, returningTo: function, visited: [function], program: program)
        else {
            self = .ordinary(parameterOrder: order)
            return
        }
        self = .loop(parameterOrder: order, body: body)
    }

    private static func entryReads(
        _ expression: NativeExpressionID, parameters: Set<BinderID>, program: NativeResolvedProgram
    ) -> (bindings: [BinderID], continues: Bool) {
        let node = program[expression]
        switch node.expression {
        case .boundValue(let binder) where parameters.contains(binder):
            return ([binder], node.computationType == node.resultType)
        case .value(.integer), .value(.boolean), .value(.string): return ([], true)
        case .ifThenElse, .and, .or, .letIn,
             .setFilter, .forAll, .exists, .choose, .functionLiteral, .sequenceSelect:
            return (entryReads(node.children[0], parameters: parameters, program: program).bindings, false)
        case .setMap:
            // The IR stores the mapped expression first; evaluation starts with the domain.
            return (entryReads(node.children[1], parameters: parameters, program: program).bindings, false)
        case .letValue:
            return entryReads(node.children[1], parameters: parameters, program: program)
        case .add, .subtract, .multiply, .negate,
             .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .not,
             .recordLiteral, .tupleLiteral, .setLiteral,
             .cardinality, .tupleLength, .tupleHead, .tupleTail, .domain, .sequenceFromSet, .powerSet, .unionAll:
            var bindings: [BinderID] = []
            for child in node.children {
                let prefix = entryReads(child, parameters: parameters, program: program)
                bindings.append(contentsOf: prefix.bindings)
                guard prefix.continues else { break }
            }
            // Do not move another argument read across an operation that can
            // fail or determine whether the rest of the body is evaluated.
            return (bindings, false)
        default: return ([], false)
        }
    }

    private static func lower(
        _ expression: NativeExpressionID, returningTo function: NativeFunctionID,
        visited: Set<NativeFunctionID>, program: NativeResolvedProgram, completed: Set<NativeExpressionID> = []
    ) -> Body? {
        guard !completed.contains(expression) else { return nil }
        let node = program[expression]
        guard node.computationType == node.resultType,
              node.resultType == program[function].resultType else { return nil }
        if let call = node.call, call.callbacks.isEmpty, case .function(let target) = call.target {
            if target == function { return .repeatCall(node.children) }
            let callee = program[target]
            guard callee.callbacks.isEmpty, !visited.contains(target),
                  let body = lower(callee.body, returningTo: function, visited: visited.union([target]), program: program)
            else { return nil }
            return .call(target, node.children, body)
        }
        switch node.expression {
        case .ifThenElse:
            let yes = lower(node.children[1], returningTo: function, visited: visited, program: program)
            let no = lower(node.children[2], returningTo: function, visited: visited, program: program)
            guard yes != nil || no != nil else { return nil }
            return .condition(node.children[0], yes ?? .result(node.children[1]), no ?? .result(node.children[2]))
        case .letIn:
            return lower(node.children[0], returningTo: function, visited: visited, program: program)
        case .letValue(let binder, _, _):
            guard let body = lower(node.children[1], returningTo: function, visited: visited, program: program) else { return nil }
            return .binding(binder, node.children[0], body)
        case .add, .subtract, .multiply, .divide, .integerDivide, .modulo, .negate,
             .union, .intersection, .setDifference, .not:
            let evaluationOrder: [NativeExpressionID]
            switch node.expression {
            case .divide, .integerDivide, .modulo: evaluationOrder = node.children.reversed()
            default: evaluationOrder = node.children
            }
            for (index, child) in evaluationOrder.enumerated() {
                guard let body = lower(child, returningTo: function, visited: visited, program: program, completed: completed) else { continue }
                let before = evaluationOrder.prefix(index).filter { !completed.contains($0) }
                let continuation = lower(expression, returningTo: function, visited: visited, program: program,
                    completed: completed.union(before).union([child])) ?? .result(expression)
                return .resume(operand: child, before: before, evaluate: body, then: continuation)
            }
            return nil
        default: return nil
        }
    }
}
