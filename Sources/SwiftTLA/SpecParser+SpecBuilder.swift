import SwiftSyntax
import SwiftParser
import SwiftBasicFormat

extension SpecParser {
    // MARK: - Unified spec builder parser

    public struct ParsedSpecComponents {
        public var variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)] = []
        public var actions: [ParsedAction] = []
        public var symmetricCollections: [ParsedSymmetricCollection] = []
        public var collectionActions: [ParsedCollectionAction] = []
        public var diagnostics: [SymmetricCollectionParseDiagnostic] = []
        public var invariants: [(name: String, body: StateExpr)] = []
        public var temporal: [(name: String, expr: TemporalExpr)] = []
        public var fairness: [FairnessCondition] = []
        public var constraint: StateExpr?
        public var imports: [String] = []
        public var importConfigurations: [FormalModuleConfiguration] = []
        public var moduleInstances: [FormalModuleInstance] = []
        public var formalParameters: [FormalModuleParameter] = []
        public var formalOperatorDefinitions: [FormalOperatorDefinition] = []
        public var definitions: [String] = []
        public var symmetrySets: [SymmetrySet] = []
        /// Opaque, pre-lowering Algorithm evidence retained independently of
        /// the ordinary parsed specification tree.
        public var algorithmFidelityTokens: [AlgorithmFidelityToken] = []
        public var constants: [String: TLAValue] = [:]
        /// Local named values (from NamedValue declarations, resolved in expressions)
        public var localConstants: [String: TLAValue] = [:]
    }

    public struct ParsedAction: Sendable, Equatable {
        public let name: String
        public let body: ActionExpr
        public let bindings: [ActionBinding]
        public let bindingSwiftTypes: [String: String]

        public init(
            name: String,
            body: ActionExpr,
            bindings: [ActionBinding] = [],
            bindingSwiftTypes: [String: String] = [:]
        ) {
            self.name = name
            self.body = body
            self.bindings = bindings
            self.bindingSwiftTypes = bindingSwiftTypes
        }
    }

    public struct ParsedSymmetricCollection {
        public let name: String
        public let elementType: String
        public let valueType: String
        public let verificationScope: Int
        public let source: String
        public let declaration: SymmetricCollectionDecl
    }

    public struct ParsedCollectionAction {
        public struct RuntimeBranch {
            public let guardExpressions: [String]
            public let updateExpression: String?
        }

        public let name: String
        public let collectionName: String
        public let body: ActionExpr
        public let runtimeBranches: [RuntimeBranch]
        public let source: String
    }

    /// Evidence retained when the source parser cannot form a formal model.
    ///
    /// The historical name is kept because callers already catch this error;
    /// it now covers every source-parser diagnostic, not only collections.
    public struct SymmetricCollectionParseDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
        public struct SourceSpan: Sendable, Hashable, CustomStringConvertible {
            public enum Location: Sendable, Hashable, CustomStringConvertible {
                case utf8Offset(Int)
                case unavailable

                public var description: String {
                    switch self {
                    case .utf8Offset(let offset): return "UTF-8 offset \(offset)"
                    case .unavailable: return "source offset unavailable"
                    }
                }
            }

            public let location: Location
            public let utf8Length: Int

            public init(location: Location, utf8Length: Int) {
                self.location = location
                self.utf8Length = utf8Length
            }

            public var description: String {
                "\(location), length \(utf8Length)"
            }
        }

        public enum ChangeStatus: String, Sendable, Hashable {
            case noFormalModelWasBuilt
        }

        /// Short stable summary for clients that already display a headline.
        public let message: String
        /// The exact Swift source fragment that the parser rejected.
        public let source: String
        public let sourceSpan: SourceSpan
        public let expected: String
        public let actual: String
        public let changeStatus: ChangeStatus
        public let nextSafeAction: String

        public init(
            message: String,
            source: String,
            expected: String = "a supported SwiftTLA declaration or expression",
            actual: String = "",
            nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again."
        ) {
            self.init(
                message: message,
                source: source,
                sourceSpan: SourceSpan(location: .unavailable, utf8Length: source.utf8.count),
                expected: expected,
                actual: actual,
                nextSafeAction: nextSafeAction
            )
        }

        public init(
            message: String,
            source: String,
            sourceSpan: SourceSpan,
            expected: String = "a supported SwiftTLA declaration or expression",
            actual: String = "",
            nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again."
        ) {
            self.message = message
            self.source = source
            self.sourceSpan = sourceSpan
            self.expected = expected
            self.actual = actual.isEmpty ? source.trimmingCharacters(in: .whitespacesAndNewlines) : actual
            self.changeStatus = .noFormalModelWasBuilt
            self.nextSafeAction = nextSafeAction
        }

        public init<Node: SyntaxProtocol>(message: String, source: Node) {
            let fragment = source.description.trimmingCharacters(in: .whitespacesAndNewlines)
            self.init(
                message: message,
                source: fragment,
                sourceSpan: SourceSpan(
                    location: .utf8Offset(source.positionAfterSkippingLeadingTrivia.utf8Offset),
                    utf8Length: fragment.utf8.count
                )
            )
        }

        public var description: String {
            "What failed: \(message) Where: \(sourceSpan). Expected: \(expected). "
                + "Actual: \(actual). Change status: \(changeStatus.rawValue). "
                + "Next safe action: \(nextSafeAction)"
        }
    }

      public static func parseSpecClosure(
        _ closure: ClosureExprSyntax,
        enumPhases: [String: [String: TLAValue]] = [:],
        enumDomains: [String: [TLAValue]] = [:]
      ) -> ParsedSpecComponents {
        parseContextLock.lock()
        defer { parseContextLock.unlock() }
        _enumPhases = enumPhases
        algorithmParseFailure = nil
        _enumDomains = enumDomains.isEmpty
            ? enumPhases.mapValues { phases in
                phases.keys.sorted().compactMap { phases[$0] }
            }
            : enumDomains
        var result = ParsedSpecComponents()
        let collectionTypes = collectSymmetricCollectionTypes(in: closure)
        for statement in closure.statements {
            if case .expr(let expression) = statement.item,
               let fc = expression.as(FunctionCallExprSyntax.self) {
                parseBuilderCall(fc, into: &result, collectionTypes: collectionTypes)
            } else if let forStmt = statement.item.as(ForStmtSyntax.self) {
                parseForLoop(forStmt, into: &result)
            } else if case .decl(let decl) = statement.item,
                      let varDecl = decl.as(VariableDeclSyntax.self) {
                parseVarDecl(varDecl, into: &result)
            }
        }
        return result
    }

    static func parseForLoop(_ forStmt: ForStmtSyntax, into result: inout ParsedSpecComponents) {
        guard let pattern = forStmt.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let sequence = forStmt.sequence.as(SequenceExprSyntax.self)
        else { return }

        // Extract range: 1...N → start=1, end=N (from literal or variable)
        let elements = Array(sequence.elements)
        guard elements.count == 3 else { return }

        // Evaluate start and end from sibling expressions
        var start = 1, end = 3
        if let startExpr = elements[0].as(IntegerLiteralExprSyntax.self) {
            start = Int(startExpr.literal.text) ?? 1
        }
        if let endExpr = elements[2].as(IntegerLiteralExprSyntax.self) {
            end = Int(endExpr.literal.text) ?? 3
        }

        let body = forStmt.body.statements
        for i in start...end {
            for bodyStmt in body {
                guard case .expr(let expr) = bodyStmt.item,
                      let fc = expr.as(FunctionCallExprSyntax.self)
                else { continue }
                parseBuilderCall(fc, into: &result, loopVar: pattern, loopValue: i)
            }
        }
    }

    /// Parses supported low-level `Var(...)` bindings into `ParsedSpecComponents.variables`.
    /// Handles both raw `Var("x", 0)` and rewrites where ModelMacro injected a string name.
    static func parseVarDecl(_ varDecl: VariableDeclSyntax, into result: inout ParsedSpecComponents) {
        for binding in varDecl.bindings {
            guard let patternName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let initializer = binding.initializer?.value,
                  let fc = initializer.as(FunctionCallExprSyntax.self)
            else { continue }

            let stateVarInfo = resolveVarCall(fc)
            let varTypeName = stateVarInfo?.1 ?? resolveVarTypeArg(fc)
            let callName = stateVarInfo?.0 ?? (resolveVarTypeArg(fc) != nil ? "Var" : nil)

            guard callName != nil else { continue }

            let args = Array(fc.arguments)

            if callName == "Var" && args.count < 2,
               let varTypeName,
               ["Function<", "Record<", "SetExpr<"].contains(where: varTypeName.contains),
               let name = args.first?.expression.as(StringLiteralExprSyntax.self)?.segments.description
                .replacingOccurrences(of: "\"", with: "") {
                result.variables.append((name, .int(0), nil, varTypeName))
                continue
            }

            if let rangeExpr = args.first(where: { $0.label?.text == "in" })?.expression {
                if callName == "SharedVar", let range = parseIntegerClosedRange(rangeExpr) {
                    result.variables.append((
                        patternName,
                        .int(range.lowerBound),
                        .setLiteral(range.map { .value(.int($0)) }),
                        "Int"
                    ))
                    continue
                }
                if callName == "SharedVar",
                   let initialSet = decodeStateExpr(rangeExpr),
                   case .setLiteral(let elements) = initialSet,
                   let first = elements.first,
                   let elementType = setExpressionElementTypeName(rangeExpr) {
                    let initial = (try? first.evaluate(in: [:])) ?? .int(0)
                    result.variables.append((patternName, initial, initialSet, elementType))
                    continue
                }
                let lowerBound = parseRangeLowerBound(rangeExpr)
                result.variables.append((patternName, .int(lowerBound), nil, varTypeName))
                continue
            }

            if let valuesArg = args.first(where: { $0.label?.text == "values" })?.expression {
                let firstValue = parseValuesFirst(valuesArg)
                result.variables.append((patternName, .string(firstValue), nil, varTypeName))
                continue
            }

            guard !args.isEmpty else { continue }

            if let stringLit = args[0].expression.as(StringLiteralExprSyntax.self) {
                let varName = stringLit.segments.description.replacingOccurrences(of: "\"", with: "")
                let initial: TLAValue = args.count >= 2
                    ? parsedInitialValue(args[1].expression)
                    : .int(0)
                let inferredType = args.count >= 2 ? initialValueTypeName(from: args[1].expression) : nil
                result.variables.append((varName, initial, nil, varTypeName ?? inferredType))
            } else {
                let initial: TLAValue = parsedInitialValue(args[0].expression)
                let inferredType = initialValueTypeName(from: args[0].expression)
                result.variables.append((patternName, initial, nil, varTypeName ?? inferredType))
            }
        }
    }

    /// Resolves a supported low-level variable call expression.
    /// Returns nil if the call is not a variable constructor.
    static func resolveVarCall(_ fc: FunctionCallExprSyntax) -> (String, String?)? {
        if let ref = fc.calledExpression.as(DeclReferenceExprSyntax.self) {
            guard ["Var", "SharedVar"].contains(ref.baseName.text) else { return nil }
            return (ref.baseName.text, nil)
        }
        if let generic = fc.calledExpression.as(GenericSpecializationExprSyntax.self),
           let ref = generic.expression.as(DeclReferenceExprSyntax.self) {
            guard ref.baseName.text == "Var" else { return nil }
            let typeArgs = Array(generic.genericArgumentClause.arguments)
            let swiftTypeName = typeArgs.count >= 1
                ? typeArgs[0].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            return (ref.baseName.text, swiftTypeName)
        }
        return nil
    }

    static func resolveVarTypeArg(_ fc: FunctionCallExprSyntax) -> String? {
        guard let generic = fc.calledExpression.as(GenericSpecializationExprSyntax.self),
              let ref = generic.expression.as(DeclReferenceExprSyntax.self),
              ref.baseName.text == "Var"
        else {
            if let ref = fc.calledExpression.as(DeclReferenceExprSyntax.self),
               ref.baseName.text == "Var" {
                return nil
            }
            return nil
        }
        let typeArgs = Array(generic.genericArgumentClause.arguments)
        return typeArgs.count >= 1
            ? typeArgs[0].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
    }

    static func parseIntegerClosedRange(_ expression: ExprSyntax) -> ClosedRange<Int>? {
        guard let sequence = expression.as(SequenceExprSyntax.self) else { return nil }
        let elements = Array(sequence.elements)
        guard elements.count == 3,
              elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text == "...",
              let lowerSyntax = elements[0].as(IntegerLiteralExprSyntax.self),
              let upperSyntax = elements[2].as(IntegerLiteralExprSyntax.self),
              let lower = Int(lowerSyntax.literal.text),
              let upper = Int(upperSyntax.literal.text),
              lower <= upper
        else { return nil }
        return lower...upper
    }

    /// Returns the formal element type from `SetExpr<Element>.literal(...)`.
    /// This is syntax-only: the parser must not consult the runtime builder.
    static func setExpressionElementTypeName(_ expression: ExprSyntax) -> String? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Where",
           let candidates = call.arguments.first?.expression {
            return setExpressionElementTypeName(candidates)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           name == "Subsets" || name == "NonEmptySubsets",
           let values = call.arguments.first(where: { $0.label?.text == "of" })?.expression,
           let element = setExpressionElementTypeName(values) {
            return "SetExpr<\(element)>"
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Functions",
           let domainSyntax = call.arguments.first(where: { $0.label?.text == "from" })?.expression,
           let domain = finiteAlgorithmDomain(domainSyntax),
           let rangeSyntax = call.arguments.first(where: { $0.label?.text == "to" })?.expression,
           let range = setExpressionElementTypeName(rangeSyntax) {
            return "Function<\(domain.typeName), \(range)>"
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           name == "Sequences" || name == "SortedSequences" || name == "ZeroBasedSequences",
           let members = call.arguments.first(where: { $0.label?.text == "of" })?.expression,
           let element = setExpressionElementTypeName(members) {
            return name == "ZeroBasedSequences"
                ? "ZeroBasedSequence<\(element)>"
                : "TupleExpr<\(element)>"
        }
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "literal",
              let base = member.base
        else { return nil }
        let typeName = base.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typeName.hasPrefix("SetExpr<"), typeName.hasSuffix(">") else { return nil }
        return String(typeName.dropFirst("SetExpr<".count).dropLast())
    }

    /// Extracts the lower bound from a range expression like `1...12`.
    static func parseRangeLowerBound(_ expression: ExprSyntax) -> Int {
        if let seq = expression.as(SequenceExprSyntax.self) {
            let elements = Array(seq.elements)
            if let firstInt = elements.first?.as(IntegerLiteralExprSyntax.self),
               let lower = Int(firstInt.literal.text) {
                return lower
            }
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let firstInt = infix.leftOperand.as(IntegerLiteralExprSyntax.self),
           let lower = Int(firstInt.literal.text) {
            return lower
        }
        return 0
    }

    /// Extracts the first string value from `["a", "b"]`.
    static func parseValuesFirst(_ expression: ExprSyntax) -> String {
        if let array = expression.as(ArrayExprSyntax.self),
           let first = array.elements.first?.expression.as(StringLiteralExprSyntax.self) {
            return first.segments.description.replacingOccurrences(of: "\"", with: "")
        }
        return ""
    }

    /// Converts a Swift initializer expression to a TLAValue.
    static func parseInitialExpr(_ expression: ExprSyntax) -> TLAValue {
        if let decoded = decodeStateExpr(expression), case .value(let value) = decoded {
            return value
        }
        if let intVal = expression.as(IntegerLiteralExprSyntax.self) {
            return .int(Int(intVal.literal.text) ?? 0)
        }
        if let boolVal = expression.as(BooleanLiteralExprSyntax.self) {
            return .bool(boolVal.literal.text == "true")
        }
        if let stringLit = expression.as(StringLiteralExprSyntax.self) {
            return .string(stringLit.segments.description.replacingOccurrences(of: "\"", with: ""))
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            if let baseRef = memberAccess.base?.as(DeclReferenceExprSyntax.self),
               let cases = _enumPhases[baseRef.baseName.text],
               let value = cases[memberAccess.declName.baseName.text] {
                return value
            }
            let caseName = memberAccess.declName.baseName.text
            for (_, cases) in _enumPhases {
                if let value = cases[caseName] { return value }
            }
        }
        if let fc = expression.as(FunctionCallExprSyntax.self),
           let memberAccess = fc.calledExpression.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "TLAValue" {
            return parseTLAValueConstructor(name: memberAccess.declName.baseName.text, call: fc) ?? .int(0)
        }
        return .int(0)
    }

    /// Returns the enum type name if `expression` is an enum case reference.
    /// `.idle` → `nil` (implicit member, type unknown from this AST).
    /// `CameraMode.idle` → `"CameraMode"` (explicit member, type known).
    static func enumCaseTypeName(from expression: ExprSyntax) -> String? {
        guard let memberAccess = expression.as(MemberAccessExprSyntax.self) else { return nil }
        if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            return base.baseName.text
        }
        return nil
    }

    static func initialValueTypeName(from expression: ExprSyntax) -> String? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "IntRange" {
            return "SetExpr<Int>"
        }
        if expression.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if expression.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        if expression.is(StringLiteralExprSyntax.self) { return "String" }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.arguments.isEmpty,
           call.trailingClosure == nil {
            let constructor = call.calledExpression.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if constructor.hasPrefix("SetExpr<") || constructor.hasPrefix("TupleExpr<")
                || constructor.hasPrefix("ZeroBasedSequence<") {
                return constructor
            }
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "filled",
           let base = member.base {
            let typeName = base.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if typeName.hasPrefix("ZeroBasedSequence<") { return typeName }
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLAValue" {
            return "TLAValue"
        }
        return enumCaseTypeName(from: expression)
    }

    /// Evaluates a closed typed formal initializer through the same expression
    /// decoder used for actions. Literal-only parsing is insufficient for
    /// values such as `IntRange(1, through: 4)`.
    static func parsedInitialValue(_ expression: ExprSyntax) -> TLAValue {
        if let decoded = decodeStateExpr(expression),
           let value = try? decoded.evaluate(in: [:]) {
            return value
        }
        return parseInitialExpr(expression)
    }

    static func parseBuilderCall(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        loopVar: String? = nil,
        loopValue: Int? = nil,
        collectionTypes: [String: (element: String, value: String)] = [:]
    ) {
        guard let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else { return }

        switch name {
        case "Algorithm":
            parseAlgorithm(call, into: &result)
        case "SymmetricCollection":
            parseSymmetricCollectionDecl(call, into: &result, collectionTypes: collectionTypes)
        case "CollectionAction":
            parseCollectionAction(call, into: &result)
        case "Variable":
            let existingVariable = call.arguments.first?.expression
                .as(DeclReferenceExprSyntax.self)?.baseName.text
            parseVariableDecl(call, into: &result)
            if let existingVariable {
                mergeVariableDeclaration(named: existingVariable, into: &result)
            }
            validateVariableDeclaration(call, into: &result)
        case "Action":
            parseAction(call, into: &result, loopVar: loopVar, loopValue: loopValue)
        case "Invariant":
            parseInvariant(call, into: &result)
        case "Constraint":
            if let argument = call.arguments.first,
               let expression = decodeStateExpr(argument.expression) {
                result.constraint = result.constraint.map { .and($0, expression) } ?? expression
            }
        case "Constant":
            parseConstantDecl(call, into: &result)
        case "Parameter":
            guard let name = extractStringArg(call, index: 0), !name.isEmpty else {
                result.diagnostics.append(.init(message: "Parameter requires a name.", source: call))
                return
            }
            guard !result.formalParameters.map(\.name).contains(name) else {
                result.diagnostics.append(.init(message: "Parameter '\(name)' is declared more than once.", source: call))
                return
            }
            let kind: FormalModuleParameterKind
            if let kindExpression = call.arguments.first(where: { $0.label?.text == "kind" })?.expression {
                guard let member = kindExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
                      let parsedKind = FormalModuleParameterKind(rawValue: member)
                else {
                    result.diagnostics.append(.init(message: "Parameter kind must be .constant or .variable.", source: kindExpression))
                    return
                }
                kind = parsedKind
            } else {
                kind = .constant
            }
            result.formalParameters.append(FormalModuleParameter(name, kind: kind))
        case "FormalDefinition":
            parseFormalDefinition(call, into: &result)
        case "Definition":
            parseDefinition(call, into: &result)
        case "LeadsTo", "Eventually", "Always", "AlwaysEventually", "EventuallyAlways":
            if let expr = decodeTemporal(call) {
                result.temporal.append((name, expr))
            }
        case "WeakFairness", "StrongFairness":
            if let fc = decodeFairness(call) {
                result.fairness.append(fc)
            }
        case "Value":
            if let name = extractStringArg(call, index: 0),
               parseNamedValueConstant(call, name: name, into: &result) { }
        case "UseSpec":
            if let name = extractStringArg(call, index: 0),
               let spec = SpecRegistry.lookup(name) {
                result.variables += spec.variables.map { (name: $0.name, initial: $0.initial, initialSet: $0.initialSet, swiftTypeName: nil) }
                result.invariants += spec.invariants.map { (name: $0.name, body: $0.body) }
                result.actions += spec.actions.map { ParsedAction(name: $0.name, body: $0.body, bindings: $0.bindings) }
            }
        case "Import":
            guard let argument = call.arguments.first?.expression else { return }
            let reference = argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let moduleName = reference.split(separator: ".").first,
                  !moduleName.isEmpty
            else {
                result.diagnostics.append(.init(message: "Import requires a named formal module.", source: call))
                return
            }
            let resolvedModuleName = FormalModuleRegistry.lookup(String(moduleName))?.name
                ?? String(moduleName)
            result.imports.append(resolvedModuleName)
            if let configuration = parseFormalModuleConfiguration(
                call,
                moduleName: resolvedModuleName
            ) {
                result.importConfigurations.append(configuration)
            }
        case "Instance":
            parseFormalModuleInstance(call, into: &result)
        case "Symmetry":
            parseSymmetry(call, into: &result)
        default:
            break
        }
    }

    private static func parseSymmetry(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let variableName = extractStringArg(call, index: 0), !variableName.isEmpty,
              let valuesSyntax = call.arguments.dropFirst().first?.expression,
              let values = parseSymmetryValues(valuesSyntax)
        else {
            result.diagnostics.append(.init(
                message: "Symmetry requires a name and a finite domain.",
                source: call.description,
                expected: "Symmetry(\"TxId\", Set(Transaction.all))"
            ))
            return
        }
        result.symmetrySets.append(SymmetrySet(variableName: variableName, values: Set(values)))
    }

    private static func parseSymmetryValues(_ expression: ExprSyntax) -> [TLAValue]? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Set",
              let domainSyntax = call.arguments.first?.expression,
              let domain = finiteAlgorithmDomain(domainSyntax)
        else { return nil }
        return domain.values
    }

    private static func parseFormalDefinition(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let definition = decodeFormalDefinition(call)
        else {
            result.diagnostics.append(.init(
                message: "FormalDefinition requires a name, supported formal parameters, and a formal body expression.",
                source: call.description,
                expected: "FormalDefinition(\"name\", parameters: [.value(\"value\")], body: expression) or FormalDefinition(\"name\", taking: Int.self) { value in expression }",
                nextSafeAction: "Use the formal-parameter form or a unary/binary typed closure with supported formal expressions."
            ))
            return
        }
        let name = definition.name
        let parameters = definition.parameters
        let body = definition.body
        guard !result.formalOperatorDefinitions.contains(where: { $0.name == name }) else {
            result.diagnostics.append(.init(
                message: "FormalDefinition '\(name)' is declared more than once.",
                source: call
            ))
            return
        }
        guard Set(parameters.map(\.name)).count == parameters.count else {
            result.diagnostics.append(.init(
                message: "FormalDefinition '\(name)' cannot repeat a parameter name.",
                source: call
            ))
            return
        }
        result.formalOperatorDefinitions.append(
            FormalOperatorDefinition(name: name, parameters: parameters, body: body)
        )
    }

    static func decodeFormalDefinition(
        _ call: FunctionCallExprSyntax
    ) -> FormalOperatorDefinition? {
        guard let name = extractStringArg(call, index: 0), !name.isEmpty else { return nil }

        if let parametersSyntax = call.arguments.first(where: { $0.label?.text == "parameters" })?.expression,
           let bodySyntax = call.arguments.first(where: { $0.label?.text == "body" })?.expression,
           let parameters = parseFormalParameters(parametersSyntax),
           let body = decodeTypedFacadeValue(bodySyntax, substitutions: [:]) ?? decodeStateExpr(bodySyntax) {
            return FormalOperatorDefinition(name: name, parameters: parameters, body: body)
        }

        guard let closure = call.trailingClosure,
              closure.statements.count == 1,
              case .expr(let bodySyntax) = closure.statements.first?.item
        else { return nil }
        let parameters = closureParameterNames(in: closure)
        let typeWitnesses = Array(call.arguments.dropFirst())
        guard (1...2).contains(parameters.count),
              parameters.count == typeWitnesses.count,
              typeWitnesses.first?.label?.text == "taking",
              typeWitnesses.dropFirst().allSatisfy({ $0.label == nil }),
              typeWitnesses.allSatisfy({ isMetatype($0.expression) })
        else { return nil }
        let formalParameters = parameters.enumerated().map { index, _ in
            FormalParameter.value("value\(index)")
        }
        let substitutions = Dictionary(uniqueKeysWithValues: zip(parameters, formalParameters).map {
            ($0, StateExpr.variable($1.name))
        })
        guard let body = decodeTypedFacadeValue(bodySyntax, substitutions: substitutions) else { return nil }
        return FormalOperatorDefinition(
            name: name,
            parameters: formalParameters,
            body: body
        )
    }

    private static func parseDefinition(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        let arguments = Array(call.arguments)
        guard arguments.count == 1,
              call.trailingClosure == nil,
              let literal = arguments[0].expression.as(StringLiteralExprSyntax.self),
              literal.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) }),
              let definition = extractStringArg(call, index: 0)
        else {
            result.diagnostics.append(.init(
                message: "Definition requires a literal TLA+ declaration.",
                source: call,
                expected: "Definition(\"Name == expression\")",
                nextSafeAction: "Pass the complete source-only TLA+ declaration as a string literal."
            ))
            return
        }
        result.definitions.append(definition)
    }

    private static func parseFormalParameters(_ expression: ExprSyntax) -> [FormalParameter]? {
        guard let array = expression.as(ArrayExprSyntax.self) else { return nil }
        let parameters: [FormalParameter?] = array.elements.map { element -> FormalParameter? in
            guard let call = element.expression.as(FunctionCallExprSyntax.self),
                  let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  let name = extractStringArg(call, index: 0)
            else { return nil }
            switch member.declName.baseName.text {
            case "value": return .value(name)
            case "operator":
                guard let arityExpression = call.arguments.first(where: { $0.label?.text == "arity" })?.expression,
                      let arityLiteral = arityExpression.as(IntegerLiteralExprSyntax.self),
                      let arity = Int(arityLiteral.literal.text), arity >= 0
                else { return nil }
                return .operator(name, arity: arity)
            default: return nil
            }
        }
        guard parameters.allSatisfy({ $0 != nil }) else { return nil }
        return parameters.compactMap { $0 }
    }

    private static func parseFormalModuleInstance(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let name = extractStringArg(call, index: 0),
              let moduleArgument = call.arguments.first(where: { $0.label?.text == "of" })?.expression
        else {
            result.diagnostics.append(.init(message: "Instance requires a name and a named formal module.", source: call))
            return
        }
        let source = moduleArgument.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let moduleName = source.split(separator: ".").first.map(String.init),
              let module = FormalModuleRegistry.lookup(moduleName)
        else {
            result.diagnostics.append(.init(message: "Instance requires a registered formal module.", source: call))
            return
        }
        let arguments: [ModuleArgument]
        if let withExpression = call.arguments.first(where: { $0.label?.text == "with" })?.expression {
            guard let array = withExpression.as(ArrayExprSyntax.self) else {
                result.diagnostics.append(.init(message: "Instance 'with' requires an array of ModuleArgument values.", source: call))
                return
            }
            var parsedArguments: [ModuleArgument] = []
            for element in array.elements {
                guard let argumentCall = element.expression.as(FunctionCallExprSyntax.self),
                      argumentCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ModuleArgument",
                      let parameter = extractStringArg(argumentCall, index: 0),
                      let valueSyntax = argumentCall.arguments.first(where: { $0.label?.text == "value" })?.expression,
                      let value = decodeTypedFacadeValue(valueSyntax, substitutions: [:]) ?? decodeStateExpr(valueSyntax)
                else {
                    result.diagnostics.append(.init(
                        message: "Each Instance argument must be ModuleArgument(\"parameter\", value: expression).",
                        source: element.expression
                    ))
                    return
                }
                parsedArguments.append(ModuleArgument(parameter, expression: value))
            }
            arguments = parsedArguments
        } else {
            arguments = []
        }
        guard Set(arguments.map(\.parameter)).count == arguments.count else {
            result.diagnostics.append(.init(message: "An Instance cannot bind the same parameter twice.", source: call))
            return
        }
        let declaredParameters = Set(module.formalParameters.map(\.name))
        guard Set(arguments.map(\.parameter)).isSubset(of: declaredParameters) else {
            result.diagnostics.append(.init(message: "Instance arguments must name parameters declared by '\(module.name)'.", source: call))
            return
        }
        result.moduleInstances.append(FormalModuleInstance(name, of: module, with: arguments))
    }

    private static func parseFormalModuleConfiguration(
        _ call: FunctionCallExprSyntax,
        moduleName: String
    ) -> FormalModuleConfiguration? {
        guard let argument = call.arguments.first(where: { $0.label?.text == "configuring" })?.expression
        else { return nil }
        let source = argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard moduleName == "ZSequences", source.hasPrefix("ZSequences.boundedNaturalNumbers(") else {
            return nil
        }
        let contents = source
            .replacingOccurrences(of: "ZSequences.boundedNaturalNumbers(", with: "")
            .dropLast()
        let bounds = contents.components(separatedBy: "...")
        guard bounds.count == 2,
              let lower = Int(bounds[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let upper = Int(bounds[1].trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return ZSequences.boundedNaturalNumbers(lower...upper)
    }

    static func mergeVariableDeclaration(
        named name: String,
        into result: inout ParsedSpecComponents
    ) {
        let matchingIndices = result.variables.indices.filter { result.variables[$0].name == name }
        guard matchingIndices.count > 1, let latest = matchingIndices.last else { return }
        let existing = result.variables[matchingIndices[0]]
        let replacement = result.variables[latest]
        result.variables.remove(at: latest)
        result.variables[matchingIndices[0]] = (
            replacement.name,
            replacement.initial,
            replacement.initialSet,
            replacement.swiftTypeName ?? existing.swiftTypeName
        )
    }

    static func validateVariableDeclaration(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        let arguments = Array(call.arguments)
        guard let reference = arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text else { return }
        guard arguments.count == 1 else {
            if arguments.count == 2, [nil, "in"].contains(arguments[1].label?.text) { return }
            result.diagnostics.append(.init(message: "Malformed Variable declaration", source: call))
            return
        }
        guard result.variables.contains(where: { $0.name == reference }) else {
            result.diagnostics.append(.init(
                message: "Variable '\(reference)' is not bound by a prior Var declaration",
                source: call
            ))
            return
        }
    }

    static func parseAction(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        loopVar: String?,
        loopValue: Int?
    ) {
        guard let actionName = extractStringArg(call, index: 0, loopVar: loopVar, loopValue: loopValue),
              let closure = call.trailingClosure
        else { return }
        let arguments = Array(call.arguments)
        let bindingArguments = arguments.dropFirst()
        if bindingArguments.isEmpty {
            if let body = decodeActionFromClosure(closure) {
                result.actions.append(.init(name: actionName, body: body))
            } else {
                // Action body uses unsupported constructs (existsAction, etc.).
                // Store a placeholder body; the macro will fall back to interpreter
                // trampoline which reads the body from the runtime spec at Self.spec.
                result.actions.append(.init(name: actionName, body: .chooseAction("_parser_skip", .value(.bool(false)))))
            }
            return
        }
        guard bindingArguments.count == 1,
              let argument = bindingArguments.first,
              argument.label?.text == "parameters",
              let parameterList = argument.expression.as(ArrayExprSyntax.self)
        else {
            result.diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' requires a parameters list of ActionParameter descriptors.",
                source: call
            ))
            return
        }
        var bindings: [ActionBinding] = []
        for (index, element) in parameterList.elements.enumerated() {
            guard let binding = actionParameter(
                element.expression,
                actionName: actionName,
                position: index + 1,
                diagnostics: &result.diagnostics
            ) else {
                continue
            }
            if bindings.contains(where: { $0.name == binding.name }) {
                result.diagnostics.append(.init(
                    message: "Parameterized action '\(actionName)' parameter '\(binding.name)' duplicates an earlier parameter name.",
                    source: element.expression
                ))
                continue
            }
            bindings.append(binding)
        }
        guard result.diagnostics.isEmpty else { return }
        guard !bindings.isEmpty else {
            result.diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' requires at least one ActionParameter descriptor.",
                source: parameterList
            ))
            return
        }
        guard closureParameterNames(in: closure).isEmpty else {
            result.diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' uses the removed closure-parameter syntax; bind values through its parameters list.",
                source: closure
            ))
            return
        }
        guard let body = decodeActionFromClosure(closure) else {
            if let expression = unsupportedActionExpression(in: closure),
               let typedUpdate = typedUpdateExpression(in: expression) {
                let message = "Parameterized action '\(actionName)' contains an unsupported typed update; "
                    + "use a directly written finite enum case or schema field token."
                result.diagnostics.append(.init(
                    message: message,
                    source: typedUpdate
                ))
            } else if let expression = unsupportedActionExpression(in: closure) {
                result.diagnostics.append(.init(
                    message: "Parameterized action '\(actionName)' contains an unsupported action expression.",
                    source: expression
                ))
            } else {
                result.diagnostics.append(.init(
                    message: "Parameterized action '\(actionName)' contains an unsupported action expression.",
                    source: closure
                ))
            }
            return
        }
        result.actions.append(.init(
            name: actionName,
            body: body,
            bindings: bindings
        ))
    }

    static func unsupportedActionExpression(in closure: ClosureExprSyntax) -> ExprSyntax? {
        closure.statements.compactMap { statement in
            guard case .expr(let expression) = statement.item,
                  decodeActionExpr(expression) == nil
            else { return nil }
            return expression
        }.first
    }

    static func typedUpdateExpression(in expression: ExprSyntax) -> ExprSyntax? {
        if let call = expression.as(FunctionCallExprSyntax.self) {
            if call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "updating" {
                return expression
            }
            for argument in call.arguments {
                if let update = typedUpdateExpression(in: argument.expression) {
                    return update
                }
            }
            if let closure = call.trailingClosure {
                for statement in closure.statements {
                    guard case .expr(let nested) = statement.item else { continue }
                    if let update = typedUpdateExpression(in: nested) {
                        return update
                    }
                }
            }
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            return typedUpdateExpression(in: infix.leftOperand)
                ?? typedUpdateExpression(in: infix.rightOperand)
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            for element in sequence.elements {
                if let update = typedUpdateExpression(in: ExprSyntax(element)) {
                    return update
                }
            }
        }
        if let tuple = expression.as(TupleExprSyntax.self) {
            for element in tuple.elements {
                if let update = typedUpdateExpression(in: element.expression) {
                    return update
                }
            }
        }
        return nil
    }

    static func actionParameter(
        _ expression: ExprSyntax,
        actionName: String,
        position: Int,
        diagnostics: inout [SymmetricCollectionParseDiagnostic]
    ) -> ActionBinding? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ActionParameter"
        else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter #\(position) requires an ActionParameter descriptor.",
                source: expression
            ))
            return nil
        }
        guard let name = extractStringArg(call, index: 0), !name.isEmpty else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter #\(position) requires a non-empty name.",
                source: call
            ))
            return nil
        }
        guard let valuesExpression = call.arguments.first(where: { $0.label?.text == "values" })?.expression else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter '\(name)' requires an explicitly written finite values array.",
                source: call
            ))
            return nil
        }
        guard let values = finiteDomain(valuesExpression) else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter '\(name)' requires an explicitly written finite values array.",
                source: valuesExpression
            ))
            return nil
        }
        guard !values.isEmpty else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter '\(name)' requires a non-empty finite values array.",
                source: valuesExpression
            ))
            return nil
        }
        guard Set(values).count == values.count else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter '\(name)' has duplicate finite-domain values.",
                source: valuesExpression
            ))
            return nil
        }
        return ActionBinding(name: name, values: values)
    }

    static func closureParameterNames(in closure: ClosureExprSyntax) -> [String] {
        guard let parameters = closure.signature?.parameterClause else { return [] }
        switch parameters {
        case .simpleInput(let list): return list.map { $0.name.text }
        case .parameterClause(let clause):
            return clause.parameters.map { $0.secondName?.text ?? $0.firstName.text }
        }
    }

    static func finiteDomain(_ expression: ExprSyntax) -> [TLAValue]? {
        if let array = expression.as(ArrayExprSyntax.self) {
            let values = array.elements.compactMap { element -> TLAValue? in
                guard case .value(let value)? = decodeStateExpr(element.expression) else { return nil }
                return value
            }
            return values.count == array.elements.count ? values : nil
        }
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "finiteValues",
              let type = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }
        return _enumDomains[type]
    }

    static func parseInvariant(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let name = extractStringArg(call, index: 0), let closure = call.trailingClosure else {
            result.diagnostics.append(.init(
                message: "Invariant declaration requires a name and a supported invariant expression.",
                source: call.description
            ))
            return
        }
        guard let body = parseInvariantBody(
            closure,
            symmetricCollections: Set(result.symmetricCollections.map(\.name))
        ) else {
            // Invariant uses unsupported expressions (for loops, function calls).
            // Skip it; runtime verifyInvariants() checks the actual invariant.
            return
        }
        result.invariants.append((name, body))
    }

    static func parseInvariantBody(
        _ closure: ClosureExprSyntax,
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        var expressions: [StateExpr] = []
        for statement in closure.statements {
            guard case .expr(let expression) = statement.item else { continue }
            guard let parsed = decodeInvariantExpression(expression, symmetricCollections: symmetricCollections)
            else { return nil }
            expressions.append(parsed)
        }
        guard let first = expressions.first else { return nil }
        return expressions.dropFirst().reduce(first, StateExpr.and)
    }

    static func decodeInvariantExpression(
        _ expression: ExprSyntax,
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        if let predicate = parseCollectionPredicate(expression, symmetricCollections: symmetricCollections) {
            return predicate
        }
        let unwrapped = unwrapSingleElementTuple(expression)
        if unwrapped != expression {
            return decodeInvariantExpression(unwrapped, symmetricCollections: symmetricCollections)
        }
        return decodeStateExpr(unwrapped)
    }

    static func unsupportedInvariantExpression(
        in closure: ClosureExprSyntax,
        symmetricCollections: Set<String>
    ) -> ExprSyntax? {
        for statement in closure.statements {
            guard case .expr(let expression) = statement.item else { continue }
            if decodeInvariantExpression(expression, symmetricCollections: symmetricCollections) == nil {
                return expression
            }
        }
        return nil
    }

    static func parseCollectionPredicate(
        _ expression: ExprSyntax,
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              let collection = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
              symmetricCollections.contains(collection),
              let kind = CollectionPredicateKind(rawValue: access.declName.baseName.text),
              let closure = call.trailingClosure
                ?? call.arguments.first?.expression.as(ClosureExprSyntax.self),
              let parameter = collectionPredicateParameter(in: closure)
        else { return nil }

        let member = FreshVarName.fresh()
        let rewrittenStatements = closure.statements.map { statement in
            PredicateValueRewriter(
                parameter: parameter,
                replacement: "\(collection).applying(\(member))"
            ).visit(statement)
        }
        let rewrittenClosure = closure.with(\.statements, CodeBlockItemListSyntax(rewrittenStatements))
        guard let bodyExpr = rewrittenClosure.statements.first.flatMap({ statement -> ExprSyntax? in
            guard case .expr(let e) = statement.item else { return nil }
            return e
        }), let body = decodeInvariantExpression(bodyExpr, symmetricCollections: symmetricCollections)
        else { return nil }

        let domain = StateExpr.domain(.variable(collection))
        switch kind {
        case .allSatisfy: return .forAll(domain, member, body)
        case .contains: return .exists(domain, member, body)
        }
    }

    static func collectionPredicateParameter(in closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause else { return "$0" }
        switch parameters {
        case .simpleInput(let list):
            guard list.count == 1 else { return nil }
            return list.first?.name.text
        case .parameterClause(let clause):
            guard clause.parameters.count == 1, let parameter = clause.parameters.first else { return nil }
            return parameter.secondName?.text ?? parameter.firstName.text
        }
    }

    enum CollectionPredicateKind: String {
        case allSatisfy
        case contains
    }

    final class PredicateValueRewriter: SyntaxRewriter {
        let parameter: String
        let replacement: String
        var closureDepth = 0

        init(parameter: String, replacement: String) {
            self.parameter = parameter
            self.replacement = replacement
        }

        override func visit(_ node: ClosureExprSyntax) -> ExprSyntax {
            if closureDepth > 0, collectionPredicateParameter(in: node) == parameter {
                return ExprSyntax(node)
            }
            closureDepth += 1
            defer { closureDepth -= 1 }
            return super.visit(node)
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            guard node.baseName.text == parameter else { return super.visit(node) }
            return ExprSyntax(stringLiteral: replacement)
        }
    }

}
