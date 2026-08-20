import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA
extension MacroExpander {
    // MARK: - Spec verification code generation
    static func generateSpecTest() -> [DeclSyntax] {
        [DeclSyntax(stringLiteral: """
        public struct VerificationError: Error, CustomStringConvertible {
            public let description: String
            public init(_ description: String) { self.description = description }
        }
        """),
        DeclSyntax(stringLiteral: """
        @discardableResult
        public static func verifySpec() throws -> Int {
            let result = try ModelChecker(compilation: Self.compiledSpecification(), maxStates: Self.verificationStateLimit).check()
            switch result {
            case .ok(let count):
                guard count > 0 else { throw VerificationError("No states found") }
                return count
            case .bounded(_, let outcome):
                switch outcome {
                case .ok(let count):
                    guard count > 0 else { throw VerificationError("No states found") }
                    return count
                default:
                    throw VerificationError("Spec verification failed: \\(result)")
                }
            default:
                throw VerificationError("Spec verification failed: \\(result)")
            }
        }
        """)]
    }
    static func generateTransitionMatrix() -> [DeclSyntax] {
        [DeclSyntax(stringLiteral: """
        private static func _formalTransitionMatrix() throws -> [(from: TLAStateProjection, invocation: TLAActionInvocation, to: TLAStateProjection)] {
            let graph = try ModelChecker(compilation: Self.compiledSpecification(), maxStates: Self.verificationStateLimit).exploreGraph()
            var matrix: [(from: TLAStateProjection, invocation: TLAActionInvocation, to: TLAStateProjection)] = []
            for (fromID, transitions) in graph.transitions {
                guard let fromState = graph.states[fromID] else { continue }
                for t in transitions {
                    guard let toState = graph.states[t.target] else { continue }
                    matrix.append((
                        from: fromState,
                        invocation: t.label.invocation,
                        to: toState
                    ))
                }
            }
            return matrix
        }
        public static func transitionMatrix() throws -> [(from: State, invocation: TLAActionInvocation, to: State)] {
            try _formalTransitionMatrix().map {
                (from: try State(projection: $0.from), invocation: $0.invocation, to: try State(projection: $0.to))
            }
        }
        """)]
    }
    static func generateTransitionsTest(hasActions: Bool) -> [DeclSyntax] {
        if !hasActions { return [] }
        return [DeclSyntax(stringLiteral: """
        public static func verifyTransitions() throws {
            let matrix = try Self._formalTransitionMatrix()
            var verified = Array(repeating: false, count: matrix.count)
            for index in matrix.indices where !verified[index] {
                let (from, invocation, _) = matrix[index]
                let expected = matrix.indices.compactMap { candidate -> TLAStateProjection? in
                    guard matrix[candidate].from == from, matrix[candidate].invocation == invocation else {
                        return nil
                    }
                    verified[candidate] = true
                    return matrix[candidate].to
                }
                var actual = try Self._runtime().successors(invocation, from: from)
                guard actual.count == expected.count else {
                    throw VerificationError("\\(invocation): expected \\(expected.count) successors, got \\(actual.count)")
                }
                for successor in expected {
                    guard let match = actual.firstIndex(of: successor) else {
                        throw VerificationError("\\(invocation): missing successor \\(successor)")
                    }
                    actual.remove(at: match)
                }
            }
        }
        """)]
    }
    static func generateInvariantsTest() -> [DeclSyntax] {
        [DeclSyntax(stringLiteral: """
        public static func verifyInvariants() throws {
            let matrix = try Self._formalTransitionMatrix()
            let runtime = try Self._runtime()
            for (_, invocation, successor) in matrix {
                for outcome in runtime.invariantOutcomes(in: successor) {
                    switch outcome {
                    case .satisfied:
                        continue
                    case .violated(let name):
                        throw VerificationError("\\(name) violated by \\(invocation)")
                    case .evaluationFailed(let name, let diagnostic), .evaluationUnavailable(let name, let diagnostic):
                        throw VerificationError("\\(name) could not be evaluated: \\(diagnostic.message)")
                    }
                }
            }
        }
        """)]
    }
    static func literalExpr(for initial: TLAValue) -> String {
        switch initial {
        case .int(let v): "\(v)"
        case .bool(let v): "\(v)"
        case .string(let v): "\"\(v)\""
        case .set(let v): "[\(v.map(String.init).joined(separator: ", "))]"
        default: "0"
        }
    }
    // MARK: - Helpers
    static func swiftType(for initial: TLAValue) -> String {
        switch initial {
        case .int: "Int"
        case .bool: "Bool"
        case .string: "String"
        case .set: "Set<Int>"
        case .tuple: "[TLAValue]"
        case .record: "[String: TLAValue]"
        case .function: "[TLAValue: TLAValue]"
        case .constant: "String"
        }
    }
    static func stateType(for variable: MachineSurfacePlan.Variable, enumInfos: [ParsedEnumInfo]) -> String {
        let type = variable.swiftType
        if ["Int", "Bool", "String", "TLAValue"].contains(type) { return type }
        if enumInfos.contains(where: { $0.typeName == type }) { return type }
        if type.hasPrefix("Record<") || type.hasPrefix("Function<") || type.hasPrefix("SetExpr<") {
            return type
        }
        return "TLAValue"
    }
    static func extractor(for initial: TLAValue) -> String {
        switch initial {
        case .int:
            return "intValue"
        case .bool:
            return "boolValue"
        case .string:
            return "stringValue"
        case .set:
            return "intSetValue"
        case .tuple:
            return "tupleValue"
        case .record:
            return "recordValue"
        case .function:
            return "functionValue"
        case .constant:
            return "stringValue"
        }
    }
    static func extractor(forSwiftType swiftType: String) -> String {
        switch swiftType {
        case "Int": "intValue"
        case "Bool": "boolValue"
        case "String": "stringValue"
        case "TLAValue": ""
        default: "intValue"
        }
    }
    static func constructor(forSwiftType swiftType: String, value: String) -> String {
        switch swiftType {
        case "Int": ".int(\(value))"
        case "Bool": ".bool(\(value))"
        case "String": ".string(\(value))"
        case "TLAValue": value
        default: ".int(0)"
        }
    }
    static func constructor(for initial: TLAValue, value: String) -> String {
        switch initial {
        case .int:
            return ".int(\(value))"
        case .bool:
            return ".bool(\(value))"
        case .string:
            return ".string(\(value))"
        case .set:
            return ".set(Set(\(value).map { .int($0) }))"
        case .tuple:
            return ".tuple(\(value))"
        case .record:
            return ".record(\(value))"
        case .function:
            return ".function(\(value))"
        case .constant:
            return ".constant(\(value))"
        }
    }
}
