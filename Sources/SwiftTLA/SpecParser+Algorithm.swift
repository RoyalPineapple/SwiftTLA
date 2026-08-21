import SwiftSyntax

private struct AlgorithmMacroDefinition: Sendable {
    let parameters: [String]
    let statements: [AlgorithmStatementModel]
}

extension ParserSession {
    /// Parses the bounded PlusCal-shaped authoring layer into an `AlgorithmModel`.
    func parseAlgorithm(
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
        var macros: [String: AlgorithmMacroDefinition] = [:]
        let outerConstants = constants
        let outerTupleVariables = algorithmTupleVariables
        algorithmTupleVariables = []
        defer {
            algorithmTupleVariables = outerTupleVariables
            constants = outerConstants
        }
        for statement in closure.statements {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let macro = parseAlgorithmMacroDeclaration(variable) {
                let name = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text ?? ""
                guard macros[name] == nil else {
                    result.diagnostics.append(.init(message: "Algorithm macro '\(name)' is declared more than once.", source: statement))
                    return
                }
                macros[name] = macro
                continue
            }
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(variable, expectedKind: "SharedVar") {
                components.append(component)
                if case .shared(let state) = component,
                   state.isTuple {
                    algorithmTupleVariables.insert(state.root)
                }
                continue
            }
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let value = parseAlgorithmLexicalValue(variable) {
                let constant = ConstantDecl(value.name, value.value)
                constants.append(constant)
                continue
            }
            guard case .expr(let expression) = statement.item else {
                let detail = algorithmParseFailure.map { " \($0)" } ?? ""
                result.diagnostics.append(.init(
                    message: "Unsupported Algorithm declaration '\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'. "
                        + "Supported declarations are SharedVar, Macro, Procedure, Each, Do, While, and properties.\(detail)",
                    source: statement
                ))
                return
            }
            if let definition = parseAlgorithmFormalDefinition(expression) {
                components.append(.formalOperator(definition))
                continue
            }
            guard let component = parseAlgorithmComponent(expression, macros: macros) else {
                let detail = algorithmParseFailure.map { " \($0)" } ?? ""
                result.diagnostics.append(.init(
                    message: "Unsupported Algorithm declaration '\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'. "
                        + "Supported declarations are SharedVar, Macro, Procedure, Each, Do, While, and properties.\(detail)",
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

        // Keep the source-level IR before the one and only parser lowering.
        // Retain the authored Algorithm in the source model.
        result.algorithmFidelityTokens.append(AlgorithmFidelityToken(model: model))

        result.sourceAlgorithms.append(Algorithm(model: model))
    }

    private func parseAlgorithmFormalDefinition(
        _ expression: ExprSyntax
    ) -> FormalOperatorDefinition? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "FormalDefinition"
        else { return nil }
        guard call.trailingClosure != nil else { return nil }
        guard let definition = decodeFormalDefinition(call) else {
            algorithmParseFailure = algorithmParseFailure
                ?? "FormalDefinition could not decode its typed parameters or formal body."
            return nil
        }
        return definition
    }

    private func parseAlgorithmComponent(
        _ expression: ExprSyntax,
        macros: [String: AlgorithmMacroDefinition]
    ) -> AlgorithmComponentModel? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }

        switch name {
        case "Procedure":
            return parseProcedure(call, macros: macros)
        case "Each":
            let component = parseEach(call, macros: macros)
            if component == nil, algorithmParseFailure == nil {
                algorithmParseFailure = "Each requires a finite enum domain and a decodable process body."
            }
            return component
        case "Do", "While":
            return parseEachComponent(expression, processParameter: "__pcal_sequential", macros: macros)
        case "Invariant":
            guard let invariant = parseAlgorithmInvariant(call) else { return nil }
            return .invariant(invariant)
        case "LeadsTo", "Eventually", "Always", "AlwaysEventually", "EventuallyAlways":
            guard let temporal = parseAlgorithmTemporal(call, named: name) else { return nil }
            return .temporal(temporal)
        case "WeakFairness", "StrongFairness", "WeakFairnessNext", "StrongFairnessNext":
            guard let fairness = decodeFairness(call) else { return nil }
            return .fairness(fairness)
        case "StateConstraint":
            guard let argument = call.arguments.first,
                  let condition = decodeStateExpr(argument.expression)
            else { return nil }
            return .stateConstraint(condition)
        default:
            return nil
        }
    }

    private func parseProcedure(
        _ call: FunctionCallExprSyntax,
        macros: [String: AlgorithmMacroDefinition]
    ) -> AlgorithmComponentModel? {
        guard let name = extractStringArg(call, index: 0), let closure = call.trailingClosure else {
            algorithmParseFailure = "Procedure requires a string literal name and a builder body."
            return nil
        }
        let bindings = closureParameterNames(in: closure)
        let parameterArguments = call.arguments.dropFirst()
        guard parameterArguments.count <= 4 else {
            algorithmParseFailure = "Procedure '\(name)' has arity \(parameterArguments.count); SwiftTLA supports 0 through 4 typed parameters. Use a Record parameter or add a typed overload."
            return nil
        }
        let parameterTypes = parameterArguments.compactMap { procedureParameterType($0.expression) }
        guard parameterTypes.count == parameterArguments.count else {
            algorithmParseFailure = "Procedure '\(name)' parameter types could not be decoded. Expected metatype arguments such as Int.self."
            return nil
        }
        guard bindings.count == parameterTypes.count else {
            algorithmParseFailure = "Procedure '\(name)' expected \(parameterTypes.count) typed parameter binding(s), found \(bindings.count)."
            return nil
        }
        let parameters = parameterTypes.enumerated().map { index, type in
            AlgorithmProcedureParameterModel(root: "parameter\(index)", initial: type.defaultValue, swiftTypeName: type.renderedName)
        }
        var locals: [AlgorithmStateModel] = []
        var steps: [AlgorithmStepModel] = []
        for item in closure.statements {
            if case .decl(let declaration) = item.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(variable, expectedKind: "LocalVar"),
               case .local(let local) = component {
                locals.append(local)
                continue
            }
            guard case .expr(let expression) = item.item,
                  let component = parseEachComponent(expression, processParameter: "__pcal_sequential", macros: macros),
                  case .step(let step) = component
            else {
                algorithmParseFailure = "Procedure '\(name)' accepts LocalVar declarations and Do or While blocks."
                return nil
            }
            let normalized = bindings.enumerated().reduce(step) { step, binding in
                .init(
                    label: step.label,
                    statements: step.statements.map {
                        $0.substitutingVariable(
                            binding.element,
                            with: .variable("parameter\(binding.offset)"),
                            assignmentTargets: .replaceWhenVariable
                        )
                    },
                    loopCondition: step.loopCondition.map { renameVar(binding.element, to: "parameter\(binding.offset)", in: $0) }
                )
            }
            steps.append(normalized)
        }
        return .procedure(.init(name: name, parameters: parameters, locals: locals, steps: steps))
    }

    private struct ProcedureParameterType {
        let renderedName: String
        let defaultValue: StateExpr
    }

    private func procedureParameterType(_ expression: ExprSyntax) -> ProcedureParameterType? {
        guard let metatype = expression.as(MemberAccessExprSyntax.self),
              metatype.declName.baseName.text == "self",
              let type = metatype.base,
              let terminalName = terminalTypeName(in: type),
              let renderedName = sourceTypeSpelling(type)
        else { return nil }
        let defaultValue: StateExpr
        switch terminalName {
        case "Int": defaultValue = .value(.int(0))
        case "Bool": defaultValue = .value(.bool(false))
        case "String": defaultValue = .value(.string(""))
        default: defaultValue = .value(.constant("default_\(terminalName)"))
        }
        return .init(
            renderedName: renderedName,
            defaultValue: defaultValue
        )
    }

    private func parseAlgorithmTemporal(
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
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1]).map(TemporalExpr.eventually) : nil
        case "Always":
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1]).map(TemporalExpr.always) : nil
        case "AlwaysEventually":
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1]).map(TemporalExpr.alwaysEventually) : nil
        case "EventuallyAlways":
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1]).map(TemporalExpr.eventuallyAlways) : nil
        default:
            expression = nil
        }
        return expression.map { .init(name: name, expr: $0) }
    }

    private func parseAlgorithmInvariant(
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
            guard let decoded = formalAlgorithmProperty(expression) else {
                algorithmParseFailure = "Invariant '\(name)' statement \(index + 1) could not be decoded: "
                    + "'\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                return nil
            }
            expressions.append(decoded)
        }
        guard !expressions.isEmpty else { return nil }
        let body = expressions.dropFirst().reduce(expressions[0], StateExpr.and)
        return .init(name: name, body: body)
    }

    private func formalAlgorithmProperty(_ expression: ExprSyntax) -> StateExpr? {
        decodeAlgorithmDomainQuantifier(expression)
            ?? decodeTypedFacadeValue(expression, substitutions: [:])
            ?? decodeStateExpr(expression)
    }

    private func parseEach(
        _ call: FunctionCallExprSyntax,
        macros: [String: AlgorithmMacroDefinition]
    ) -> AlgorithmComponentModel? {
        guard let domainSyntax = call.arguments.first?.expression,
              let domain = finiteAlgorithmDomain(domainSyntax),
              let closure = call.trailingClosure
        else {
            let knownDomains = enumDefinitions.map(\.typeName).sorted()
            let known = knownDomains.isEmpty ? "none" : knownDomains.joined(separator: ", ")
            algorithmParseFailure = "Each could not resolve its finite domain. Known finite domains: \(known)."
            return nil
        }
        let parameter = closureParameterNames(in: closure).first ?? "__pcal_self"
        var components: [AlgorithmComponentModel] = []
        for (index, statement) in closure.statements.enumerated() {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(variable, expectedKind: "LocalVar") {
                guard case .local(let state) = component else { return nil }
                components.append(.local(.init(
                    root: state.root,
                    initial: parameter == "__pcal_self"
                        ? state.initial
                        : renameVar(parameter, to: "__pcal_self", in: state.initial),
                    initialSet: state.initialSet,
                    swiftTypeName: state.swiftTypeName
                )))
                continue
            }
            guard case .expr(let expression) = statement.item else { return nil }
            guard let component = parseEachComponent(expression, processParameter: parameter, macros: macros) else {
                if algorithmParseFailure == nil {
                    algorithmParseFailure = "Process component \(index + 1) could not be decoded: "
                        + "'\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
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
    private func parseAlgorithmVariableDeclaration(
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
           let initial = decodeTypedFacadeValue(initialSyntax, substitutions: [:])
                ?? decodeStateExpr(initialSyntax) {
            state = AlgorithmStateModel(
                root: declaredName,
                initial: initial,
                swiftTypeName: algorithmInitialTypeName(initialSyntax),
                isTuple: isTupleInitialValue(initialSyntax)
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
                  let setSyntax = initializer.arguments.first(where: { $0.label?.text == "in" })?.expression {
            guard let initialSet = decodeStateExpr(setSyntax),
                  case .set(let elements) = try? evaluateClosed(initialSet),
                  !elements.isEmpty,
                  let initial = elements.min(),
                  let typeName = setExpressionElementTypeName(setSyntax)
            else {
                algorithmParseFailure = algorithmParseFailure
                    ?? ("SharedVar(_:in:) requires a non-empty static formal domain; "
                        + "could not decode '\(setSyntax.description.trimmingCharacters(in: .whitespacesAndNewlines))'.")
                return nil
            }
            state = AlgorithmStateModel(
                root: declaredName,
                initial: .value(initial),
                initialSet: initialSet,
                swiftTypeName: typeName
            )
        } else {
            algorithmParseFailure = "\(expectedKind) declaration must use an explicit initial value or finite domain."
            return nil
        }
        return expectedKind == "SharedVar" ? .shared(state) : .local(state)
    }

    private func parseAlgorithmMacroDeclaration(
        _ declaration: VariableDeclSyntax
    ) -> AlgorithmMacroDefinition? {
        guard let initializer = declaration.bindings.first?.initializer?.value.as(FunctionCallExprSyntax.self),
              let closure = initializer.trailingClosure
        else { return nil }
        let parameters = closureParameterNames(in: closure)
        guard Set(parameters).count == parameters.count else {
            algorithmParseFailure = "Statement macro parameters must have distinct names."
            return nil
        }
        guard declaration.bindings.count == 1,
              isAlgorithmMacroInitializer(initializer),
              let statements = parseAlgorithmStatements(
                closure.statements,
                processParameter: "__pcal_macro_no_process",
                macros: [:]
              )
        else { return nil }
        return .init(parameters: parameters, statements: statements)
    }

    /// An immutable `let` in an Algorithm is a compile-time formal alias,
    /// not a state variable or host-language computation. Accept only closed
    /// expressions that the DSL evaluator can reduce now. The same value is
    /// then visible to subsequent syntax decoding through the parser's formal
    /// constant table.
    private func parseAlgorithmLexicalValue(
        _ declaration: VariableDeclSyntax
    ) -> (name: String, value: TLAValue)? {
        guard declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let initializer = binding.initializer?.value
        else { return nil }

        guard let expression = decodeStateExpr(initializer) else {
            algorithmParseFailure = algorithmParseFailure
                ?? "Algorithm let '\(name)' must be a closed formal value; its expression could not be decoded."
            return nil
        }
        guard let value = try? evaluateClosed(expression) else {
            algorithmParseFailure = "Algorithm let '\(name)' must be a closed formal value; it depends on runtime state or has no matching value."
            return nil
        }
        return (name, value)
    }

    private func isAlgorithmMacroInitializer(_ initializer: FunctionCallExprSyntax) -> Bool {
        if initializer.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Macro" {
            return true
        }
        return initializer.calledExpression
            .as(GenericSpecializationExprSyntax.self)?
            .expression
            .as(DeclReferenceExprSyntax.self)?
            .baseName.text == "Macro"
    }

    private func algorithmInitialTypeName(_ expression: ExprSyntax) -> String? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "literal",
           let base = member.base {
            return sourceTypeSpelling(base)
        }
        return initialValueTypeName(from: expression)
    }

    private func isTupleInitialValue(_ expression: ExprSyntax) -> Bool {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "literal",
           typedFacadeType(member.base)?.name == "TupleExpr" {
            return true
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.arguments.isEmpty,
           typedFacadeType(call.calledExpression)?.name == "TupleExpr" {
            return true
        }
        return false
    }

    private func parseEachComponent(
        _ expression: ExprSyntax,
        processParameter: String,
        macros: [String: AlgorithmMacroDefinition]
    ) -> AlgorithmComponentModel? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }

        switch name {
        case "Do", "While":
            guard let label = algorithmLabel(call.arguments.first?.expression),
                  let closure = call.trailingClosure,
                  let statements = parseAlgorithmStatements(
                    closure.statements,
                    processParameter: processParameter,
                    macros: macros
                  )
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
        case "Invariant":
            guard let invariant = parseAlgorithmInvariant(call) else { return nil }
            return .invariant(.init(
                name: invariant.name,
                body: replacingProcessParameter(in: invariant.body, named: processParameter)
            ))
        default:
            return nil
        }
    }

    private func parseAlgorithmStatements(
        _ statements: CodeBlockItemListSyntax,
        processParameter: String,
        macros: [String: AlgorithmMacroDefinition]
    ) -> [AlgorithmStatementModel]? {
        var result: [AlgorithmStatementModel] = []
        for (index, statement) in statements.enumerated() {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self) {
                guard let binding = parseFormalLet(variable) else {
                    if algorithmParseFailure == nil {
                        algorithmParseFailure = "Statement \(index + 1) could not be decoded: "
                            + "'\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                    }
                    return nil
                }
                let remaining = CodeBlockItemListSyntax(Array(statements.dropFirst(index + 1)))
                guard let body = parseAlgorithmStatements(
                    remaining,
                    processParameter: processParameter,
                    macros: macros
                ) else { return nil }
                let value = replacingProcessParameter(in: binding.value, named: processParameter)
                return result + body.map {
                    $0.substitutingVariable(
                        binding.name,
                        with: value,
                        assignmentTargets: .replaceWhenVariable
                    )
                }
            }
            guard case .expr(let expression) = statement.item
            else {
                if algorithmParseFailure == nil {
                    algorithmParseFailure = "Statement \(index + 1) could not be decoded: "
                        + "'\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                }
                return nil
            }
            if let expanded = parseMacroInvocation(expression, macros: macros) {
                result += expanded.map {
                    $0.substitutingVariable(
                        "__pcal_macro_no_process",
                        with: .variable(processParameter),
                        assignmentTargets: .replaceWhenVariable
                    ).substitutingVariable(
                        processParameter,
                        with: .variable("__pcal_self"),
                        assignmentTargets: .replaceWhenVariable
                    )
                }
                continue
            }
            guard let parsed = parseAlgorithmStatement(
                expression,
                processParameter: processParameter,
                macros: macros
            ) else {
                if algorithmParseFailure == nil {
                    algorithmParseFailure = "Statement \(index + 1) could not be decoded: "
                        + "'\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                }
                return nil
            }
            result.append(parsed)
        }
        return result
    }

    /// Parses a Swift `let` inside a formal block as a lexical formal alias.
    /// It never evaluates host-language code. The initializer must be an
    /// expression the formal parser can represent.
    private func parseFormalLet(_ declaration: VariableDeclSyntax) -> (name: String, value: StateExpr)? {
        guard declaration.bindingSpecifier.text == "let",
              declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let initializer = binding.initializer?.value,
              let value = decodeTypedFacadeValue(initializer, substitutions: [:])
                ?? decodeStateExpr(initializer)
        else { return nil }
        return (name, value)
    }

    private func parseAlgorithmStatement(
        _ expression: ExprSyntax,
        processParameter: String,
        macros: [String: AlgorithmMacroDefinition]
    ) -> AlgorithmStatementModel? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }

        switch name {
        case "Await", "When":
            guard let expression = call.arguments.first?.expression,
                  let condition = decodeAlgorithmStateExpression(expression)
            else { return nil }
            return .await(replacingProcessParameter(in: condition, named: processParameter))
        case "Assert":
            guard let expression = call.arguments.first?.expression,
                  let condition = decodeAlgorithmStateExpression(expression)
            else { return nil }
            return .assert(replacingProcessParameter(in: condition, named: processParameter))
        case "Assign":
            guard let target = algorithmTarget(call.arguments.first?.expression),
                  let valueSyntax = call.arguments.first(where: { $0.label?.text == "to" })?.expression,
                  let value = decodeAlgorithmStateExpression(valueSyntax)
            else { return nil }
            return .set(target: target, value: replacingProcessParameter(in: value, named: processParameter))
        case "Goto":
            guard let label = algorithmLabel(call.arguments.first?.expression) else { return nil }
            return .goto(.init(name: label))
        case "Call":
            guard let target = extractStringArg(call, index: 0) else {
                algorithmParseFailure = "Call requires a procedure name string literal."
                return nil
            }
            let arguments = call.arguments.dropFirst().compactMap { argument in
                decodeAlgorithmStateExpression(argument.expression).map {
                    replacingProcessParameter(in: $0, named: processParameter)
                }
            }
            guard arguments.count == call.arguments.count - 1 else {
                algorithmParseFailure = "Call '\(target)' has an argument that is not a formal expression."
                return nil
            }
            return .call(target: target, arguments: arguments)
        case "Return":
            guard call.arguments.isEmpty else {
                algorithmParseFailure = "Return takes no arguments."
                return nil
            }
            return .return
        case "Stop":
            return .stop
        case "Skip":
            return .skip
        case "If":
            guard let conditionSyntax = call.arguments.first?.expression,
                  let condition = decodeAlgorithmStateExpression(conditionSyntax),
                  let thenClosure = call.trailingClosure,
                  let then = parseAlgorithmStatements(
                      thenClosure.statements,
                      processParameter: processParameter,
                      macros: macros
                  )
            else { return nil }
            let elseClosure = call.additionalTrailingClosures.first?.closure
                ?? call.arguments.first(where: { $0.label?.text == "else" })?.expression.as(ClosureExprSyntax.self)
            let otherwise = elseClosure.flatMap {
                parseAlgorithmStatements($0.statements, processParameter: processParameter, macros: macros)
            } ?? []
            return .ifElse(replacingProcessParameter(in: condition, named: processParameter), then, otherwise)
        case "Either":
            guard let first = call.trailingClosure.flatMap({
                parseAlgorithmStatements($0.statements, processParameter: processParameter, macros: macros)
            }),
                  let secondClosure = call.additionalTrailingClosures.first?.closure
                    ?? call.arguments.first(where: { $0.label?.text == "or" })?.expression.as(ClosureExprSyntax.self),
                  let second = parseAlgorithmStatements(
                      secondClosure.statements,
                      processParameter: processParameter,
                      macros: macros
                  )
            else { return nil }
            return .either(first, second)
        case "Choose":
            guard let closure = call.trailingClosure,
                  !call.arguments.isEmpty,
                  let body = parseAlgorithmStatements(closure.statements, processParameter: processParameter, macros: macros)
            else { return nil }
            let choices = closureParameterNames(in: closure)
            guard choices.count == call.arguments.count else { return nil }
            let domains = call.arguments.map(\.expression).compactMap { syntax in
                finiteAlgorithmDomain(syntax)?.values
                    ?? parseIntegerClosedRange(syntax).map { $0.map(TLAValue.int) }
            }
            guard domains.count == choices.count else { return nil }
            var nestedBody = body
            for index in choices.indices.reversed() {
                let replacement = "__pcal_choice_\(index)"
                nestedBody = nestedBody.map {
                    $0.substitutingVariable(
                        choices[index],
                        with: .variable(replacement),
                        assignmentTargets: .replaceWhenVariable
                    )
                }
                nestedBody = [.choose(variable: replacement, domain: domains[index], nestedBody)]
            }
            return nestedBody[0]
        case "With":
            guard let closure = call.trailingClosure,
                  let body = parseAlgorithmStatements(closure.statements, processParameter: processParameter, macros: macros)
            else { return nil }
            let sources = call.arguments.compactMap { algorithmWithSource($0.expression) }
            guard sources.count == call.arguments.count else { return nil }
            let bindings = closureParameterNames(in: closure)
            switch (sources.count, bindings.count) {
            case (1, 1):
                let replacement = "__pcal_with"
                return .with(
                    variable: replacement,
                    source: replacingProcessParameter(in: sources[0], named: processParameter),
                    body.map {
                        $0.substitutingVariable(
                            bindings[0],
                            with: .variable(replacement),
                            assignmentTargets: .replaceWhenVariable
                        )
                    }
                )
            case (1, 2):
                // `With(SetExpr<Pair<A, B>>) { first, second in ... }` is
                // PlusCal's `with <<first, second>> \in Pairs`. Keep one
                // formal selection, then bind both tuple positions inside its
                // scope so the emitted TLA+ and runtime builder agree.
                let tupleBinding = generatedBinderName()
                let firstBinding = generatedBinderName()
                let secondBinding = generatedBinderName()
                let replacedBody = body
                    .map {
                        $0.substitutingVariable(
                            bindings[0],
                            with: .variable(firstBinding),
                            assignmentTargets: .replaceWhenVariable
                        )
                    }
                    .map {
                        $0.substitutingVariable(
                            bindings[1],
                            with: .variable(secondBinding),
                            assignmentTargets: .replaceWhenVariable
                        )
                    }
                return .with(
                    variable: tupleBinding,
                    source: replacingProcessParameter(in: sources[0], named: processParameter),
                    [
                        .letBinding(
                            variable: firstBinding,
                            value: .tupleAccess(.variable(tupleBinding), 1),
                            [
                                .letBinding(
                                    variable: secondBinding,
                                    value: .tupleAccess(.variable(tupleBinding), 2),
                                    replacedBody
                                )
                            ]
                        )
                    ]
                )
            default:
                guard sources.count == bindings.count, (1...4).contains(sources.count) else {
                    algorithmParseFailure = "What failed: With binding pattern. Where: With closure. "
                        + "Expected one binding, a two-member Pair pattern, or one formal source per binding (up to four); "
                        + "found \(bindings.count) binding(s) and \(sources.count) source(s). "
                        + "Next safe action: use independent With sources or a Pair."
                    return nil
                }
                var boundBody = body
                var selections: [(variable: String, source: StateExpr)] = []
                for (index, binding) in bindings.enumerated() {
                    let variable = "__pcal_with_\(index)"
                    boundBody = boundBody.map {
                        $0.substitutingVariable(
                            binding,
                            with: .variable(variable),
                            assignmentTargets: .replaceWhenVariable
                        )
                    }
                    selections.append((variable, replacingProcessParameter(in: sources[index], named: processParameter)))
                }
                for selection in selections.reversed() {
                    boundBody = [.with(variable: selection.variable, source: selection.source, boundBody)]
                }
                return boundBody[0]
            }
        case "Let":
            guard let valueSyntax = call.arguments.first?.expression,
                  let value = decodeAlgorithmStateExpression(valueSyntax),
                  let closure = call.trailingClosure,
                  let bound = closureParameterNames(in: closure).first,
                  let body = parseAlgorithmStatements(closure.statements, processParameter: processParameter, macros: macros)
            else { return nil }
            let replacement = generatedBinderName()
            return .letBinding(
                variable: replacement,
                value: replacingProcessParameter(in: value, named: processParameter),
                body.map {
                    $0.substitutingVariable(
                        bound,
                        with: .variable(replacement),
                        assignmentTargets: .replaceWhenVariable
                    )
                }
            )
        default:
            return nil
        }
    }

    private func algorithmWithSource(_ syntax: ExprSyntax) -> StateExpr? {
        finiteAlgorithmDomain(syntax).map { domain in
            StateExpr.setLiteral(domain.values.map(StateExpr.value))
        } ?? decodeAlgorithmStateExpression(syntax)
    }

    private func decodeAlgorithmStateExpression(_ syntax: ExprSyntax) -> StateExpr? {
        decodeTypedFacadeValue(syntax, substitutions: [:]) ?? decodeStateExpr(syntax)
    }

    /// Expands a bounded statement macro into the surrounding atomic block.
    /// Every formal parameter is a direct algorithm variable so macro expansion
    /// remains in the same typed state namespace as its caller.
    private func parseMacroInvocation(
        _ expression: ExprSyntax,
        macros: [String: AlgorithmMacroDefinition]
    ) -> [AlgorithmStatementModel]? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let macro = macros[name]
        else { return nil }

        guard call.arguments.count == macro.parameters.count else {
            algorithmParseFailure = "Statement macro '\(name)' expects \(macro.parameters.count) arguments but received \(call.arguments.count)."
            return nil
        }
        var arguments: [StateExpr] = []
        for (index, argumentSyntax) in call.arguments.enumerated() {
            guard let argument = decodeAlgorithmStateExpression(argumentSyntax.expression) else {
                algorithmParseFailure = "Statement macro '\(name)' argument \(index + 1) is not a formal expression. Use an expression understood by the SwiftTLA DSL."
                return nil
            }
            arguments.append(argument)
        }
        for (parameter, argument) in zip(macro.parameters, arguments) {
            let isVariable: Bool
            if case .variable = argument { isVariable = true } else { isVariable = false }
            guard !macroAssigns(to: parameter, in: macro.statements) || isVariable else {
                algorithmParseFailure = "What failed: statement macro '\(name)' assigns through parameter '\(parameter)'. "
                    + "Where: its invocation argument. Expected a formal variable assignment target; found \(argument). "
                    + "Next safe action: pass a SharedVar or LocalVar, "
                    + "or make the parameter read-only in the macro body."
                return nil
            }
        }
        return zip(macro.parameters, arguments).reduce(macro.statements) { statements, binding in
            statements.map {
                $0.substitutingVariable(
                    binding.0,
                    with: binding.1,
                    assignmentTargets: .reject(.statementMacroAssignmentTarget)
                )
            }
        }
    }

    private func macroAssigns(
        to parameter: String,
        in statements: [AlgorithmStatementModel]
    ) -> Bool {
        for statement in statements {
            switch statement {
            case .rejected:
                continue
            case .set(let target, _):
                if target.root == parameter { return true }
            case .letBinding(let binder, _, let body),
                 .with(let binder, _, let body),
                 .choose(let binder, _, let body):
                if binder == parameter { continue }
                if macroAssigns(to: parameter, in: body) { return true }
            case .ifElse(_, let then, let otherwise):
                if macroAssigns(to: parameter, in: then) || macroAssigns(to: parameter, in: otherwise) { return true }
            case .either(let first, let second):
                if macroAssigns(to: parameter, in: first) || macroAssigns(to: parameter, in: second) { return true }
            case .await, .assert, .call, .goto, .return, .stop, .skip:
                continue
            }
        }
        return false
    }

    private func algorithmTarget(_ expression: ExprSyntax?) -> AlgorithmLValueModel? {
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

    private func algorithmLabel(_ expression: ExprSyntax?) -> String? {
        guard let expression else { return nil }
        if let literal = expression.as(StringLiteralExprSyntax.self) {
            return literal.segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
        }
        if let access = expression.as(MemberAccessExprSyntax.self) {
            if let type = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
               case .string(let rawLabel) = enumDefinition(named: type)?
                    .value(named: access.declName.baseName.text) {
                return rawLabel
            }
            return access.declName.baseName.text
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        return nil
    }

    func finiteAlgorithmDomain(_ expression: ExprSyntax) -> (typeName: String, values: [TLAValue])? {
        guard let access = expression.as(MemberAccessExprSyntax.self),
              access.declName.baseName.text == "all",
              let type = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let values = enumDefinition(named: type)?.formalDomain, !values.isEmpty
        else { return nil }
        return (type, values)
    }

    private func replacingProcessParameter(in expression: StateExpr, named parameter: String) -> StateExpr {
        parameter == "__pcal_self" ? expression : renameVar(parameter, to: "__pcal_self", in: expression)
    }
}
