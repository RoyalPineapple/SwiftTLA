import SwiftSyntax

private struct AlgorithmMacroDefinition: Sendable {
    let parameters: [String]
    let body: CodeBlockItemListSyntax
    let assignmentParameters: Set<String>
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
        let outerStateNames = algorithmStateNames
        algorithmTupleVariables = []
        algorithmStateNames = []
        defer {
            algorithmTupleVariables = outerTupleVariables
            algorithmStateNames = outerStateNames
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
                if case .shared(let state) = component {
                    algorithmStateNames.insert(state.root)
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
            return parseProcedure(call, macros: macros, scope: .empty)
        case "Each":
            let component = parseEach(call, macros: macros, scope: .empty)
            if component == nil, algorithmParseFailure == nil {
                algorithmParseFailure = "Each requires a finite enum domain and a decodable process body."
            }
            return component
        case "Do", "While":
            return parseEachComponent(
                expression,
                processParameter: "__pcal_sequential",
                macros: macros,
                scope: .empty
            )
        case "Invariant":
            guard let invariant = parseAlgorithmInvariant(call, scope: .empty) else { return nil }
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
        macros: [String: AlgorithmMacroDefinition],
        scope: TypedFacadeScope
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
        var procedureScope = typedFacadeScope(
            scope,
            bindings: bindings.enumerated().map { index, sourceName in
                (sourceName: sourceName, value: .variable(parameters[index].root))
            }
        )
        var locals: [AlgorithmStateModel] = []
        var steps: [AlgorithmStepModel] = []
        for item in closure.statements {
            if case .decl(let declaration) = item.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(
                    variable,
                    expectedKind: "LocalVar",
                    scope: procedureScope
               ),
               case .local(let local) = component {
                locals.append(local)
                algorithmStateNames.insert(local.root)
                procedureScope = typedFacadeScope(
                    procedureScope,
                    binding: local.root,
                    to: .variable(local.root)
                )
                continue
            }
            guard case .expr(let expression) = item.item,
                  let component = parseEachComponent(
                    expression,
                    processParameter: "__pcal_sequential",
                    macros: macros,
                    scope: procedureScope
                  ),
                  case .step(let step) = component
            else {
                algorithmParseFailure = "Procedure '\(name)' accepts LocalVar declarations and Do or While blocks."
                return nil
            }
            steps.append(step)
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
              let terminalName = terminalTypeName(in: type)
        else { return nil }
        let defaultValue: StateExpr
        switch terminalName {
        case "Int": defaultValue = .value(.int(0))
        case "Bool": defaultValue = .value(.bool(false))
        case "String": defaultValue = .value(.string(""))
        default: defaultValue = .value(.constant("default_\(terminalName)"))
        }
        return .init(
            renderedName: terminalName,
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
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1], scope: .empty).map(TemporalExpr.eventually) : nil
        case "Always":
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1], scope: .empty).map(TemporalExpr.always) : nil
        case "AlwaysEventually":
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1], scope: .empty).map(TemporalExpr.alwaysEventually) : nil
        case "EventuallyAlways":
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1], scope: .empty).map(TemporalExpr.eventuallyAlways) : nil
        default:
            expression = nil
        }
        return expression.map { .init(name: name, expr: $0) }
    }

    private func parseAlgorithmInvariant(
        _ call: FunctionCallExprSyntax,
        scope: TypedFacadeScope
    ) -> NamedInvariant? {
        guard let name = extractStringArg(call, index: 0),
              let closure = call.trailingClosure
        else { return nil }

        var bodyScope = scope
        var expressions: [StateExpr] = []
        for (index, statement) in closure.statements.enumerated() {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let binding = parseFormalLet(variable, scope: bodyScope) {
                bodyScope = typedFacadeScope(bodyScope, binding: binding.name, to: binding.value)
                continue
            }
            let expression: ExprSyntax?
            if case .expr(let value) = statement.item {
                expression = value
            } else if let returned = statement.item.as(ReturnStmtSyntax.self) {
                expression = returned.expression
            } else {
                expression = nil
            }
            guard let expression else {
                algorithmParseFailure = "Invariant '\(name)' statement \(index + 1) is not a formal expression."
                return nil
            }
            guard let decoded = formalAlgorithmProperty(expression, scope: bodyScope) else {
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

    private func formalAlgorithmProperty(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        if let quantifier = decodeAlgorithmDomainQuantifier(expression, scope: scope) {
            return quantifier
        }
        return decodeTypedFacadeValue(expression, scope: scope)
    }

    private func parseEach(
        _ call: FunctionCallExprSyntax,
        macros: [String: AlgorithmMacroDefinition],
        scope: TypedFacadeScope
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
        var processScope = typedFacadeScope(
            scope,
            binding: parameter,
            to: .variable("__pcal_self")
        )
        var components: [AlgorithmComponentModel] = []
        for (index, statement) in closure.statements.enumerated() {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(
                    variable,
                    expectedKind: "LocalVar",
                    scope: processScope
               ) {
                guard case .local(let state) = component else { return nil }
                components.append(.local(.init(
                    root: state.root,
                    initial: state.initial,
                    initialSet: state.initialSet,
                    swiftTypeName: state.swiftTypeName
                )))
                algorithmStateNames.insert(state.root)
                processScope = typedFacadeScope(
                    processScope,
                    binding: state.root,
                    to: .variable(state.root)
                )
                continue
            }
            guard case .expr(let expression) = statement.item else { return nil }
            guard let component = parseEachComponent(
                expression,
                processParameter: parameter,
                macros: macros,
                scope: processScope
            ) else {
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

    /// Parses one PlusCal-shaped state declaration into the source model.
    private func parseAlgorithmVariableDeclaration(
        _ declaration: VariableDeclSyntax,
        expectedKind: String,
        scope: TypedFacadeScope = .empty
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
           let initial = decodeAlgorithmStateExpression(initialSyntax, scope: scope)
                ?? decodeStateExpr(initialSyntax) {
            state = AlgorithmStateModel(
                root: declaredName,
                initial: initial,
                swiftTypeName: algorithmInitialTypeName(initialSyntax),
                isTuple: isTupleInitialValue(initialSyntax)
            )
        } else if expectedKind == "LocalVar",
                  let initialSyntax = initializer.arguments.first(where: { $0.label?.text == "initial" })?.expression,
                  let emptySet = initialSyntax.as(FunctionCallExprSyntax.self),
                  emptySet.arguments.isEmpty,
                  let generic = emptySet.calledExpression.as(GenericSpecializationExprSyntax.self),
                  terminalTypeName(in: generic.expression) == "SetExpr",
                  let element = generic.genericArgumentClause.arguments.first?.argument,
                  let typeName = Self.sourceTypeSpelling(element) {
            state = AlgorithmStateModel(
                root: declaredName,
                initial: .value(.set([])),
                swiftTypeName: "SetExpr<\(typeName)>"
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
              isAlgorithmMacroInitializer(initializer)
        else { return nil }
        let scope = typedFacadeScope(
            .empty,
            bindings: parameters.map { (sourceName: $0, value: .variable($0)) }
        )
        guard let statements = parseAlgorithmStatements(
            closure.statements,
            processParameter: "__pcal_macro_no_process",
            macros: [:],
            scope: scope
        ) else { return nil }
        return .init(
            parameters: parameters,
            body: closure.statements,
            assignmentParameters: Set(parameters.filter { macroAssigns(to: $0, in: statements) })
        )
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
            return typedFacadeType(base)?.renderedSourceName ?? terminalTypeName(in: base)
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
        macros: [String: AlgorithmMacroDefinition],
        scope: TypedFacadeScope
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
                    macros: macros,
                    scope: scope
                  )
            else { return nil }
            let loopCondition: StateExpr?
            if name == "While" {
                guard let conditionSyntax = call.arguments.dropFirst().first?.expression,
                      let condition = decodeAlgorithmStateExpression(conditionSyntax, scope: scope)
                else { return nil }
                loopCondition = condition
            } else {
                loopCondition = nil
            }
            return .step(.init(label: .init(name: label), statements: statements, loopCondition: loopCondition))
        case "Invariant":
            guard let invariant = parseAlgorithmInvariant(call, scope: scope) else { return nil }
            return .invariant(invariant)
        default:
            return nil
        }
    }

    private func parseAlgorithmStatements(
        _ statements: CodeBlockItemListSyntax,
        processParameter: String,
        macros: [String: AlgorithmMacroDefinition],
        scope: TypedFacadeScope
    ) -> [AlgorithmStatementModel]? {
        var result: [AlgorithmStatementModel] = []
        for (index, statement) in statements.enumerated() {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self) {
                guard let binding = parseFormalLet(variable, scope: scope) else {
                    if algorithmParseFailure == nil {
                        algorithmParseFailure = "Statement \(index + 1) could not be decoded: "
                            + "'\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                    }
                    return nil
                }
                let remaining = CodeBlockItemListSyntax(Array(statements.dropFirst(index + 1)))
                let bodyScope = typedFacadeScope(scope, binding: binding.name, to: binding.value)
                guard let body = parseAlgorithmStatements(
                    remaining,
                    processParameter: processParameter,
                    macros: macros,
                    scope: bodyScope
                ) else { return nil }
                return result + body
            }
            guard case .expr(let expression) = statement.item
            else {
                if algorithmParseFailure == nil {
                    algorithmParseFailure = "Statement \(index + 1) could not be decoded: "
                        + "'\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                }
                return nil
            }
            if let expanded = parseMacroInvocation(
                expression,
                processParameter: processParameter,
                macros: macros,
                scope: scope
            ) {
                result += expanded
                continue
            }
            guard let parsed = parseAlgorithmStatement(
                expression,
                processParameter: processParameter,
                macros: macros,
                scope: scope
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
    private func parseFormalLet(
        _ declaration: VariableDeclSyntax,
        scope: TypedFacadeScope
    ) -> (name: String, value: StateExpr)? {
        guard declaration.bindingSpecifier.text == "let",
              declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let initializer = binding.initializer?.value,
              let value = decodeAlgorithmStateExpression(initializer, scope: scope)
        else { return nil }
        return (name, value)
    }

    private func parseAlgorithmStatement(
        _ expression: ExprSyntax,
        processParameter: String,
        macros: [String: AlgorithmMacroDefinition],
        scope: TypedFacadeScope
    ) -> AlgorithmStatementModel? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }

        switch name {
        case "Await", "When":
            guard let expression = call.arguments.first?.expression,
                  let condition = decodeAlgorithmStateExpression(expression, scope: scope)
            else { return nil }
            return .await(condition)
        case "Assert":
            guard let expression = call.arguments.first?.expression,
                  let condition = decodeAlgorithmStateExpression(expression, scope: scope)
            else { return nil }
            return .assert(condition)
        case "Assign":
            guard let target = algorithmTarget(call.arguments.first?.expression, scope: scope),
                  let valueSyntax = call.arguments.first(where: { $0.label?.text == "to" })?.expression,
                  let value = decodeAlgorithmStateExpression(valueSyntax, scope: scope)
            else { return nil }
            return .set(target: target, value: value)
        case "Goto":
            guard let label = algorithmLabel(call.arguments.first?.expression) else { return nil }
            return .goto(.init(name: label))
        case "Call":
            guard let target = extractStringArg(call, index: 0) else {
                algorithmParseFailure = "Call requires a procedure name string literal."
                return nil
            }
            let arguments = call.arguments.dropFirst().compactMap { argument in
                decodeAlgorithmStateExpression(argument.expression, scope: scope)
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
                  let condition = decodeAlgorithmStateExpression(conditionSyntax, scope: scope),
                  let thenClosure = call.trailingClosure,
                  let then = parseAlgorithmStatements(
                      thenClosure.statements,
                      processParameter: processParameter,
                      macros: macros,
                      scope: scope
                  )
            else { return nil }
            let elseClosure = call.additionalTrailingClosures.first?.closure
                ?? call.arguments.first(where: { $0.label?.text == "else" })?.expression.as(ClosureExprSyntax.self)
            let otherwise = elseClosure.flatMap {
                parseAlgorithmStatements(
                    $0.statements,
                    processParameter: processParameter,
                    macros: macros,
                    scope: scope
                )
            } ?? []
            return .ifElse(condition, then, otherwise)
        case "Either":
            guard let first = call.trailingClosure.flatMap({
                parseAlgorithmStatements(
                    $0.statements,
                    processParameter: processParameter,
                    macros: macros,
                    scope: scope
                )
            }),
                  let secondClosure = call.additionalTrailingClosures.first?.closure
                    ?? call.arguments.first(where: { $0.label?.text == "or" })?.expression.as(ClosureExprSyntax.self),
                  let second = parseAlgorithmStatements(
                      secondClosure.statements,
                      processParameter: processParameter,
                      macros: macros,
                      scope: scope
                  )
            else { return nil }
            return .either(first, second)
        case "Choose":
            guard let closure = call.trailingClosure,
                  !call.arguments.isEmpty
            else { return nil }
            let choices = closureParameterNames(in: closure)
            guard choices.count == call.arguments.count else { return nil }
            let domains = call.arguments.map(\.expression).compactMap { syntax in
                finiteAlgorithmDomain(syntax)?.values
                    ?? parseIntegerClosedRange(syntax).map { $0.map(TLAValue.int) }
            }
            guard domains.count == choices.count else { return nil }
            let choiceBindings = choices.indices.map { index in
                (sourceName: choices[index], value: StateExpr.variable("__pcal_choice_\(index)"))
            }
            guard var nestedBody = parseAlgorithmStatements(
                closure.statements,
                processParameter: processParameter,
                macros: macros,
                scope: typedFacadeScope(scope, bindings: choiceBindings)
            ) else { return nil }
            for index in choices.indices.reversed() {
                let replacement = "__pcal_choice_\(index)"
                nestedBody = [.choose(variable: replacement, domain: domains[index], nestedBody)]
            }
            return nestedBody[0]
        case "With":
            guard let closure = call.trailingClosure
            else { return nil }
            let sources = call.arguments.compactMap { algorithmWithSource($0.expression, scope: scope) }
            guard sources.count == call.arguments.count else { return nil }
            let bindings = closureParameterNames(in: closure)
            switch (sources.count, bindings.count) {
            case (1, 1):
                let replacement = "__pcal_with"
                guard let body = parseAlgorithmStatements(
                    closure.statements,
                    processParameter: processParameter,
                    macros: macros,
                    scope: typedFacadeScope(scope, binding: bindings[0], to: .variable(replacement))
                ) else { return nil }
                return .with(
                    variable: replacement,
                    source: sources[0],
                    body
                )
            case (1, 2):
                // `With(SetExpr<Pair<A, B>>) { first, second in ... }` is
                // PlusCal's `with <<first, second>> \in Pairs`. Keep one
                // formal selection, then bind both tuple positions inside its
                // scope so the emitted TLA+ and runtime builder agree.
                let tupleBinding = generatedBinderName()
                let firstBinding = generatedBinderName()
                let secondBinding = generatedBinderName()
                let pairScope = typedFacadeScope(
                    scope,
                    bindings: [
                        (sourceName: bindings[0], value: .variable(firstBinding)),
                        (sourceName: bindings[1], value: .variable(secondBinding))
                    ]
                )
                guard let replacedBody = parseAlgorithmStatements(
                    closure.statements,
                    processParameter: processParameter,
                    macros: macros,
                    scope: pairScope
                ) else { return nil }
                return .with(
                    variable: tupleBinding,
                    source: sources[0],
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
                let boundScope = typedFacadeScope(
                    scope,
                    bindings: bindings.enumerated().map { index, binding in
                        (sourceName: binding, value: .variable("__pcal_with_\(index)"))
                    }
                )
                guard var boundBody = parseAlgorithmStatements(
                    closure.statements,
                    processParameter: processParameter,
                    macros: macros,
                    scope: boundScope
                ) else { return nil }
                var selections: [(variable: String, source: StateExpr)] = []
                for (index, _) in bindings.enumerated() {
                    let variable = "__pcal_with_\(index)"
                    selections.append((variable, sources[index]))
                }
                for selection in selections.reversed() {
                    boundBody = [.with(variable: selection.variable, source: selection.source, boundBody)]
                }
                return boundBody[0]
            }
        case "Let":
            guard let valueSyntax = call.arguments.first?.expression,
                  let value = decodeAlgorithmStateExpression(valueSyntax, scope: scope),
                  let closure = call.trailingClosure,
                  let bound = closureParameterNames(in: closure).first
            else { return nil }
            let replacement = generatedBinderName()
            guard let body = parseAlgorithmStatements(
                closure.statements,
                processParameter: processParameter,
                macros: macros,
                scope: typedFacadeScope(scope, binding: bound, to: .variable(replacement))
            ) else { return nil }
            return .letBinding(
                variable: replacement,
                value: value,
                body
            )
        default:
            return nil
        }
    }

    private func algorithmWithSource(
        _ syntax: ExprSyntax,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        finiteAlgorithmDomain(syntax).map { domain in
            StateExpr.setLiteral(domain.values.map(StateExpr.value))
        } ?? decodeAlgorithmStateExpression(syntax, scope: scope)
    }

    private func decodeAlgorithmStateExpression(
        _ syntax: ExprSyntax,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        decodeTypedFacadeValue(syntax, scope: scope)
    }

    /// Parses a bounded statement macro in the lexical scope of its invocation.
    private func parseMacroInvocation(
        _ expression: ExprSyntax,
        processParameter: String,
        macros: [String: AlgorithmMacroDefinition],
        scope: TypedFacadeScope
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
            guard let argument = decodeAlgorithmStateExpression(argumentSyntax.expression, scope: scope) else {
                algorithmParseFailure = "Statement macro '\(name)' argument \(index + 1) is not a formal expression. Use an expression understood by the SwiftTLA DSL."
                return nil
            }
            arguments.append(argument)
        }
        for (parameter, argument) in zip(macro.parameters, arguments) {
            let isVariable: Bool
            if case .variable = argument { isVariable = true } else { isVariable = false }
            guard !macro.assignmentParameters.contains(parameter) || isVariable else {
                algorithmParseFailure = "What failed: statement macro '\(name)' assigns through parameter '\(parameter)'. "
                    + "Where: its invocation argument. Expected a formal variable assignment target; found \(argument). "
                    + "Next safe action: pass a SharedVar or LocalVar, "
                    + "or make the parameter read-only in the macro body."
                return nil
            }
        }
        let invocationScope = typedFacadeScope(
            scope,
            bindings: zip(macro.parameters, arguments).map { (sourceName: $0.0, value: $0.1) }
        )
        return parseAlgorithmStatements(
            macro.body,
            processParameter: processParameter,
            macros: [:],
            scope: invocationScope
        )
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

    private func algorithmTarget(
        _ expression: ExprSyntax?,
        scope: TypedFacadeScope
    ) -> AlgorithmLValueModel? {
        guard let expression else { return nil }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            if let bound = scope.value(for: reference) {
                guard case .variable(let root) = bound else { return nil }
                return .root(root)
            }
            return .root(reference.baseName.text)
        }
        if let access = expression.as(MemberAccessExprSyntax.self),
           access.declName.baseName.text == "algorithmLValue",
           let base = access.base?.as(DeclReferenceExprSyntax.self) {
            if let bound = scope.value(for: base) {
                guard case .variable(let root) = bound else { return nil }
                return .root(root)
            }
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

}
