import SwiftParser
import SwiftSyntax
import SwiftTLA

private let nativeBoolType = "SwiftTLA.TLAValue.BooleanLiteralType"

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
    _ declaration: DeclSyntax?, actionID: Int, parameters: String, arguments: String,
    configurationParameters: String, configurationArguments: String
) throws {
    let expected = Parser.parse(source: """
    private static func _visitSuccessors\(actionID)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(configurationParameters), checking context: inout CheckingContext<CheckingRegisters>?,
                                                  _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
        var emitted: [Snapshot] = []
        return try _visitUpdates\(actionID)(from: state\(arguments.isEmpty ? "" : ", " + arguments)\(configurationArguments), checking: &context) { updates in
            let candidate = updates.applying(to: state)
            if !emitted.contains(candidate) {
                emitted.append(candidate)
                try visit(candidate)
            }
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
