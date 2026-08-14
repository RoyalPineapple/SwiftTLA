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
                    message: "Unsupported Algorithm declaration. Supported declarations are SharedVar and Each.",
                    source: statement
                ))
                return
            }
            guard let component = parseAlgorithmComponent(expression) else {
                result.diagnostics.append(.init(
                    message: "Unsupported Algorithm declaration. Supported declarations are SharedVar and Each.",
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
        for variable in lowered.variables {
            if let index = result.variables.firstIndex(where: { $0.name == variable.name }) {
                result.variables[index] = (variable.name, variable.initial, variable.initialSet, result.variables[index].swiftTypeName)
            } else {
                result.variables.append((variable.name, variable.initial, variable.initialSet, nil))
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
        result.fairness += lowered.fairness
    }

    private static func parseAlgorithmComponent(_ expression: ExprSyntax) -> AlgorithmComponentModel? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }

        switch name {
        case "Shared":
            guard let reference = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
                  let initialSyntax = call.arguments.first(where: { $0.label?.text == "initial" })?.expression,
                  let initial = literalAlgorithmValue(initialSyntax)
            else { return nil }
            return .shared(.init(root: reference, initial: initial))
        case "Each":
            return parseEach(call)
        default:
            return nil
        }
    }

    private static func parseEach(_ call: FunctionCallExprSyntax) -> AlgorithmComponentModel? {
        guard let domainSyntax = call.arguments.first?.expression,
              let domain = finiteAlgorithmDomain(domainSyntax),
              let closure = call.trailingClosure
        else { return nil }
        let parameter = closureParameterNames(in: closure).first ?? "__pcal_self"
        var components: [AlgorithmComponentModel] = []
        for statement in closure.statements {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(variable, expectedKind: "LocalVar") {
                components.append(component)
                continue
            }
            guard case .expr(let expression) = statement.item else { return nil }
            guard let component = parseEachComponent(expression, processParameter: parameter) else {
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
              initializer.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == expectedKind,
              let initialSyntax = initializer.arguments.first(where: { $0.label?.text == "initial" })?.expression,
              let initial = literalAlgorithmValue(initialSyntax)
        else { return nil }

        if let literalName = extractStringArg(initializer, index: 0), literalName != declaredName {
            return nil
        }

        let state = AlgorithmStateModel(root: declaredName, initial: initial)
        return expectedKind == "SharedVar" ? .shared(state) : .local(state)
    }

    private static func parseEachComponent(
        _ expression: ExprSyntax,
        processParameter: String
    ) -> AlgorithmComponentModel? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }

        switch name {
        case "Local":
            guard let reference = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
                  let initialSyntax = call.arguments.first(where: { $0.label?.text == "initial" })?.expression,
                  let initial = literalAlgorithmValue(initialSyntax)
            else { return nil }
            return .local(.init(root: reference, initial: initial))
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
        for statement in statements {
            guard case .expr(let expression) = statement.item,
                  let parsed = parseAlgorithmStatement(expression, processParameter: processParameter)
            else { return nil }
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
        case "If":
            guard let conditionSyntax = call.arguments.first?.expression,
                  let condition = decodeStateExpr(conditionSyntax),
                  let thenClosure = call.trailingClosure,
                  let then = parseAlgorithmStatements(thenClosure.statements, processParameter: processParameter)
            else { return nil }
            let elseClosure = call.additionalTrailingClosures.first?.closure
            let otherwise = elseClosure.flatMap { parseAlgorithmStatements($0.statements, processParameter: processParameter) } ?? []
            return .ifElse(replacingProcessParameter(in: condition, named: processParameter), then, otherwise)
        case "Either":
            guard let first = call.trailingClosure.flatMap({ parseAlgorithmStatements($0.statements, processParameter: processParameter) }),
                  let secondClosure = call.additionalTrailingClosures.first?.closure,
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

    private static func literalAlgorithmValue(_ expression: ExprSyntax) -> TLAValue? {
        if let decoded = decodeStateExpr(expression), case .value(let value) = decoded {
            return value
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
