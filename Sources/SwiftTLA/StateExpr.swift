enum CompilerControlSymbol: String, Sendable {
    case programCounter = "pc"
    case stack
    case procedure
    case done = "Done"
    case terminatingAction = "Terminating"
}

func generatedBinderName(
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column
) -> String {
    let fileID = String(describing: file)
    let component = fileID.split(separator: "/").last ?? "binder"
    let stem = component.split(separator: ".").first ?? component
    let identifierStem = String(stem.map { character in
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
            ? character
            : "_"
    })
    return "__binder_\(identifierStem)_\(line)_\(column)"
}

/// A local TLA+ operator declared inside a `LET … IN` expression.
///
/// The AST retains each operator's lexical scope for evaluation and rendering.
public struct LocalOperator: Hashable, Sendable {
    public let name: String
    public let parameters: [String]
    /// A bounded local recursive function parameter (`name[param \in domain]`).
    public let domain: StateExpr?
    public let body: StateExpr
    let sourceIssue: SourceModelIssue?

    public init(_ name: String, parameters: [String] = [], domain: StateExpr? = nil, body: StateExpr) {
        self.name = name
        self.parameters = parameters
        self.domain = domain
        self.body = body
        if name.isEmpty {
            self.sourceIssue = .formalDeclaration(kind: "local operator", name: nil, problem: "it has no name")
        } else if domain != nil, parameters.count != 1 {
            self.sourceIssue = .formalDeclaration(kind: "bounded local function", name: name, problem: "it has \(parameters.count) parameters")
        } else {
            self.sourceIssue = nil
        }
    }
}

/// A formal function body with named, scoped inputs.
///
/// The evaluator binds its inputs while evaluating the formal operator that
/// receives it.
public struct FormalLambda: Hashable, Sendable {
    public let parameters: [String]
    public let body: StateExpr
    let sourceIssue: SourceModelIssue?

    public init(parameters: [String], body: StateExpr) {
        self.parameters = parameters
        self.body = body
        if parameters.isEmpty {
            self.sourceIssue = .formalDeclaration(kind: "formal lambda", name: nil, problem: "it has no parameters")
        } else if Set(parameters).count != parameters.count {
            self.sourceIssue = .formalDeclaration(kind: "formal lambda", name: nil, problem: "it repeats a parameter name")
        } else {
            self.sourceIssue = nil
        }
    }
}

/// A formal operator passed or applied by the specification.
///
/// A lambda retains its parameters and body. A reference retains its operator
/// name and required arity. The runtime and renderer consume the same form.
public indirect enum FormalOperator: Hashable, Sendable {
    case lambda(FormalLambda)
    case reference(String, arity: Int)

    public var arity: Int {
        switch self {
        case .lambda(let lambda): lambda.parameters.count
        case .reference(_, let arity): arity
        }
    }

}

/// One argument supplied to a formal operator call.
///
/// The cases preserve whether a TLA+ argument is a value or an operator.
public indirect enum FormalCallArgument: Hashable, Sendable {
    case value(StateExpr)
    case `operator`(FormalOperator)
}

/// One ordered parameter of a formal operator definition.
///
/// The order is part of TLA+ operator application.  Keeping the kind beside
/// the name lets the evaluator reject a value where the source requires an
/// operator, or the reverse, before it evaluates the definition body.
public enum FormalParameter: Hashable, Sendable {
    case value(String)
    case `operator`(String, arity: Int)

    public var name: String {
        switch self {
        case .value(let name), .operator(let name, _): name
        }
    }
}

/// An executable formal definition, including higher-order parameters.
///
/// This is distinct from a Swift function: its body stays in `StateExpr`, so
/// the evaluator, alpha-equivalence checker, and TLA+ exporter all observe
/// the same operation and its supplied operators.
public struct FormalOperatorDefinition: Hashable, Sendable {
    public let name: String
    public let parameters: [FormalParameter]
    public let body: StateExpr
    public let plusCalPhase: AuthoredPlusCalDeclarationPhase
    public let plusCalDependencies: [String]
    let sourceIssue: SourceModelIssue?

    public init(
        name: String,
        parameters: [FormalParameter],
        body: StateExpr,
        plusCalPhase: AuthoredPlusCalDeclarationPhase = .prelude,
        plusCalDependencies: [String] = []
    ) {
        self.name = name
        self.parameters = parameters
        self.body = body
        self.plusCalPhase = plusCalPhase
        self.plusCalDependencies = plusCalDependencies
        if name.isEmpty {
            self.sourceIssue = .formalDeclaration(kind: "formal operator", name: nil, problem: "it has no name")
        } else if Set(parameters.map(\.name)).count != parameters.count {
            self.sourceIssue = .formalDeclaration(kind: "formal operator", name: name, problem: "it repeats a parameter name")
        } else {
            self.sourceIssue = nil
        }
    }
}

public struct StateRecordExpression: Hashable, Sendable {
    public struct Field: Hashable, Sendable {
        public let name: String
        public let value: StateExpr

        public init(name: String, value: StateExpr) {
            self.name = name
            self.value = value
        }
    }

    public let fields: [Field]

    public init(_ fields: [Field]) {
        self.fields = fields.sorted { $0.name < $1.name }
    }

    public init(_ fields: [String: StateExpr]) {
        self.init(fields.map { .init(name: $0.key, value: $0.value) })
    }

    init(orderedFields: [Field]) {
        fields = orderedFields
    }

    public func value(named name: String) -> StateExpr? {
        fields.first { $0.name == name }?.value
    }
}

/// An invalid construct retained in the typed source model until compilation.
public enum SourceModelIssue: Hashable, Sendable, CustomStringConvertible {
    case recordField(schema: String)
    case recordLiteral(schema: String, duplicateFields: [String], missingFields: [String])
    case invalidRecordSchema(schema: String, problem: String)
    case functionLiteral(domain: String, duplicateValues: [String], missingValues: [String])
    case staticSelection(String)
    case sequenceElementDomain(operation: String)
    case negativeSequenceLength(operation: String, lowerBound: Int)
    case finiteDomain(type: String, problem: String)
    case finiteDomainValue(type: String, value: String)
    case actionBinding(action: String, parameter: String?, problem: String)
    case formalDeclaration(kind: String, name: String?, problem: String)
    case missingVariableInitializer(name: String, type: String)
    case symmetricMember(collection: String, owner: String)

    private var diagnostic: (code: CompilationDiagnostic.Code, expected: String, actual: String, nextSafeAction: String) {
        switch self {
        case .recordField(let schema):
            return (
                .invalidTypedRecordField,
                "a field declared by \(schema)",
                "an undeclared record field",
                "Use one of the fields declared by \(schema), then compile again."
            )
        case .recordLiteral(let schema, let duplicates, let missing):
            let details = [
                duplicates.isEmpty ? nil : "repeated fields: \(duplicates.joined(separator: ", "))",
                missing.isEmpty ? nil : "missing fields: \(missing.joined(separator: ", "))"
            ].compactMap { $0 }.joined(separator: "; ")
            return (.invalidTypedRecordLiteral, "one value for every field declared by \(schema)", details, "Provide each declared record field exactly once, then compile again.")
        case .invalidRecordSchema(let schema, let problem):
            return (.invalidTypedRecordLiteral, "unique nonempty fields declared by \(schema)", problem, "Correct the field declarations in \(schema), then compile again.")
        case .functionLiteral(let domain, let duplicates, let missing):
            let details = [
                duplicates.isEmpty ? nil : "repeated domain values: \(duplicates.joined(separator: ", "))",
                missing.isEmpty ? nil : "missing domain values: \(missing.joined(separator: ", "))"
            ].compactMap { $0 }.joined(separator: "; ")
            return (.invalidTypedFunctionLiteral, "one value for every member of \(domain)", details, "Provide every finite domain value exactly once, then compile again.")
        case .staticSelection(let reason):
            return (.invalidStaticSelection, "a closed formal selection with a matching value", reason, "Use a closed domain with at least one matching value, then compile again.")
        case .sequenceElementDomain(let operation):
            return (.invalidSequenceElementDomain, "SetExpr.literal(...) as the element domain for \(operation)", "a symbolic formal set", "Use SetExpr.literal(...) for this bounded sequence declaration, then compile again.")
        case .negativeSequenceLength(let operation, let lowerBound):
            return (.invalidSequenceLength, "a non-negative lower sequence length for \(operation)", "\(lowerBound)", "Use only non-negative sequence lengths, then compile again.")
        case .finiteDomain(let type, let problem):
            return (.invalidFiniteDomain, "a non-empty finite domain with distinct formal values for \(type)", problem, "Declare one or more distinct finite values, then compile again.")
        case .finiteDomainValue(let type, let value):
            return (.invalidFiniteDomainValue, "a value declared by \(type).finiteValues", value, "Use a declared finite-domain value, then compile again.")
        case .actionBinding(let action, let parameter, let problem):
            let location = parameter.map { "parameter '\($0)' of action '\(action)'" } ?? "parameters of action '\(action)'"
            return (.invalidActionBinding, "a named parameter with a non-empty, distinct finite domain", "\(location): \(problem)", "Declare each action parameter once with one or more distinct values, then compile again.")
        case .formalDeclaration(let kind, let name, let problem):
            let location = name.map { "\(kind) '\($0)'" } ?? kind
            return (.invalidFormalDeclaration, "a valid \(kind) declaration", "\(location): \(problem)", "Correct the declaration, then compile again.")
        case .missingVariableInitializer(let name, let type):
            return (
                .missingVariableInitializer,
                "an explicit \(type) initial value for variable '\(name)'",
                "variable '\(name)' has no initial value",
                "Provide the initial value in Var or Variable, then compile again."
            )
        case .symmetricMember(let collection, let owner):
            return (.invalidSymmetricMember, "a member declared by symmetric collection '\(collection)'", "the member belongs to symmetric collection '\(owner)'", "Use a member from '\(collection)', then compile again.")
        }
    }

    func compilationDiagnostic(
        stage: CompilationDiagnostic.Stage,
        path: String
    ) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: diagnostic.code,
            stage: stage,
            path: path,
            expected: diagnostic.expected,
            actual: diagnostic.actual,
            nextSafeAction: diagnostic.nextSafeAction
        )
    }

    public var description: String { diagnostic.actual }
}

public indirect enum StateExpr: Hashable, Sendable, CustomStringConvertible {
    case sourceIssue(SourceModelIssue)
    case value(TLAValue)
    case variable(String)
    case processLocalFamily(String)
    case currentProcess
    case programCounter
    case procedureStack
    case controlLocation(ControlLocationReference)

    case add(StateExpr, StateExpr)
    case subtract(StateExpr, StateExpr)
    case multiply(StateExpr, StateExpr)
    case divide(StateExpr, StateExpr)
    case modulo(StateExpr, StateExpr)
    case negate(StateExpr)
    case integerDivide(StateExpr, StateExpr)

    case equal(StateExpr, StateExpr)
    case notEqual(StateExpr, StateExpr)
    case lessThan(StateExpr, StateExpr)
    case lessOrEqual(StateExpr, StateExpr)
    case greaterThan(StateExpr, StateExpr)
    case greaterOrEqual(StateExpr, StateExpr)

    case and(StateExpr, StateExpr)
    case or(StateExpr, StateExpr)
    case not(StateExpr)

    case ifThenElse(StateExpr, StateExpr, StateExpr)

    case setLiteral([StateExpr])
    case `in`(StateExpr, StateExpr)
    case subset(StateExpr, StateExpr)
    case union(StateExpr, StateExpr)
    case intersection(StateExpr, StateExpr)
    case setDifference(StateExpr, StateExpr)
    case cardinality(StateExpr)
    case setFilter(StateExpr, String, StateExpr)
    case setMap(StateExpr, String, StateExpr)
    case powerSet(StateExpr)
    case unionAll(StateExpr)
    case integerRange(StateExpr, StateExpr)

    case tupleLiteral([StateExpr])
    case tupleAccess(StateExpr, Int)
    case tupleDynamicAccess(StateExpr, StateExpr)
    case tupleLength(StateExpr)
    case tupleAppend(StateExpr, StateExpr)
    case tupleHead(StateExpr)
    case tupleTail(StateExpr)
    case tupleConcatenate(StateExpr, StateExpr)

    case recordLiteral(StateRecordExpression)
    case recordAccess(StateExpr, String)
    case domain(StateExpr)
    case functionLiteral(StateExpr, String, StateExpr)
    case functionApply(StateExpr, StateExpr)
    case except(StateExpr, StateExpr, StateExpr)
    case caseExpr([StateExpr], StateExpr?)

    case forAll(StateExpr, String, StateExpr)
    case exists(StateExpr, String, StateExpr)
    case choose(StateExpr, String, StateExpr)
    case enabledAction(String)

    case sequenceFromSet(StateExpr)
    case setSum(StateExpr, StateExpr)
    case functionSet(StateExpr, StateExpr)
    case foldFunction(FormalLambda, initial: StateExpr, sequence: StateExpr)

    case operatorApplication(FormalOperator, [FormalCallArgument])

    case recursiveCall(String, [StateExpr])
    /// A scoped TLA+ `LET name == value IN body` value expression.
    case letValue(String, StateExpr, StateExpr)
    case letIn([LocalOperator], StateExpr)

    public var description: String {
        do {
            return try authoredPlusCalSource(path: "description", validatingIdentifiers: false)
        } catch {
            return "<invalid formal expression>"
        }
    }
}


private extension FormalCallArgument {
    var referencedLocalOperators: Set<String> {
        switch self {
        case .value(let expression): localOperatorCalls(in: expression)
        case .operator(.lambda(let lambda)): localOperatorCalls(in: lambda.body)
        case .operator(.reference): []
        }
    }
}

func localOperatorCalls(in expression: StateExpr) -> Set<String> {
    switch expression {
    case .sourceIssue, .value, .variable, .processLocalFamily, .currentProcess, .programCounter, .procedureStack, .controlLocation, .enabledAction:
        return []
    case .recursiveCall(let name, let arguments):
        return Set([name]).union(
            arguments.reduce(into: Set<String>()) { $0.formUnion(localOperatorCalls(in: $1)) }
        )
    case .letValue(_, let value, let body):
        return localOperatorCalls(in: value).union(localOperatorCalls(in: body))
    case .letIn:
        // Nested scopes bring their own recursive declarations.
        return []
    case .negate(let value), .not(let value), .cardinality(let value), .powerSet(let value),
         .unionAll(let value), .tupleLength(let value), .tupleHead(let value), .tupleTail(let value),
         .domain(let value), .sequenceFromSet(let value):
        return localOperatorCalls(in: value)
    case .add(let lhs, let rhs), .subtract(let lhs, let rhs), .multiply(let lhs, let rhs),
         .divide(let lhs, let rhs), .modulo(let lhs, let rhs), .integerDivide(let lhs, let rhs),
         .equal(let lhs, let rhs), .notEqual(let lhs, let rhs), .lessThan(let lhs, let rhs),
         .lessOrEqual(let lhs, let rhs), .greaterThan(let lhs, let rhs), .greaterOrEqual(let lhs, let rhs),
         .and(let lhs, let rhs), .or(let lhs, let rhs), .in(let lhs, let rhs), .subset(let lhs, let rhs),
         .union(let lhs, let rhs), .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs),
         .tupleDynamicAccess(let lhs, let rhs), .tupleAppend(let lhs, let rhs),
         .tupleConcatenate(let lhs, let rhs), .functionApply(let lhs, let rhs),
         .functionSet(let lhs, let rhs), .setSum(let lhs, let rhs):
        return localOperatorCalls(in: lhs).union(localOperatorCalls(in: rhs))
    case .ifThenElse(let condition, let then, let otherwise):
        return localOperatorCalls(in: condition)
            .union(localOperatorCalls(in: then))
            .union(localOperatorCalls(in: otherwise))
    case .setLiteral(let values), .tupleLiteral(let values):
        return values.reduce(into: Set<String>()) { $0.formUnion(localOperatorCalls(in: $1)) }
    case .tupleAccess(let tuple, _), .recordAccess(let tuple, _):
        return localOperatorCalls(in: tuple)
    case .recordLiteral(let fields):
        return fields.fields.reduce(into: Set<String>()) { $0.formUnion(localOperatorCalls(in: $1.value)) }
    case .functionLiteral(let domain, _, let body), .setFilter(let domain, _, let body),
         .forAll(let domain, _, let body), .exists(let domain, _, let body), .choose(let domain, _, let body):
        return localOperatorCalls(in: domain).union(localOperatorCalls(in: body))
    case .setMap(let value, _, let domain):
        return localOperatorCalls(in: value).union(localOperatorCalls(in: domain))
    case .except(let function, let key, let value):
        return localOperatorCalls(in: function)
            .union(localOperatorCalls(in: key))
            .union(localOperatorCalls(in: value))
    case .caseExpr(let pairs, let fallback):
        return pairs.reduce(into: fallback.map(localOperatorCalls(in:)) ?? Set<String>()) {
            $0.formUnion(localOperatorCalls(in: $1))
        }
    case .integerRange(let lower, let upper):
        return localOperatorCalls(in: lower).union(localOperatorCalls(in: upper))
    case .foldFunction(let operation, let initial, let sequence):
        return localOperatorCalls(in: operation.body)
            .union(localOperatorCalls(in: initial))
            .union(localOperatorCalls(in: sequence))
    case .operatorApplication(let operation, let arguments):
        let operatorCalls: Set<String>
        switch operation {
        case .lambda(let lambda): operatorCalls = localOperatorCalls(in: lambda.body)
        case .reference: operatorCalls = []
        }
        return arguments.reduce(into: operatorCalls) { $0.formUnion($1.referencedLocalOperators) }
    }
}

extension StateExpr {
    public static func int(_ value: Int) -> StateExpr { .value(.int(value)) }
    public static func bool(_ value: Bool) -> StateExpr { .value(.bool(value)) }
}

extension StateExpr: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .value(.int(value)) }
}

extension StateExpr: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .value(.bool(value)) }
}

extension StateExpr: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .value(.string(value)) }
}
