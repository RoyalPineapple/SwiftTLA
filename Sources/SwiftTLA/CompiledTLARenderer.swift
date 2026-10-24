private enum StateRenderingTask {
    case expression(CompiledExpression)
    case setMember(CompiledExpression)
    case finishSetMember(start: Int)
    case finishSet(start: Int)
    case checkedView(FormalValueShape, sourceType: CompiledValueType, start: Int)
    case formalArgument(CompiledFormalCallArgument)
    case formalOperator(CompiledFormalOperator)
    case localOperator(CompiledOperatorDefinition)
    case text(String)
}

private enum ActionRenderingTask {
    case expression(CompiledActionExpr)
    case text(String)
}

private enum OrderedEvaluationSite {
    case choice(guard_: String)
    case noMatchingCase(guard_: String)
    case arithmetic(operation: NativeMachineEvaluationError.IntegerOperation, guard_: String, operands: String)
    case divisionByZero(guard_: String, divisor: String)
    case negativeModuloDivisor(guard_: String, divisor: String)
    case functionArgumentOutsideDomain(guard_: String)
    case sequenceIndexOutOfBounds(guard_: String, operands: String)
    case emptySequence(guard_: String)

    var guard_: String {
        switch self {
        case .choice(let guard_), .noMatchingCase(let guard_), .arithmetic(_, let guard_, _),
             .divisionByZero(let guard_, _), .negativeModuloDivisor(let guard_, _),
             .functionArgumentOutsideDomain(let guard_),
             .sequenceIndexOutOfBounds(let guard_, _),
             .emptySequence(let guard_): guard_
        }
    }

    func selected(by predicate: String, whenTrue: Bool) -> Self {
        let guarded = whenTrue
            ? "(IF \(predicate) THEN \(guard_) ELSE TRUE)"
            : "(IF \(predicate) THEN TRUE ELSE \(guard_))"
        switch self {
        case .choice: return .choice(guard_: guarded)
        case .noMatchingCase: return .noMatchingCase(guard_: guarded)
        case .arithmetic(let operation, _, let operands):
            return .arithmetic(operation: operation, guard_: guarded, operands: operands)
        case .divisionByZero(_, let divisor):
            return .divisionByZero(guard_: guarded, divisor: divisor)
        case .negativeModuloDivisor(_, let divisor):
            return .negativeModuloDivisor(guard_: guarded, divisor: divisor)
        case .functionArgumentOutsideDomain:
            return .functionArgumentOutsideDomain(guard_: guarded)
        case .sequenceIndexOutOfBounds(_, let operands):
            return .sequenceIndexOutOfBounds(guard_: guarded, operands: operands)
        case .emptySequence:
            return .emptySequence(guard_: guarded)
        }
    }
}

enum RenderedEvaluationFailureKind {
    case noMatchingCase
    case overflow(NativeMachineEvaluationError.IntegerOperation)
    case divisionByZero
    case negativeModuloDivisor
    case functionArgumentOutsideDomain
    case sequenceIndexOutOfBounds
    case emptySequence
}

struct RenderedEvaluationFailure {
    let predicate: String
    let operands: String?
    let kind: RenderedEvaluationFailureKind
}

private enum FiniteCandidateMembers {
    case unavailable
    case values([CompiledValue])

    var values: [CompiledValue]? {
        if case .values(let members) = self { return members }
        return nil
    }
}

private final class FiniteCandidateCache {
    var members: [CompiledExpression: FiniteCandidateMembers] = [:]
}

struct CompiledTLARenderer {
    let moduleName: String
    let reservedNames: Set<String>
    let layout: CompiledLayout
    let bindings: CompiledBindingTable
    let operators: CompiledOperators
    let actions: [CompiledAction]
    let functions: [ResolvedFunction]
    var enums: CompiledEnums = .init()
    var moduleNames: [String: String] = [:]
    var parameterDomains: [BinderID: CompiledExpression] = [:]
    private let finiteCandidateCache = FiniteCandidateCache()

    func assumptions(_ behavior: CompiledBehavior) throws -> [String] {
        var result = try layout.parameters.map { parameter in
            guard let domain = behavior.parameterDomains[parameter.binder] else {
                throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                    path: "parameters.\(parameter.reference.name).domain", expected: "a resolved domain", actual: "missing domain",
                    nextSafeAction: "Resolve the parameter domain before export.")
            }
            return "ASSUME \(try binderName(parameter.binder)) \\in \(try state(domain))"
        }
        for register in layout.checkingRegisters {
            guard let initial = behavior.checkingRegisterInitializations[register.id] else {
                throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                    path: "checkingRegisters.\(register.reference.name).initial",
                    expected: "a resolved initialization", actual: "missing initialization",
                    nextSafeAction: "Resolve the checking register initialization before export.")
            }
            result.append("ASSUME TLCSet(\(register.id.ordinal), \(try state(initial)))")
        }
        if let assume = behavior.assume {
            result.append("ASSUME \(try state(assume.expression))")
        }
        return result
    }

    func resolvedFunctionDefinitions() throws -> [String] {
        guard !functions.isEmpty else { return [] }
        let signatures = try functions.enumerated().map { index, function in
            let name = try resolvedFunctionName(.init(ordinal: index))
            let captures = try functionStateCaptures(.init(ordinal: index))
            let slots = Array(repeating: "_", count: function.parameters.count + captures.count).joined(separator: ", ")
            return name + (slots.isEmpty ? "" : "(\(slots))")
        }
        return try ["RECURSIVE " + signatures.joined(separator: ", ")] + functions.enumerated().map { index, function in
            let name = try resolvedFunctionName(.init(ordinal: index))
            let captures = try functionStateCaptures(.init(ordinal: index))
            let names = try captures.map { try stateCaptureName($0) }
            let substitutions = Dictionary(uniqueKeysWithValues: zip(captures, names))
            let parameters = try (function.parameters.map { try binderName($0.binder) } + names).joined(separator: ", ")
            let body = try state(function.body, stateNames: substitutions)
            let value = try function.domainGuard.map { "CASE \(try state($0, stateNames: substitutions)) -> (\(body))" } ?? body
            return name + (parameters.isEmpty ? "" : "(\(parameters))") + " == " + value
        }
    }

    private func functionStateCaptures(_ id: ResolvedFunctionID) throws -> [VariableID] {
        var pending = [id]
        var visited: Set<ResolvedFunctionID> = []
        var variables: Set<VariableID> = []
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else { continue }
            guard functions.indices.contains(current.ordinal) else { throw missing("resolved function", current.ordinal) }
            let function = functions[current.ordinal]
            var expressions = [function.body] + (function.domainGuard.map { [$0] } ?? [])
            while let expression = expressions.popLast() {
                switch expression.operation {
                case .stateVariable(let variable): variables.insert(variable)
                case .call(let callee): pending.append(callee)
                default: break
                }
                expressions.append(contentsOf: expression.children)
            }
        }
        return variables.sorted { $0.ordinal < $1.ordinal }
    }

    private func stateCaptureName(_ variable: VariableID) throws -> String {
        let occupied = reservedNames.union(bindings.binders.values).union(bindings.operatorNames.values)
            .union(layout.declarations.map(\.name)).union(layout.actions.map(\.renderedName))
        var name = "__\(moduleName)_state\(variable.ordinal)"
        while occupied.contains(name) { name += "_" }
        return name
    }

    private func resolvedFunctionName(_ id: ResolvedFunctionID) throws -> String {
        guard functions.indices.contains(id.ordinal) else { throw missing("resolved function", id.ordinal) }
        let occupied = reservedNames.union(bindings.binders.values).union(bindings.operatorNames.values)
            .union(layout.declarations.map(\.name)).union(layout.actions.map(\.renderedName))
        var name = "__\(moduleName)_resolvedFunction\(id.ordinal)"
        while occupied.contains(name) { name += "_" }
        return name
    }

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
                    let assignment = "\(try variableName(variable))' = \(try state(value))"
                    let defined = try evaluationDefined(value)
                    parts.append(defined.map { "(IF \($0) THEN \(assignment) ELSE FALSE)" } ?? assignment)
                case .unchanged(let variable):
                    parts.append("UNCHANGED \(try variableName(variable))")
                case .guard_(let condition):
                    let predicate = try state(condition)
                    let defined = try evaluationDefined(condition)
                    // A state predicate produces one Boolean, not a successor per existential witness.
                    let rendered: String
                    if case .value(.boolean) = condition.operation {
                        rendered = predicate
                    } else {
                        rendered = "(\(predicate)) = TRUE"
                    }
                    parts.append(defined.map { "(IF \($0) THEN \(rendered) ELSE FALSE)" } ?? rendered)
                case .existsAction(let binder, let set, let body):
                    let defined = try evaluationDefined(set)
                    if let defined { parts.append("(IF \(defined) THEN ") }
                    parts.append("(\\E \(try binderName(binder)) \\in \(try state(set)): ")
                    schedule([.expression(body), .text(defined == nil ? ")" : ") ELSE FALSE)")])
                case .ifElse(let condition, let then, let otherwise):
                    let defined = try evaluationDefined(condition)
                    if let defined { parts.append("(IF \(defined) THEN ") }
                    parts.append("(IF \(try state(condition)) THEN (")
                    schedule([
                        .expression(then), .text(") ELSE ("), .expression(otherwise),
                        .text(defined == nil ? "))" : ")) ELSE FALSE)")
                    ])
                case .define(let binder, let value, let body):
                    let defined = try evaluationDefined(value)
                    if let defined { parts.append("(IF \(defined) THEN ") }
                    parts.append("(LET \(try binderName(binder)) == \(try state(value)) IN ")
                    schedule([.expression(body), .text(defined == nil ? ")" : ") ELSE FALSE)")])
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

    func choiceFailure(_ action: CompiledActionExpr) throws -> String? {
        switch action {
        case .assign(_, let value):
            return try expressionChoiceFailure(value)
        case .existsAction(let binder, let domain, let body):
            let domainFailure = try expressionChoiceFailure(domain)
            guard let bodyFailure = try choiceFailure(body) else { return domainFailure }
            let allFailures = try anyFailurePredicate(body)
            let predicate = try firstFailingCandidate(binder, domain: domain, anyFailure: allFailures,
                selected: bodyFailure, otherwise: "FALSE")
            let guarded = try evaluationDefined(domain).map { "(IF \($0) THEN \(predicate) ELSE FALSE)" } ?? predicate
            return domainFailure.map { "(\($0) \\/ \(guarded))" } ?? guarded
        case .define(let binder, let value, let body):
            // shortcut: consecutive bindings use an explicit stack; mixed action trees still recurse.
            var definitions = [(binder, value, try expressionChoiceFailure(value))]
            var remaining = body
            while case .define(let nestedBinder, let nestedValue, let nestedBody) = remaining {
                definitions.append((nestedBinder, nestedValue, try expressionChoiceFailure(nestedValue)))
                remaining = nestedBody
            }
            var failure = try choiceFailure(remaining)
            for (binder, value, valueFailure) in definitions.reversed() {
                guard let bodyFailure = failure else {
                    failure = valueFailure
                    continue
                }
                let defined = try evaluationDefined(value)
                guard repeatable(value) || defined != nil else {
                    failure = valueFailure
                    continue
                }
                let predicate = "(LET \(try binderName(binder)) == \(try state(value)) IN \(bodyFailure))"
                let guarded = defined.map { "(IF \($0) THEN \(predicate) ELSE FALSE)" } ?? predicate
                failure = valueFailure.map { "(\($0) \\/ \(guarded))" } ?? guarded
            }
            return failure
        case .guard_(let condition):
            return try expressionChoiceFailure(condition)
        case .and(.guard_(let condition), let body):
            let conditionFailure = try expressionChoiceFailure(condition)
            guard let selection = try selectedCondition(condition), let failure = try choiceFailure(body) else {
                return conditionFailure
            }
            let predicate = "((\(selection.predicate)) = TRUE /\\ \(failure))"
            let bodyFailure = selection.defined.map { "(IF \($0) THEN \(predicate) ELSE FALSE)" } ?? predicate
            return conditionFailure.map { "(\($0) \\/ \(bodyFailure))" } ?? bodyFailure
        case .and(let lhs, let rhs):
            let leftFailure = try choiceFailure(lhs)
            guard let rightFailure = try choiceFailure(rhs) else { return leftFailure }
            let reachedRight = "((ENABLED (\(try self.action(lhs)))) /\\ \(rightFailure))"
            return disjunction(leftFailure, reachedRight)
        case .or(let lhs, let rhs):
            let earlier = try anyFailurePredicate(lhs)
            let later = try choiceFailure(rhs).map { failure in
                earlier.map { "(IF \($0) THEN FALSE ELSE \(failure))" } ?? failure
            }
            switch (try choiceFailure(lhs), later) {
            case (nil, nil): return nil
            case (let failure?, nil), (nil, let failure?): return failure
            case (let lhs?, let rhs?): return "(\(lhs) \\/ \(rhs))"
            }
        case .ifElse(let condition, let yes, let no):
            let conditionFailure = try expressionChoiceFailure(condition)
            guard let selection = try selectedCondition(condition) else { return conditionFailure }
            let yesFailure = try choiceFailure(yes)
            let noFailure = try choiceFailure(no)
            guard yesFailure != nil || noFailure != nil else { return conditionFailure }
            let branch = "(IF \(selection.predicate) THEN \(yesFailure ?? "FALSE") ELSE \(noFailure ?? "FALSE"))"
            let guarded = selection.defined.map { "(IF \($0) THEN \(branch) ELSE FALSE)" } ?? branch
            return conditionFailure.map { "(\($0) \\/ \(guarded))" } ?? guarded
        default: return nil
        }
    }

    private func expressionChoiceFailure(_ value: CompiledExpression) throws -> String? {
        if let sites = try orderedFallibleSites(value) {
            var preceding: [String] = []
            var failures: [String] = []
            for site in sites {
                if case .choice(let guard_) = site {
                    failures.append(preceded("~(\(guard_))", by: preceding))
                }
                preceding.append(site.guard_)
            }
            if failures.isEmpty { return nil }
            return failures.count == 1 ? failures[0] : "(\(failures.joined(separator: " \\/ ")))"
        }
        guard let defined = try choiceDefined(value) else { return nil }
        return "~(\(defined))"
    }

    func evaluationFailures(_ action: CompiledActionExpr) throws -> [RenderedEvaluationFailure] {
        switch action {
        case .assign(_, let value):
            return try expressionEvaluationFailures(value)
        case .existsAction(let binder, let domain, let body):
            let domainFailures = try expressionEvaluationFailures(domain)
            let bodyFailures = try evaluationFailures(body)
            guard !bodyFailures.isEmpty else { return domainFailures }
            let defined = try evaluationDefined(domain)
            let allFailures = try anyFailurePredicate(body)
            return try domainFailures + bodyFailures.map { failure in
                let predicate = try firstFailingCandidate(binder, domain: domain, anyFailure: allFailures,
                    selected: failure.predicate, otherwise: "FALSE")
                let operands = try failure.operands.map { value in
                    try firstFailingCandidate(binder, domain: domain, anyFailure: allFailures,
                        selected: "(IF \(failure.predicate) THEN {\(value)} ELSE {})", otherwise: "{}")
                }
                return .init(
                    predicate: defined.map { "(IF \($0) THEN \(predicate) ELSE FALSE)" } ?? predicate,
                    operands: operands,
                    kind: failure.kind)
            }
        case .define(let binder, let value, let body):
            // shortcut: consecutive bindings use an explicit stack; mixed action trees still recurse.
            var definitions = [(binder, value, try evaluationDefined(value),
                try expressionEvaluationFailures(value))]
            var remaining = body
            while case .define(let nestedBinder, let nestedValue, let nestedBody) = remaining {
                definitions.append((nestedBinder, nestedValue, try evaluationDefined(nestedValue),
                    try expressionEvaluationFailures(nestedValue)))
                remaining = nestedBody
            }
            var failures = try evaluationFailures(remaining)
            for (binder, value, defined, originalFailures) in definitions.reversed() {
                var valueFailures = originalFailures
                // shortcut: values without a complete definedness rule still stop later-failure enumeration.
                guard repeatable(value) || defined != nil else {
                    failures = valueFailures
                    continue
                }
                let name = try binderName(binder)
                let renderedValue = try state(value)
                for failure in failures {
                    let predicate = "(LET \(name) == \(renderedValue) IN \(failure.predicate))"
                    let operands = failure.operands.map { "(LET \(name) == \(renderedValue) IN \($0))" }
                    valueFailures.append(.init(predicate: defined.map { "(IF \($0) THEN \(predicate) ELSE FALSE)" } ?? predicate,
                        operands: operands, kind: failure.kind))
                }
                failures = valueFailures
            }
            return failures
        case .guard_(let condition):
            return try expressionEvaluationFailures(condition)
        case .ifElse(let condition, let yes, let no):
            let conditionFailures = try expressionEvaluationFailures(condition)
            guard let selection = try selectedCondition(condition) else { return conditionFailures }
            let selected = try evaluationFailures(yes).map {
                let failure = "(IF \(selection.predicate) THEN \($0.predicate) ELSE FALSE)"
                return RenderedEvaluationFailure(predicate: selection.defined.map { "(IF \($0) THEN \(failure) ELSE FALSE)" } ?? failure,
                    operands: $0.operands, kind: $0.kind)
            }
            let unselected = try evaluationFailures(no).map {
                let failure = "(IF \(selection.predicate) THEN FALSE ELSE \($0.predicate))"
                return RenderedEvaluationFailure(predicate: selection.defined.map { "(IF \($0) THEN \(failure) ELSE FALSE)" } ?? failure,
                    operands: $0.operands, kind: $0.kind)
            }
            return conditionFailures + selected + unselected
        case .and(.guard_(let condition), let body):
            let conditionFailures = try expressionEvaluationFailures(condition)
            guard let selection = try selectedCondition(condition) else {
                return conditionFailures
            }
            return try conditionFailures + evaluationFailures(body).map {
                let predicate = "((\(selection.predicate)) = TRUE /\\ \($0.predicate))"
                return .init(predicate: selection.defined.map { "(IF \($0) THEN \(predicate) ELSE FALSE)" } ?? predicate,
                    operands: $0.operands, kind: $0.kind)
            }
        case .and(let lhs, let rhs):
            let leftFailures = try evaluationFailures(lhs)
            let rightFailures = try evaluationFailures(rhs)
            guard !rightFailures.isEmpty else { return leftFailures }
            let reachedRight = "(ENABLED (\(try self.action(lhs))))"
            return leftFailures + rightFailures.map {
                .init(predicate: "(\(reachedRight) /\\ \($0.predicate))", operands: $0.operands, kind: $0.kind)
            }
        case .or(let lhs, let rhs):
            let left = try evaluationFailures(lhs)
            let earlier = try anyFailurePredicate(lhs)
            let right = try evaluationFailures(rhs).map { failure in
                RenderedEvaluationFailure(predicate: earlier.map { "(IF \($0) THEN FALSE ELSE \(failure.predicate))" }
                    ?? failure.predicate, operands: failure.operands, kind: failure.kind)
            }
            return left + right
        default: return []
        }
    }

    func anyFailurePredicate(_ action: CompiledActionExpr) throws -> String? {
        switch action {
        case .assign(_, let value):
            return try expressionAnyFailure(value)
        case .existsAction(let binder, let domain, let body):
            let domainFailure = try expressionAnyFailure(domain)
            guard let bodyFailure = try anyFailurePredicate(body) else { return domainFailure }
            let quantified = "(\\E \(try binderName(binder)) \\in \(try state(domain)): \(bodyFailure))"
            let guarded = try evaluationDefined(domain).map { "(IF \($0) THEN \(quantified) ELSE FALSE)" }
                ?? quantified
            return disjunction(domainFailure, guarded)
        case .define:
            var definitions: [(binder: BinderID, value: CompiledExpression, failure: String?)] = []
            var remaining = action
            while case .define(let binder, let value, let body) = remaining {
                definitions.append((binder, value, try expressionAnyFailure(value)))
                remaining = body
            }
            var failure = try anyFailurePredicate(remaining)
            for (binder, value, valueFailure) in definitions.reversed() {
                guard let bodyFailure = failure else {
                    failure = valueFailure
                    continue
                }
                let defined = try evaluationDefined(value)
                guard repeatable(value) || defined != nil else {
                    failure = valueFailure
                    continue
                }
                let bound = "(LET \(try binderName(binder)) == \(try state(value)) IN \(bodyFailure))"
                let guarded = defined.map { "(IF \($0) THEN \(bound) ELSE FALSE)" } ?? bound
                failure = disjunction(valueFailure, guarded)
            }
            return failure
        case .guard_(let condition):
            return try expressionAnyFailure(condition)
        case .ifElse(let condition, let yes, let no):
            let conditionFailure = try expressionAnyFailure(condition)
            guard let selection = try selectedCondition(condition) else { return conditionFailure }
            let yesFailure = try anyFailurePredicate(yes)
            let noFailure = try anyFailurePredicate(no)
            guard yesFailure != nil || noFailure != nil else { return conditionFailure }
            let branch = "(IF \(selection.predicate) THEN \(yesFailure ?? "FALSE") ELSE \(noFailure ?? "FALSE"))"
            let guarded = selection.defined.map { "(IF \($0) THEN \(branch) ELSE FALSE)" } ?? branch
            return disjunction(conditionFailure, guarded)
        case .and(.guard_(let condition), let body):
            let conditionFailure = try expressionAnyFailure(condition)
            guard let selection = try selectedCondition(condition),
                  let bodyFailure = try anyFailurePredicate(body) else { return conditionFailure }
            let selected = "(IF \(selection.predicate) THEN \(bodyFailure) ELSE FALSE)"
            let guarded = selection.defined.map { "(IF \($0) THEN \(selected) ELSE FALSE)" } ?? selected
            return disjunction(conditionFailure, guarded)
        case .and(let lhs, let rhs):
            let leftFailure = try anyFailurePredicate(lhs)
            guard let rightFailure = try anyFailurePredicate(rhs) else { return leftFailure }
            let reachedRight = "(ENABLED (\(try self.action(lhs))))"
            return disjunction(leftFailure, "(\(reachedRight) /\\ \(rightFailure))")
        case .or(let lhs, let rhs):
            let first = try anyFailurePredicate(lhs)
            let second = try anyFailurePredicate(rhs)
            switch (first, second) {
            case (nil, nil): return nil
            case (let first?, nil): return first
            case (nil, let second?): return second
            case (let first?, let second?): return "(IF \(first) THEN TRUE ELSE \(second))"
            }
        default:
            let predicates = try evaluationFailures(action).map(\.predicate)
                + (try choiceFailure(action).map { [$0] } ?? [])
            guard !predicates.isEmpty else { return nil }
            return predicates.count == 1 ? predicates[0] : "(\(predicates.joined(separator: " \\/ ")))"
        }
    }

    private func expressionAnyFailure(_ value: CompiledExpression) throws -> String? {
        if let defined = try evaluationDefined(value), defined != "TRUE" { return "~(\(defined))" }
        let predicates = try expressionEvaluationFailures(value).map(\.predicate)
            + (try expressionChoiceFailure(value).map { [$0] } ?? [])
        guard !predicates.isEmpty else { return nil }
        return predicates.count == 1 ? predicates[0] : "(\(predicates.joined(separator: " \\/ ")))"
    }

    private func disjunction(_ first: String?, _ second: String) -> String {
        first.map { "(\($0) \\/ \(second))" } ?? second
    }

    private func canonicalLeastPredicate(_ type: CompiledValueType, _ member: String, _ other: String) throws -> String? {
        switch type {
        case .int: return "\(member) <= \(other)"
        case .bool: return "(\(member) = FALSE \\/ \(other) = TRUE)"
        default:
            guard let members = choiceMembers(type), !members.isEmpty,
                  members.allSatisfy(choiceMemberHasExactIdentity) else { return nil }
            return try rankedLeastPredicate(members.sorted(), member, other)
        }
    }

    private func rankedLeastPredicate(_ members: [CompiledValue], _ member: String, _ other: String) throws -> String {
        func rank(_ value: String) throws -> String {
            let cases = try members.enumerated().map { index, member in
                "\(value) = \(try member.rendered(using: layout)) -> \(index)"
            }.joined(separator: " [] ")
            return "(CASE \(cases))"
        }
        return try "\(rank(member)) <= \(rank(other))"
    }

    private func firstFailingCandidate(
        _ binder: BinderID,
        domain: CompiledExpression,
        anyFailure: String?,
        selected: String,
        otherwise: String
    ) throws -> String {
        guard case .set(let memberType) = domain.resultType,
              let failure = anyFailure else {
            throw CompilationDiagnostic(code: .unsupportedCanonicalCandidateOrder, stage: .rendering,
                path: "actions.with[\(binder.ordinal)].domain",
                expected: "a set domain and an identified branch failure",
                actual: "the candidate failure order cannot be established",
                nextSafeAction: "Use a set domain whose candidate order the TLA+ renderer can reproduce.")
        }
        let occupied = reservedNames.union(bindings.binders.values).union(bindings.operatorNames.values)
            .union(layout.declarations.map(\.name)).union(layout.actions.map(\.renderedName))
        var names: [String] = []
        for stem in ["FailedCandidates", "FirstFailingCandidate", "EarlierCandidate"] {
            var name = "__SwiftTLA\(stem)\(binder.ordinal)"
            while occupied.contains(name) || names.contains(name) { name += "_" }
            names.append(name)
        }
        let bound = try binderName(binder)
        let failed = names[0]
        let first = names[1]
        let earlier = names[2]
        let ordered: String
        if let typedOrder = try canonicalLeastPredicate(memberType, first, earlier) {
            ordered = typedOrder
        } else if let members = closedChoiceMembers(domain) ?? parameterChoiceMembers(domain) {
            ordered = try rankedLeastPredicate(members, first, earlier)
        } else {
            throw CompilationDiagnostic(code: .unsupportedCanonicalCandidateOrder, stage: .rendering,
                path: "actions.with[\(binder.ordinal)].domain",
                expected: "a canonical order for every candidate in the domain",
                actual: "the state-dependent candidate set has no renderable total order",
                nextSafeAction: "Use an Int, Bool, finite enum, or finite parameter domain for a fallible With body.")
        }
        let least = "(CHOOSE \(first) \\in \(failed): \\A \(earlier) \\in \(failed): \(ordered))"
        return "(LET \(failed) == {\(bound) \\in \(try state(domain)): \(failure)} IN "
            + "(IF \(failed) = {} THEN \(otherwise) ELSE "
            + "(LET \(bound) == \(least) IN \(selected))))"
    }

    private func selectedCondition(_ condition: CompiledExpression) throws -> (predicate: String, defined: String?)? {
        let defined = try evaluationDefined(condition)
        guard arithmeticTreeIsRepeatable(condition) || defined != nil else { return nil }
        return (try state(condition), defined)
    }

    private func checkedShapePredicate(_ shape: FormalValueShape, value: String,
                                       sourceType: CompiledValueType) throws -> String {
        try shape.predicate(for: value, sourceType: sourceType,
            namedMembers: { enums.domains[$0]?.sorted() },
            renderFinite: { try $0.rendered(using: layout).description })
    }

    func expressionEvaluationFailures(
        _ value: CompiledExpression, stateNames: [VariableID: String] = [:]
    ) throws -> [RenderedEvaluationFailure] {
        var failures: [RenderedEvaluationFailure] = []
        if let sites = try orderedFallibleSites(value, stateNames: stateNames) {
            var preceding: [String] = []
            for site in sites {
                switch site {
                case .choice: break
                case .noMatchingCase(let guard_):
                    failures.append(.init(predicate: preceded("~(\(guard_))", by: preceding),
                        operands: nil, kind: .noMatchingCase))
                case .arithmetic(let operation, let guard_, let operands):
                    failures.append(.init(predicate: preceded("~(\(guard_))", by: preceding),
                        operands: operands, kind: .overflow(operation)))
                case .divisionByZero(let guard_, let divisor):
                    failures.append(.init(predicate: preceded("~(\(guard_))", by: preceding),
                        operands: divisor, kind: .divisionByZero))
                case .negativeModuloDivisor(let guard_, let divisor):
                    failures.append(.init(predicate: preceded("~(\(guard_))", by: preceding),
                        operands: divisor, kind: .negativeModuloDivisor))
                case .functionArgumentOutsideDomain(let guard_):
                    failures.append(.init(predicate: preceded("~(\(guard_))", by: preceding),
                        operands: nil, kind: .functionArgumentOutsideDomain))
                case .sequenceIndexOutOfBounds(let guard_, let operands):
                    failures.append(.init(predicate: preceded("~(\(guard_))", by: preceding),
                        operands: operands, kind: .sequenceIndexOutOfBounds))
                case .emptySequence(let guard_):
                    failures.append(.init(predicate: preceded("~(\(guard_))", by: preceding),
                        operands: nil, kind: .emptySequence))
                }
                preceding.append(site.guard_)
            }
        } else {
            var precedingGuards: [String] = []
            for site in try arithmeticSites(value, stateNames: stateNames) {
                let failure = "~(\(site.guard_))"
                let predicate = preceded(failure, by: precedingGuards)
                failures.append(.init(predicate: predicate, operands: site.operands,
                    kind: .overflow(site.operation)))
                precedingGuards.append(site.guard_)
            }
        }
        return failures
    }

    func evaluationDefined(
        _ value: CompiledExpression, stateNames: [VariableID: String] = [:]
    ) throws -> String? {
        if let sites = try orderedFallibleSites(value, stateNames: stateNames) {
            let defined: String = sites.reversed().reduce("TRUE") { result, site in
                "(IF \(site.guard_) THEN \(result) ELSE FALSE)"
            }
            return defined
        }
        return try choiceDefined(value, stateNames: stateNames)
            ?? arithmeticDefined(value, stateNames: stateNames)
    }

    private func preceded(_ predicate: String, by guards: [String]) -> String {
        guards.reversed().reduce(predicate) { result, guard_ in
            "(IF \(guard_) THEN \(result) ELSE FALSE)"
        }
    }

    private func orderedFallibleSites(
        _ expression: CompiledExpression, stateNames: [VariableID: String] = [:]
    ) throws -> [OrderedEvaluationSite]? {
        // shortcut: effectful expressions still need path-sensitive outcome rules.
        func collect(_ value: CompiledExpression) throws -> [OrderedEvaluationSite]? {
            switch value.operation {
            case .convert:
                guard value.children.count == 1 else { return nil }
                return try collect(value.children[0])
            case .recordAccess, .tupleAccess:
                guard value.children.count == 1 else { return nil }
                return try collect(value.children[0])
            case .assertView(let shape):
                guard value.children.count == 1,
                      let preceding = try collect(value.children[0]) else { return nil }
                let operand = try state(value.children[0], stateNames: stateNames)
                return preceding + [.noMatchingCase(guard_: try checkedShapePredicate(shape,
                    value: operand, sourceType: value.children[0].resultType))]
            case .ifThenElse:
                guard value.children.count == 3,
                      let condition = try collect(value.children[0]),
                      let selected = try collect(value.children[1]),
                      let unselected = try collect(value.children[2]) else { return nil }
                let predicate = try state(value.children[0], stateNames: stateNames)
                return condition + selected.map { $0.selected(by: predicate, whenTrue: true) }
                    + unselected.map { $0.selected(by: predicate, whenTrue: false) }
            case .and, .or:
                guard value.children.count == 2,
                      let left = try collect(value.children[0]),
                      let right = try collect(value.children[1]) else { return nil }
                let predicate = try state(value.children[0], stateNames: stateNames)
                return left + right.map {
                    $0.selected(by: predicate, whenTrue: value.operation == .and)
                }
            case .choose:
                guard let defined = try choiceDefined(value, stateNames: stateNames) else { return nil }
                return [.choice(guard_: defined)]
            case .functionApply:
                guard value.children.count == 2,
                      case .dictionary = value.children[0].resultType else { return nil }
                var preceding: [OrderedEvaluationSite] = []
                let children = value.operation.evaluatesRightOperandFirst
                    ? Array(value.children.reversed()) : value.children
                for child in children {
                    guard let sites = try collect(child) else { return nil }
                    preceding += sites
                }
                let function = try state(value.children[0], stateNames: stateNames)
                let argument = try state(value.children[1], stateNames: stateNames)
                return preceding + [.functionArgumentOutsideDomain(
                    guard_: "(\(argument) \\in DOMAIN (\(function)))")]
            case .tupleDynamicAccess, .tupleRemoving, .tuplePrefix:
                guard value.children.count == 2 else { return nil }
                var preceding: [OrderedEvaluationSite] = []
                for child in value.children {
                    guard let sites = try collect(child) else { return nil }
                    preceding += sites
                }
                let sequence = try state(value.children[0], stateNames: stateNames)
                let index = try state(value.children[1], stateNames: stateNames)
                let defined = value.operation == .tuplePrefix
                    ? "(\(index) <= Len(\(sequence)))"
                    : "(\(index) \\in DOMAIN (\(sequence)))"
                return preceding + [.sequenceIndexOutOfBounds(
                    guard_: defined,
                    operands: "<<\(index), Len(\(sequence))>>")]
            case .tupleHead, .tupleTail:
                guard value.children.count == 1,
                      let preceding = try collect(value.children[0]) else { return nil }
                let sequence = try state(value.children[0], stateNames: stateNames)
                return preceding + [.emptySequence(guard_: "Len(\(sequence)) > 0")]
            case .setSum:
                guard value.resultType == .int, value.children.count == 2,
                      case .dictionary = value.children[0].resultType else { return nil }
                var preceding: [OrderedEvaluationSite] = []
                for child in value.children {
                    guard let sites = try collect(child) else { return nil }
                    preceding += sites
                }
                let function = try state(value.children[0], stateNames: stateNames)
                let domain = try state(value.children[1], stateNames: stateNames)
                preceding.append(.functionArgumentOutsideDomain(
                    guard_: "(\(domain) \\subseteq DOMAIN (\(function)))"))
                let sum = try state(value, stateNames: stateNames)
                let minimum = TLAValue.int(.min).description
                let maximum = TLAValue.int(.max).description
                return preceding + [.arithmetic(operation: .summation,
                    guard_: "(\(sum) >= \(minimum) /\\ \(sum) <= \(maximum))",
                    operands: try sortedSummationOperands(value, stateNames: stateNames))]
            case .add, .subtract, .multiply, .negate, .divide, .integerDivide, .modulo:
                guard value.resultType == .int,
                      value.children.count == (value.operation == .negate ? 1 : 2) else { return nil }
                var preceding: [OrderedEvaluationSite] = []
                let children = value.operation.evaluatesRightOperandFirst ? Array(value.children.reversed()) : value.children
                for child in children {
                    guard let sites = try collect(child) else { return nil }
                    preceding += sites
                }
                switch value.operation {
                case .divide, .integerDivide:
                    let dividend = try state(value.children[0], stateNames: stateNames)
                    let divisor = try state(value.children[1], stateNames: stateNames)
                    let minimum = TLAValue.int(.min).description
                    return preceding + [
                        .divisionByZero(guard_: "\(divisor) # 0", divisor: divisor),
                        .arithmetic(operation: .division,
                            guard_: "(IF \(divisor) # -1 THEN TRUE ELSE \(dividend) # \(minimum))",
                            operands: "<<\(dividend), \(divisor)>>")
                    ]
                case .modulo:
                    let divisor = try state(value.children[1], stateNames: stateNames)
                    return preceding + [
                        .divisionByZero(guard_: "\(divisor) # 0", divisor: divisor),
                        .negativeModuloDivisor(guard_: "\(divisor) > 0", divisor: divisor)
                    ]
                default:
                    let site = try arithmeticSite(value, stateNames: stateNames)
                    return preceding + [.arithmetic(operation: site.operation,
                        guard_: site.guard_, operands: site.operands)]
                }
            case .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .not,
                 .in, .setLiteral, .tupleLiteral, .tupleAppend, .tupleConcatenate, .tupleLength,
                 .cardinality:
                var preceding: [OrderedEvaluationSite] = []
                let children = value.operation.evaluatesRightOperandFirst
                    ? Array(value.children.reversed()) : value.children
                for child in children {
                    guard let sites = try collect(child) else { return nil }
                    preceding += sites
                }
                return preceding
            default:
                return repeatable(value) ? [] : nil
            }
        }
        guard let sites = try collect(expression) else { return nil }
        let hasSpecialFailure = sites.contains {
            switch $0 {
            case .noMatchingCase, .divisionByZero, .negativeModuloDivisor, .functionArgumentOutsideDomain,
                 .sequenceIndexOutOfBounds, .emptySequence: true
            case .arithmetic(operation: .summation, guard_: _, operands: _): true
            default: false
            }
        }
        let hasChoice = sites.contains { if case .choice = $0 { return true }; return false }
        let hasNestedChoice: Bool
        if hasChoice {
            hasNestedChoice = try choiceDefined(expression, stateNames: stateNames) == nil
        } else {
            hasNestedChoice = false
        }
        func hasLazyBranch(_ value: CompiledExpression) -> Bool {
            switch value.operation {
            case .ifThenElse, .and, .or: return true
            default: return value.children.contains(where: hasLazyBranch)
            }
        }
        guard !sites.isEmpty, hasSpecialFailure || hasNestedChoice || hasLazyBranch(expression) else { return nil }
        return sites
    }

    private func sortedSummationOperands(
        _ expression: CompiledExpression, stateNames: [VariableID: String] = [:]
    ) throws -> String {
        let function = try state(expression.children[0], stateNames: stateNames)
        let domain = try state(expression.children[1], stateNames: stateNames)
        let occupied = reservedNames.union(bindings.binders.values).union(bindings.operatorNames.values)
            .union(layout.declarations.map(\.name)).union(layout.actions.map(\.renderedName))
            .union(stateNames.values)
        var names: [String] = []
        for role in ["index", "candidate", "member"] {
            var name = "__SwiftTLASum_\(role)"
            while occupied.contains(name) || names.contains(name) { name += "_" }
            names.append(name)
        }
        let position = names[0], candidate = names[1], member = names[2]
        let values = "{(\(function))[\(member)] : \(member) \\in (\(domain))}"
        let earlier = "{\(member) \\in (\(domain)) : (\(function))[\(member)] < \(candidate)}"
        let through = "{\(member) \\in (\(domain)) : (\(function))[\(member)] <= \(candidate)}"
        return "[\(position) \\in 1..Cardinality(\(domain)) |-> "
            + "(CHOOSE \(candidate) \\in \(values): "
            + "Cardinality(\(earlier)) < \(position) /\\ \(position) <= Cardinality(\(through)))]"
    }

    private func arithmeticDefined(
        _ value: CompiledExpression, stateNames: [VariableID: String] = [:]
    ) throws -> String? {
        let sites = try arithmeticSites(value, stateNames: stateNames)
        guard !sites.isEmpty else { return nil }
        return sites.count == 1 ? sites[0].guard_ : preceded("TRUE", by: sites.map(\.guard_))
    }

    private func arithmeticSites(
        _ value: CompiledExpression, stateNames: [VariableID: String] = [:]
    ) throws -> [(
        guard_: String, operands: String, operation: NativeMachineEvaluationError.IntegerOperation
    )] {
        // shortcut: only pure checked arithmetic, including total comparisons, is guarded; extend to other fallible expressions.
        guard arithmeticTreeIsRepeatable(value) else { return [] }
        var operations: [CompiledExpression] = []
        func collect(_ expression: CompiledExpression) {
            for child in expression.children { collect(child) }
            switch expression.operation {
            case .add, .subtract, .multiply, .negate: operations.append(expression)
            default: break
            }
        }
        collect(value)
        return try operations.map { try arithmeticSite($0, stateNames: stateNames) }
    }

    private func arithmeticSite(
        _ expression: CompiledExpression, stateNames: [VariableID: String] = [:]
    ) throws -> (
        guard_: String, operands: String, operation: NativeMachineEvaluationError.IntegerOperation
    ) {
        let lhs = try state(expression.children[0], stateNames: stateNames)
        let swiftIntMinimum = TLAValue.int(.min).description
        let swiftIntMaximum = TLAValue.int(.max).description
        if case .negate = expression.operation {
            let small = "(\(lhs) >= -1000000000 /\\ \(lhs) <= 1000000000)"
            return ("(IF \(small) THEN TRUE ELSE \(lhs) # \(swiftIntMinimum))", "<<\(lhs)>>", .negation)
        }
        let rhs = try state(expression.children[1], stateNames: stateNames)
        let smallLimit = expression.operation == .multiply ? 40000 : 1000000000
        let small = "(\(lhs) >= -\(smallLimit) /\\ \(lhs) <= \(smallLimit) /\\ \(rhs) >= -\(smallLimit) /\\ \(rhs) <= \(smallLimit))"
        let exact: String
        let operation: NativeMachineEvaluationError.IntegerOperation
        switch expression.operation {
        case .add:
            operation = .addition
            exact = "(IF \(rhs) > 0 THEN \(lhs) <= \(swiftIntMaximum) - (\(rhs)) ELSE IF \(rhs) < 0 THEN \(lhs) >= \(swiftIntMinimum) - (\(rhs)) ELSE TRUE)"
        case .subtract:
            operation = .subtraction
            exact = "(IF \(rhs) > 0 THEN \(lhs) >= \(swiftIntMinimum) + (\(rhs)) ELSE IF \(rhs) < 0 THEN \(lhs) <= \(swiftIntMaximum) + (\(rhs)) ELSE TRUE)"
        case .multiply:
            operation = .multiplication
            exact = "(\(lhs) * \(rhs) >= \(swiftIntMinimum) /\\ \(lhs) * \(rhs) <= \(swiftIntMaximum))"
        default:
            throw CompiledValueType.diagnostic("rendering.arithmetic", "expected checked arithmetic")
        }
        return ("(IF \(small) THEN TRUE ELSE \(exact))", "<<\(lhs), \(rhs)>>", operation)
    }

    private func arithmeticTreeIsRepeatable(_ expression: CompiledExpression) -> Bool {
        switch expression.operation {
        case .add, .subtract, .multiply, .negate:
            return (expression.resultType == .int || expression.resultType == .unknown)
                && expression.children.count == (expression.operation == .negate ? 1 : 2)
                && expression.children.allSatisfy(arithmeticTreeIsRepeatable)
        case .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .not,
             .tupleLiteral:
            return expression.children.allSatisfy(arithmeticTreeIsRepeatable)
        default:
            return repeatable(expression)
        }
    }

    func choiceDefined(_ value: CompiledExpression, stateNames: [VariableID: String] = [:]) throws -> String? {
        if case .not = value.operation, value.children.count == 1 {
            return try choiceDefined(value.children[0], stateNames: stateNames)
        }
        guard case .choose(let binder) = value.operation else { return nil }
        guard value.children.count == 2 else {
            throw CompiledValueType.diagnostic("rendering.choose", "choice requires a domain and predicate")
        }
        // shortcut: only repeatable total operands may be guarded; extend with per-operation proofs.
        guard value.children.allSatisfy(repeatable) else { return nil }
        return "(\\E \(try binderName(binder)) \\in \(try state(value.children[0], stateNames: stateNames)) : \(try state(value.children[1], stateNames: stateNames)))"
    }

    private func repeatable(_ expression: CompiledExpression) -> Bool {
        switch expression.operation {
        case .value, .stateVariable, .boundValue, .controlLocation,
             .setLiteral, .tupleLiteral, .equal, .notEqual, .lessThan, .lessOrEqual,
             .greaterThan, .greaterOrEqual, .and, .or, .not, .in:
            return expression.children.allSatisfy(repeatable)
        default:
            return false
        }
    }

    func temporal(_ property: CompiledTemporal<CompiledStateQuery>) throws -> String {
        var result = try temporal(property.expression)
        for binding in property.bindings.reversed() {
            result = "(\\A \(try binderName(binding.binder)) \\in \(try state(binding.domain)): \(result))"
        }
        return result
    }

    func temporal(
        _ expression: TemporalCondition<CompiledStateQuery>
    ) throws -> String {
        switch expression {
        case .always(let predicate):
            let claim = predicate.expression
            if case .stutteringStep = claim.operation {
                return "[][\(try state(claim))]_(\(try state(claim.children[0])))"
            }
            return "[]\(try state(claim))"
        case .eventually(let predicate): return "<>\(try state(predicate.expression))"
        case .alwaysEventually(let predicate): return "[]<>\(try state(predicate.expression))"
        case .eventuallyAlways(let predicate): return "<>[]\(try state(predicate.expression))"
        case .leadsTo(let source, let target): return "(\(try state(source.expression)) ~> \(try state(target.expression)))"
        case .all(let conditions):
            return conditions.isEmpty ? "TRUE" : "(" + (try conditions.map { try temporal($0) }).joined(separator: " /\\ ") + ")"
        case .conditional(let predicate, let yes, let no):
            return "(IF \(try state(predicate.expression)) THEN \(try temporal(yes)) ELSE \(try temporal(no)))"
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
        actionCalls: [CompiledActionCall: String]
    ) throws -> String {
        let action: String
        let vars = try condition.projection.map { "(\(try state($0)))" } ?? vars
        switch condition.scope {
        case .next:
            action = "Next"
        case .action(let id):
            action = try actionReference(id)
        case .actionGroup(let ids):
            action = "(" + (try ids.map { try actionReference($0) }).joined(separator: " \\/ ") + ")"
        case .actionCall(let call):
            guard let name = actionCalls[call] else { throw missing("action", call.action.ordinal) }
            action = name
        case .actionCallGroup:
            throw missing("unexpanded process fairness group", 0)
        case .eachAction(let id):
            let bindings = actions[id.ordinal].bindings
            let parameters = try bindings.map { try binderName($0.binder) }
            let name = layout.actions[id.ordinal].renderedName
            let invocation = name + (parameters.isEmpty ? "" : "(\(parameters.joined(separator: ", ")))")
            var result = "\(condition.isStrong ? "SF" : "WF")_\(vars)(\(invocation))"
            for (parameter, binding) in zip(parameters, bindings).reversed() {
                result = "(\\A \(parameter) \\in \(try state(binding.domain)): \(result))"
            }
            return result
        case .eachActionGroup(let ids):
            guard let first = ids.first else { throw missing("process fairness group", 0) }
            let bindings = actions[first.ordinal].bindings
            let parameters = try bindings.map { try binderName($0.binder) }
            let invocation = ids.map { id in
                layout.actions[id.ordinal].renderedName + "(" + parameters.joined(separator: ", ") + ")"
            }.joined(separator: " \\/ ")
            let group = ids.count == 1 ? invocation : "(\(invocation))"
            var result = "\(condition.isStrong ? "SF" : "WF")_\(vars)(\(group))"
            for (parameter, binding) in zip(parameters, bindings).reversed() {
                result = "(\\A \(parameter) \\in \(try state(binding.domain)): \(result))"
            }
            return result
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
        return "\(layout.namespace) == INSTANCE \(moduleNames[layout.moduleName] ?? layout.moduleName)\(withClause)"
    }

    func state(_ expression: CompiledExpression, stateNames: [VariableID: String] = [:]) throws -> String {
        var tasks = [StateRenderingTask.expression(expression)]
        var parts: [String] = []
        let occupied = reservedNames.union(bindings.binders.values).union(bindings.operatorNames.values)
            .union(layout.declarations.map(\.name)).union(layout.actions.map(\.renderedName))
            .union(stateNames.values)
        var nextDivisionName = 0
        var nextChoiceName = 0

        func divisionName(_ role: String) -> String {
            var name = "__\(moduleName)_\(role)\(nextDivisionName)"
            nextDivisionName += 1
            while occupied.contains(name) { name += "_" }
            return name
        }

        func choiceName(_ role: String) -> String {
            var name = "__\(moduleName)_\(role)\(nextChoiceName)"
            nextChoiceName += 1
            while occupied.contains(name) { name += "_" }
            return name
        }

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
            case .setMember(let member):
                tasks.append(.finishSetMember(start: parts.count))
                tasks.append(.expression(member))
            case .finishSetMember(let start):
                let member = parts[start...].joined()
                parts.replaceSubrange(start..., with: [member])
            case .finishSet(let start):
                let members = parts[start...].sorted().joined(separator: ", ")
                parts.replaceSubrange(start..., with: ["{\(members)}"])
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
            case .checkedView(let shape, let sourceType, let start):
                let operand = parts[start...].joined()
                parts.removeSubrange(start...)
                var name = "_checkedValue"
                let shapeNames = String(describing: shape)
                while operand.contains(name) || shapeNames.contains(name) { name += "_" }
                let predicate = try checkedShapePredicate(shape, value: name, sourceType: sourceType)
                parts.append("(LET \(name) == \(operand) IN CASE \(predicate) -> \(name))")
            case .expression(let expression):
                switch expression.operation {
                case .setMap, .unionAll:
                    if let fields = cartesianRecordFields(expression) {
                        var rendered: [StateRenderingTask] = [.text("[")]
                        for (index, field) in fields.enumerated() {
                            if index > 0 { rendered.append(.text(", ")) }
                            rendered.append(.text("\(field.name): "))
                            rendered.append(.expression(field.domain))
                        }
                        rendered.append(.text("]"))
                        schedule(rendered)
                    } else {
                        try schedule(expression.operation, expression.children)
                    }
                case .setLiteral:
                    tasks.append(.finishSet(start: parts.count))
                    tasks.append(contentsOf: expression.children.reversed().map(StateRenderingTask.setMember))
                case .assertView(let shape):
                    let value = expression.children[0]

                    tasks.append(.checkedView(shape, sourceType: value.resultType, start: parts.count))
                    tasks.append(.expression(value))
                case .nextState, .stutteringStep:
                    try schedule(expression.operation, expression.children)
                case .value(let value): parts.append(try value.rendered(using: layout).description)
                case .integerSet: parts.append("Int")
                case .stateVariable(let variable): parts.append(try stateNames[variable] ?? variableName(variable))
                case .boundValue(let binder): parts.append(try binderName(binder))
                case .checkingRegister(let id): parts.append("TLCGet(\(id.ordinal))")
                case .checkingLevel: parts.append("TLCGet(\"level\")")
                case .checkingDiameter: parts.append("TLCGet(\"stats\").diameter")
                case .setCheckingRegister(let id):
                    parts.append("TLCSet(\(id.ordinal), ")
                    tasks.append(.text(")"))
                    tasks.append(.expression(expression.children[0]))
                case .controlLocation(let location): parts.append(try controlLocationName(location))
                case .operatorReference(let operation): parts.append(try operatorName(operation))
                case .enabledAction(let action): parts.append("ENABLED \(try actionReference(action))")
                case .convert:
                    tasks.append(.expression(expression.children[0]))
                case .call(let id):
                    let name = try resolvedFunctionName(id)
                    guard expression.children.count == functions[id.ordinal].parameters.count else {
                        throw missing("resolved function arguments", id.ordinal)
                    }
                    parts.append(name)
                    let captures = try functionStateCaptures(id)
                    if !expression.children.isEmpty || !captures.isEmpty {
                        parts.append("(")
                        var arguments: [StateRenderingTask] = []
                        for (index, child) in expression.children.enumerated() {
                            if index > 0 { arguments.append(.text(", ")) }
                            arguments.append(.expression(child))
                        }
                        for variable in captures {
                            if !arguments.isEmpty { arguments.append(.text(", ")) }
                            arguments.append(.text(try stateNames[variable] ?? variableName(variable)))
                        }
                        arguments.append(.text(")"))
                        schedule(arguments)
                    }
                case .checkedCall:
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
                    parts.append("(LET ")
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
                    rendered.append(.text(")"))
                    schedule(rendered)
                case .divide, .integerDivide:
                    guard expression.children.count == 2 else {
                        throw CompiledValueType.diagnostic("rendering.divide", "integer division requires two operands")
                    }
                    let dividend = divisionName("dividend")
                    let divisor = divisionName("divisor")
                    parts.append("(LET \(dividend) == ")
                    schedule([.expression(expression.children[0]), .text(" IN (LET \(divisor) == "),
                        .expression(expression.children[1]),
                        .text(" IN (IF \(divisor) < 0 THEN (-\(dividend)) \\div (-\(divisor)) ELSE \(dividend) \\div \(divisor))))")])
                case .choose(let binder) where expression.resultType == .int || expression.resultType == .bool
                    || expression.resultType == .array(.int) || expression.resultType == .array(.bool)
                    || choiceMembers(expression) != nil:
                    guard expression.children.count == 2 else {
                        throw CompiledValueType.diagnostic("rendering.choose", "choice requires a domain and predicate")
                    }
                    let member = try binderName(binder)
                    let candidates = choiceName("choiceCandidates")
                    let other = choiceName("choiceOther")
                    let least: String
                    if let ordered = try canonicalLeastPredicate(expression.resultType, member, other) {
                        least = ordered
                    } else if let members = choiceMembers(expression) {
                        least = try rankedLeastPredicate(members, member, other)
                    } else if expression.resultType == .array(.int) || expression.resultType == .array(.bool) {
                        let index = choiceName("choiceIndex")
                        let prefix = choiceName("choicePrefix")
                        let equalPrefix = "(\\A \(prefix) \\in 1..(\(index) - 1) : \(member)[\(prefix)] = \(other)[\(prefix)])"
                        let less = expression.resultType == .array(.int)
                            ? "\(member)[\(index)] < \(other)[\(index)]"
                            : "(\(member)[\(index)] = FALSE /\\ \(other)[\(index)] = TRUE)"
                        let firstDifference = "(\\E \(index) \\in 1..Len(\(member)) : IF \(index) <= Len(\(other)) THEN (\(equalPrefix) /\\ \(less)) ELSE FALSE)"
                        let properPrefix = "(IF Len(\(member)) < Len(\(other)) THEN (\\A \(prefix) \\in 1..Len(\(member)) : \(member)[\(prefix)] = \(other)[\(prefix)]) ELSE FALSE)"
                        least = "(\(member) = \(other) \\/ \(firstDifference) \\/ \(properPrefix))"
                    } else {
                        throw CompiledValueType.diagnostic("rendering.choose", "choice has no finite member order")
                    }
                    parts.append("(LET \(candidates) == {\(member) \\in ")
                    schedule([.expression(expression.children[0]), .text(" : "),
                        .expression(expression.children[1]),
                        .text("} IN (CHOOSE \(member) \\in \(candidates) : (\\A \(other) \\in \(candidates) : \(least))))")])
                case .add, .subtract, .multiply, .modulo, .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .and, .or, .in, .subset, .union, .intersection, .setDifference, .tupleDynamicAccess, .tupleAppend, .tupleConcatenate, .tupleRemoving, .tuplePrefix, .sequenceSelect, .functionApply, .functionSet, .randomSubset, .randomElement, .setSum, .integerRange, .negate, .not, .printT, .cardinality, .powerSet, .sequenceSet, .tupleLength, .tupleHead, .tupleTail, .domain, .sequenceFromSet, .sequenceFromFunction, .ifThenElse, .setFilter, .tupleLiteral, .tupleAccess, .recordLiteral, .recordAccess, .functionLiteral, .except, .caseExpr, .forAll, .exists, .choose, .foldFunction, .letValue:
                    try schedule(expression.operation, expression.children)

                }
            }
        }
        return parts.joined()
    }

    private func choiceMembers(_ type: CompiledValueType) -> [CompiledValue]? {
        switch type {
        case .finite(let members): return members.isEmpty ? nil : members
        case .named(let name):
            guard let members = enums.cases[name]?.map(\.value), !members.isEmpty else { return nil }
            return members
        default: return nil
        }
    }

    private func choiceMembers(_ expression: CompiledExpression) -> [CompiledValue]? {
        if let members = choiceMembers(expression.resultType) { return members }
        // shortcut: only closed values with exact Swift/TLA identity have a renderable rank; dynamic domains need a general value order.
        let supportsClosedRank: Bool
        switch expression.resultType {
        case .string, .unknown, .array, .tuple: supportsClosedRank = true
        default: supportsClosedRank = false
        }
        guard supportsClosedRank, let domain = expression.children.first else { return nil }
        return closedChoiceMembers(domain)
    }

    private func closedChoiceMembers(_ domain: CompiledExpression) -> [CompiledValue]? {
        let domainValue = domain.computation
        let members: [CompiledValue]
        switch domainValue.operation {
        case .value(.set(let values)):
            members = Array(values)
        case .setLiteral:
            members = domainValue.children.compactMap(closedChoiceMember)
            guard members.count == domainValue.children.count else { return nil }
        default:
            return nil
        }
        guard members.count > 1, members.allSatisfy(choiceMemberHasExactIdentity) else { return nil }
        return Array(Set(members)).sorted()
    }

    private func parameterChoiceMembers(_ domain: CompiledExpression) -> [CompiledValue]? {
        if let cached = finiteCandidateCache.members[domain] { return cached.values }
        let members = computedParameterChoiceMembers(domain)
        finiteCandidateCache.members[domain] = members.map(FiniteCandidateMembers.values) ?? .unavailable
        return members
    }

    private func computedParameterChoiceMembers(_ domain: CompiledExpression) -> [CompiledValue]? {
        if case .boundValue(let binder) = domain.computation.operation {
            return directParameterChoiceMembers(binder)
        }
        guard case .domain = domain.computation.operation,
              domain.computation.children.count == 1,
              let selected = domain.computation.children.first?.computation,
              case .tupleDynamicAccess = selected.operation,
              selected.children.count == 2,
              case .boundValue(let parameter) = selected.children[0].computation.operation,
              case .value(.integer) = selected.children[1].computation.operation,
              let parameterDomain = parameterDomains[parameter] else { return nil }
        // shortcut: rank tuple-selected keys only for a singleton literal parameter; prove wider projections before accepting them.
        switch parameterDomain.computation.operation {
        case .setLiteral:
            guard parameterDomain.computation.children.count == 1 else { return nil }
        case .value(.set(let values)):
            guard values.count == 1 else { return nil }
        default: return nil
        }
        let parameterEvaluator = CompiledEvaluator(variableValues: [:], operators: operators)
        guard case .set(let allowedValues) = try? parameterEvaluator.evaluate(parameterDomain),
              let allowedValue = allowedValues.first, allowedValues.count == 1 else { return nil }
        let evaluator = CompiledEvaluator(variableValues: [:], operators: operators,
            bindings: CompiledBindings().binding(allowedValue, to: parameter))
        guard case .set(let members) = try? evaluator.evaluate(domain) else { return nil }
        guard !members.isEmpty, members.allSatisfy(choiceMemberHasExactIdentity) else { return nil }
        return members.sorted()
    }

    private func directParameterChoiceMembers(_ binder: BinderID) -> [CompiledValue]? {
        guard let parameterDomain = parameterDomains[binder] else { return nil }
        let allowedValues: [CompiledValue]
        switch parameterDomain.computation.operation {
        case .value(.set(let values)):
            allowedValues = Array(values)
        case .setLiteral:
            allowedValues = parameterDomain.computation.children.compactMap(closedChoiceMember)
            guard allowedValues.count == parameterDomain.computation.children.count else { return nil }
        default: return nil
        }
        var members: Set<CompiledValue> = []
        for allowedValue in allowedValues {
            guard case .set(let values) = allowedValue else { return nil }
            members.formUnion(values)
        }
        guard !members.isEmpty, members.allSatisfy(choiceMemberHasExactIdentity) else { return nil }
        return members.sorted()
    }

    private func closedChoiceMember(_ expression: CompiledExpression) -> CompiledValue? {
        let value = expression.computation
        switch value.operation {
        case .value(let value): return value
        case .setLiteral:
            let members = value.children.compactMap(closedChoiceMember)
            return members.count == value.children.count ? .set(Set(members)) : nil
        case .tupleLiteral:
            let members = value.children.compactMap(closedChoiceMember)
            return members.count == value.children.count ? .tuple(members) : nil
        default: return nil
        }
    }

    private func choiceMemberHasExactIdentity(_ value: CompiledValue) -> Bool {
        switch value {
        case .integer, .boolean, .constant: true
        case .string(let text): TLAValue.canonicalSwiftString(text) == .string(text)
        case .tuple(let members): members.allSatisfy(choiceMemberHasExactIdentity)
        default: false
        }
    }

    /// Serialize a bijective, independent record comprehension without materializing a UNION of sets.
    private func cartesianRecordFields(_ expression: CompiledExpression) -> [(name: String, domain: CompiledExpression)]? {
        var body = expression.computation
        var domains: [BinderID: CompiledExpression] = [:]
        while true {
            let flattened: Bool
            if case .unionAll = body.operation {
                body = body.children[0].computation
                flattened = true
            } else {
                flattened = false
            }
            guard case .setMap(let binder) = body.operation,
                  domains[binder] == nil else { return nil }
            domains[binder] = body.children[1]
            body = body.children[0].computation
            if !flattened { break }
        }
        guard case .recordLiteral(let names) = body.operation,
              names.count == domains.count, names.count == body.children.count,
              Set(names).count == names.count else { return nil }
        var fields: [(name: String, domain: CompiledExpression)] = []
        var used: Set<BinderID> = []
        for (name, value) in zip(names, body.children) {
            guard case .boundValue(let binder) = value.computation.operation,
                  let domain = domains[binder], used.insert(binder).inserted else { return nil }
            fields.append((name, domain))
        }
        var pending = Array(domains.values)
        while let domain = pending.popLast() {
            switch domain.operation {
            case .boundValue(let binder):
                if used.contains(binder) { return nil }
            case .value, .stateVariable, .integerRange, .convert:
                break
            // Moving a fallible domain outside an empty outer iteration can introduce an error.
            // Other operations can also hide lexical captures outside their expression children.
            default: return nil
            }
            pending.append(contentsOf: domain.children)
        }
        return fields
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

    func actionReference(_ id: ActionID, named operatorName: String? = nil) throws -> String {
        guard layout.actions.indices.contains(id.ordinal),
              actions.indices.contains(id.ordinal) else { throw missing("action", id.ordinal) }
        let name = operatorName ?? layout.actions[id.ordinal].renderedName
        let action = actions[id.ordinal]
        guard !action.bindings.isEmpty else { return name }
        let parameters = try action.bindings.map { try binderName($0.binder) }
        let domains = try zip(parameters, action.bindings).map { parameter, binding in
            let domain = try binding.literalMembers.map { try CompiledValue.set(Set($0)).rendered(using: layout).description }
                ?? state(binding.domain)
            return "\(parameter) \\in \(domain)"
        }
        if action.bindings.contains(where: { $0.literalMembers == nil }) {
            return domains.reversed().reduce("\(name)(\(parameters.joined(separator: ", ")))") {
                "(\\E \($1): \($0))"
            }
        }
        return "(\\E \(domains.joined(separator: ", ")): \(name)(\(parameters.joined(separator: ", "))))"
    }

    func binderName(_ id: BinderID) throws -> String {
        guard let name = bindings.binderName(id) else { throw missing("binder", id.ordinal) }
        return name
    }

    func procedureName(_ id: ProcedureID) throws -> String {
        guard let procedure = layout.procedure(id) else { throw missing("procedure", id.ordinal) }
        return procedure.name
    }

    func controlLocationFormalName(_ id: ControlLocationID) throws -> String {
        guard let location = layout.controlLocation(id) else { throw missing("control location", id.ordinal) }
        return location.formalName
    }

    private func operatorName(_ id: OperatorID) throws -> String {
        guard let name = bindings.operatorName(id) else { throw missing("operator", id.ordinal) }
        return name
    }

    private func controlLocationName(_ id: ControlLocationID) throws -> String {
        guard let location = layout.controlLocation(id) else { throw missing("control location", id.ordinal) }
        return "\"\(location.formalName)\""
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
        case .and: ("(IF ", " THEN ", " ELSE FALSE)")
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
        case .randomSubset: ("RandomSubset(", ", ", ")")
        case .randomElement: ("RandomElement(", "", ")")
        case .setSum: ("SumFunctionOnSet(", ", ", ")")
        case .integerRange: ("", "..", "")
        case .negate: ("(-", "", ")")
        case .nextState: ("(", "", ")'")
        case .not: ("(~", "", ")")
        case .printT: ("PrintT(", "", ")")
        case .cardinality: ("Cardinality(", "", ")")
        case .powerSet: ("SUBSET (", "", ")")
        case .sequenceSet: ("Seq(", "", ")")
        case .unionAll: ("UNION ", "", "")
        case .tupleLength: ("Len(", "", ")")
        case .tupleHead: ("Head(", "", ")")
        case .tupleTail: ("Tail(", "", ")")
        case .domain: ("DOMAIN ", "", "")
        case .sequenceFromSet: ("SeqFromSet(", "", ")")
        case .setLiteral: ("{", ", ", "}")
        case .tupleLiteral: ("<<", ", ", ">>")
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
        case .stutteringStep:
            parts = [.text("(IF ("), .operand(0), .text(" = ("), .operand(0),
                .text(")') THEN TRUE ELSE "), .operand(1), .text(")")]
        case .ifThenElse:
            parts = [.text("(IF "), .operand(0), .text(" THEN "), .operand(1),
                .text(" ELSE "), .operand(2), .text(")")]
        case .tupleRemoving:
            parts = [.text("(SubSeq("), .operand(0), .text(", 1, ("), .operand(1),
                .text(" - 1)) \\o SubSeq("), .operand(0), .text(", ("), .operand(1),
                .text(" + 1), Len("), .operand(0), .text(")))")]
        case .tuplePrefix:
            parts = [.text("SubSeq("), .operand(0), .text(", 1, "), .operand(1), .text(")")]
        case .sequenceSelect(let binder):
            parts = [.text("SelectSeq("), .operand(0), .text(", LAMBDA \(try binderName(binder)): "),
                .operand(1), .text(")")]
        case .sequenceFromFunction:
            parts = [.operand(0)]
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
            parts = [.text("(\\A \(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1), .text(")")]
        case .exists(let binder):
            parts = [.text("(\\E \(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1), .text(")")]
        case .choose(let binder):
            parts = [.text("(CHOOSE \(try binderName(binder)) \\in "), .operand(0), .text(" : "), .operand(1), .text(")")]
        case .foldFunction(let binders):
            parts = [.text("FoldFunction(LAMBDA \(try binders.map(binderName).joined(separator: ", ")) : "),
                .operand(0), .text(", "), .operand(1), .text(", "), .operand(2), .text(")")]
        case .letValue(let binder):
            parts = [.text("(LET \(try binderName(binder)) == "), .operand(0), .text(" IN "), .operand(1), .text(")")]
        default:
            throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                path: "compiledRenderer.operation", expected: "an operand syntax template",
                actual: String(describing: self), nextSafeAction: "Check operation lowering before rendering.")
        }
        return parts
    }
}
