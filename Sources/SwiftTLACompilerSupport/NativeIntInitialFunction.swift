import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA

private let nativeIntType = nativeIntTypeTokens.joined()
private let nativeBoolType = "SwiftTLA.TLAValue.BooleanLiteralType"

package func nativeSourceIdentifier(_ name: String) throws -> String {
    let tokens = Parser.parse(source: name).tokens(viewMode: .sourceAccurate).filter {
        $0.tokenKind != .endOfFile
    }
    guard tokens.count == 1, let token = tokens.first, token.text == name, name != "_" else {
        throw invalidSourceIdentifier(name)
    }
    switch token.tokenKind {
    case .identifier: return name
    case .keyword: return "`\(name)`"
    default: throw invalidSourceIdentifier(name)
    }
}

private func invalidSourceIdentifier(_ name: String) -> CompilationDiagnostic {
    CompilationDiagnostic(
        code: .unsupportedGeneratedValueShape,
        stage: .validation,
        path: "generatedMachineAPI.identifiers.\(name)",
        expected: "one named Swift identifier for a generated state field or action parameter",
        actual: name,
        nextSafeAction: "Choose a named Swift identifier; formal action labels may use arbitrary names."
    )
}

@discardableResult
package func verifyNativeIntInitialOutput(_ declaration: DeclSyntax?, program: CompiledProgram,
    variables: [(id: VariableID, swiftIdentifier: String)]) throws -> [VariableID: [NativeIntInitialStep]]? {
    guard let source = try intInitialOutputSource(declaration, program: program, variables: variables) else { return nil }
    // Template lines have complete lexemes; parse them separately to avoid recursive closure nesting.
    let expectedTokens = source.split(separator: "\n").flatMap { line in
        Parser.parse(source: String(line)).tokens(viewMode: .sourceAccurate)
            .filter { $0.tokenKind != .endOfFile }
    }
    let actualTokens = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)) } ?? []
    func sameToken(_ actual: TokenSyntax, _ expected: TokenSyntax) -> Bool {
        guard actual.text.utf8.elementsEqual(expected.text.utf8) else { return false }
        if actual.tokenKind == expected.tokenKind { return true }
        // Fragment parsing can leave generic angle delimiters classified as operators.
        switch (actual.tokenKind, expected.tokenKind) {
        case (.leftAngle, .binaryOperator), (.leftAngle, .prefixOperator),
             (.leftAngle, .postfixOperator), (.rightAngle, .binaryOperator),
             (.rightAngle, .prefixOperator), (.rightAngle, .postfixOperator),
             (.binaryOperator, .leftAngle), (.prefixOperator, .leftAngle),
             (.postfixOperator, .leftAngle), (.binaryOperator, .rightAngle),
             (.prefixOperator, .rightAngle), (.postfixOperator, .rightAngle):
            return true
        default: return false
        }
    }
    guard declaration?.is(FunctionDeclSyntax.self) == true,
          actualTokens.elementsEqual(expectedTokens, by: sameToken) else {
        let detail = zip(actualTokens, expectedTokens).enumerated()
            .first { !sameToken($0.element.0, $0.element.1) }
            .map { "token \($0.offset): expected \($0.element.1.tokenKind), actual \($0.element.0.tokenKind)" }
            ?? "token counts: expected \(expectedTokens.count), actual \(actualTokens.count)"
        throw intInitialOutputMismatch(actual: detail)
    }
    let slots = nativeVariableSlots(program.layout)
    var decoded: [VariableID: [NativeIntInitialStep]] = [:]
    for initialization in program.behavior.initializations {
        guard case .value(let expression) = initialization.initialization,
              expression.resultType == .int else { continue }
        decoded[initialization.variable] = try verifyOrderedIntInitialExpression(declaration,
            named: slots[initialization.variable]!, expression: expression, slots: slots)
    }
    return decoded
}

private func intInitialOutputMismatch(
    actual: String = "the generated initial function contains an unrecognized statement or changed value"
) -> CompilationDiagnostic {
    CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
        path: "native._initialStates.completeIntOutput",
        expected: "the complete ordered Int initial-state and failure template",
        actual: actual,
        nextSafeAction: "Report this native initialization generation failure.")
}

private func intInitialOutputSource(_ declaration: DeclSyntax?, program: CompiledProgram,
    variables: [(id: VariableID, swiftIdentifier: String)]) throws -> String? {
    // shortcut: other domain/child operations, configuration and invariant selection need their own rules.
    guard program.layout.parameters.isEmpty, program.behavior.initialInvariant == nil,
          program.behavior.initializations.count == program.layout.variables.count else { return nil }
    let allocated = nativeVariableSlots(program.layout)
    func variable(_ id: VariableID) -> String { allocated[id]! }
    var bindings: [(name: String, type: String, value: String)] = []
    let slots = Dictionary(uniqueKeysWithValues: program.layout.variables.map {
        ($0.id, variable($0.id))
    })
    for initialization in program.behavior.initializations {
        let value: String
        let type: String
        switch initialization.initialization {
        case .value(let expression):
            switch (expression.operation, expression.resultType) {
            case (.value(.integer(let integer)), .int):
                type = nativeIntType
                value = integer == Int.min ? "\(nativeIntType).min" : String(integer)
            case (.controlLocation(let location), .controlLocation):
                type = "_ControlLocation"
                value = "_ControlLocation.location\(location.ordinal)"
            case (_, .int):
                guard let checked = checkedIntInitialValue(expression, slots: slots) else { return nil }
                type = nativeIntType
                value = checked
            default: return nil
            }
        case .memberOf(let domain):
            guard program.variableTypes[initialization.variable] == .int,
                  domain.resultType == .set(.int),
                  let checked = checkedIntInitialDomainValue(domain, slots: slots) else { return nil }
            type = nativeIntType
            value = checked
        }
        bindings.append((variable(initialization.variable), type, value))
    }
    let actualTokens = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) } ?? []
    let predicatePrefix = "_membershipPredicate"
    let predicateNames = actualTokens.indices.compactMap { index -> String? in
        guard actualTokens[index] == "func", index + 1 < actualTokens.count,
              actualTokens[index + 1].hasPrefix(predicatePrefix) else { return nil }
        return actualTokens[index + 1]
    }
    guard Set(predicateNames).count == predicateNames.count,
          predicateNames.allSatisfy({ name in
              Int(name.dropFirst(predicatePrefix.count)).map { $0 >= 0 } == true
          }) else { throw intInitialOutputMismatch() }
    var nextPredicate = 0
    let visible = Dictionary(uniqueKeysWithValues: variables.map {
        ($0.id, $0.swiftIdentifier)
    })
    let publicFields = variables.map {
        "\($0.swiftIdentifier.replacingOccurrences(of: "`", with: "")): \(variable($0.id))"
    }.joined(separator: ", ")
    let hiddenFields = program.layout.variables.filter { visible[$0.id] == nil }.map {
        ", \(variable($0.id)): \(variable($0.id))"
    }.joined()
    var body = "var result: [Snapshot] = []\nvar failures: [SwiftTLA.InitialEvaluationFailure] = []\nvar evaluatingInitializerOrdinal: \(nativeIntType)?\nvar evaluatingInitialBindings: @Sendable () throws -> SwiftTLA.TLAStateProjection = { try SwiftTLA._nativeFormalProjection([]) }\n"
    body += "try SwiftTLA._visitNativeInitialBranch({\n"
    var closing = ""
    for (index, pair) in zip(program.behavior.initializations, bindings).enumerated() {
        let (initialization, binding) = pair
        let prefix = zip(program.behavior.initializations, bindings).prefix(index)
        let captures = prefix.map { $0.1.name }
        let entries = prefix.map { prior, binding -> String in
            let value: String
            if binding.type == nativeIntType {
                value = "SwiftTLA._nativeFormalInt(\(binding.name))"
            } else {
                let cases = program.layout.controlLocations.map {
                    "case .location\($0.id.ordinal): return .string(\(String(reflecting: $0.formalName)))"
                }.joined(separator: "\n")
                value = "try { () throws -> SwiftTLA.TLAValue in switch \(binding.name) {\n\(cases)\n} }()"
            }
            return ".init(token: SwiftTLA._nativeFormalProjectionToken(Self.__swifttlaFormalProjectionTokens, at: \(prior.variable.ordinal)), value: \(value))"
        }
        let capture = captures.isEmpty ? "" : "[" + captures.joined(separator: ", ") + "] in "
        body += "evaluatingInitialBindings = { \(capture)try SwiftTLA._nativeFormalProjection([\(entries.joined(separator: ", "))]) }\n"
        body += "evaluatingInitializerOrdinal = \(initialization.variable.ordinal)\n"
        switch initialization.initialization {
        case .value:
            body += "let \(binding.name): \(binding.type) = \(binding.value)\n"
            body += "evaluatingInitializerOrdinal = nil\n"
            if let field = visible[initialization.variable] {
                let condition = binding.type == nativeIntType
                    ? "SwiftTLA._nativeIntInitialMatches(_selectedInitial?.\(field), \(binding.name))"
                    : "_selectedInitial == nil || _selectedInitial!.\(field) == \(binding.name)"
                body += "if \(condition) {\n"
                closing = "}\n" + closing
            }
        case .memberOf(let domain):
            let ordered = "\(binding.value).sorted(by: { (lhs: \(nativeIntType), rhs: \(nativeIntType)) -> \(nativeBoolType) in\nreturn lhs < rhs\n})"
            if let field = visible[initialization.variable] {
                guard let membership = checkedIntInitialDomainMembership(domain, candidate: binding.name,
                    slots: slots, predicateNames: predicateNames, nextPredicate: &nextPredicate) else {
                    throw intInitialOutputMismatch()
                }
                body += """
                let \(binding.name)Candidates: [\(nativeIntType)] = try SwiftTLA._NativeMachineOperations.initialCandidates(
                    selecting: _selectedInitial.map(\\.\(field)),
                    enumerate: { \(ordered) },
                    contains: { \(binding.name) in
                    let \(binding.name)_isMember = \(membership)
                    return \(binding.name)_isMember
                    }
                )
                for \(binding.name) in \(binding.name)Candidates {

                """
            } else {
                body += "for \(binding.name) in \(ordered) {\n"
            }
            body += "evaluatingInitializerOrdinal = nil\ntry SwiftTLA._visitNativeInitialBranch({\n"
            closing = """
            }, onEvaluationFailure: { failure in
                SwiftTLA._appendNativeOutcome(&failures, .init(
                    site: SwiftTLA._nativeInitialFailureSite(evaluatingInitializerOrdinal),
                    failure: failure, projectingBefore: evaluatingInitialBindings))
            })
            }

            """ + closing
        }
    }
    body += "SwiftTLA._appendNativeOutcome(&result, Snapshot(state: State(\(publicFields))\(hiddenFields)))\n" + closing
    body += """
    }, onEvaluationFailure: { failure in
        SwiftTLA._appendNativeOutcome(&failures, .init(
            site: SwiftTLA._nativeInitialFailureSite(evaluatingInitializerOrdinal),
            failure: failure, projectingBefore: evaluatingInitialBindings))
    })
    return SwiftTLA._nativeInitialOutcomes(states: result, failures: failures)
    """
    guard nextPredicate == predicateNames.count else { throw intInitialOutputMismatch() }
    return """
    private static func _initialStates(_selectedInitial: State? = nil) throws -> SwiftTLA.InitialEvaluationOutcomes<Snapshot> {
        \(body)
    }
    """
}

private func checkedIntInitialDomainValue(_ root: CompiledExpression,
                                          slots: [VariableID: String]) -> String? {
    var pending = [(root, false)]
    var values: [String] = []
    while let (node, expanded) = pending.popLast() {
        if node.resultType == .int {
            guard let value = checkedIntInitialValue(node, slots: slots) else { return nil }
            values.append(value)
            continue
        }
        let types: [CompiledValueType]
        switch (node.operation, node.resultType) {
        case (.integerSet, .set(.int)) where node.children.isEmpty: types = []
        case (.equal, .bool) where node.children.count == 2: types = [.int, .int]
        case (.integerRange, .set(.int)) where node.children.count == 2: types = [.int, .int]
        case (.setLiteral, .set(.int)): types = node.children.map { _ in .int }
        case (.ifThenElse, .set(.int)) where node.children.count == 3:
            types = [.bool, .set(.int), .set(.int)]
        default: return nil
        }
        guard zip(node.children, types).allSatisfy({ $0.0.resultType == $0.1 }) else { return nil }
        if !expanded {
            pending.append((node, true))
            pending.append(contentsOf: node.children.reversed().map { ($0, false) })
            continue
        }
        guard values.count >= types.count else { return nil }
        let children = Array(values.suffix(types.count))
        values.removeLast(types.count)
        let value: String
        switch node.operation {
        case .integerSet: value = "(try SwiftTLA._NativeMachineOperations.integerSet())"
        case .equal: value = "(\(children[0]) == \(children[1]))"
        case .integerRange:
            value = "(try SwiftTLA._NativeMachineOperations.integerRange(\(children[0]), \(children[1])))"
        case .setLiteral: value = "Set<\(nativeIntType)>([\(children.joined(separator: ", "))])"
        case .ifThenElse: value = "(\(children[0]) ? \(children[1]) : \(children[2]))"
        default: return nil
        }
        values.append(value)
    }
    return values.count == 1 ? values[0] : nil
}

private func checkedIntInitialDomainMembership(_ root: CompiledExpression, candidate: String,
                                               slots: [VariableID: String], predicateNames: [String],
                                               nextPredicate: inout Int) -> String? {
    var nodes = [root]
    var symbolic = false
    while let node = nodes.popLast() {
        if node.operation == .integerRange || node.operation == .integerSet { symbolic = true; break }
        nodes.append(contentsOf: node.children)
    }
    if !symbolic {
        return checkedIntInitialDomainValue(root, slots: slots).map { "(\($0).contains(\(candidate)))" }
    }
    var pending: [(CompiledExpression, String?)] = [(root, nil)]
    var values: [(declaration: String, call: String)] = []
    while let (node, assignedName) = pending.popLast() {
        guard let name = assignedName else {
            guard nextPredicate < predicateNames.count else { return nil }
            let name = predicateNames[nextPredicate]
            nextPredicate += 1
            pending.append((node, name))
            if case .ifThenElse = node.operation {
                guard node.children.count == 3 else { return nil }
                pending.append((node.children[2], nil))
                pending.append((node.children[1], nil))
            }
            continue
        }
        let body: String
        switch node.operation {
        case .integerSet:
            guard node.children.isEmpty, node.resultType == .set(.int) else { return nil }
            body = "return { _ in true }"
        case .integerRange:
            guard node.children.count == 2,
                  let lower = checkedIntInitialDomainValue(node.children[0], slots: slots),
                  let upper = checkedIntInitialDomainValue(node.children[1], slots: slots) else { return nil }
            body = """
            let bounds = (\(lower), \(upper))
            return { candidate in bounds.0 <= candidate && candidate <= bounds.1 }
            """
        case .setLiteral:
            guard let members = checkedIntInitialDomainValue(node, slots: slots) else { return nil }
            body = "let members = \(members)\nreturn { members.contains($0) }"
        case .ifThenElse:
            guard node.children.count == 3, values.count >= 2,
                  let condition = checkedIntInitialDomainValue(node.children[0], slots: slots) else { return nil }
            let second = values.removeLast()
            let first = values.removeLast()
            body = """
            \(first.declaration)
            \(second.declaration)
            if \(condition) { return \(first.call) }
            return \(second.call)
            """
        default: return nil
        }
        values.append(("func \(name)() throws -> ((\(nativeIntType)) -> \(nativeBoolType)) {\n\(body)\n}", "try \(name)()"))
    }
    guard values.count == 1, let predicate = values.first else { return nil }
    return """
    (try { () throws -> \(nativeBoolType) in
        \(predicate.declaration)
        let contains = \(predicate.call)
        let candidate = \(candidate)
        return contains(candidate)
    }())
    """
}

package func checkedIntInitialValue(_ root: CompiledExpression,
                                    slots: [VariableID: String]) -> String? {
    let arithmetic: Bool
    if case .add = root.operation { arithmetic = true } else { arithmetic = false }
    var pending = [(root, false)]
    var values: [String] = []
    var statements: [String] = []
    while let (node, expanded) = pending.popLast() {
        guard node.resultType == .int else { return nil }
        let value: String
        switch node.operation {
        case .add:
            guard node.children.count == 2 else { return nil }
            if !expanded {
                pending.append((node, true))
                pending.append((node.children[1], false))
                pending.append((node.children[0], false))
                continue
            }
            guard values.count >= 2 else { return nil }
            let rhs = values.removeLast()
            let lhs = values.removeLast()
            value = "try SwiftTLA._nativeIntAdd(\(lhs), \(rhs))"
        case .stateVariable(let id):
            guard node.children.isEmpty, let slot = slots[id] else { return nil }
            value = slot
        case .value(.integer(let integer)):
            guard node.children.isEmpty else { return nil }
            value = integer == Int.min ? "\(nativeIntType).min" : String(integer)
        default: return nil
        }
        if arithmetic {
            let name = "_arithmetic\(statements.count)"
            statements.append("let \(name): \(nativeIntType) = \(value)")
            values.append(name)
        } else {
            values.append(value)
        }
    }
    guard values.count == 1, let value = values.first else { return nil }
    if !arithmetic { return value }
    return "(try { () throws -> \(nativeIntType) in\n\(statements.joined(separator: "\n"))\nreturn \(value)\n}())"
}
