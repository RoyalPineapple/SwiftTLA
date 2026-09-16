import SwiftSyntax
import SwiftTLA

extension ParserSession {
    func parseValidation(_ call: FunctionCallExprSyntax, into components: inout TLASpec) -> Bool {
        var root = call
        var overrides: [FunctionCallExprSyntax] = []
        while let member = root.calledExpression.as(MemberAccessExprSyntax.self),
              ["expect", "expectDeadlock", "checking", "checkingDeadlock"].contains(member.declName.baseName.text),
              let base = member.base?.as(FunctionCallExprSyntax.self) {
            overrides.append(root)
            root = base
        }
        guard compilerGrammarName(in: root.calledExpression) == "Validation" else { return false }
        func declaration() throws(SourceParseDiagnostic) -> ValidationDeclaration {
            guard let name = extractStringArg(root, index: 0), let body = root.trailingClosure else {
                throw SourceParseDiagnostic(message: "Validation requires a name and typed parameter bindings.", source: root)
            }
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
                bindings.append(.init(parameter: parameter, value: value))
            }
            var scenario = ValidationDeclaration(name: name, bindings: bindings)
            for override in overrides.reversed() {
                if let member = override.calledExpression.as(MemberAccessExprSyntax.self) {
                    if member.declName.baseName.text == "checking" {
                        guard override.arguments.count == 1, let argument = override.arguments.first,
                              argument.label?.text == "only",
                              let array = argument.expression.as(ArrayExprSyntax.self) else {
                            throw SourceParseDiagnostic(message: "Check selection requires checking(only: [modelProperty]).", source: override)
                        }
                        var references: [PropertyReference] = []
                        for element in array.elements {
                            guard let reference = element.expression.as(DeclReferenceExprSyntax.self),
                                  let property = specBindings.properties[reference.baseName.text] else {
                                throw SourceParseDiagnostic(message: "Check selection requires model-owned property handles.", source: element)
                            }
                            references.append(property.reference)
                        }
                        scenario.propertySelections.append(references)
                        continue
                    }
                    if member.declName.baseName.text == "checkingDeadlock" {
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
                      let expected = ValidationExpectation(rawValue: outcome.declName.baseName.text) else {
                    throw SourceParseDiagnostic(message: "An expectation requires .satisfied or .violated.", source: override)
                }
                if member.declName.baseName.text == "expectDeadlock", override.arguments.count == 1 {
                    scenario.deadlockExpectations.append(expected)
                } else if member.declName.baseName.text == "expect", override.arguments.count == 2,
                          let first = override.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
                          let property = specBindings.properties[first.baseName.text] {
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
