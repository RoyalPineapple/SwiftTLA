import SwiftSyntax
import SwiftTLA

extension ParserSession {
    func validationRoot(_ call: FunctionCallExprSyntax) -> FunctionCallExprSyntax? {
        var root = call
        while let member = root.calledExpression.as(MemberAccessExprSyntax.self),
              ["expect", "expectDeadlock", "checking", "checkingDeadlock", "checkingMode", "simulating", "behavior", "usingSymmetry", "usingFairness"].contains(member.declName.baseName.sourceIdentifierName),
              let base = member.base?.as(FunctionCallExprSyntax.self) {
            root = base
        }
        return compilerGrammarName(in: root.calledExpression) == "Validation" ? root : nil
    }

    func parseValidation(_ call: FunctionCallExprSyntax, into components: inout TLASpec,
                         boundName: String? = nil) -> Bool {
        var root = call
        var overrides: [FunctionCallExprSyntax] = []
        while let member = root.calledExpression.as(MemberAccessExprSyntax.self),
              ["expect", "expectDeadlock", "checking", "checkingDeadlock", "checkingMode", "simulating", "behavior", "usingSymmetry", "usingFairness"].contains(member.declName.baseName.sourceIdentifierName),
              let base = member.base?.as(FunctionCallExprSyntax.self) {
            overrides.append(root)
            root = base
        }
        guard compilerGrammarName(in: root.calledExpression) == "Validation" else { return false }
        func declaration() throws(SourceParseDiagnostic) -> ValidationDeclaration {
            guard let name = boundName,
                  root.arguments.allSatisfy({ $0.label != nil }),
                  !root.arguments.contains(where: { $0.label?.text == "_name" }),
                  let body = root.trailingClosure else {
                throw SourceParseDiagnostic(message: "Validation requires an immutable let binding and typed parameter bindings.", source: root)
            }
            let displayLabel = try declarationDisplayLabel(root, kind: "validation")
            var bindings: [ValidationBinding] = []
            for statement in body.statements {
                guard case .expr(let expression) = statement.item,
                      let binding = expression.as(FunctionCallExprSyntax.self),
                      compilerGrammarName(in: binding.calledExpression) == "Bind",
                      binding.arguments.count == 2,
                      let first = binding.arguments.first, let last = binding.arguments.last,
                      last.label?.text == "to",
                      case .parameter(let parameter)? = decodeTypedFacadeValue(first.expression, scope: sourceScope),
                      let value = decodeTypedFacadeValue(last.expression, scope: sourceScope) else {
                    throw SourceParseDiagnostic(message: "Validation bindings require Bind(modelParameter, to: value).", source: statement)
                }
                recordValidationBinding(named: name, parameter: parameter.name, at: last.expression)
                bindings.append(.init(parameter: parameter, value: value))
            }
            var scenario = ValidationDeclaration(name: name, displayLabel: displayLabel, bindings: bindings)
            for override in overrides.reversed() {
                if let member = override.calledExpression.as(MemberAccessExprSyntax.self) {
                    if member.declName.baseName.sourceIdentifierName == "behavior" {
                        guard override.arguments.count == 1,
                              let value = override.arguments.first?.expression.as(MemberAccessExprSyntax.self),
                              let behavior = ModelBehavior(rawValue: value.declName.baseName.sourceIdentifierName) else {
                            throw SourceParseDiagnostic(message: "Behavior selection requires .specification or .initialAndNext.", source: override)
                        }
                        scenario.behaviorSelections.append(behavior)
                        continue
                    }
                    if member.declName.baseName.sourceIdentifierName == "usingSymmetry" {
                        guard override.arguments.count == 1,
                              let argument = override.arguments.first,
                              let reference = argument.expression.as(DeclReferenceExprSyntax.self),
                              let symmetry = specBindings.symmetries[reference.baseName.sourceIdentifierName] else {
                            throw SourceParseDiagnostic(message: "Symmetry selection requires a registered model-owned symmetry binding.", source: override)
                        }
                        recordValidationSymmetry(named: scenario.name, at: argument.expression)
                        scenario.symmetrySelections.append(symmetry.reference)
                        continue
                    }
                    if member.declName.baseName.sourceIdentifierName == "usingFairness" {
                        guard override.arguments.count == 1,
                              let argument = override.arguments.first,
                              let reference = argument.expression.as(DeclReferenceExprSyntax.self),
                              let profile = specBindings.fairnessProfiles[reference.baseName.sourceIdentifierName] else {
                            throw SourceParseDiagnostic(message: "Fairness selection requires a registered model-owned profile binding.", source: override)
                        }
                        recordValidationFairness(named: scenario.name, at: argument.expression)
                        scenario.fairnessProfileSelections.append(profile.reference)
                        continue
                    }
                    if member.declName.baseName.sourceIdentifierName == "checkingMode" {
                        guard override.arguments.count == 1,
                              let value = override.arguments.first?.expression.as(MemberAccessExprSyntax.self) else {
                            throw SourceParseDiagnostic(message: "Checking mode requires .exhaustive or .decisiveCounterexample.", source: override)
                        }
                        let mode: ValidationCheckingMode
                        switch value.declName.baseName.sourceIdentifierName {
                        case "exhaustive": mode = .exhaustive
                        case "decisiveCounterexample": mode = .decisiveCounterexample
                        default: throw SourceParseDiagnostic(message: "Checking mode requires .exhaustive or .decisiveCounterexample.", source: override)
                        }
                        scenario.checkingModeSelections.append(mode)
                        continue
                    }
                    if member.declName.baseName.sourceIdentifierName == "simulating" {
                        let arguments = Array(override.arguments)
                        guard (1...2).contains(arguments.count),
                              arguments[0].label?.text == "traces",
                              let traces = SourceIntegerLiteral.value(arguments[0].expression),
                              arguments.count == 1 || arguments[1].label?.text == "maximumDepth" else {
                            throw SourceParseDiagnostic(message: "Simulation requires simulating(traces: positiveInt, maximumDepth: positiveInt).", source: override)
                        }
                        let maximumDepth = arguments.count == 2
                            ? SourceIntegerLiteral.value(arguments[1].expression) : 100
                        guard let maximumDepth, traces > 0, maximumDepth > 0 else {
                            throw SourceParseDiagnostic(message: "Simulation trace count and maximum depth must be positive integer literals.", source: override)
                        }
                        scenario.checkingModeSelections.append(.simulation(
                            traces: traces, maximumDepth: maximumDepth))
                        continue
                    }
                    if member.declName.baseName.sourceIdentifierName == "checking" {
                        guard override.arguments.count == 1, let argument = override.arguments.first,
                              argument.label?.text == "only",
                              let array = argument.expression.as(ArrayExprSyntax.self) else {
                            throw SourceParseDiagnostic(message: "Check selection requires checking(only: [modelProperty]).", source: override)
                        }
                        var references: [PropertyReference] = []
                        for element in array.elements {
                            guard let reference = element.expression.as(DeclReferenceExprSyntax.self),
                                  let property = specBindings.properties[reference.baseName.sourceIdentifierName] else {
                                throw SourceParseDiagnostic(message: "Check selection requires model-owned property handles.", source: element)
                            }
                            references.append(property.reference)
                        }
                        scenario.propertySelections.append(references)
                        continue
                    }
                    if member.declName.baseName.sourceIdentifierName == "checkingDeadlock" {
                        guard override.arguments.count == 1,
                              let literal = override.arguments.first?.expression.as(BooleanLiteralExprSyntax.self) else {
                            throw SourceParseDiagnostic(message: "Deadlock selection requires checkingDeadlock(true) or checkingDeadlock(false).", source: override)
                        }
                        scenario.deadlockSelections.append(literal.literal.text == "true")
                        continue
                    }
                }
                guard let member = override.calledExpression.as(MemberAccessExprSyntax.self),
                      let last = override.arguments.last,
                      let outcome = last.expression.as(MemberAccessExprSyntax.self),
                      let expected = ValidationExpectation(rawValue: outcome.declName.baseName.sourceIdentifierName) else {
                    throw SourceParseDiagnostic(message: "An expectation requires .satisfied or .violated.", source: override)
                }
                if member.declName.baseName.sourceIdentifierName == "expectDeadlock", override.arguments.count == 1 {
                    scenario.deadlockExpectations.append(expected)
                } else if member.declName.baseName.sourceIdentifierName == "expect", override.arguments.count == 2,
                          let first = override.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
                          let property = specBindings.properties[first.baseName.sourceIdentifierName] {
                    scenario.expectations.append((property.reference, expected))
                } else {
                    throw SourceParseDiagnostic(message: "A property expectation requires a model-owned property handle.", source: override)
                }
            }
            return scenario
        }
        do { components.validationScenarios.append(try declaration()) }
        catch { components.diagnostics.append(error) }
        return true
    }
}
