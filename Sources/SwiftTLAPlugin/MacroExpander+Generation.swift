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
            let result = try ModelChecker(spec: Self.spec, maxStates: Self.verificationStateLimit).check()
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
        private static func _formalTransitionMatrix() throws -> [(from: [String: TLAValue], invocation: TLAActionInvocation, to: [String: TLAValue])] {
            let graph = try ModelChecker(spec: Self.spec, maxStates: Self.verificationStateLimit).exploreGraph()
            var matrix: [(from: [String: TLAValue], invocation: TLAActionInvocation, to: [String: TLAValue])] = []
            for (fromID, transitions) in graph.transitions {
                guard let fromState = graph.states[fromID] else { continue }
                for t in transitions {
                    guard let toState = graph.states[t.target] else { continue }
                    matrix.append((from: fromState, invocation: t.label.invocation, to: toState))
                }
            }
            return matrix
        }
        public static func transitionMatrix() throws -> [(from: State, invocation: TLAActionInvocation, to: State)] {
            try _formalTransitionMatrix().map {
                (from: try State(formalDictionary: $0.from), invocation: $0.invocation, to: try State(formalDictionary: $0.to))
            }
        }
        """)]
    }
    static func generateTransitionsTest(_ actions: [SpecParser.ParsedAction]) -> [DeclSyntax] {
        if actions.isEmpty { return [] }
        return [DeclSyntax(stringLiteral: """
        public static func verifyTransitions() throws {
            let matrix = try Self._formalTransitionMatrix()
            var verified = Array(repeating: false, count: matrix.count)
            for index in matrix.indices where !verified[index] {
                let (from, invocation, _) = matrix[index]
                let expected = matrix.indices.compactMap { candidate -> [String: TLAValue]? in
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
                for inv in runtime.spec.invariants {
                    guard try inv.body.evaluateBool(
                        in: successor,
                        runtimeFuncs: runtime.spec.runtimeFuncs,
                        recursiveFuncs: runtime.spec.recursiveFuncs
                    ) else {
                        throw VerificationError("\\(inv.name) violated by \\(invocation)")
                    }
                }
            }
        }
        """)]
    }
    // MARK: - Observable code generation
    static func generateObservableMembers(
        typeName: String,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        actions: [SpecParser.ParsedAction],
        enumInfos: [ParsedEnumInfo] = []
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []
        let actionIdentifiers = generatedActionIdentifiers(actions: actions)
        for (a, identifier) in zip(actions, actionIdentifiers) {
            let callbackName = "on" + identifier.prefix(1).capitalized + identifier.dropFirst()
            let callbackType: String
            if !a.bindings.isEmpty {
                let parameterTypes = a.bindings.map { swiftType(for: a, binding: $0) }.joined(separator: ", ")
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
        decls.append(DeclSyntax(generateVariablesEnum(variables: variables)))
        decls.append(DeclSyntax(generateActionsEnum(actions: actions)))
        decls.append(DeclSyntax(generateActionLabel(actions: actions)))
        decls.append(DeclSyntax(generateStateStruct(variables: variables, enumInfos: enumInfos)))
        decls.append(DeclSyntax(stringLiteral: """
        private let _machine = CanonicalMachineStorage(CanonicalMachine(
            runtime: \(typeName).runtime,
            initial: try! State(formalDictionary: \(typeName).runtime.initialStates().first!),
            stateDictionary: { $0.asDictionary },
            snapshotFromDictionary: { try State(formalDictionary: $0) }
        ))
        """))
        decls.append(contentsOf: generateCanonicalMachineMembers(
            isActor: true,
            hasActions: !actions.isEmpty
        ))
        decls.append(contentsOf: generateVariableProperties(variables: variables, enumInfos: enumInfos).map(DeclSyntax.init))
        decls.append(contentsOf: generateObservableActionMethods(variables: variables, actions: actions).map(DeclSyntax.init))
        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "runtime"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "SpecRuntime")),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "SpecRuntime(spec: spec)") }
                    ))
                )]
            )
        ))
        return decls
    }
    static func generateObservableActionMethods(
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        actions: [SpecParser.ParsedAction]
    ) -> [FunctionDeclSyntax] {
        let identifiers = generatedActionIdentifiers(actions: actions)
        return zip(actions, identifiers).map { a, identifier in
            let callbackName = "on" + identifier.prefix(1).capitalized + identifier.dropFirst()
            if !a.bindings.isEmpty {
                let parameters = a.bindings.map { binding in
                    "\(binding.name): \(swiftType(for: a, binding: binding))"
                }.joined(separator: ", ")
                let callbackArguments = a.bindings.map(\.name).joined(separator: ", ")
                let source = """
                public func _\(identifier)(\(parameters)) throws -> TransitionResult {
                    let evidence = try apply(.\(identifier)(\(a.bindings.map { "\($0.name): \($0.name)" }.joined(separator: ", "))))
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
    static func tlaValueConstructor(for swiftType: String, value: String) -> String {
        switch swiftType {
        case "Int": return ".int(\(value))"
        case "Bool": return ".bool(\(value))"
        default: return ".string(\(value))"
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
    static func generateCallbackProtocol(typeName: String, actions: [SpecParser.ParsedAction]) throws -> [DeclSyntax] {
        let protoName = "\(typeName)Actions"
        var callbackDecls: [String] = []
        var defaultDecls: [String] = []
        for (_, identifier) in zip(actions, generatedActionIdentifiers(actions: actions)) {
            let callbackName = "on" + identifier.prefix(1).capitalized + identifier.dropFirst()
            callbackDecls.append("func \(callbackName)()")
            defaultDecls.append("""
                func \(callbackName)() {
                    runtimeWarning("\(typeName).\(callbackName)() not overridden")
                }
                """)
        }
        let protoCode = """
            protocol \(protoName) {
                \(callbackDecls.joined(separator: "\n    "))
            }
            """
        let extCode = """
            extension \(protoName) {
                \(defaultDecls.joined(separator: "\n    "))
            }
            """
        let conformanceCode = """
            extension \(typeName): \(protoName) {}
            """
        return [
            DeclSyntax(stringLiteral: protoCode),
            DeclSyntax(stringLiteral: extCode),
            DeclSyntax(stringLiteral: conformanceCode)
        ]
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
    static func stateType(for v: (name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?), enumInfos: [ParsedEnumInfo]) -> String {
        let inferred = v.swiftTypeName ?? swiftType(for: v.initial)
        if ["Int", "Bool", "String"].contains(inferred) { return inferred }
        if enumInfos.contains(where: { $0.typeName == inferred }) { return inferred }
        if inferred.hasPrefix("Record<") || inferred.hasPrefix("Function<") || inferred.hasPrefix("SetExpr<") {
            return inferred
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
    // MARK: - Native action codegen
    static func codegenExpr(
        _ expr: StateExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo],
        boundVarName: String? = nil
    ) -> String {
        let forceTLAValue = containsTLAValueField(expr, variables: variables, enumInfos: enumInfos, boundVarName: boundVarName)
        return codegenExprInner(expr, variables: variables, enumInfos: enumInfos, forceTLAValue: forceTLAValue, boundVarName: boundVarName)
    }
    static func codegenExprInner(
        _ expr: StateExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo],
        forceTLAValue: Bool,
        boundVarName: String? = nil
    ) -> String {
        let cg: (StateExpr) -> String = {
            codegenExprInner(
                $0,
                variables: variables,
                enumInfos: enumInfos,
                forceTLAValue: forceTLAValue,
                boundVarName: boundVarName
            )
        }
        switch expr {
        case .variable(let name):
            if name == boundVarName { return name }
            return "_state.\(name)"
        case .value(let val):
            return valueLiteral(val, forceTLAValue: forceTLAValue, enumInfos: enumInfos)
        case .add(let a, let b): return "(\(cg(a)) + \(cg(b)))"
        case .subtract(let a, let b): return "(\(cg(a)) - \(cg(b)))"
        case .multiply(let a, let b): return "(\(cg(a)) * \(cg(b)))"
        case .divide(let a, let b): return "(\(cg(a)) / \(cg(b)))"
        case .modulo(let a, let b): return "(\(cg(a)) % \(cg(b)))"
        case .negate(let a): return "(-\(cg(a)))"
        case .integerDivide(let a, let b): return "(\(cg(a)) / \(cg(b)))"
        case .equal(let a, let b): return "(\(cg(a)) == \(cg(b)))"
        case .notEqual(let a, let b): return "(\(cg(a)) != \(cg(b)))"
        case .lessThan(let a, let b): return "(\(cg(a)) < \(cg(b)))"
        case .lessOrEqual(let a, let b): return "(\(cg(a)) <= \(cg(b)))"
        case .greaterThan(let a, let b): return "(\(cg(a)) > \(cg(b)))"
        case .greaterOrEqual(let a, let b): return "(\(cg(a)) >= \(cg(b)))"
        case .and(let a, let b): return "(\(cg(a)) && \(cg(b)))"
        case .or(let a, let b): return "(\(cg(a)) || \(cg(b)))"
        case .not(let a): return "(!\(cg(a)))"
        case .ifThenElse(let c, let t, let f):
            if forceTLAValue {
                return "TLAValue.ternary(condition: \(cg(c)), then: \(cg(t)), else: \(cg(f)))"
            }
            return "(\(cg(c)) ? \(cg(t)) : \(cg(f)))"
        case .cardinality(let s): return "\(cg(s)).cardinality"
        case .functionApply(let f, let x): return "\(cg(f))[\(cg(x))]"
        case .recordAccess(let r, let field): return "\(cg(r))[\"\(field)\"]"
        case .in(let e, let s): return "\(cg(s)).contains(\(cg(e)))"
        case .union(let a, let b): return "\(cg(a)).union(\(cg(b)))"
        case .intersection(let a, let b): return "\(cg(a)).intersection(\(cg(b)))"
        case .setDifference(let a, let b): return "\(cg(a)).subtracting(\(cg(b)))"
        case .subset(let a, let b): return "\(cg(a)).isSubset(of: \(cg(b)))"
        case .tupleAccess(let t, let i): return "(\(cg(t)))[\(i)]"
        case .tupleDynamicAccess(let tuple, let index):
            return "(\(cg(tuple)))[(\(cg(index))) - 1]"
        case .tupleAppend(let t, let e): return "(\(cg(t)) + [\(cg(e))])"
        case .tupleHead(let t): return "(\(cg(t))).first!"
        case .tupleTail(let t): return "Array((\(cg(t))).dropFirst())"
        case .except(let f, let k, let v): return "\(cg(f)).updating(\(cg(k)), to: \(cg(v)))"
        case .domain(let f): return "\(cg(f)).keys"
        case .setFilter(let s, let qv, let p):
            let predicate = codegenExprInner(
                p,
                variables: variables,
                enumInfos: enumInfos,
                forceTLAValue: forceTLAValue,
                boundVarName: qv
            )
            return "\(cg(s)).filter { \(qv) in \(predicate) }"
        case .setMap(let e, let qv, let s):
            let mapping = codegenExprInner(
                e,
                variables: variables,
                enumInfos: enumInfos,
                forceTLAValue: forceTLAValue,
                boundVarName: qv
            )
            return "\(cg(s)).map { \(qv) in \(mapping) }"
        case .powerSet(let s): return "\(cg(s)).powerSet"
        case .unionAll(let s): return "\(cg(s)).flattened"
        case .integerRange(let lower, let upper):
            return "Set(\(cg(lower))...\(cg(upper)))"
        case .tupleLiteral(let es):
            return "[\(es.map { cg($0) }.joined(separator: ", "))]"
        case .recordLiteral(let fs):
            return "[\(fs.map { "\"\($0.key)\": \(cg($0.value))" }.joined(separator: ", "))]"
        case .setLiteral(let es):
            return "Set([\(es.map { cg($0) }.joined(separator: ", "))])"
        case .functionLiteral(let d, let qv, let b):
            let body = codegenExprInner(
                b,
                variables: variables,
                enumInfos: enumInfos,
                forceTLAValue: forceTLAValue,
                boundVarName: qv
            )
            return "\(cg(d)).asFunctionLiteral { \(qv) in \(body) }"
        case .caseExpr:
            return "StateExpr.caseExpr([], nil)"
        case .forAll, .exists, .choose, .sequenceFromSet, .setSum, .functionSet, .foldFunction, .operatorApplication, .recursiveCall, .letValue, .letIn, .enabledAction:
            return "Self.runtime.evaluateExpr(\(expr.description), in: _state.asDictionary)"
        case .tupleLength(let t):
            return "TLAValue.int((\(cg(t)).tupleValue.count))"
        case .tupleConcatenate(let a, let b):
            return "(\(cg(a)) + \(cg(b)))"
        }
    }
    static func containsTLAValueField(
        _ expr: StateExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo],
        boundVarName: String? = nil
    ) -> Bool {
        var found = false
        walkStateExpr(expr) { e in
            if case .variable(let name) = e, name != boundVarName {
                if isTLAValueField(name, variables: variables, enumInfos: enumInfos) {
                    found = true; return true
                }
            }
            return false
        }
        return found
    }
    static func walkStateExpr(_ expr: StateExpr, visitor: (StateExpr) -> Bool) {
        if visitor(expr) { return }
        switch expr {
        case .variable, .value: break
        case .add(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .subtract(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .multiply(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .divide(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .modulo(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .negate(let a): walkStateExpr(a, visitor: visitor)
        case .integerDivide(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .equal(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .notEqual(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .lessThan(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .lessOrEqual(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .greaterThan(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .greaterOrEqual(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .and(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .or(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .not(let a): walkStateExpr(a, visitor: visitor)
        case .ifThenElse(let c, let t, let f):
            walkStateExpr(c, visitor: visitor)
            walkStateExpr(t, visitor: visitor)
            walkStateExpr(f, visitor: visitor)
        case .cardinality(let s): walkStateExpr(s, visitor: visitor)
        case .functionApply(let f, let x): walkStateExpr(f, visitor: visitor); walkStateExpr(x, visitor: visitor)
        case .recordAccess(let r, _): walkStateExpr(r, visitor: visitor)
        case .in(let e, let s): walkStateExpr(e, visitor: visitor); walkStateExpr(s, visitor: visitor)
        case .union(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .intersection(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .setDifference(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .subset(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .tupleAccess(let t, _): walkStateExpr(t, visitor: visitor)
        case .tupleDynamicAccess(let tuple, let index):
            walkStateExpr(tuple, visitor: visitor); walkStateExpr(index, visitor: visitor)
        case .tupleAppend(let t, let e): walkStateExpr(t, visitor: visitor); walkStateExpr(e, visitor: visitor)
        case .tupleHead(let t): walkStateExpr(t, visitor: visitor)
        case .tupleTail(let t): walkStateExpr(t, visitor: visitor)
        case .tupleLength(let t): walkStateExpr(t, visitor: visitor)
        case .tupleConcatenate(let a, let b): walkStateExpr(a, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .except(let f, let k, let v): walkStateExpr(f, visitor: visitor); walkStateExpr(k, visitor: visitor); walkStateExpr(v, visitor: visitor)
        case .domain(let f): walkStateExpr(f, visitor: visitor)
        case .setFilter(let s, _, let p): walkStateExpr(s, visitor: visitor); walkStateExpr(p, visitor: visitor)
        case .setMap(let e, _, let s): walkStateExpr(e, visitor: visitor); walkStateExpr(s, visitor: visitor)
        case .powerSet(let s): walkStateExpr(s, visitor: visitor)
        case .unionAll(let s): walkStateExpr(s, visitor: visitor)
        case .integerRange(let lower, let upper):
            walkStateExpr(lower, visitor: visitor); walkStateExpr(upper, visitor: visitor)
        case .tupleLiteral(let es): es.forEach { walkStateExpr($0, visitor: visitor) }
        case .recordLiteral(let fs): fs.values.forEach { walkStateExpr($0, visitor: visitor) }
        case .setLiteral(let es): es.forEach { walkStateExpr($0, visitor: visitor) }
        case .functionLiteral(let d, _, let b): walkStateExpr(d, visitor: visitor); walkStateExpr(b, visitor: visitor)
        case .foldFunction(let operation, let initial, let sequence):
            walkStateExpr(operation.body, visitor: visitor)
            walkStateExpr(initial, visitor: visitor)
            walkStateExpr(sequence, visitor: visitor)
        case .operatorApplication(let operation, let arguments):
            if case .lambda(let lambda) = operation {
                walkStateExpr(lambda.body, visitor: visitor)
            }
            arguments.forEach { argument in
                switch argument {
                case .value(let expression): walkStateExpr(expression, visitor: visitor)
                case .operator(.lambda(let lambda)): walkStateExpr(lambda.body, visitor: visitor)
                case .operator(.reference): break
                }
            }
        case .caseExpr(let ps, let fb): ps.forEach { walkStateExpr($0, visitor: visitor) }; fb.map { walkStateExpr($0, visitor: visitor) }
        case .forAll, .exists, .choose, .sequenceFromSet, .setSum, .functionSet, .recursiveCall, .enabledAction: break
        case .letValue(_, let value, let body):
            walkStateExpr(value, visitor: visitor)
            walkStateExpr(body, visitor: visitor)
        case .letIn(let operators, let body):
            operators.forEach { walkStateExpr($0.body, visitor: visitor) }
            walkStateExpr(body, visitor: visitor)
        }
    }
    static func isTLAValueField(
        _ name: String,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> Bool {
        guard let v = variables.first(where: { $0.name == name }) else { return false }
        let typeName = v.swiftTypeName ?? swiftType(for: v.initial)
        if ["Int", "Bool", "String"].contains(typeName) { return false }
        if enumInfos.contains(where: { $0.typeName == typeName }) { return false }
        return true
    }
    static func valueLiteral(_ value: TLAValue, forceTLAValue: Bool, enumInfos: [ParsedEnumInfo]) -> String {
        if forceTLAValue {
            switch value {
            case .int(let n): return ".int(\(n))"
            case .bool(let b): return ".bool(\(b))"
            case .string(let s): return ".string(\"\(s)\")"
            default: return ".int(0)"
            }
        }
        for info in enumInfos {
            for (caseName, caseValue) in info.cases where caseValue == value {
                return ".\(caseName)"
            }
        }
        switch value {
        case .int(let n): return "\(n)"
        case .bool(let b): return "\(b)"
        case .string(let s): return "\"\(s)\""
        default: return "0"
        }
    }
    // MARK: - Action body codegen (T2)
    static func codegenActionBody(
        _ action: ActionExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> String? {
        let expanded = inlineDefines(in: action)
        guard !containsNondeterministic(expanded) else { return nil }
        guard !containsRuntimeOnlyExpr(expanded) else { return nil }
        let disjuncts = distributeOr(expanded)
        if disjuncts.isEmpty { return nil }
        if disjuncts.count == 1 {
            return codegenSingleDisjunct(disjuncts[0], variables: variables, enumInfos: enumInfos)
        }
        return codegenMultiDisjunct(disjuncts, variables: variables, enumInfos: enumInfos)
    }
    static func containsRuntimeOnlyExpr(_ action: ActionExpr) -> Bool {
        var found = false
        walkActionExpr(action) { a in
            let exprNodes: [StateExpr] = {
                switch a {
                case .assign(_, let e): return [e]
                case .guard_(let e): return [e]
                case .chooseAction(_, let s): return [s]
                case .existsAction(_, let s, _): return [s]
                case .ifElse(let c, _, _): return [c]
                case .define(_, let e, _): return [e]
                default: return []
                }
            }()
            for e in exprNodes {
                if containsRuntimeOnlyStateExpr(e) { found = true; return true }
            }
            return false
        }
        return found
    }
    static func containsRuntimeOnlyStateExpr(_ expr: StateExpr) -> Bool {
        var found = false
        walkStateExpr(expr) { e in
            switch e {
            case .forAll, .exists, .choose, .sequenceFromSet, .setSum,
                 .functionSet, .recursiveCall, .enabledAction:
                found = true; return true
            case .caseExpr:
                found = true; return true
            default: return false
            }
        }
        return found
    }
    static func containsNondeterministic(_ action: ActionExpr) -> Bool {
        var found = false
        walkActionExpr(action) { a in
            switch a {
            case .chooseAction, .existsAction:
                found = true; return true
            default: return false
            }
        }
        return found
    }
    static func walkActionExpr(_ action: ActionExpr, visitor: (ActionExpr) -> Bool) {
        if visitor(action) { return }
        switch action {
        case .assign: break
        case .unchanged: break
        case .guard_: break
        case .ifElse(_, let t, let e):
            walkActionExpr(t, visitor: visitor); walkActionExpr(e, visitor: visitor)
        case .define(_, _, let b):
            walkActionExpr(b, visitor: visitor)
        case .and(let a, let b):
            walkActionExpr(a, visitor: visitor); walkActionExpr(b, visitor: visitor)
        case .or(let a, let b):
            walkActionExpr(a, visitor: visitor); walkActionExpr(b, visitor: visitor)
        case .existsAction(_, _, let b):
            walkActionExpr(b, visitor: visitor)
        case .chooseAction: break
        }
    }
    static func inlineDefines(in action: ActionExpr) -> ActionExpr {
        switch action {
        case .define(let name, let expr, let body):
            let inlined = substituteActionVar(name, with: expr, in: body)
            return inlineDefines(in: inlined)
        case .and(let a, let b):
            return .and(inlineDefines(in: a), inlineDefines(in: b))
        case .or(let a, let b):
            return .or(inlineDefines(in: a), inlineDefines(in: b))
        case .ifElse(let c, let t, let e):
            return .ifElse(c, inlineDefines(in: t), inlineDefines(in: e))
        case .existsAction(let v, let s, let b):
            return .existsAction(v, s, inlineDefines(in: b))
        default:
            return action
        }
    }
    static func substituteActionVar(_ name: String, with expr: StateExpr, in action: ActionExpr) -> ActionExpr {
        switch action {
        case .assign(let v, let e):
            return .assign(v, substituteInStateExpr(name, with: expr, in: e))
        case .unchanged(let v):
            if v == name { return .unchanged(v) }
            return action
        case .guard_(let e):
            return .guard_(substituteInStateExpr(name, with: expr, in: e))
        case .chooseAction(let v, let s):
            return .chooseAction(v, substituteInStateExpr(name, with: expr, in: s))
        case .existsAction(let v, let s, let b):
            return .existsAction(v, substituteInStateExpr(name, with: expr, in: s),
                                 substituteActionVar(name, with: expr, in: b))
        case .ifElse(let c, let t, let e):
            return .ifElse(substituteInStateExpr(name, with: expr, in: c),
                           substituteActionVar(name, with: expr, in: t),
                           substituteActionVar(name, with: expr, in: e))
        case .define(let v, let e, let b):
            if v == name { return action }
            return .define(v, substituteInStateExpr(name, with: expr, in: e),
                           substituteActionVar(name, with: expr, in: b))
        case .and(let a, let b):
            return .and(substituteActionVar(name, with: expr, in: a),
                        substituteActionVar(name, with: expr, in: b))
        case .or(let a, let b):
            return .or(substituteActionVar(name, with: expr, in: a),
                       substituteActionVar(name, with: expr, in: b))
        }
    }
    static func substituteInStateExpr(_ name: String, with expr: StateExpr, in state: StateExpr) -> StateExpr {
        if case .variable(let v) = state, v == name { return expr }
        func sub(_ s: StateExpr) -> StateExpr { substituteInStateExpr(name, with: expr, in: s) }
        switch state {
        case .variable, .value: break
        case .add(let a, let b): return .add(sub(a), sub(b))
        case .subtract(let a, let b): return .subtract(sub(a), sub(b))
        case .multiply(let a, let b): return .multiply(sub(a), sub(b))
        case .divide(let a, let b): return .divide(sub(a), sub(b))
        case .modulo(let a, let b): return .modulo(sub(a), sub(b))
        case .negate(let a): return .negate(sub(a))
        case .integerDivide(let a, let b): return .integerDivide(sub(a), sub(b))
        case .equal(let a, let b): return .equal(sub(a), sub(b))
        case .notEqual(let a, let b): return .notEqual(sub(a), sub(b))
        case .lessThan(let a, let b): return .lessThan(sub(a), sub(b))
        case .lessOrEqual(let a, let b): return .lessOrEqual(sub(a), sub(b))
        case .greaterThan(let a, let b): return .greaterThan(sub(a), sub(b))
        case .greaterOrEqual(let a, let b): return .greaterOrEqual(sub(a), sub(b))
        case .and(let a, let b): return .and(sub(a), sub(b))
        case .or(let a, let b): return .or(sub(a), sub(b))
        case .not(let a): return .not(sub(a))
        case .ifThenElse(let c, let t, let f): return .ifThenElse(sub(c), sub(t), sub(f))
        case .cardinality(let s): return .cardinality(sub(s))
        case .functionApply(let f, let x): return .functionApply(sub(f), sub(x))
        case .recordAccess(let r, let f): return .recordAccess(sub(r), f)
        case .in(let e, let s): return .in(sub(e), sub(s))
        case .union(let a, let b): return .union(sub(a), sub(b))
        case .intersection(let a, let b): return .intersection(sub(a), sub(b))
        case .setDifference(let a, let b): return .setDifference(sub(a), sub(b))
        case .subset(let a, let b): return .subset(sub(a), sub(b))
        case .tupleAccess(let t, let i): return .tupleAccess(sub(t), i)
        case .tupleDynamicAccess(let tuple, let index): return .tupleDynamicAccess(sub(tuple), sub(index))
        case .tupleAppend(let t, let e): return .tupleAppend(sub(t), sub(e))
        case .tupleHead(let t): return .tupleHead(sub(t))
        case .tupleTail(let t): return .tupleTail(sub(t))
        case .tupleLength(let t): return .tupleLength(sub(t))
        case .tupleConcatenate(let a, let b): return .tupleConcatenate(sub(a), sub(b))
        case .except(let f, let k, let v): return .except(sub(f), sub(k), sub(v))
        case .domain(let f): return .domain(sub(f))
        case .setFilter(let s, let qv, let p): return .setFilter(sub(s), qv, sub(p))
        case .setMap(let e, let qv, let s): return .setMap(sub(e), qv, sub(s))
        case .powerSet(let s): return .powerSet(sub(s))
        case .unionAll(let s): return .unionAll(sub(s))
        case .integerRange(let lower, let upper): return .integerRange(sub(lower), sub(upper))
        case .tupleLiteral(let es): return .tupleLiteral(es.map(sub))
        case .recordLiteral(let fs): return .recordLiteral(fs.mapValues(sub))
        case .setLiteral(let es): return .setLiteral(es.map(sub))
        case .functionLiteral(let d, let qv, let b): return .functionLiteral(sub(d), qv, sub(b))
        case .foldFunction(let operation, let initial, let sequence):
            return .foldFunction(
                FormalLambda(
                    parameters: operation.parameters,
                    body: operation.parameters.contains(name) ? operation.body : sub(operation.body)
                ),
                initial: sub(initial),
                sequence: sub(sequence)
            )
        case .operatorApplication(let operation, let arguments):
            let substitutedOperator: FormalOperator
            switch operation {
            case .lambda(let lambda):
                substitutedOperator = .lambda(
                    FormalLambda(
                        parameters: lambda.parameters,
                        body: lambda.parameters.contains(name) ? lambda.body : sub(lambda.body)
                    )
                )
            case .reference:
                substitutedOperator = operation
            }
            return .operatorApplication(substitutedOperator, arguments.map { argument in
                switch argument {
                case .value(let expression): return FormalCallArgument.value(sub(expression))
                case .operator(.reference(let name, let arity)):
                    return FormalCallArgument.operator(.reference(name, arity: arity))
                case .operator(.lambda(let lambda)):
                    return FormalCallArgument.operator(.lambda(FormalLambda(
                        parameters: lambda.parameters,
                        body: lambda.parameters.contains(name) ? lambda.body : sub(lambda.body)
                    )))
                }
            })
        case .caseExpr(let ps, let fb): return .caseExpr(ps.map(sub), fb.map(sub))
        case .forAll, .exists, .choose, .sequenceFromSet, .setSum, .functionSet,
             .recursiveCall, .enabledAction: break
        case .letValue(let local, let value, let body):
            return .letValue(local, sub(value), local == name ? body : sub(body))
        case .letIn(let operators, let body):
            return .letIn(
                operators.map { operation in
                    LocalOperator(
                        operation.name,
                        parameters: operation.parameters,
                        body: operation.parameters.contains(name) ? operation.body : sub(operation.body)
                    )
                },
                sub(body)
            )
        }
        return state
    }
    static func codegenSingleDisjunct(
        _ disjunct: ActionExpr,
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> String {
        let extracted: (assignments: [String: StateExpr], guards: [StateExpr])
        do {
            extracted = try ActionEnumerator.extractAssignments(disjunct)
        } catch {
            return "fatalError(\"\\(error)\")"
        }
        let guardExprs = extracted.guards.map { codegenExpr($0, variables: variables, enumInfos: enumInfos) }
        let guardBlock = guardExprs.isEmpty ? "" : "guard \(guardExprs.joined(separator: ", ")) else { return }"
        let assignments = extracted.assignments.compactMap { name, expr -> String? in
            if case .variable(let refName) = expr, refName == name { return nil }
            let rhs = codegenExpr(expr, variables: variables, enumInfos: enumInfos)
                .replacingOccurrences(of: "_state.", with: "_saved.")
            return "_state.\(name) = \(rhs)"
        }
        let body = ["let _saved = _state", guardBlock].filter { !$0.isEmpty } + assignments
        return body.filter { !$0.isEmpty }.joined(separator: "\n        ")
    }
    static func codegenMultiDisjunct(
        _ disjuncts: [ActionExpr],
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        enumInfos: [ParsedEnumInfo]
    ) -> String {
        let parts = disjuncts.map { disjunct -> String in
            let extracted: (assignments: [String: StateExpr], guards: [StateExpr])
            do {
                extracted = try ActionEnumerator.extractAssignments(disjunct)
            } catch {
                return "fatalError(\"\\(error)\")"
            }
            let guardExprs = extracted.guards.map { codegenExpr($0, variables: variables, enumInfos: enumInfos) }
            let condition = guardExprs.isEmpty ? "true" : guardExprs.joined(separator: " && ")
            let assignments = extracted.assignments.compactMap { name, expr -> String? in
                if case .variable(let refName) = expr, refName == name { return nil }
                let rhs = codegenExpr(expr, variables: variables, enumInfos: enumInfos).replacingOccurrences(of: "_state.", with: "_saved.")
                return "_state.\(name) = \(rhs)"
            }
            return "if \(condition) {\n            \(assignments.joined(separator: "\n            "))\n            return\n        }"
        }
        var result = "let _saved = _state\n        "
        for (i, part) in parts.enumerated() {
            if !part.isEmpty {
                if i > 0 { result += "\n        _state = _saved\n        " }
                result += part
            }
        }
        return result
    }
    // MARK: - Apply dispatcher generation (T3)
    static func generateApplyDispatcher(
        actions: [SpecParser.ParsedAction],
        nativeNames: Set<String>,
        isActor: Bool = false
    ) -> FunctionDeclSyntax {
        let identifiers = generatedActionIdentifiers(actions: actions)
        let switchCases = zip(actions, identifiers).map { a, identifier in
            if nativeNames.contains(a.name) {
                let methodName = isActor ? "_\(identifier)" : "apply\(identifier)"
                return "case .\(identifier): \(methodName)()"
            } else {
                return "case .\(identifier): _state = _apply(action)"
            }
        }.joined(separator: "\n        ")
        let source = """
        \(isActor ? "fileprivate" : "private mutating") func _applyAction(_ action: Actions) {
            switch action {
            \(switchCases)
            }
        }
        """
        return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
    }
}
