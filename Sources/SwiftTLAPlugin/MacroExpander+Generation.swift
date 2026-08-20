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
                        from: try TLAStateProjection(formalValues: fromState),
                        invocation: t.label.invocation,
                        to: try TLAStateProjection(formalValues: toState)
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
                var actual = try Self.runtime.successors(invocation, from: from)
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
            let runtime = Self.runtime
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
    // MARK: - Observable code generation
    static func generateObservableMembers(
        typeName: String,
        plan: MachineSurfacePlan,
        enumInfos: [ParsedEnumInfo] = []
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []
        for action in plan.actions {
            let callbackName = "on" + action.swiftIdentifier.prefix(1).capitalized + action.swiftIdentifier.dropFirst()
            let callbackType: String
            let bindings = action.bindings.filter(\.isPublic)
            if !bindings.isEmpty {
                let parameterTypes = bindings.map(\.swiftType).joined(separator: ", ")
                callbackType = "(@Sendable (\(parameterTypes), State, State) -> Void)?"
            } else {
                callbackType = "(@Sendable (State, State) async -> Void)?"
            }
            decls.append(DeclSyntax(stringLiteral: "private let _\(callbackName) = LockedValue<\(callbackType)>(nil)"))
            decls.append(DeclSyntax(stringLiteral: """
            public var \(callbackName): \(callbackType) {
                get { _\(callbackName).value }
                set { _\(callbackName).value = newValue }
            }
            """))
        }
        decls.append(DeclSyntax(generateVariablesEnum(variables: plan.variables)))
        decls.append(DeclSyntax(generateActionsEnum(actions: plan.actions)))
        decls.append(DeclSyntax(generateActionLabel(actions: plan.actions)))
        decls.append(DeclSyntax(generateStateStruct(variables: plan.variables, enumInfos: enumInfos)))
        decls.append(DeclSyntax(stringLiteral: """
        private static func _initialState() -> State {
            do {
                guard let projection = try \(typeName).runtime.initialStateProjections().first else {
                    fatalError("The compiled model has no initial state.")
                }
                return try State(projection: projection)
            } catch {
                fatalError(String(describing: error))
            }
        }
        """))
        decls.append(DeclSyntax(stringLiteral: """
        private let _machine = CanonicalMachineStorage(CanonicalMachine(
            runtime: \(typeName).runtime,
            initial: Self._initialState(),
            projectionForSnapshot: { try $0.formalProjection() },
            snapshotFromProjection: { try State(projection: $0) }
        ))
        """))
        decls.append(contentsOf: generateCanonicalMachineMembers(
            isActor: true,
            hasActions: !plan.actions.isEmpty
        ))
        decls.append(contentsOf: generateVariableProperties(variables: plan.variables, enumInfos: enumInfos).map(DeclSyntax.init))
        decls.append(contentsOf: generateObservableActionMethods(actions: plan.actions).map(DeclSyntax.init))
        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "runtime"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "SpecRuntime")),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "do { return try SpecRuntime(compilation: compiledSpecification()) } catch { fatalError(String(describing: error)) }") }
                    ))
                )]
            )
        ))
        return decls
    }
    static func generateObservableActionMethods(
        actions: [MachineSurfacePlan.Action]
    ) -> [FunctionDeclSyntax] {
        return actions.map { action in
            let identifier = action.swiftIdentifier
            let callbackName = "on" + identifier.prefix(1).capitalized + identifier.dropFirst()
            let bindings = action.bindings.filter(\.isPublic)
            if !bindings.isEmpty {
                let parameters = bindings.map { binding in
                    "\(binding.formalName): \(binding.swiftType)"
                }.joined(separator: ", ")
                let callbackArguments = bindings.map(\.formalName).joined(separator: ", ")
                let source = """
                public func _\(identifier)(\(parameters)) throws -> TransitionResult {
                    let evidence = try apply(.\(identifier)(\(bindings.map { "\($0.formalName): \($0.formalName)" }.joined(separator: ", "))))
                    if let h = \(callbackName) { h(\(callbackArguments), evidence.before, evidence.after) }
                    return evidence
                }
                """
                return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
            }
            let source = """
                public func _\(identifier)() throws -> TransitionResult {
                let evidence = try apply(.\(identifier))
                if let h = \(callbackName) { Task { await h(evidence.before, evidence.after) } }
                return evidence
            }
            """
            return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
        }
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
