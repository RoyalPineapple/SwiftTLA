import SwiftParser
import SwiftSyntax
import SwiftTLA

private let nativeBoolType = "SwiftTLA.TLAValue.BooleanLiteralType"

package func verifyGeneratedPublicSendOutput(_ declarations: [DeclSyntax]) throws {
    func tokens(_ source: String) -> [String] {
        Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
            .filter { $0.tokenKind != .endOfFile }.map(\.text)
    }
    func invalid(_ path: String, _ expected: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation, path: path,
            expected: expected, actual: "the emitted action route or label differs",
            nextSafeAction: "Report this native action routing failure."
        )
    }
    let methods = declarations.compactMap { $0.as(FunctionDeclSyntax.self) }
    let successorWrappers = methods.filter {
        $0.name.text == "_successors"
            && $0.signature.parameterClause.parameters.first?.firstName.text == "for"
    }
    let expectedSuccessorWrappers = [
        """
        private func _successors(for action: Action) throws -> [Snapshot] {
            var context: CheckingContext<CheckingRegisters>?
            return try _successors(for: action, checking: &context)
        }
        """,
        """
        private func _successors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?) throws -> [Snapshot] {
            var result: [Snapshot] = []
            let failures = try _visitSuccessors(for: action, checking: &context) { SwiftTLA._appendNativeOutcome(&result, $0) }
            if let failure = SwiftTLA._firstNativeEvaluationFailure(failures) { throw failure }
            return result
        }
        """,
    ]
    guard successorWrappers.count == expectedSuccessorWrappers.count,
          expectedSuccessorWrappers.allSatisfy({ expected in
              successorWrappers.filter {
                  Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) == tokens(expected)
              }.count == 1
          }) else {
        throw invalid("native.action.successorRoute", "both wrappers preserve the complete successor list")
    }
    let outcomes = declarations.compactMap { $0.as(EnumDeclSyntax.self) }.filter { $0.name.text == "_SendOutcome" }
    let collectors = methods.filter { $0.name.text == "_sendOutcome" }
    guard outcomes.count == 1, collectors.count == 1,
          Array(outcomes[0].tokens(viewMode: .sourceAccurate)).map(\.text) == tokens("""
        private enum _SendOutcome {
            case none, one(Snapshot), many

            mutating func record(_ candidate: Snapshot) {
                switch self {
                case .none: self = .one(candidate)
                case .one, .many: self = .many
                }
            }

            func selected(missing: GeneratedMachineError, ambiguous: GeneratedMachineError) throws -> Snapshot {
                switch self {
                case .none: throw missing
                case .many: throw ambiguous
                case .one(let first): return first
                }
            }
        }
        """),
          Array(collectors[0].tokens(viewMode: .sourceAccurate)).map(\.text) == tokens("""
        private func _sendOutcome(for action: Action) throws -> _SendOutcome {
            var context: CheckingContext<CheckingRegisters>?
            var result: _SendOutcome = .none
            let failures = try _visitSuccessors(for: action, checking: &context) { result.record($0) }
            if let failure = SwiftTLA._firstNativeEvaluationFailure(failures) { throw failure }
            return result
        }
        """) else {
        throw invalid("native.action.sendCollector", "retain only the first candidate and drain failures before selection")
    }
    let send = methods.filter { $0.name.text == "send" }
    let expectedSend = tokens("""
        public mutating func send(_ action: Action) throws -> Transition {
            let next = try _sendOutcome(for: action).selected(missing: .noMatchingSuccessor, ambiguous: .ambiguousAction)
            let before = state
            _execution = next
            return Transition(action: action, before: before, after: state)
        }
        """)
    guard send.count == 1,
          Array(send[0].tokens(viewMode: .sourceAccurate)).map(\.text) == expectedSend else {
        throw invalid("native.action.send", "the public send applies exactly one selected successor")
    }
}

package func verifyGeneratedValidationDelegationOutput(_ declaration: DeclSyntax?) throws {
    let expected = Parser.parse(source: """
    public func visitValidationOutcomes(checking context: inout CheckingContext<CheckingRegisters>,
                                        _ visit: (Action, Self) throws -> \(nativeBoolType),
                                        onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) {
        var run: CheckingContext<CheckingRegisters>? = context
        defer { context = run! }
        return try _visitSuccessors(checking: &run, visit, onEvaluationFailure: onEvaluationFailure)
    }
    """).statements.first?.item.as(FunctionDeclSyntax.self)
    guard let actual = declaration?.as(FunctionDeclSyntax.self), let expected,
          Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expected.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.validation.delegation",
            expected: "forward every successor and exact action failure through the generated checking entry point",
            actual: "the emitted validation entry point differs from the checked rule",
            nextSafeAction: "Report this native validation generation failure."
        )
    }
}

package func verifyGeneratedSuccessorOutput(
    _ declaration: DeclSyntax?, body: CompiledActionExpr, actionID: Int, parameters: String, arguments: String,
    configurationParameters: String, configurationArguments: String
) throws {
    let single = body.emitsAtMostOneCandidate
    let callback = single ? "try visit(updates.applying(to: state))" : """
    let candidate = updates.applying(to: state)
    if !emitted.contains(candidate) {
        emitted.append(candidate)
        try visit(candidate)
    }
    """
    let expected = Parser.parse(source: """
    private static func _visitSuccessors\(actionID)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(configurationParameters), checking context: inout CheckingContext<CheckingRegisters>?,
                                                  _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
        \(single ? "" : "var emitted: [Snapshot] = []")
        return try _visitUpdates\(actionID)(from: state\(arguments.isEmpty ? "" : ", " + arguments)\(configurationArguments), checking: &context) { updates in
            \(callback)
        }
    }
    """).statements.first?.item.as(FunctionDeclSyntax.self)
    guard let actual = declaration?.as(FunctionDeclSyntax.self), let expected,
          Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expected.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.action.successor.\(actionID)",
            expected: "apply every complete compiled update and visit each resulting snapshot once",
            actual: "the emitted successor wrapper differs from the checked rule",
            nextSafeAction: "Report this native successor generation failure."
        )
    }
}

package func nativeOrderedIntAssignmentFailureSource(actionOrdinal: Int, preceding: [String]) -> String {
    "SwiftTLA._recordNativeOrderedIntAssignmentFailure(&context, actionOrdinal: \(actionOrdinal), "
        + "assignmentOrdinal: \(preceding.count + 1), preceding: [\(preceding.joined(separator: ", "))], reason: failure)"
}

private func nativeAlternativeFailureRecordingSource(regions: [AlternativeFailureRegion], site: BinderID,
    action: Int, lexical: [String], program: CompiledProgram) -> String? {
    func recording(in region: AlternativeFailureRegion, at position: Int, prefix: String) -> String? {
        guard lexical.count == position else { return nil }
        let before = zip(region.bindings.prefix(position), lexical).compactMap { origin, local -> String? in
            guard let name = program.binderNames[origin.binder], "_\(name)_\(origin.binder.ordinal)" == local else {
                return nil
            }
            return "(binding: \(origin.binder.ordinal), target: \(origin.target.ordinal), value: \(local))"
        }
        guard before.count == position else { return nil }
        return prefix + "site: \(site.ordinal), target: \(region.bindings[position].target.ordinal), "
            + "before: [\(before.joined(separator: ", "))], reason: failure)"
    }
    if let region = regions.first, let position = region.sharedIndex(of: site) {
        return recording(in: region, at: position,
            prefix: "SwiftTLA._recordNativeSharedPrefixFailure(&context, action: \(action), ")
    }
    for region in regions {
        guard let position = region.index(of: site) else { continue }
        return recording(in: region, at: position,
            prefix: "SwiftTLA._recordNativeAlternativeFailure(&context, action: \(action), branch: \(region.armOrdinal), ")
    }
    return nil
}

package func nativeActionFailureRecordingSource(value: CompiledExpression, site: BinderID, action: ActionID,
    lexical: [String], regions: [AlternativeFailureRegion], program: CompiledProgram,
    projectedPreceding: [String]? = nil) -> String? {
    let addition = value.operation == .add && value.resultType == .int
    if addition || value.isObservedAlternativeIntegerOperation,
       let branch = nativeAlternativeFailureRecordingSource(regions: regions, site: site,
           action: action.ordinal, lexical: lexical, program: program) {
        return branch
    }
    guard addition, program.requiresOrderedIntOutput(action) || projectedPreceding != nil else { return nil }
    return nativeOrderedIntAssignmentFailureSource(actionOrdinal: action.ordinal, preceding: projectedPreceding ?? lexical)
}
