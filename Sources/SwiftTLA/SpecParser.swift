import SwiftSyntax
import SwiftParser
import SwiftBasicFormat

/// Parses SwiftSyntax AST nodes into DSL types (StateExpr, ActionExpr, etc.).
/// Every AST pattern maps deterministically to a DSL value.
/// Tests live in SpecParserTests.
public enum SpecParser {

    /// Local constants collected during parsing (for `Value` / `let` bindings).
    nonisolated(unsafe) private static var _constants: [String: TLAValue] = [:]

    /// Enum phase map (typeName → caseName → TLAValue) set per-parse by the macro.
    nonisolated(unsafe) private static var _enumPhases: [String: [String: TLAValue]] = [:]

    // MARK: - Compact expression decoder

    public static func decodeStateExpr(_ expression: ExprSyntax) -> StateExpr? {
        if let intLit = expression.as(IntegerLiteralExprSyntax.self) {
            return .value(.int(Int(intLit.literal.text) ?? 0))
        }
        if let boolLit = expression.as(BooleanLiteralExprSyntax.self) {
            return .value(.bool(boolLit.literal.text == "true"))
        }
        if let stringLit = expression.as(StringLiteralExprSyntax.self) {
            return .value(.string(stringLit.segments.description))
        }
        if let ref = expression.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            if let resolved = _constants[name] { return .value(resolved) }
            return .variable(name)
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self),
           let baseRef = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           let cases = _enumPhases[baseRef.baseName.text] {
            return cases[memberAccess.declName.baseName.text].map { .value($0) }
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base,
           let selfExpr = decodeStateExpr(base) {
            let propName = memberAccess.declName.baseName.text
            switch propName {
            case "cardinality": return .cardinality(selfExpr)
            case "flattened": return .unionAll(selfExpr)
            case "subsets": return .powerSet(selfExpr)
            case "domain": return .domain(selfExpr)
            case "count": return .tupleLength(selfExpr)
            case "head": return .tupleHead(selfExpr)
            case "tail": return .tupleTail(selfExpr)
            case "isEmpty": return .equal(.cardinality(selfExpr), .value(.int(0)))
            default: return .recordAccess(selfExpr, propName)
            }
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            if let result = decodeCollectionPredicate(call) { return result }
            return decodeMethodCall(memberAccess, call)
        }
        if let tuple = expression.as(TupleExprSyntax.self),
           let single = tuple.elements.first?.expression {
            return decodeStateExpr(single)
        }
        if let seq = expression.as(SequenceExprSyntax.self) {
            return decodeInfixExpr(Array(seq.elements))
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let opText = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
           let lhs = decodeStateExpr(infix.leftOperand),
           let rhs = decodeStateExpr(infix.rightOperand) {
            return applyInfixOp(opText, lhs, rhs)
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            let operand = decodeStateExpr(prefix.expression)
            if prefix.operator.text == "!", let operand { return .not(operand) }
            if prefix.operator.text == "-", let operand { return .negate(operand) }
        }
        return nil
    }

    private static func decodeMethodCall(_ memberAccess: MemberAccessExprSyntax, _ call: FunctionCallExprSyntax) -> StateExpr? {
        let methodName = memberAccess.declName.baseName.text
        let args = Array(call.arguments)
        let base = memberAccess.base
        let selfExpr = base.flatMap { decodeStateExpr($0) }
        switch methodName {
        case "isIn":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .in(selfExpr, argExpr)
        case "union":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .union(selfExpr, argExpr)
        case "intersection":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .intersection(selfExpr, argExpr)
        case "subtracting":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .setDifference(selfExpr, argExpr)
        case "isSubset":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .subset(selfExpr, argExpr)
        case "applying":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .functionApply(selfExpr, argExpr)
        case "filtering":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .setFilter(selfExpr, .fresh(), argExpr)
        case "mapping":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .setMap(argExpr, .fresh(), selfExpr)
        case "appending":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .tupleAppend(selfExpr, argExpr)
        case "concatenating":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .tupleConcatenate(selfExpr, argExpr)
        case "integerDivided":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            return .integerDivide(selfExpr, argExpr)
        case "updated":
            guard let selfExpr, args.count >= 2,
                  let key = decodeStateExpr(args[0].expression),
                  let val = decodeStateExpr(args[1].expression) else { return nil }
            return .except(selfExpr, key, val)
        case "at":
            guard let selfExpr,
                  let idx = args.first?.expression.as(IntegerLiteralExprSyntax.self).flatMap({ Int($0.literal.text) })
            else { return nil }
            return .tupleAccess(selfExpr, idx)
        case "set", "tuple", "singleton":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            if let array = args.first?.expression.as(ArrayExprSyntax.self) {
                let exprs = array.elements.compactMap { decodeStateExpr($0.expression) }
                return (methodName == "tuple") ? .tupleLiteral(exprs) : .setLiteral(exprs)
            }
            if methodName == "singleton", let single = args.first.flatMap({ decodeStateExpr($0.expression) }) {
                return .setLiteral([single])
            }
            return nil
        case "record":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            var fields: [String: StateExpr] = [:]
            for arg in args {
                guard let label = arg.label?.text, let val = decodeStateExpr(arg.expression) else { return nil }
                fields[label] = val
            }
            return .recordLiteral(fields)
        case "if":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  args.count >= 3,
                  let cond = decodeStateExpr(args[0].expression),
                  let thenVal = decodeStateExpr(args[1].expression),
                  let elseVal = decodeStateExpr(args[2].expression) else { return nil }
            return .ifThenElse(cond, thenVal, elseVal)
        case "enabled":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            let name = args.first?.expression.as(StringLiteralExprSyntax.self)?.segments.description
                .replacingOccurrences(of: "\"", with: "") ?? ""
            return .enabledAction(name)
        case "function", "for", "exists", "choose", "any", "functionLiteral":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            let exprs = args.compactMap { decodeStateExpr($0.expression) }
            switch methodName {
            case "function", "functionLiteral": return exprs.count >= 2 ? .functionLiteral(exprs[0], .fresh(), exprs[1]) : nil
            case "for": return exprs.count >= 2 ? .forAll(exprs[0], .fresh(), exprs[1]) : nil
            case "exists": return exprs.count >= 2 ? .exists(exprs[0], .fresh(), exprs[1]) : nil
            case "choose": return exprs.count >= 2 ? .choose(exprs[0], .fresh(), exprs[1]) : nil
            case "any": return exprs.count >= 1 ? .choose(exprs[0], .fresh(), .value(.bool(true))) : nil
            default: return nil
            }
        case "firstMatch":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            var pairs: [StateExpr] = []
            var fallback: StateExpr?
            for arg in args {
                if arg.label?.text == "fallback" { fallback = decodeStateExpr(arg.expression) }
                else if let tuple = arg.expression.as(TupleExprSyntax.self) {
                    for elem in tuple.elements { if let p = decodeStateExpr(elem.expression) { pairs.append(p) } }
                }
            }
            return .caseExpr(pairs, fallback)
        default:
            return nil
        }
    }

    private static func decodeInfixExpr(_ elements: [ExprSyntax]) -> StateExpr? {
        guard elements.count >= 3, elements.count % 2 == 1 else { return nil }
        if elements.count == 3 {
            guard let opText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let lhs = decodeStateExpr(elements[0]),
                  let rhs = decodeStateExpr(elements[2]) else { return nil }
            return applyInfixOp(opText, lhs, rhs)
        }
        if let orIdx = stride(from: 1, to: elements.count, by: 2).first(where: {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "||"
        }) {
            guard let left = decodeInfixExpr(Array(elements[0..<orIdx])),
                  let right = decodeInfixExpr(Array(elements[(orIdx + 1)..<elements.count]))
            else { return nil }
            return .or(left, right)
        }
        if let andIdx = stride(from: 1, to: elements.count, by: 2).first(where: {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&"
        }) {
            guard let left = decodeInfixExpr(Array(elements[0..<andIdx])),
                  let right = decodeInfixExpr(Array(elements[(andIdx + 1)..<elements.count]))
            else { return nil }
            return .and(left, right)
        }
        var result = decodeStateExpr(elements[0])
        for i in stride(from: 1, to: elements.count, by: 2) {
            guard let opText = elements[i].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let lhs = result,
                  let rhs = decodeStateExpr(elements[i + 1]) else { return nil }
            result = applyInfixOp(opText, lhs, rhs)
        }
        return result
    }

    private static func applyInfixOp(_ op: String, _ lhs: StateExpr, _ rhs: StateExpr) -> StateExpr? {
        switch op {
        case "+": return .add(lhs, rhs)
        case "-": return .subtract(lhs, rhs)
        case "*": return .multiply(lhs, rhs)
        case "/": return .divide(lhs, rhs)
        case "%": return .modulo(lhs, rhs)
        case "<": return .lessThan(lhs, rhs)
        case "<=": return .lessOrEqual(lhs, rhs)
        case ">": return .greaterThan(lhs, rhs)
        case ">=": return .greaterOrEqual(lhs, rhs)
        case "==": return .equal(lhs, rhs)
        case "!=": return .notEqual(lhs, rhs)
        case "&&": return .and(lhs, rhs)
        case "||": return .or(lhs, rhs)
        case "...":
            guard case .value(.int(let f)) = lhs, case .value(.int(let l)) = rhs else { return nil }
            return .setLiteral((f...l).map { .value(.int($0)) })
        default: return nil
        }
    }

    public static func decodeActionExpr(_ expression: ExprSyntax) -> ActionExpr? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let access = call.calledExpression.as(MemberAccessExprSyntax.self),
           access.declName.baseName.text == "becomes",
           let baseRef = access.base?.as(DeclReferenceExprSyntax.self) {
            let varName = baseRef.baseName.text
            if let arg = call.arguments.first?.expression,
               let state = decodeStateExpr(arg) {
                if case .choose(let chosenSet, _, _) = state {
                    return .chooseAction(varName, chosenSet)
                }
                return .assign(varName, state)
            }
            return .assign(varName, .value(.int(0)))
        }
        if let access = expression.as(MemberAccessExprSyntax.self),
           access.declName.baseName.text == "stays",
           let baseRef = access.base?.as(DeclReferenceExprSyntax.self) {
            return .unchanged(baseRef.baseName.text)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let access = call.calledExpression.as(MemberAccessExprSyntax.self),
           access.declName.baseName.text == "when" {
            let outerCondition = call.arguments.first.flatMap { decodeStateExpr($0.expression) }
            guard let inner = access.base.flatMap({ decodeActionExpr($0) }) else { return nil }
            guard let outer = outerCondition else { return inner }
            // Merge: inner is always .and(.guard_(innerConditions), innerAction) or just .guard_ + .assign
            // We want: .and(.guard_(outer && innerConditions), innerAction)
            if case .and(.guard_(let innerCond), let innerAction) = inner {
                return .and(.guard_(.and(outer, innerCond)), innerAction)
            }
            return .and(.guard_(outer), inner)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let ref = call.calledExpression.as(DeclReferenceExprSyntax.self),
           ref.baseName.text == "choose",
           let varArg = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
           let fromArg = call.arguments.dropFirst().first?.expression,
           let setExpr = decodeStateExpr(fromArg) {
            return .chooseAction(varArg.baseName.text, setExpr)
        }
        if let seq = expression.as(SequenceExprSyntax.self) {
            return decodeActionSequence(Array(seq.elements))
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let opText = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            let leftAction = decodeActionExpr(infix.leftOperand)
            let rightAction = decodeActionExpr(infix.rightOperand)
            let leftState = decodeStateExpr(infix.leftOperand)
            let rightState = decodeStateExpr(infix.rightOperand)
            if opText == "||" {
                let l = leftAction ?? leftState.map(ActionExpr.guard_)
                let r = rightAction ?? rightState.map(ActionExpr.guard_)
                if let l, let r { return .or(l, r) }
            }
            if opText == "&&" {
                let l = leftAction ?? leftState.map(ActionExpr.guard_)
                let r = rightAction ?? rightState.map(ActionExpr.guard_)
                if let l, let r { return .and(l, r) }
            }
        }
        if let tuple = expression.as(TupleExprSyntax.self),
           let single = tuple.elements.first?.expression {
            return decodeActionExpr(single)
        }
        if let state = decodeStateExpr(expression) {
            return .guard_(state)
        }
        return nil
    }

    private static func decodeActionSequence(_ elements: [ExprSyntax]) -> ActionExpr? {
        guard elements.count >= 1 else { return nil }
        if elements.count == 1 { return decodeActionExpr(elements[0]) }
        if let orIdx = stride(from: 1, to: elements.count, by: 2).first(where: {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "||"
        }) {
            guard let left = decodeActionSequence(Array(elements[0..<orIdx])),
                  let right = decodeActionSequence(Array(elements[(orIdx + 1)..<elements.count]))
            else { return nil }
            return .or(left, right)
        }
        if let andIdx = stride(from: 1, to: elements.count, by: 2).first(where: {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&"
        }) {
            guard let left = decodeActionSequence(Array(elements[0..<andIdx])),
                  let right = decodeActionSequence(Array(elements[(andIdx + 1)..<elements.count]))
            else { return nil }
            return .and(left, right)
        }
        if elements.count >= 3 {
            guard let opText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text else { return nil }
            if opText == "||" || opText == "&&" {
                guard let left = decodeActionExpr(elements[0]),
                      let right = decodeActionExpr(elements[2]) else { return nil }
                return opText == "||" ? .or(left, right) : .and(left, right)
            }
            if let state = decodeInfixExpr(elements) { return .guard_(state) }
        }
        return nil
    }

    private static func unwrapSingleElementTuple(_ expression: ExprSyntax) -> ExprSyntax {
        if let tuple = expression.as(TupleExprSyntax.self),
           tuple.elements.count == 1,
           let nested = tuple.elements.first?.expression {
            return nested
        }
        return expression
    }

    public static func decodeActionFromClosure(_ closure: ClosureExprSyntax) -> ActionExpr? {
        var actions: [ActionExpr] = []
        for statement in closure.statements {
            guard case .expr(let expression) = statement.item else { continue }
            guard let action = decodeActionExpr(expression) else { return nil }
            actions.append(action)
        }
        guard let first = actions.first else { return .guard_(.value(.bool(true))) }
        return actions.dropFirst().reduce(first) { .and($0, $1) }
    }

    private static func decodeCollectionPredicate(_ call: FunctionCallExprSyntax) -> StateExpr? {
        guard let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              let collection = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let method = CollectionPredicateKind(rawValue: access.declName.baseName.text),
              let closure = call.trailingClosure
                ?? call.arguments.first?.expression.as(ClosureExprSyntax.self),
              let parameter = collectionPredicateParameter(in: closure)
        else { return nil }
        let member = QuantVar.fresh()
        let rewrittenStatements = closure.statements.map { statement in
            PredicateValueRewriter(
                parameter: parameter,
                replacement: "\(collection).applying(\(member.name))"
            ).visit(statement)
        }
        let rewrittenClosure = closure.with(\.statements, CodeBlockItemListSyntax(rewrittenStatements))
        guard let bodyExpr = rewrittenClosure.statements.first.flatMap({ stmt -> ExprSyntax? in
            guard case .expr(let e) = stmt.item else { return nil }
            return e
        }), let body = decodeStateExpr(bodyExpr) else { return nil }
        let domain = StateExpr.domain(.variable(collection))
        switch method {
        case .allSatisfy: return .forAll(domain, member, body)
        case .contains: return .exists(domain, member, body)
        }
    }

    public static func decodeTemporal(_ call: FunctionCallExprSyntax) -> TemporalExpr? {
        guard let ref = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
        let name = ref.declName.baseName.text
        let firstArg = call.arguments.first.flatMap { decodeStateExpr($0.expression) }
        switch name {
        case "leadsTo":
            let source = ref.base.flatMap { decodeStateExpr($0) } ?? .value(.bool(true))
            return firstArg.map { .leadsTo(source, $0) }
        case "always": return firstArg.map { .always($0) }
        case "eventually": return firstArg.map { .eventually($0) }
        case "alwaysEventually": return firstArg.map { .alwaysEventually($0) }
        case "eventuallyAlways": return firstArg.map { .eventuallyAlways($0) }
        default: return nil
        }
    }

    public static func decodeFairness(_ call: FunctionCallExprSyntax) -> FairnessCondition? {
        guard let ref = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
        let name = ref.declName.baseName.text
        let actionName = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?
            .segments.description.replacingOccurrences(of: "\"", with: "") ?? ""
        switch name {
        case "weakFairness": return .weakFairness(actionName)
        case "strongFairness": return .strongFairness(actionName)
        default: return nil
        }
    }

    // MARK: - Unified spec builder parser

    public struct ParsedSpecComponents {
        public var variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)] = []
        public var actions: [(name: String, body: ActionExpr)] = []
        public var symmetricCollections: [ParsedSymmetricCollection] = []
        public var collectionActions: [ParsedCollectionAction] = []
        public var diagnostics: [SymmetricCollectionParseDiagnostic] = []
        public var invariants: [(name: String, body: StateExpr)] = []
        public var temporal: [(name: String, expr: TemporalExpr)] = []
        public var fairness: [FairnessCondition] = []
        public var constants: [String: TLAValue] = [:]
        /// Local named values (from NamedValue declarations, resolved in expressions)
        public var localConstants: [String: TLAValue] = [:]
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

    public struct SymmetricCollectionParseDiagnostic: Error, CustomStringConvertible {
        public let message: String
        public let source: String
        public let sourceOffset: Int?

        public init(message: String, source: String, sourceOffset: Int? = nil) {
            self.message = message
            self.source = source
            self.sourceOffset = sourceOffset
        }

        public init<Node: SyntaxProtocol>(message: String, source: Node) {
            self.init(
                message: message,
                source: source.description,
                sourceOffset: source.positionAfterSkippingLeadingTrivia.utf8Offset
            )
        }

        public var description: String { message }
    }

      public static func parseSpecClosure(_ closure: ClosureExprSyntax, enumPhases: [String: [String: TLAValue]] = [:]) -> ParsedSpecComponents {
        _enumPhases = enumPhases
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
                parseStateVarDecl(varDecl, into: &result)
            }
        }
        return result
    }

    private static func parseForLoop(_ forStmt: ForStmtSyntax, into result: inout ParsedSpecComponents) {
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

    /// Parses `let x = Var(...)` or `let x = StateVar(...)` bindings into `ParsedSpecComponents.variables`.
    /// Handles both raw `Var("x", 0)` and rewrites where ModelMacro injected a string name.
    private static func parseStateVarDecl(_ varDecl: VariableDeclSyntax, into result: inout ParsedSpecComponents) {
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

            if callName == "Var" && args.count < 2 { continue }

            if let rangeExpr = args.first(where: { $0.label?.text == "in" })?.expression {
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
                let initial: TLAValue = args.count >= 2 ? parseInitialExpr(args[1].expression) : .int(0)
                let inferredType = args.count >= 2 ? enumCaseTypeName(from: args[1].expression) : nil
                result.variables.append((varName, initial, nil, varTypeName ?? inferredType))
            } else {
                let initial: TLAValue = parseInitialExpr(args[0].expression)
                let inferredType = enumCaseTypeName(from: args[0].expression)
                result.variables.append((patternName, initial, nil, varTypeName ?? inferredType))
            }
        }
    }

    /// Resolves a StateVar call expression to (callName, swiftTypeName).
    /// Returns nil if the call is not a StateVar constructor.
    private static func resolveVarCall(_ fc: FunctionCallExprSyntax) -> (String, String?)? {
        if let ref = fc.calledExpression.as(DeclReferenceExprSyntax.self) {
            guard ref.baseName.text == "StateVar" else { return nil }
            return ("StateVar", nil)
        }
        if let generic = fc.calledExpression.as(GenericSpecializationExprSyntax.self),
           let ref = generic.expression.as(DeclReferenceExprSyntax.self) {
            guard ref.baseName.text == "StateVar" else { return nil }
            let typeArgs = Array(generic.genericArgumentClause.arguments)
            let swiftTypeName = typeArgs.count >= 1
                ? typeArgs[0].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            return ("StateVar", swiftTypeName)
        }
        return nil
    }

    private static func resolveVarTypeArg(_ fc: FunctionCallExprSyntax) -> String? {
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

    /// Extracts the lower bound from a range expression like `1...12`.
    private static func parseRangeLowerBound(_ expression: ExprSyntax) -> Int {
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
    private static func parseValuesFirst(_ expression: ExprSyntax) -> String {
        if let array = expression.as(ArrayExprSyntax.self),
           let first = array.elements.first?.expression.as(StringLiteralExprSyntax.self) {
            return first.segments.description.replacingOccurrences(of: "\"", with: "")
        }
        return ""
    }

    /// Converts a Swift initializer expression to a TLAValue.
    private static func parseInitialExpr(_ expression: ExprSyntax) -> TLAValue {
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
    private static func enumCaseTypeName(from expression: ExprSyntax) -> String? {
        guard let memberAccess = expression.as(MemberAccessExprSyntax.self) else { return nil }
        if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            return base.baseName.text
        }
        return nil
    }

    private static func parseBuilderCall(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        loopVar: String? = nil,
        loopValue: Int? = nil,
        collectionTypes: [String: (element: String, value: String)] = [:]
    ) {
        guard let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else { return }

        switch name {
        case "SymmetricCollection":
            parseSymmetricCollectionDecl(call, into: &result, collectionTypes: collectionTypes)
        case "CollectionAction":
            parseCollectionAction(call, into: &result)
        case "Variable":
            parseVariableDecl(call, into: &result)
        case "Action":
            if let actionName = extractStringArg(call, index: 0, loopVar: loopVar, loopValue: loopValue),
                let body = call.trailingClosure.flatMap(decodeActionFromClosure) {
                result.actions.append((actionName, body))
            } else if let actionName = extractStringArg(call, index: 0, loopVar: loopVar, loopValue: loopValue),
                      call.trailingClosure != nil {
                // Action body uses unsupported constructs (existsAction, etc.).
                // Store a placeholder body; the macro will fall back to interpreter
                // trampoline which reads the body from the runtime spec at Self.spec.
                result.actions.append((actionName, .chooseAction("_parser_skip", .value(.bool(false)))))
            }
        case "Invariant":
            parseInvariant(call, into: &result)
        case "Constant":
            parseConstantDecl(call, into: &result)
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
                result.actions += spec.actions.map { (name: $0.name, body: $0.body) }
            }
        default:
            break
        }
    }

    private static func parseInvariant(
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

    private static func parseInvariantBody(
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

    private static func decodeInvariantExpression(
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

    private static func unsupportedInvariantExpression(
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

    private static func parseCollectionPredicate(
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

        let member = QuantVar.fresh()
        let rewrittenStatements = closure.statements.map { statement in
            PredicateValueRewriter(
                parameter: parameter,
                replacement: "\(collection).applying(\(member.name))"
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

    private static func collectionPredicateParameter(in closure: ClosureExprSyntax) -> String? {
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

    private enum CollectionPredicateKind: String {
        case allSatisfy
        case contains
    }

    private final class PredicateValueRewriter: SyntaxRewriter {
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

    private static func collectSymmetricCollectionTypes(
        in closure: ClosureExprSyntax
    ) -> [String: (element: String, value: String)] {
        var types: [String: (element: String, value: String)] = [:]
        for statement in closure.statements {
            guard case .decl(let declaration) = statement.item,
                  let variable = declaration.as(VariableDeclSyntax.self)
            else { continue }
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                      let specialization = call.calledExpression.as(GenericSpecializationExprSyntax.self),
                      specialization.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "SymmetricCollectionVar"
                else { continue }
                let arguments = Array(specialization.genericArgumentClause.arguments)
                guard arguments.count == 2 else { continue }
                types[name] = (
                    arguments[0].argument.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    arguments[1].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        return types
    }

    private static func parseSymmetricCollectionDecl(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        collectionTypes: [String: (element: String, value: String)]
    ) {
        let arguments = Array(call.arguments)
        guard let collectionName = arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let types = collectionTypes[collectionName],
              let scopeArgument = arguments.first(where: { $0.label?.text == "verificationScope" })?.expression,
              let scopeLiteral = scopeArgument.as(IntegerLiteralExprSyntax.self),
              let scope = Int(scopeLiteral.literal.text),
              let initialExpression = arguments.first(where: { $0.label?.text == "initial" })?.expression,
              let initial = parseLiteralValue(initialExpression)
        else {
            result.diagnostics.append(.init(
                message: "Symmetric collections require SymmetricCollectionVar<Element, Value>, "
                    + "a positive integer literal scope, and a literal uniform initial value.",
                source: call.description
            ))
            return
        }

        let declaration = SymmetricCollectionDecl(name: collectionName, verificationScope: scope, initial: initial)
        result.symmetricCollections.append(.init(
            name: collectionName,
            elementType: types.element,
            valueType: types.value,
            verificationScope: scope,
            source: call.description,
            declaration: declaration
        ))
        result.variables.append((collectionName, declaration.variable.initial, nil, nil))
    }

    private static func parseCollectionAction(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        let arguments = Array(call.arguments)
        guard let actionName = extractStringArg(call, index: 0),
              let collectionName = arguments.first(where: { $0.label?.text == "on" })?.expression
                .as(DeclReferenceExprSyntax.self)?.baseName.text,
              let closure = call.trailingClosure
        else { return }

        guard let memberName = collectionActionMemberName(in: closure) else {
            result.diagnostics.append(.init(
                message: "Collection action '\(actionName)' requires one named opaque member parameter.",
                source: closure.description
            ))
            return
        }
        let member = QuantVar.fresh()
        let diagnosticCount = result.diagnostics.count
        validateMemberUses(
            memberName,
            in: closure,
            owning: collectionName,
            action: actionName,
            into: &result
        )
        guard let actionBody = parseCollectionActionBody(
            closure,
            collection: collectionName,
            member: memberName,
            binding: member.name
        ) else {
            if result.diagnostics.count == diagnosticCount {
                result.diagnostics.append(.init(
                    message: "Collection action '\(actionName)' contains an unsupported action expression.",
                    source: closure.description
                ))
            }
            return
        }
        result.collectionActions.append(.init(
            name: actionName,
            collectionName: collectionName,
            body: .existsAction(member.name, .domain(.variable(collectionName)), actionBody),
            runtimeBranches: runtimeBranches(
                in: closure,
                collection: collectionName,
                member: memberName,
                runtimeVariables: Set(result.variables.map(\.name))
            ),
            source: call.description
        ))
        result.actions.append((actionName, .existsAction(
            member.name,
            .domain(.variable(collectionName)),
            actionBody
        )))
    }

    private static func collectionActionMemberName(in closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause else { return nil }
        switch parameters {
        case .simpleInput(let list):
            return list.first?.name.text
        case .parameterClause(let clause):
            guard let parameter = clause.parameters.first else { return nil }
            return parameter.secondName?.text ?? parameter.firstName.text
        }
    }

    private static func validateMemberUses(
        _ member: String,
        in closure: ClosureExprSyntax,
        owning collection: String,
        action: String,
        into result: inout ParsedSpecComponents
    ) {
        let validator = CollectionMemberUseValidator(member: member, collection: collection)
        validator.walk(Syntax(closure))
        for violation in validator.violations {
            result.diagnostics.append(identityDiagnostic(
                collection: collection, action: action, source: violation.source,
                detail: violation.detail
            ))
        }
    }

    private static func identityDiagnostic(
        collection: String,
        action: String,
        source: String,
        detail: String
    ) -> SymmetricCollectionParseDiagnostic {
        .init(
            message: "\(detail) for symmetric collection '\(collection)' in action '\(action)': "
                + "member identity is opaque and may only select or update its owning collection. "
                + "Model the distinction as member state or use a non-symmetric collection.",
            source: source
        )
    }

    private static func parseCollectionActionBody(
        _ closure: ClosureExprSyntax,
        collection: String,
        member: String,
        binding: String
    ) -> ActionExpr? {
        let actions = closure.statements.compactMap { statement -> ActionExpr? in
            guard case .expr(let expression) = statement.item else { return nil }
            return parseCollectionActionExpression(
                expression,
                collection: collection,
                member: member,
                binding: binding
            )
        }
        guard !actions.isEmpty else { return nil }
        return actions.dropFirst().reduce(actions[0]) { .and($0, $1) }
    }

    private static func parseCollectionActionExpression(
        _ expression: ExprSyntax,
        collection: String,
        member: String,
        binding: String
    ) -> ActionExpr? {
        let unwrapped = unwrapSingleElementTuple(expression)
        if unwrapped != expression {
            return parseCollectionActionExpression(
                unwrapped,
                collection: collection,
                member: member,
                binding: binding
            )
        }
        if let sequence = expression.as(SequenceExprSyntax.self),
           let split = collectionActionSequenceSplit(Array(sequence.elements)) {
            let left = parseCollectionActionExpression(
                split.left,
                collection: collection,
                member: member,
                binding: binding
            )
            let right = parseCollectionActionExpression(
                split.right,
                collection: collection,
                member: member,
                binding: binding
            )
            guard let left, let right else { return nil }
            return split.operatorText == "&&" ? .and(left, right) : .or(left, right)
        }
        if let update = collectionUpdate(expression, collection: collection, member: member) {
            let rewritten = CollectionReadRewriter(
                collection: collection,
                member: member,
                replacement: binding
            ).visit(update.expression)
            guard let value = decodeStateExpr(rewritten) else { return nil }
            return .assign(collection, .except(.variable(collection), .variable(binding), value))
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
           let left = parseCollectionActionExpression(infix.leftOperand, collection: collection, member: member, binding: binding),
           let right = parseCollectionActionExpression(infix.rightOperand, collection: collection, member: member, binding: binding) {
            if op == "&&" { return .and(left, right) }
            if op == "||" { return .or(left, right) }
        }
        let rewritten = CollectionReadRewriter(
            collection: collection,
            member: member,
            replacement: binding
        ).visit(expression)
        return decodeStateExpr(rewritten).map(ActionExpr.guard_)
    }

    private static func collectionActionSequenceSplit(
        _ elements: [ExprSyntax]
    ) -> (left: ExprSyntax, operatorText: String, right: ExprSyntax)? {
        guard elements.count >= 3, elements.count % 2 == 1 else { return nil }
        let operators = stride(from: 1, to: elements.count, by: 2)
        let splitIndex = operators.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "||"
        } ?? operators.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&"
        }
        guard let splitIndex,
              let operatorText = elements[splitIndex].as(BinaryOperatorExprSyntax.self)?.operator.text,
              let left = parseExpression(elements[0..<splitIndex]),
              let right = parseExpression(elements[(splitIndex + 1)..<elements.count])
        else { return nil }
        return (left, operatorText, right)
    }

    private static func parseExpression(_ elements: ArraySlice<ExprSyntax>) -> ExprSyntax? {
        let source = elements.map(\.description).joined()
        return SwiftParser.Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self)
    }

    private static func collectionUpdate(
        _ expression: ExprSyntax,
        collection: String,
        member: String
    ) -> LabeledExprSyntax? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              access.declName.baseName.text == "update",
              access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
              let selector = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              selector.baseName.text == member
        else { return nil }
        return call.arguments.first(where: { $0.label?.text == "to" })
    }

    private static func runtimeBranches(
        in closure: ClosureExprSyntax,
        collection: String,
        member: String,
        runtimeVariables: Set<String>
    ) -> [ParsedCollectionAction.RuntimeBranch] {
        let expressions = closure.statements.compactMap { statement -> ExprSyntax? in
            guard case .expr(let expression) = statement.item else { return nil }
            return expression
        }
        guard let first = expressions.first else { return [] }
        return expressions.dropFirst().reduce(
            runtimeBranches(
                for: first,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
        ) { partial, expression in
            combineRuntimeBranches(
                partial,
                runtimeBranches(
                    for: expression,
                    collection: collection,
                    member: member,
                    runtimeVariables: runtimeVariables
                )
            )
        }
    }

    private static func runtimeBranches(
        for expression: ExprSyntax,
        collection: String,
        member: String,
        runtimeVariables: Set<String>
    ) -> [ParsedCollectionAction.RuntimeBranch] {
        if let tuple = expression.as(TupleExprSyntax.self),
           tuple.elements.count == 1,
           let nested = tuple.elements.first?.expression {
            return runtimeBranches(
                for: nested,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
        }
        if let sequence = expression.as(SequenceExprSyntax.self),
           let split = collectionActionSequenceSplit(Array(sequence.elements)) {
            let left = runtimeBranches(
                for: split.left,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
            let right = runtimeBranches(
                for: split.right,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
            return split.operatorText == "&&"
                ? combineRuntimeBranches(left, right)
                : left + right
        }
        if let update = collectionUpdate(expression, collection: collection, member: member) {
            let runtimeUpdate = CollectionReadRewriter(
                collection: collection,
                member: member,
                replacement: "entry.value",
                asStateExpression: false,
                runtimeVariables: runtimeVariables
            ).visit(update.expression).formatted().description
            return [.init(guardExpressions: [], updateExpression: runtimeUpdate)]
        }
        let runtimeGuard = CollectionRuntimeGuardRewriter(
            collection: collection,
            member: member,
            runtimeVariables: runtimeVariables
        ).visit(expression).formatted().description
        return [.init(guardExpressions: [runtimeGuard], updateExpression: nil)]
    }

    private static func combineRuntimeBranches(
        _ left: [ParsedCollectionAction.RuntimeBranch],
        _ right: [ParsedCollectionAction.RuntimeBranch]
    ) -> [ParsedCollectionAction.RuntimeBranch] {
        left.flatMap { lhs in
            right.compactMap { rhs in
                guard lhs.updateExpression == nil || rhs.updateExpression == nil else { return nil }
                return .init(
                    guardExpressions: lhs.guardExpressions + rhs.guardExpressions,
                    updateExpression: lhs.updateExpression ?? rhs.updateExpression
                )
            }
        }
    }

    private final class CollectionRuntimeGuardRewriter: SyntaxRewriter {
        let collection: String
        let member: String
        let runtimeVariables: Set<String>

        init(collection: String, member: String, runtimeVariables: Set<String>) {
            self.collection = collection
            self.member = member
            self.runtimeVariables = runtimeVariables
        }

        override func visit(_ node: SubscriptCallExprSyntax) -> ExprSyntax {
            guard node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
                  node.arguments.count == 1,
                  node.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == member
            else { return super.visit(node) }
            return ExprSyntax(stringLiteral: "(entry.value)")
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            guard runtimeVariables.contains(node.baseName.text) else { return super.visit(node) }
            return ExprSyntax(stringLiteral: "_state.\(node.baseName.text)")
        }
    }

    private final class CollectionReadRewriter: SyntaxRewriter {
        let collection: String
        let member: String
        let replacement: String
        let asStateExpression: Bool
        let runtimeVariables: Set<String>

        init(
            collection: String,
            member: String,
            replacement: String,
            asStateExpression: Bool = true,
            runtimeVariables: Set<String> = []
        ) {
            self.collection = collection
            self.member = member
            self.replacement = replacement
            self.asStateExpression = asStateExpression
            self.runtimeVariables = runtimeVariables
        }

        override func visit(_ node: SubscriptCallExprSyntax) -> ExprSyntax {
            guard node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
                  node.arguments.count == 1,
                  node.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == member
            else { return super.visit(node) }
            if asStateExpression {
                return ExprSyntax(stringLiteral: "\(collection).applying(\(replacement))")
            }
            return ExprSyntax(stringLiteral: "(\(replacement)) ")
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            guard !asStateExpression, runtimeVariables.contains(node.baseName.text)
            else { return super.visit(node) }
            return ExprSyntax(stringLiteral: "_state.\(node.baseName.text)")
        }
    }

    private final class CollectionMemberUseValidator: SyntaxVisitor {
        struct Violation {
            let detail: String
            let source: String
        }

        let member: String
        let collection: String
        var closureDepth = 0
        var permittedMemberOffsets: Set<Int> = []
        var violations: [Violation] = []

        init(member: String, collection: String) {
            self.member = member
            self.collection = collection
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
            closureDepth += 1
            return .visitChildren
        }

        override func visitPost(_ node: ClosureExprSyntax) {
            closureDepth -= 1
        }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if node.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
               node.declName.baseName.text == "domain" {
                violations.append(.init(
                    detail: "Raw verification-domain access is unavailable",
                    source: node.description
                ))
            }
            return .visitChildren
        }

        override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
            if node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
               let selector = node.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
               node.arguments.count == 1,
               selector.baseName.text == member {
                permittedMemberOffsets.insert(selector.positionAfterSkippingLeadingTrivia.utf8Offset)
            }
            return .visitChildren
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let access = node.calledExpression.as(MemberAccessExprSyntax.self),
               access.declName.baseName.text == "update",
               let selector = node.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
               selector.baseName.text == member {
                permittedMemberOffsets.insert(selector.positionAfterSkippingLeadingTrivia.utf8Offset)
                if let target = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
                   target != collection {
                    violations.append(.init(
                        detail: "Cross-collection member use is unavailable (including '\(target)')",
                        source: node.description
                    ))
                }
            }
            return .visitChildren
        }

        override func visit(_ node: ExpressionSegmentSyntax) -> SyntaxVisitorContinueKind {
            if let expression = node.expressions.first?.expression.as(DeclReferenceExprSyntax.self),
               expression.baseName.text == member {
                violations.append(.init(
                    detail: "String interpolation of a member token is unavailable",
                    source: node.description
                ))
            }
            return .visitChildren
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            guard node.baseName.text == member else { return .visitChildren }
            if closureDepth > 1 {
                violations.append(.init(
                    detail: "Capturing a member token in a nested closure is unavailable",
                    source: node.description
                ))
            } else if !permittedMemberOffsets.contains(node.positionAfterSkippingLeadingTrivia.utf8Offset) {
                violations.append(.init(
                    detail: "Member identity observation or cross-collection use is unavailable",
                    source: node.description
                ))
            }
            return .visitChildren
        }
    }

    private static func parseLiteralValue(_ expression: ExprSyntax) -> TLAValue? {
        if let integer = expression.as(IntegerLiteralExprSyntax.self) {
            return Int(integer.literal.text).map(TLAValue.int)
        }
        if let boolean = expression.as(BooleanLiteralExprSyntax.self) {
            return .bool(boolean.literal.text == "true")
        }
        if let string = expression.as(StringLiteralExprSyntax.self) {
            return .string(string.segments.description.replacingOccurrences(of: "\"", with: ""))
        }
        return nil
    }

    private static func extractStringArg(
        _ call: FunctionCallExprSyntax,
        index: Int,
        loopVar: String? = nil,
        loopValue: Int? = nil
    ) -> String? {
        let args = Array(call.arguments)
        guard index < args.count else { return nil }
        guard let stringLit = args[index].expression.as(StringLiteralExprSyntax.self) else { return nil }

        // Build string from segments, substituting loop variable
        var result = ""
        for segment in stringLit.segments {
            if let text = segment.as(StringSegmentSyntax.self)?.content.text {
                result += text
            } else if let expr = segment.as(ExpressionSegmentSyntax.self),
                      let loopVar, let loopValue,
                      let expr0 = expr.expressions.first?.expression,
                      let declRef = expr0.as(DeclReferenceExprSyntax.self),
                      declRef.baseName.text == loopVar {
                result += "\(loopValue)"
            }
        }
        return result
    }

    private static func parseVariableDecl(_ call: FunctionCallExprSyntax, into result: inout ParsedSpecComponents) {
        let args = Array(call.arguments)
        guard let firstName = args.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? args.first?.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        else { return }

        // Variable(name, in: set)
        if args.count >= 2 {
            let label = args[1].label?.text
            if label == "in" {
                if let setExpr = decodeStateExpr(args[1].expression) {
                    result.variables.append((firstName, .set([]), setExpr, nil))
                    return
                }
            }
        }

        // Variable(name, value)
        if args.count >= 2 {
            let valExpr = args[1].expression
            if let intVal = valExpr.as(IntegerLiteralExprSyntax.self) {
                result.variables.append((firstName, .int(Int(intVal.literal.text) ?? 0), nil, nil))
                return
            }
            if let boolVal = valExpr.as(BooleanLiteralExprSyntax.self) {
                result.variables.append((firstName, .bool(boolVal.literal.text == "true"), nil, nil))
                return
            }
            if let stringVal = valExpr.as(StringLiteralExprSyntax.self) {
                result.variables.append((firstName, .string(stringVal.segments.description), nil, nil))
                return
            }
            // TLAValue.set([]), TLAValue.tuple([]), etc.
            if let fc = valExpr.as(FunctionCallExprSyntax.self),
               let memberAccess = fc.calledExpression.as(MemberAccessExprSyntax.self),
               let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
               base.baseName.text == "TLAValue" {
                let name = memberAccess.declName.baseName.text
                if let parsed = parseTLAValueConstructor(name: name, call: fc) {
                    result.variables.append((firstName, parsed, nil, nil))
                    return
                }
            }
        }

        // Variable(name, initializerExpr) — fallback
        if args.count >= 2 {
            let initial: TLAValue = .int(0)
            result.variables.append((firstName, initial, nil, nil))
        }
    }

    private static func parseTLAValueConstructor(name: String, call: FunctionCallExprSyntax) -> TLAValue? {
        switch name {
        case "set":     return .set([])
        case "tuple":   return .tuple([])
        case "record":  return .record([:])
        case "function": return .function([:])
        default:        return nil
        }
    }

    private static func parseConstantDecl(_ call: FunctionCallExprSyntax, into result: inout ParsedSpecComponents) {
        let args = Array(call.arguments)
        guard args.count >= 2,
              let name = extractStringArg(call, index: 0)
        else { return }
        if let intVal = args[1].expression.as(IntegerLiteralExprSyntax.self) {
            result.constants[name] = .int(Int(intVal.literal.text) ?? 0)
        } else if let boolVal = args[1].expression.as(BooleanLiteralExprSyntax.self) {
            result.constants[name] = .bool(boolVal.literal.text == "true")
        } else if args[1].expression.as(StringLiteralExprSyntax.self) != nil {
            result.constants[name] = .string(extractStringArg(call, index: 1) ?? "")
        }
    }

    /// Parse `NamedValue("poweredOn", 5)` → register in localConstants
    private static func parseNamedValueConstant(_ call: FunctionCallExprSyntax, name: String, into result: inout ParsedSpecComponents) -> Bool {
        let args = Array(call.arguments)
        guard args.count >= 2 else { return false }
        if let intVal = args[1].expression.as(IntegerLiteralExprSyntax.self), let v = Int(intVal.literal.text) {
            result.localConstants[name] = .int(v); return true
        }
        if let boolVal = args[1].expression.as(BooleanLiteralExprSyntax.self) {
            result.localConstants[name] = .bool(boolVal.literal.text == "true"); return true
        }
        return false
    }
}
