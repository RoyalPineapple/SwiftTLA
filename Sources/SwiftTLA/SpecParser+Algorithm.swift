import SwiftSyntax

private struct AlgorithmMacroDefinition: Sendable {
    let parameters: [String]
    let body: CodeBlockItemListSyntax
    let assignmentParameters: Set<String>
}

private enum AlgorithmStateDeclarationKind: Equatable {
    case shared
    case local

    var sourceName: String {
        switch self {
        case .shared: "SharedVar"
        case .local: "LocalVar"
        }
    }
}

private enum AlgorithmSourceConstruct: Equatable {
    case formalDefinition
    case macro
    case state(AlgorithmStateDeclarationKind)
    case scopedState(AlgorithmStateDeclarationKind, scope: String)
    case procedure
    case each
    case doStep
    case whileStep
    case invariant
    case leadsTo
    case eventually
    case always
    case alwaysEventually
    case eventuallyAlways
    case fairness
    case assume
    case theorem
    case stateConstraint
    case awaitCondition
    case assert
    case assign
    case goto
    case call
    case `return`
    case stop
    case skip
    case ifElse
    case either
    case choose
    case with
    case letBinding

    var declaredConstruct: DeclaredLanguageConstruct {
        switch self {
        case .formalDefinition: .formalDefinition
        case .macro: .statementMacro
        case .state(.shared), .scopedState(.shared, _): .sharedVariable
        case .state(.local), .scopedState(.local, _): .localVariable
        case .procedure: .procedure
        case .each: .each
        case .doStep: .atomicStep
        case .whileStep: .whileLoop
        case .invariant: .invariant
        case .leadsTo, .eventually, .always, .alwaysEventually, .eventuallyAlways: .temporalProperty
        case .fairness: .genericFairness
        case .assume: .algorithmAssume
        case .theorem: .algorithmTheorem
        case .stateConstraint: .stateConstraint
        case .awaitCondition: .awaitCondition
        case .assert: .assertion
        case .assign: .assignment
        case .goto: .goto
        case .call: .call
        case .return: .return
        case .stop: .stop
        case .skip: .skip
        case .ifElse: .ifElse
        case .either: .either
        case .choose: .choose
        case .with: .withBinding
        case .letBinding: .letBinding
        }
    }

    init?(_ expression: ExprSyntax) {
        if let reference = Self.reference(in: expression) {
            self.init(reference)
            return
        }
        guard let member = expression.as(MemberAccessExprSyntax.self),
              let scope = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }
        switch member.declName.baseName.text {
        case "sharedVar": self = .scopedState(.shared, scope: scope)
        case "localVar": self = .scopedState(.local, scope: scope)
        default: return nil
        }
    }

    static func referenceName(in expression: ExprSyntax) -> String? {
        reference(in: expression)?.baseName.text
    }

    func isState(_ kind: AlgorithmStateDeclarationKind, in scope: String?) -> Bool {
        switch self {
        case .state(let actual): actual == kind
        case .scopedState(let actual, let owner): actual == kind && owner == scope
        default: false
        }
    }

    private init?(_ reference: DeclReferenceExprSyntax) {
        switch reference.baseName.text {
        case "FormalDefinition": self = .formalDefinition
        case "Macro": self = .macro
        case "SharedVar": self = .state(.shared)
        case "LocalVar": self = .state(.local)
        case "Procedure": self = .procedure
        case "Each": self = .each
        case "Do": self = .doStep
        case "While": self = .whileStep
        case "Invariant": self = .invariant
        case "LeadsTo": self = .leadsTo
        case "Eventually": self = .eventually
        case "Always": self = .always
        case "AlwaysEventually": self = .alwaysEventually
        case "EventuallyAlways": self = .eventuallyAlways
        case "WeakFairness", "StrongFairness", "WeakFairnessNext", "StrongFairnessNext":
            self = .fairness
        case "Assume": self = .assume
        case "Theorem": self = .theorem
        case "StateConstraint": self = .stateConstraint
        case "Await", "When": self = .awaitCondition
        case "Assert": self = .assert
        case "Assign": self = .assign
        case "Goto": self = .goto
        case "Call": self = .call
        case "Return": self = .return
        case "Stop": self = .stop
        case "Skip": self = .skip
        case "If": self = .ifElse
        case "Either": self = .either
        case "Choose": self = .choose
        case "With": self = .with
        case "Let": self = .letBinding
        default: return nil
        }
    }

    private static func reference(in expression: ExprSyntax) -> DeclReferenceExprSyntax? {
        expression.as(DeclReferenceExprSyntax.self)
            ?? expression.as(GenericSpecializationExprSyntax.self)?
                .expression.as(DeclReferenceExprSyntax.self)
    }
}

extension ParserSession {
    private func algorithmReference(
        for construct: AlgorithmSourceConstruct,
        in expression: ExprSyntax
    ) -> LanguageConstructReference {
        .declared(
            construct: construct.declaredConstruct,
            authoredName: AlgorithmSourceConstruct.referenceName(in: expression)
                ?? construct.declaredConstruct.rawValue
        )
    }

    private func unsupportedSourceDecodingDiagnostic<Node: SyntaxProtocol>(
        _ reference: LanguageConstructReference,
        source: Node,
        requireAdmission: Bool = false
    ) -> LanguageCapabilityDiagnostic? {
        let capability = LanguageCapabilityLedger.capability(for: reference)
        guard capability?.dimensions.sourceDecoding != .supported
            || (requireAdmission && capability?.status == .unsupported)
        else {
            return nil
        }
        let sourceText = source.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let actual: String
        if reference.construct == nil {
            actual = "unregistered Algorithm declaration '\(reference.authoredName)'"
        } else if capability?.dimensions.sourceDecoding == .supported {
            actual = "Algorithm declaration '\(reference.authoredName)' is not admitted in Algorithm"
        } else {
            actual = "Algorithm declaration '\(reference.authoredName)' does not support source decoding"
        }
        return .init(
            code: .unsupportedConstruct,
            construct: reference,
            operation: .sourceDecoding,
            source: sourceText,
            sourcePath: ["Algorithm", reference.authoredName],
            sourceSpan: .init(
                location: .utf8Offset(source.positionAfterSkippingLeadingTrivia.utf8Offset),
                utf8Length: sourceText.utf8.count
            ),
            expected: capability?.boundary ?? "a registered Algorithm declaration with supported source decoding",
            actual: actual,
            nextSafeAction: capability?.nextSafeAction ?? "Use an admitted Algorithm declaration."
        )
    }

    private func unsupportedSourceDecodingDiagnostic<Node: SyntaxProtocol>(
        in expression: ExprSyntax,
        source: Node
    ) -> LanguageCapabilityDiagnostic? {
        guard let sourceName = AlgorithmSourceConstruct.referenceName(in: expression) else { return nil }
        return unsupportedSourceDecodingDiagnostic(
            .unregistered(sourceName: sourceName),
            source: source,
            requireAdmission: true
        )
    }

    private func admitsSourceDecoding(
        _ construct: AlgorithmSourceConstruct,
        expression: ExprSyntax
    ) -> Bool {
        LanguageCapabilityLedger.capability(
            for: algorithmReference(for: construct, in: expression)
        )?.dimensions.sourceDecoding == .supported
    }

    private func recordAlgorithmCapabilityDiagnostic<Node: SyntaxProtocol>(
        _ reference: LanguageConstructReference,
        source: Node
    ) {
        guard let diagnostic = unsupportedSourceDecodingDiagnostic(
            reference,
            source: source,
            requireAdmission: true
        ) else {
            return
        }
        if algorithmCapabilityDiagnostic == nil {
            algorithmCapabilityDiagnostic = diagnostic
        }
    }

    private func algorithmBuilderClosure(in call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        call.trailingClosure
            ?? call.arguments.first(where: { $0.label?.text == "scoped" })?.expression.as(ClosureExprSyntax.self)
    }

    /// Parses the bounded PlusCal-shaped authoring layer into an `AlgorithmModel`.
    func parseAlgorithm(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) -> Algorithm? {
        algorithmParseFailure = nil
        algorithmCapabilityDiagnostic = nil
        if let diagnostic = unsupportedSourceDecodingDiagnostic(
            .declared(construct: .algorithm, authoredName: "Algorithm"),
            source: call
        ) {
            result.diagnostics.append(.init(capability: diagnostic))
            return nil
        }
        guard let name = extractStringArg(call, index: 0),
              let closure = algorithmBuilderClosure(in: call)
        else {
            result.diagnostics.append(.init(
                message: "Algorithm requires a string literal name and a builder body.",
                source: call
            ))
            return nil
        }
        let fairness: SequentialAlgorithmFairness
        if let expression = call.arguments.first(where: { $0.label?.text == "fairness" })?.expression {
            guard let access = expression.as(MemberAccessExprSyntax.self) else {
                result.diagnostics.append(.init(
                    message: "Algorithm fairness must be .none or .weak.",
                    source: expression
                ))
                return nil
            }
            switch access.declName.baseName.text {
            case "none": fairness = .none
            case "weak": fairness = .weak
            default:
                result.diagnostics.append(.init(
                    message: "Algorithm fairness must be .none or .weak.",
                    source: expression
                ))
                return nil
            }
        } else {
            fairness = .none
        }

        var components: [AlgorithmComponentModel] = []
        var macros: [String: AlgorithmMacroDefinition] = [:]
        let outerConstants = constants
        let outerTupleVariables = algorithmTupleVariables
        let outerSourceScope = sourceScope
        algorithmTupleVariables = []
        sourceScope = .empty
        let declarationScope = closureParameterNames(in: closure).first
        defer {
            algorithmTupleVariables = outerTupleVariables
            sourceScope = outerSourceScope
            constants = outerConstants
        }
        for statement in closure.statements {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let macro = parseAlgorithmMacroDeclaration(variable, scope: sourceScope) {
                let name = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text ?? ""
                guard macros[name] == nil else {
                    result.diagnostics.append(.init(message: "Algorithm macro '\(name)' is declared more than once.", source: statement))
                    return nil
                }
                macros[name] = macro
                continue
            }
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(
                    variable,
                    kind: .shared,
                    scope: sourceScope,
                    declarationScope: declarationScope
               ) {
                components.append(component)
                if case .shared(let state) = component,
                   state.isTuple {
                    algorithmTupleVariables.insert(state.root)
                }
                if case .shared(let state) = component {
                    sourceScope = typedFacadeScope(
                        sourceScope,
                        binding: state.root,
                        to: .variable(state.root)
                    )
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
            if let diagnostic = algorithmCapabilityDiagnostic {
                result.diagnostics.append(.init(capability: diagnostic))
                return nil
            }
            guard case .expr(let expression) = statement.item else {
                let detail = algorithmParseFailure.map { " \($0)" } ?? ""
                result.diagnostics.append(.init(
                    message: "Unsupported Algorithm declaration '\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'. "
                        + "Supported declarations are SharedVar, Macro, Procedure, Each, Do, While, and properties.\(detail)",
                    source: statement
                ))
                return nil
            }
            guard let call = expression.as(FunctionCallExprSyntax.self) else {
                if let diagnostic = unsupportedSourceDecodingDiagnostic(in: expression, source: expression) {
                    result.diagnostics.append(.init(capability: diagnostic))
                    return nil
                }
                let detail = algorithmParseFailure.map { " \($0)" } ?? ""
                result.diagnostics.append(.init(
                    message: "Unsupported Algorithm declaration '\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'. "
                        + "Supported declarations are SharedVar, Macro, Procedure, Each, Do, While, and properties.\(detail)",
                    source: expression
                ))
                return nil
            }
            guard let construct = AlgorithmSourceConstruct(call.calledExpression) else {
                if let diagnostic = unsupportedSourceDecodingDiagnostic(
                    in: call.calledExpression, source: call
                ) {
                    result.diagnostics.append(.init(capability: diagnostic))
                    return nil
                }
                let detail = algorithmParseFailure.map { " \($0)" } ?? ""
                result.diagnostics.append(.init(
                    message: "Unsupported Algorithm declaration '\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'. "
                        + "Supported declarations are SharedVar, Macro, Procedure, Each, Do, While, and properties.\(detail)",
                    source: expression
                ))
                return nil
            }
            if let diagnostic = unsupportedSourceDecodingDiagnostic(
                algorithmReference(for: construct, in: call.calledExpression),
                source: call
            ) {
                result.diagnostics.append(.init(capability: diagnostic))
                return nil
            }
            if case .formalDefinition = construct {
                guard let definition = decodeFormalDefinition(call) else {
                    algorithmParseFailure = algorithmParseFailure
                        ?? "FormalDefinition could not decode its typed parameters or formal body."
                    let detail = algorithmParseFailure.map { " \($0)" } ?? ""
                    result.diagnostics.append(.init(
                        message: "Unsupported Algorithm declaration '\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'. "
                            + "Supported declarations are SharedVar, Macro, Procedure, Each, Do, While, and properties.\(detail)",
                        source: expression
                    ))
                    return nil
                }
                components.append(.formalOperator(definition))
                continue
            }
            guard let component = parseAlgorithmComponent(
                call,
                construct: construct,
                macros: macros,
                scope: sourceScope
            ) else {
                if let diagnostic = algorithmCapabilityDiagnostic {
                    result.diagnostics.append(.init(capability: diagnostic))
                    return nil
                }
                let detail = algorithmParseFailure.map { " \($0)" } ?? ""
                result.diagnostics.append(.init(
                    message: "Unsupported Algorithm declaration '\(expression.description.trimmingCharacters(in: .whitespacesAndNewlines))'. "
                        + "Supported declarations are SharedVar, Macro, Procedure, Each, Do, While, and properties.\(detail)",
                    source: expression
                ))
                return nil
            }
            components.append(component)
        }

        let model = AlgorithmModel(name: name, sequentialFairness: fairness, components: components)
        let diagnostics = AlgorithmValidator.validate(model)
        guard diagnostics.isEmpty else {
            result.diagnostics.append(.init(
                message: "Invalid Algorithm '\(name)': \(diagnostics.map(\.description).joined(separator: "; "))",
                source: call
            ))
            return nil
        }

        return Algorithm(model: model)
    }

    private func parseAlgorithmComponent(
        _ call: FunctionCallExprSyntax,
        construct: AlgorithmSourceConstruct,
        macros: [String: AlgorithmMacroDefinition],
        scope: TypedFacadeScope
    ) -> AlgorithmComponentModel? {
        guard admitsSourceDecoding(construct, expression: call.calledExpression) else { return nil }
        switch construct {
        case .procedure:
            return parseProcedure(call, macros: macros, scope: scope)
        case .each:
            let component = parseEach(call, macros: macros, scope: scope)
            if component == nil, algorithmParseFailure == nil {
                algorithmParseFailure = "Each requires a finite enum domain and a decodable process body."
            }
            return component
        case .doStep, .whileStep:
            return parseEachComponent(
                call,
                construct: construct,
                processParameter: "__pcal_sequential",
                macros: macros,
                scope: scope
            )
        case .invariant:
            guard let invariant = parseAlgorithmInvariant(call, scope: scope) else { return nil }
            return .invariant(invariant)
        case .leadsTo, .eventually, .always, .alwaysEventually, .eventuallyAlways:
            guard let temporal = parseAlgorithmTemporal(call, construct: construct, scope: scope) else { return nil }
            return .temporal(temporal)
        case .fairness, .assume, .theorem:
            return .unsupported(construct.declaredConstruct)
        case .stateConstraint:
            guard let argument = call.arguments.first,
                  let condition = decodeAlgorithmStateExpression(argument.expression, scope: scope)
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
        guard let name = extractStringArg(call, index: 0), let closure = algorithmBuilderClosure(in: call) else {
            algorithmParseFailure = "Procedure requires a string literal name and a builder body."
            return nil
        }
        let bindings = closureParameterNames(in: closure)
        let parameterArguments = call.arguments.dropFirst().filter { $0.label?.text != "scoped" }
        guard parameterArguments.count <= 4 else {
            algorithmParseFailure = "Procedure '\(name)' has arity \(parameterArguments.count); SwiftTLA supports 0 through 4 typed parameters. Use a Record parameter or add a typed overload."
            return nil
        }
        let parameterTypes = parameterArguments.compactMap { procedureParameterType($0.expression) }
        guard parameterTypes.count == parameterArguments.count else {
            algorithmParseFailure = "Procedure '\(name)' parameter types could not be decoded. Expected metatype arguments such as Int.self."
            return nil
        }
        let declarationScope = bindings.count == parameterTypes.count + 1 ? bindings.last : nil
        let parameterBindings = declarationScope == nil ? bindings : Array(bindings.dropLast())
        guard parameterBindings.count == parameterTypes.count else {
            algorithmParseFailure = "Procedure '\(name)' expected \(parameterTypes.count) typed parameter binding(s), found \(parameterBindings.count)."
            return nil
        }
        let parameters = parameterTypes.enumerated().map { index, type in
            AlgorithmProcedureParameterModel(root: "parameter\(index)", initial: type.defaultValue, swiftTypeName: type.renderedName)
        }
        var procedureScope = typedFacadeScope(
            scope,
            bindings: parameterBindings.enumerated().map { index, sourceName in
                (sourceName: sourceName, value: .variable(parameters[index].root))
            }
        )
        var components: [AlgorithmComponentModel] = []
        for item in closure.statements {
            if case .decl(let declaration) = item.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(
                    variable,
                    kind: .local,
                    scope: procedureScope,
                    declarationScope: declarationScope
               ),
               case .local(let local) = component {
                components.append(component)
                procedureScope = typedFacadeScope(
                    procedureScope,
                    binding: local.root,
                    to: .variable(local.root)
                )
                continue
            }
            guard case .expr(let expression) = item.item,
                  let call = expression.as(FunctionCallExprSyntax.self)
            else {
                algorithmParseFailure = "Procedure '\(name)' accepts LocalVar declarations and Do or While blocks."
                return nil
            }
            guard let construct = AlgorithmSourceConstruct(call.calledExpression) else {
                guard let sourceName = AlgorithmSourceConstruct.referenceName(in: call.calledExpression) else {
                    return nil
                }
                recordAlgorithmCapabilityDiagnostic(.unregistered(sourceName: sourceName), source: call)
                algorithmParseFailure = "Procedure '\(name)' accepts LocalVar declarations and Do or While blocks."
                return nil
            }
            if LanguageCapabilityLedger.capability(for: algorithmReference(
                for: construct,
                in: call.calledExpression
            ))?.status == .unsupported {
                components.append(.unsupported(construct.declaredConstruct))
                continue
            }
            guard admitsSourceDecoding(construct, expression: call.calledExpression),
                  let component = parseEachComponent(
                    call,
                    construct: construct,
                    processParameter: "__pcal_sequential",
                    macros: macros,
                    scope: procedureScope
                  ),
                  case .step = component
            else {
                algorithmParseFailure = "Procedure '\(name)' accepts LocalVar declarations and Do or While blocks."
                return nil
            }
            components.append(component)
        }
        return .procedure(.init(name: name, parameters: parameters, components: components))
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
        construct: AlgorithmSourceConstruct,
        scope: TypedFacadeScope
    ) -> NamedTemporal? {
        guard let name = extractStringArg(call, index: 0) else { return nil }
        let arguments = Array(call.arguments).map(\.expression)
        let expression: TemporalExpr?
        switch construct {
        case .leadsTo:
            guard arguments.count == 3,
                  let from = formalAlgorithmProperty(arguments[1], scope: scope),
                  let to = formalAlgorithmProperty(arguments[2], scope: scope)
            else { return nil }
            expression = .leadsTo(from, to)
        case .eventually:
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1], scope: scope).map(TemporalExpr.eventually) : nil
        case .always:
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1], scope: scope).map(TemporalExpr.always) : nil
        case .alwaysEventually:
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1], scope: scope).map(TemporalExpr.alwaysEventually) : nil
        case .eventuallyAlways:
            expression = arguments.count == 2 ? formalAlgorithmProperty(arguments[1], scope: scope).map(TemporalExpr.eventuallyAlways) : nil
        default:
            return nil
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
              let closure = algorithmBuilderClosure(in: call)
        else {
            let knownDomains = enumDefinitions.map(\.typeName).sorted()
            let known = knownDomains.isEmpty ? "none" : knownDomains.joined(separator: ", ")
            algorithmParseFailure = "Each could not resolve its finite domain. Known finite domains: \(known)."
            return nil
        }
        let closureParameters = closureParameterNames(in: closure)
        let parameter = closureParameters.first ?? "self"
        let declarationScope = closureParameters.count > 1 ? closureParameters.last : nil
        var processScope = typedFacadeScope(
            scope,
            binding: parameter,
            to: .currentProcess
        )
        var components: [AlgorithmComponentModel] = []
        for (index, statement) in closure.statements.enumerated() {
            if case .decl(let declaration) = statement.item,
               let variable = declaration.as(VariableDeclSyntax.self),
               let component = parseAlgorithmVariableDeclaration(
                    variable,
                    kind: .local,
                    scope: processScope,
                    declarationScope: declarationScope
               ) {
                guard case .local(let state) = component else { return nil }
                components.append(.local(.init(
                    root: state.root,
                    initial: state.initial,
                    initialSet: state.initialSet,
                    swiftTypeName: state.swiftTypeName
                )))
                processScope = typedFacadeScope(
                    processScope,
                    binding: state.root,
                    to: .variable(state.root)
                )
                continue
            }
            guard case .expr(let expression) = statement.item,
                  let componentCall = expression.as(FunctionCallExprSyntax.self)
            else {
                return nil
            }
            guard let construct = AlgorithmSourceConstruct(componentCall.calledExpression) else {
                guard let sourceName = AlgorithmSourceConstruct.referenceName(in: componentCall.calledExpression) else {
                    return nil
                }
                recordAlgorithmCapabilityDiagnostic(.unregistered(sourceName: sourceName), source: componentCall)
                return nil
            }
            if LanguageCapabilityLedger.capability(for: algorithmReference(
                for: construct,
                in: componentCall.calledExpression
            ))?.status == .unsupported {
                components.append(.unsupported(construct.declaredConstruct))
                continue
            }
            guard admitsSourceDecoding(construct, expression: componentCall.calledExpression),
                  let component = parseEachComponent(
                componentCall,
                construct: construct,
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
        kind: AlgorithmStateDeclarationKind,
        scope: TypedFacadeScope = .empty,
        declarationScope: String? = nil
    ) -> AlgorithmComponentModel? {
        guard declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let declaredName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
              let construct = AlgorithmSourceConstruct(initializer.calledExpression),
              admitsSourceDecoding(construct, expression: initializer.calledExpression),
              construct.isState(kind, in: declarationScope)
        else { return nil }

        if let literalName = extractStringArg(initializer, index: 0), literalName != declaredName {
            return nil
        }

        let declaredType = binding.typeAnnotation?.type.as(IdentifierTypeSyntax.self)
        let expectedDeclarationType = kind == .shared ? "SharedVariable" : "LocalVariable"
        let declaredValueType = declaredType?.name.text == expectedDeclarationType
            ? declaredType?.genericArgumentClause?.arguments.first.flatMap { Self.terminalTypeName($0.argument) }
            : nil
        let state: AlgorithmStateModel
        if let initialSyntax = initializer.arguments.first(where: { $0.label?.text == "initial" })?.expression,
           let initial = decodeTypedFacadeValue(
               initialSyntax,
               scope: scope,
               expectedEnumType: declaredValueType
           ) ?? decodeStateExpr(initialSyntax) {
            state = AlgorithmStateModel(
                root: declaredName,
                initial: initial,
                swiftTypeName: algorithmInitialTypeName(initialSyntax),
                isTuple: isTupleInitialValue(initialSyntax)
            )
        } else if kind == .local,
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
        } else if kind == .shared,
                  let rangeSyntax = initializer.arguments.first(where: { $0.label?.text == "in" })?.expression,
                  let range = parseIntegerClosedRange(rangeSyntax) {
            state = AlgorithmStateModel(
                root: declaredName,
                initial: .value(.int(range.lowerBound)),
                initialSet: .setLiteral(range.map { .value(.int($0)) }),
                swiftTypeName: "Int"
            )
        } else if kind == .shared,
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
            algorithmParseFailure = "\(kind.sourceName) declaration must use an explicit initial value or finite domain."
            return nil
        }
        return kind == .shared ? .shared(state) : .local(state)
    }

    private func parseAlgorithmMacroDeclaration(
        _ declaration: VariableDeclSyntax,
        scope: TypedFacadeScope
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
              let construct = AlgorithmSourceConstruct(initializer.calledExpression),
              admitsSourceDecoding(construct, expression: initializer.calledExpression),
              construct == .macro
        else { return nil }
        let macroScope = typedFacadeScope(
            scope,
            bindings: parameters.map { (sourceName: $0, value: .variable($0)) }
        )
        guard let statements = parseAlgorithmStatements(
            closure.statements,
            processParameter: "__pcal_macro_no_process",
            macros: [:],
            scope: macroScope
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

    private func algorithmInitialTypeName(_ expression: ExprSyntax) -> String? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let type = typedFacadeType(member.base) {
            switch (member.declName.baseName.text, type.name) {
            case ("literal", _), ("mapping", "Function"):
                return type.renderedSourceName
            default:
                break
            }
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
        _ call: FunctionCallExprSyntax,
        construct: AlgorithmSourceConstruct,
        processParameter: String,
        macros: [String: AlgorithmMacroDefinition],
        scope: TypedFacadeScope
    ) -> AlgorithmComponentModel? {
        guard admitsSourceDecoding(construct, expression: call.calledExpression) else { return nil }
        switch construct {
        case .doStep, .whileStep:
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
            if construct == .whileStep {
                guard let conditionSyntax = call.arguments.dropFirst().first?.expression,
                      let condition = decodeAlgorithmStateExpression(conditionSyntax, scope: scope)
                else { return nil }
                loopCondition = condition
            } else {
                loopCondition = nil
            }
            return .step(.init(label: .init(name: label), statements: statements, loopCondition: loopCondition))
        case .invariant:
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
            guard let call = expression.as(FunctionCallExprSyntax.self) else {
                if algorithmParseFailure == nil {
                    algorithmParseFailure = "Statement \(index + 1) could not be decoded: "
                        + "'\(statement.description.trimmingCharacters(in: .whitespacesAndNewlines))'."
                }
                return nil
            }
            guard let construct = AlgorithmSourceConstruct(call.calledExpression) else {
                guard let sourceName = AlgorithmSourceConstruct.referenceName(in: call.calledExpression) else {
                    return nil
                }
                recordAlgorithmCapabilityDiagnostic(.unregistered(sourceName: sourceName), source: call)
                return nil
            }
            recordAlgorithmCapabilityDiagnostic(
                algorithmReference(for: construct, in: call.calledExpression), source: call
            )
            if algorithmCapabilityDiagnostic != nil { return nil }
            guard let parsed = parseAlgorithmStatement(
                call,
                construct: construct,
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
        _ call: FunctionCallExprSyntax,
        construct: AlgorithmSourceConstruct,
        processParameter: String,
        macros: [String: AlgorithmMacroDefinition],
        scope: TypedFacadeScope
    ) -> AlgorithmStatementModel? {
        guard admitsSourceDecoding(construct, expression: call.calledExpression) else { return nil }

        switch construct {
        case .awaitCondition:
            guard let expression = call.arguments.first?.expression,
                  let condition = decodeAlgorithmStateExpression(expression, scope: scope)
            else { return nil }
            return .await(condition)
        case .assert:
            guard let expression = call.arguments.first?.expression,
                  let condition = decodeAlgorithmStateExpression(expression, scope: scope)
            else { return nil }
            return .assert(condition)
        case .assign:
            guard let target = algorithmTarget(call.arguments.first?.expression, scope: scope),
                  let valueSyntax = call.arguments.first(where: { $0.label?.text == "to" })?.expression,
                  let value = decodeAlgorithmStateExpression(valueSyntax, scope: scope)
            else { return nil }
            return .set(target: target, value: value)
        case .goto:
            guard let label = algorithmLabel(call.arguments.first?.expression) else { return nil }
            return .goto(.init(name: label))
        case .call:
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
        case .return:
            guard call.arguments.isEmpty else {
                algorithmParseFailure = "Return takes no arguments."
                return nil
            }
            return .return
        case .stop:
            return .stop
        case .skip:
            return .skip
        case .ifElse:
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
        case .either:
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
        case .choose:
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
        case .with:
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
        case .letBinding:
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
              let name = AlgorithmSourceConstruct.referenceName(in: call.calledExpression),
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
