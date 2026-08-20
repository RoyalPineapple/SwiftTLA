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
    static func generateTransitionsTest(hasActions: Bool) -> [DeclSyntax] {
        if !hasActions { return [] }
        return [DeclSyntax(stringLiteral: """
        public static func verifyTransitions() throws -> Int {
            try Self._verifiedGeneratedMachineContract().transitionCount
        }
        """)]
    }
    static func generateInvariantsTest() -> [DeclSyntax] {
        [DeclSyntax(stringLiteral: """
        public static func verifyInvariants() throws -> Int {
            try Self._verifiedGeneratedMachineContract().invariantCheckCount
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
        case .record: "TLARecord"
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
