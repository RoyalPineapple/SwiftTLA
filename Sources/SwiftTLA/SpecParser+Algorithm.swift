import SwiftSyntax

extension SpecParser {
    /// Parses the bounded PlusCal-shaped authoring layer into the same TLA+ AST
    /// used by the ordinary builder parser. This path deliberately constructs an
    /// `AlgorithmModel` and uses `AlgorithmLowerer`; it does not maintain a
    /// second lowering implementation in the macro.
    static func parseAlgorithm(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let name = extractStringArg(call, index: 0),
              let closure = call.trailingClosure
        else {
            result.diagnostics.append(.init(
                message: "Algorithm requires a string literal name and a builder body.",
                source: call
            ))
            return
        }

        var components: [AlgorithmComponentModel] = []
        for statement in closure.statements {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(variable, expectedKind: "SharedVar") {
                components.append(component)
                continue
            }
            guard case .expr(let expression) = statement.item else {
                result.diagnostics.append(.init(
                    message: "Unsupported Algorithm declaration '\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'. Supported declarations are SharedVar, Each, Do, and While.",
                    source: statement
                ))
                return
            }
            guard let component = parseAlgorithmComponent(expression) else {
                let detail = algorithmParseFailure.map { " \($0)" } ?? ""
                result.diagnostics.append(.init(
                    message: "Unsupported Algorithm declaration '\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'. Supported declarations are SharedVar, Each, Do, and While.\(detail)",
                    source: expression
                ))
                return
            }
            components.append(component)
        }

        let model = AlgorithmModel(name: name, components: components)
        let diagnostics = AlgorithmValidator.validate(model)
        guard diagnostics.isEmpty else {
            result.diagnostics.append(.init(
                message: "Invalid Algorithm '\(name)': \(diagnostics.map(\.description).joined(separator: "; "))",
                source: call
            ))
            return
        }

        let lowered = AlgorithmLowerer.lower(model)
        let stateTypes = Dictionary(uniqueKeysWithValues: algorithmStateDeclarations(in: model).compactMap { state in
            state.swiftTypeName.map { (state.root, $0) }
        })
        let localRoots: Set<String> = Set(model.processes.flatMap { process in
            process.components.compactMap {
                guard case .local(let state) = $0 else { return nil }
                return state.root
            }
        })
        for variable in lowered.variables {
            if let index = result.variables.firstIndex(where: { $0.name == variable.name }) {
                result.variables[index] = (variable.name, variable.initial, variable.initialSet, result.variables[index].swiftTypeName)
            } else {
                let inferredType = stateTypes[variable.name]
                let projectedType: String?
                if localRoots.contains(variable.name) {
                    projectedType = "TLAValue"
                } else {
                    projectedType = inferredType
                }
                result.variables.append((
                    variable.name,
                    variable.initial,
                    variable.initialSet,
                    projectedType
                ))
            }
        }
        let processTypes = Dictionary(uniqueKeysWithValues: model.processes.map { process in
            (process.domain, process.typeName)
        })
        result.actions += lowered.actions.map { action in
            let bindingTypes = action.bindings.reduce(into: [String: String]()) { types, binding in
                if let type = processTypes[binding.values] { types[binding.name] = type }
            }
            return .init(
                name: action.name,
                body: action.body,
                bindings: action.bindings,
                bindingSwiftTypes: bindingTypes
            )
        }
        result.invariants += lowered.invariants.map { ($0.name, $0.body) }
        result.temporal += lowered.temporalProperties.map { ($0.name, $0.expr) }
        result.fairness += lowered.fairness
    }

    private static func algorithmStateDeclarations(in model: AlgorithmModel) -> [AlgorithmStateModel] {
        model.components.flatMap { component in
            switch component {
            case .shared(let state): return [state]
            case .process(let process):
                return process.components.compactMap {
                    guard case .local(let state) = $0 else { return nil }
                    return state
                }
            default: return []
            }
        }
    }

    private static func parseAlgorithmComponent(_ expression: ExprSyntax) -> AlgorithmComponentModel? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }

        switch name {
        case "Each":
            let component = parseEach(call)
            if component == nil, algorithmParseFailure == nil {
                algorithmParseFailure = "Each requires a finite enum domain and a decodable process body."
            }
            return component
        case "Do", "While":
            return parseEachComponent(expression, processParameter: "__pcal_sequential")
        case "Invariant":
            guard let invariant = parseAlgorithmInvariant(call) else { return nil }
            return .invariant(invariant)
        case "LeadsTo", "Eventually", "Always", "AlwaysEventually", "EventuallyAlways":
            guard let temporal = parseAlgorithmTemporal(call, named: name) else { return nil }
            return .temporal(temporal)
        case "WeakFairness", "StrongFairness":
            guard let fairness = decodeFairness(call) else { return nil }
            return .fairness(fairness)
        default:
            return nil
        }
    }

    private static func parseAlgorithmTemporal(
        _ call: FunctionCallExprSyntax,
        named kind: String
    ) -> NamedTemporal? {
        guard let name = extractStringArg(call, index: 0) else { return nil }
        let arguments = Array(call.arguments).map(\.expression)
        let expression: TemporalExpr?
        switch kind {
        case "LeadsTo":
            guard arguments.count == 3,
                  let from = decodeStateExpr(arguments[1]),
                  let to = decodeStateExpr(arguments[2])
            else { return nil }
            expression = .leadsTo(from, to)
        case "Eventually":
            expression = arguments.count == 2 ? decodeStateExpr(arguments[1]).map(TemporalExpr.eventually) : nil
        case "Always":
            expression = arguments.count == 2 ? decodeStateExpr(arguments[1]).map(TemporalExpr.always) : nil
        case "AlwaysEventually":
            expression = arguments.count == 2 ? decodeStateExpr(arguments[1]).map(TemporalExpr.alwaysEventually) : nil
        case "EventuallyAlways":
            expression = arguments.count == 2 ? decodeStateExpr(arguments[1]).map(TemporalExpr.eventuallyAlways) : nil
        default:
            expression = nil
        }
        return expression.map { .init(name: name, expr: $0) }
    }

    private static func parseAlgorithmInvariant(
        _ call: FunctionCallExprSyntax
    ) -> NamedInvariant? {
        guard let name = extractStringArg(call, index: 0),
              let closure = call.trailingClosure
        else { return nil }

        var expressions: [StateExpr] = []
        for (index, statement) in closure.statements.enumerated() {
            guard case .expr(let expression) = statement.item else {
                algorithmParseFailure = "Invariant '\(name)' statement \(index + 1) is not a formal expression."
                return nil
            }
            guard let decoded = decodeStateExpr(expression) else {
                algorithmParseFailure = "Invariant '\(name)' statement \(index + 1) could not be decoded: '\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                return nil
            }
            expressions.append(decoded)
        }
        guard !expressions.isEmpty else { return nil }
        let body = expressions.dropFirst().reduce(expressions[0], StateExpr.and)
        return .init(name: name, body: body)
    }

    private static func parseEach(_ call: FunctionCallExprSyntax) -> AlgorithmComponentModel? {
        guard let domainSyntax = call.arguments.first?.expression,
              let domain = finiteAlgorithmDomain(domainSyntax),
              let closure = call.trailingClosure
        else {
            algorithmParseFailure = "Each could not resolve its finite domain."
            return nil
        }
        let parameter = closureParameterNames(in: closure).first ?? "__pcal_self"
        var components: [AlgorithmComponentModel] = []
        for (index, statement) in closure.statements.enumerated() {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(variable, expectedKind: "LocalVar") {
                components.append(component)
                continue
            }
            guard case .expr(let expression) = statement.item else { return nil }
            guard let component = parseEachComponent(expression, processParameter: parameter) else {
                if algorithmParseFailure == nil {
                    algorithmParseFailure = "Process component \(index + 1) could not be decoded: '\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                }
                return nil
            }
            components.append(component)
        }
        let fairness: AlgorithmFairness
        if let expression = call.arguments.first(where: { $0.label?.text == "fairness" })?.expression,
           let access = expression.as(MemberAccessExprSyntax.self) {
            switch access.declName.baseName.text {
            case "none": fairness = .none
            case "weak": fairness = .weak
            case "strong": fairness = .strong
            default: return nil
            }
        } else {
            fairness = .none
        }
        return .process(.init(typeName: domain.typeName, domain: domain.values, fairness: fairness, components: components))
    }

    /// Parses the declaration spelling used by the public PlusCal-shaped DSL.
    /// The runtime builder receives the same declaration through `#spec`'s
    /// registration rewrite; this parser deliberately does its own decoding.
    private static func parseAlgorithmVariableDeclaration(
        _ declaration: VariableDeclSyntax,
        expectedKind: String
    ) -> AlgorithmComponentModel? {
        guard declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let declaredName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
              initializer.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == expectedKind
        else { return nil }

        if let literalName = extractStringArg(initializer, index: 0), literalName != declaredName {
            return nil
        }

        let state: AlgorithmStateModel
        if let initialSyntax = initializer.arguments.first(where: { $0.label?.text == "initial" })?.expression,
           let initial = decodeStateExpr(initialSyntax) {
            state = AlgorithmStateModel(
                root: declaredName,
                initial: initial,
                swiftTypeName: algorithmInitialTypeName(initialSyntax)
            )
        } else if expectedKind == "SharedVar",
                  let rangeSyntax = initializer.arguments.first(where: { $0.label?.text == "in" })?.expression,
                  let range = parseIntegerClosedRange(rangeSyntax) {
            state = AlgorithmStateModel(
                root: declaredName,
                initial: .value(.int(range.lowerBound)),
                initialSet: .setLiteral(range.map { .value(.int($0)) }),
                swiftTypeName: "Int"
            )
        } else if expectedKind == "SharedVar",
                  let setSyntax = initializer.arguments.first(where: { $0.label?.text == "in" })?.expression,
                  let initialSet = decodeStateExpr(setSyntax),
                  case .setLiteral(let elements) = initialSet,
                  let initial = elements.first,
                  let typeName = setExpressionElementTypeName(setSyntax) {
            state = AlgorithmStateModel(
                root: declaredName,
                initial: initial,
                initialSet: initialSet,
                swiftTypeName: typeName
            )
        } else {
            return nil
        }
        return expectedKind == "SharedVar" ? .shared(state) : .local(state)
    }

    private static func algorithmInitialTypeName(_ expression: ExprSyntax) -> String? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "literal",
           let base = member.base {
            return base.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return initialValueTypeName(from: expression)
    }

    private static func parseEachComponent(
        _ expression: ExprSyntax,
        processParameter: String
    ) -> AlgorithmComponentModel? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }

        switch name {
        case "Do", "While":
            guard let label = algorithmLabel(call.arguments.first?.expression),
                  let closure = call.trailingClosure,
                  let statements = parseAlgorithmStatements(closure.statements, processParameter: processParameter)
            else { return nil }
            let loopCondition: StateExpr?
            if name == "While" {
                guard let conditionSyntax = call.arguments.dropFirst().first?.expression,
                      let condition = decodeStateExpr(conditionSyntax)
                else { return nil }
                loopCondition = replacingProcessParameter(in: condition, named: processParameter)
            } else {
                loopCondition = nil
            }
            return .step(.init(label: .init(name: label), statements: statements, loopCondition: loopCondition))
        default:
            return nil
        }
    }

    private static func parseAlgorithmStatements(
        _ statements: CodeBlockItemListSyntax,
        processParameter: String
    ) -> [AlgorithmStatementModel]? {
        var result: [AlgorithmStatementModel] = []
        for (index, statement) in statements.enumerated() {
            guard case .expr(let expression) = statement.item,
                  let parsed = parseAlgorithmStatement(expression, processParameter: processParameter)
            else {
                if algorithmParseFailure == nil {
                    algorithmParseFailure = "Statement \(index + 1) could not be decoded: '\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                }
                return nil
            }
            result.append(parsed)
        }
        return result
    }

    private static func parseAlgorithmStatement(
        _ expression: ExprSyntax,
        processParameter: String
    ) -> AlgorithmStatementModel? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }

        switch name {
        case "Await", "When":
            guard let expression = call.arguments.first?.expression,
                  let condition = decodeStateExpr(expression)
            else { return nil }
            return .await(replacingProcessParameter(in: condition, named: processParameter))
        case "Assert":
            guard let expression = call.arguments.first?.expression,
                  let condition = decodeStateExpr(expression)
            else { return nil }
            return .assert(replacingProcessParameter(in: condition, named: processParameter))
        case "Assign":
            guard let target = algorithmTarget(call.arguments.first?.expression),
                  let valueSyntax = call.arguments.first(where: { $0.label?.text == "to" })?.expression,
                  let value = decodeStateExpr(valueSyntax)
            else { return nil }
            return .set(target: target, value: replacingProcessParameter(in: value, named: processParameter))
        case "Goto":
            guard let label = algorithmLabel(call.arguments.first?.expression) else { return nil }
            return .goto(.init(name: label))
        case "Stop":
            return .stop
        case "Skip":
            return .skip
        case "If":
            guard let conditionSyntax = call.arguments.first?.expression,
                  let condition = decodeStateExpr(conditionSyntax),
                  let thenClosure = call.trailingClosure,
                  let then = parseAlgorithmStatements(thenClosure.statements, processParameter: processParameter)
            else { return nil }
            let elseClosure = call.additionalTrailingClosures.first?.closure
                ?? call.arguments.first(where: { $0.label?.text == "else" })?.expression.as(ClosureExprSyntax.self)
            let otherwise = elseClosure.flatMap { parseAlgorithmStatements($0.statements, processParameter: processParameter) } ?? []
            return .ifElse(replacingProcessParameter(in: condition, named: processParameter), then, otherwise)
        case "Either":
            guard let first = call.trailingClosure.flatMap({ parseAlgorithmStatements($0.statements, processParameter: processParameter) }),
                  let secondClosure = call.additionalTrailingClosures.first?.closure
                    ?? call.arguments.first(where: { $0.label?.text == "or" })?.expression.as(ClosureExprSyntax.self),
                  let second = parseAlgorithmStatements(secondClosure.statements, processParameter: processParameter)
            else { return nil }
            return .either(first, second)
        case "Choose":
            guard let domainSyntax = call.arguments.first?.expression,
                  let domain = finiteAlgorithmDomain(domainSyntax),
                  let closure = call.trailingClosure,
                  let choice = closureParameterNames(in: closure).first,
                  let body = parseAlgorithmStatements(closure.statements, processParameter: processParameter)
            else { return nil }
            // Rebind the lexical choice to the stable IR binder after parsing.
            let replacement = "__pcal_choice"
            return .choose(
                variable: replacement,
                domain: domain.values,
                body.map { replaceAlgorithmVariable($0, from: choice, to: replacement) }
            )
        case "With":
            guard let sourceSyntax = call.arguments.first?.expression,
                  let source = (finiteAlgorithmDomain(sourceSyntax).map { domain in
                      StateExpr.setLiteral(domain.values.map(StateExpr.value))
                  } ?? decodeStateExpr(sourceSyntax)),
                  let closure = call.trailingClosure,
                  let bound = closureParameterNames(in: closure).first,
                  let body = parseAlgorithmStatements(closure.statements, processParameter: processParameter)
            else { return nil }
            let replacement = "__pcal_with"
            return .with(
                variable: replacement,
                source: replacingProcessParameter(in: source, named: processParameter),
                body.map { replaceAlgorithmVariable($0, from: bound, to: replacement) }
            )
        case "Let":
            guard let valueSyntax = call.arguments.first?.expression,
                  let value = decodeStateExpr(valueSyntax),
                  let closure = call.trailingClosure,
                  let bound = closureParameterNames(in: closure).first,
                  let body = parseAlgorithmStatements(closure.statements, processParameter: processParameter)
            else { return nil }
            let replacement = FreshVarName.fresh()
            return .letBinding(
                variable: replacement,
                value: replacingProcessParameter(in: value, named: processParameter),
                body.map { replaceAlgorithmVariable($0, from: bound, to: replacement) }
            )
        default:
            return nil
        }
    }

    private static func algorithmTarget(_ expression: ExprSyntax?) -> AlgorithmLValueModel? {
        guard let expression else { return nil }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return .root(reference.baseName.text)
        }
        if let access = expression.as(MemberAccessExprSyntax.self),
           access.declName.baseName.text == "algorithmLValue",
           let base = access.base?.as(DeclReferenceExprSyntax.self) {
            return .root(base.baseName.text)
        }
        return nil
    }

    private static func algorithmLabel(_ expression: ExprSyntax?) -> String? {
        guard let expression else { return nil }
        if let literal = expression.as(StringLiteralExprSyntax.self) {
            return literal.segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
        }
        if let access = expression.as(MemberAccessExprSyntax.self) {
            return access.declName.baseName.text
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        return nil
    }

    private static func finiteAlgorithmDomain(_ expression: ExprSyntax) -> (typeName: String, values: [TLAValue])? {
        guard let access = expression.as(MemberAccessExprSyntax.self),
              access.declName.baseName.text == "all",
              let type = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let values = _enumDomains[type], !values.isEmpty
        else { return nil }
        return (type, values)
    }

    private static func replacingProcessParameter(in expression: StateExpr, named parameter: String) -> StateExpr {
        parameter == "__pcal_self" ? expression : renameVar(parameter, to: "__pcal_self", in: expression)
    }

    private static func replaceAlgorithmVariable(
        _ statement: AlgorithmStatementModel,
        from: String,
        to: String
    ) -> AlgorithmStatementModel {
        switch statement {
        case .await(let expression): return .await(renameVar(from, to: to, in: expression))
        case .assert(let expression): return .assert(renameVar(from, to: to, in: expression))
        case .set(let target, let value):
            let rewrittenTarget: AlgorithmLValueModel
            switch target {
            case .root: rewrittenTarget = target
            case .function(let root, let key): rewrittenTarget = .function(root: root, key: renameVar(from, to: to, in: key))
            }
            return .set(target: rewrittenTarget, value: renameVar(from, to: to, in: value))
        case .letBinding(let variable, let value, let body):
            return .letBinding(
                variable: variable,
                value: renameVar(from, to: to, in: value),
                variable == from ? body : body.map { replaceAlgorithmVariable($0, from: from, to: to) }
            )
        case .with(let variable, let source, let body):
            return .with(
                variable: variable,
                source: renameVar(from, to: to, in: source),
                body.map { replaceAlgorithmVariable($0, from: from, to: to) }
            )
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(renameVar(from, to: to, in: condition), then.map { replaceAlgorithmVariable($0, from: from, to: to) }, otherwise.map { replaceAlgorithmVariable($0, from: from, to: to) })
        case .either(let first, let second):
            return .either(first.map { replaceAlgorithmVariable($0, from: from, to: to) }, second.map { replaceAlgorithmVariable($0, from: from, to: to) })
        case .choose(let variable, let domain, let body):
            return .choose(variable: variable, domain: domain, body.map { replaceAlgorithmVariable($0, from: from, to: to) })
        case .goto, .stop, .skip: return statement
        }
    }
}
