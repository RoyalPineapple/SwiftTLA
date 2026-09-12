import SwiftTLA

/// Evaluation order and recursive-call lowering over the checked function graph.
enum NativeFunctionPlan: Sendable {
    indirect enum Body: Sendable {
        case result(CompiledExpression)
        case condition(CompiledExpression, Body, Body)
        case binding(BinderID, CompiledExpression, Body)
        case call(ResolvedFunctionID, [CompiledExpression], Body)
        case repeatCall([CompiledExpression])
        /// Freeze earlier operands, then continue evaluation when this operand returns.
        case resume(operand: CompiledExpression, before: [CompiledExpression], evaluate: Body, then: Body)

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

    init(function: ResolvedFunctionID, functions: [ResolvedFunction]) {
        let resolved = functions[function.ordinal]
        guard resolved.callbacks.isEmpty, resolved.domainGuard == nil else {
            self = .ordinary(parameterOrder: [])
            return
        }
        let parameters = Set(resolved.parameters.map(\.binder))
        let prefix = Self.entryReads(resolved.body, parameters: parameters)
        var seen: Set<BinderID> = []
        let order = prefix.bindings.filter { seen.insert($0).inserted }
        // Forcing these arguments preserves the original first-use order. Once
        // forced, a tail argument captures values instead of a chain of thunks.
        guard let body = Self.lower(resolved.body, returningTo: function, visited: [function], functions: functions),
              seen == parameters || Self.canDeferArguments(in: body, parameters: resolved.parameters.map(\.binder),
                  deferred: parameters.subtracting(seen))
        else {
            self = .ordinary(parameterOrder: order)
            return
        }
        self = .loop(parameterOrder: order, body: body)
    }

    /// A deferred update must demand its own previous value first. Independent
    /// updates can then be composed and evaluated iteratively when demanded.
    private static func canDeferArguments(
        in body: Body, parameters: [BinderID], deferred: Set<BinderID>
    ) -> Bool {
        switch body {
        case .result: return true
        case .condition(_, let yes, let no):
            return canDeferArguments(in: yes, parameters: parameters, deferred: deferred)
                && canDeferArguments(in: no, parameters: parameters, deferred: deferred)
        case .repeatCall(let arguments):
            return zip(parameters, arguments).allSatisfy { parameter, argument in
                let isDeferred = deferred.contains(parameter)
                if isDeferred && entryReads(argument, parameters: Set(parameters)).bindings.first != parameter {
                    return false
                }
                var pending = [argument]
                while let id = pending.popLast() {
                    let node = id
                    // Calls can capture bindings not present in their argument list.
                    if case .call = node.operation { return false }
                    if case .boundValue(let binding) = node.operation, deferred.contains(binding),
                       !isDeferred || binding != parameter { return false }
                    pending.append(contentsOf: node.children)
                }
                return true
            }
        case .binding, .call, .resume: return false
        }
    }

    private static func entryReads(
        _ expression: CompiledExpression, parameters: Set<BinderID>
    ) -> (bindings: [BinderID], continues: Bool) {
        let node = expression
        switch node.operation {
        case .boundValue(let binder) where parameters.contains(binder):
            return ([binder], true)
        case .convert:
            return (entryReads(node.children[0], parameters: parameters).bindings, false)
        case .value(.integer), .value(.boolean), .value(.string): return ([], true)
        case .ifThenElse, .and, .or,
             .setFilter, .forAll, .exists, .choose, .functionLiteral, .sequenceSelect:
            return (entryReads(node.children[0], parameters: parameters).bindings, false)
        case .setMap:
            // The IR stores the mapped expression first; evaluation starts with the domain.
            return (entryReads(node.children[1], parameters: parameters).bindings, false)
        case .letValue:
            return entryReads(node.children[1], parameters: parameters)
        case .add, .subtract, .multiply, .negate,
             .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .not,
             .recordLiteral, .tupleLiteral, .setLiteral,
             .cardinality, .tupleLength, .tupleHead, .tupleTail, .domain, .sequenceFromSet, .powerSet, .unionAll:
            var bindings: [BinderID] = []
            for child in node.children {
                let prefix = entryReads(child, parameters: parameters)
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
        _ expression: CompiledExpression, returningTo function: ResolvedFunctionID,
        visited: Set<ResolvedFunctionID>, functions: [ResolvedFunction], completed: Set<CompiledExpression> = []
    ) -> Body? {
        guard !completed.contains(expression) else { return nil }
        let node = expression
        guard node.resultType == functions[function.ordinal].resultType else { return nil }
        if case .call(let call) = node.operation, call.callbacks.isEmpty, case .function(let target) = call.target {
            if target == function { return .repeatCall(node.children) }
            let callee = functions[target.ordinal]
            guard callee.callbacks.isEmpty, !visited.contains(target),
                  let body = lower(callee.body, returningTo: function, visited: visited.union([target]), functions: functions)
            else { return nil }
            return .call(target, node.children, body)
        }
        switch node.operation {
        case .ifThenElse:
            let yes = lower(node.children[1], returningTo: function, visited: visited, functions: functions)
            let no = lower(node.children[2], returningTo: function, visited: visited, functions: functions)
            guard yes != nil || no != nil else { return nil }
            return .condition(node.children[0], yes ?? .result(node.children[1]), no ?? .result(node.children[2]))
        case .letValue(let binder):
            guard let body = lower(node.children[1], returningTo: function, visited: visited, functions: functions) else { return nil }
            return .binding(binder, node.children[0], body)
        case .add, .subtract, .multiply, .divide, .integerDivide, .modulo, .negate,
             .union, .intersection, .setDifference, .not:
            let evaluationOrder = node.operation.evaluatesRightOperandFirst ? Array(node.children.reversed()) : node.children
            for (index, child) in evaluationOrder.enumerated() {
                guard let body = lower(child, returningTo: function, visited: visited, functions: functions, completed: completed) else { continue }
                let before = evaluationOrder.prefix(index).filter { !completed.contains($0) }
                let continuation = lower(expression, returningTo: function, visited: visited, functions: functions,
                    completed: completed.union(before).union([child])) ?? .result(expression)
                return .resume(operand: child, before: before, evaluate: body, then: continuation)
            }
            return nil
        default: return nil
        }
    }
}
