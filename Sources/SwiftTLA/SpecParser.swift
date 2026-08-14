import SwiftSyntax
import SwiftParser
import SwiftBasicFormat
import Foundation

/// Parses SwiftSyntax AST nodes into DSL types (StateExpr, ActionExpr, etc.).
/// Every AST pattern maps deterministically to a DSL value.
/// Tests live in SpecParserTests.
public enum SpecParser {

    /// Local constants collected during parsing (for `Value` / `let` bindings).
    nonisolated(unsafe) static var _constants: [String: TLAValue] = [:]

    /// Enum phase map (typeName → caseName → TLAValue) set per-parse by the macro.
    nonisolated(unsafe) static var _enumPhases: [String: [String: TLAValue]] = [:]

    nonisolated(unsafe) static var _enumDomains: [String: [TLAValue]] = [:]
    /// Tuple-shaped algorithm state currently in scope. This lets the parser
    /// distinguish `sequence[index]` from a finite-function lookup without
    /// exposing raw type maps to authors.
    nonisolated(unsafe) static var _algorithmTupleVariables: Set<String> = []
    nonisolated(unsafe) static var algorithmParseFailure: String?

    /// The parser carries enum information while it decodes one macro body.
    /// Macro expansion is concurrent, so one parse must not overwrite another
    /// parse's enum context.
    static let parseContextLock = NSLock()

    // MARK: - Compact expression decoder

    public static func decodeStateExpr(_ expression: ExprSyntax) -> StateExpr? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Finished",
           call.arguments.isEmpty {
            return .equal(.variable("pc"), .value(.string("Done")))
        }
        if let sequences = decodeBoundedSequenceDomain(expression) {
            return sequences
        }
        if let boundedQuantifier = decodeAlgorithmDomainQuantifier(expression) {
            return boundedQuantifier
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "If",
           let conditionSyntax = call.arguments.first?.expression,
           let thenSyntax = call.arguments.first(where: { $0.label?.text == "then" })?.expression,
           let elseSyntax = call.arguments.first(where: { $0.label?.text == "else" })?.expression,
           let condition = decodeStateExpr(conditionSyntax),
           let thenValue = decodeStateExpr(thenSyntax),
           let elseValue = decodeStateExpr(elseSyntax) {
            return .ifThenElse(condition, thenValue, elseValue)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           name == "Exists" || name == "ForAll" || name == "All",
           let domainSyntax = call.arguments.first(where: { $0.label?.text == "in" })?.expression,
           let domain = decodeStateExpr(domainSyntax),
           let closure = call.trailingClosure,
           closure.statements.count == 1,
           case .expr(let bodySyntax) = closure.statements.first?.item,
           let parameter = closureParameterNames(in: closure).first,
           closureParameterNames(in: closure).count == 1,
           let predicate = decodeTypedFacadeValue(
               bodySyntax,
               substitutions: [parameter: .variable(parameter)]
           ) {
            return name == "Exists"
                ? .exists(domain, parameter, predicate)
                : .forAll(domain, parameter, predicate)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "IntRange",
           let lower = call.arguments.first?.expression,
           let upper = call.arguments.first(where: { $0.label?.text == "through" })?.expression,
           let lowerExpression = decodeStateExpr(lower),
           let upperExpression = decodeStateExpr(upper) {
            return .integerRange(lowerExpression, upperExpression)
        }
        // Empty typed formal values are ordinary initializers in the Swift
        // surface. Decode them directly so the source parser and runtime
        // builder agree on the same collection-shaped initial state.
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.arguments.isEmpty,
           call.trailingClosure == nil {
            let constructor = call.calledExpression.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if constructor.hasPrefix("SetExpr<") { return .value(.set([])) }
            if constructor.hasPrefix("TupleExpr<") { return .value(.tuple([])) }
        }
        if let typedFacadeExpr = decodeTypedFacadeExpr(expression, substitutions: [:]) {
            return typedFacadeExpr
        }
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
            case "stateExpr": return selfExpr
            case "expr": return selfExpr
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

    /// Independently expands the bounded `Sequences(of:lengths:)` spelling
    /// used by the algorithm builder. This is the finite model-checking form
    /// of TLA+ `Seq(S)`, not a Swift array literal.
    private static func decodeBoundedSequenceDomain(_ expression: ExprSyntax) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Sequences",
              let memberSyntax = call.arguments.first(where: { $0.label?.text == "of" })?.expression,
              let lengthSyntax = call.arguments.first(where: { $0.label?.text == "lengths" })?.expression,
              let memberSet = decodeStateExpr(memberSyntax),
              case .setLiteral(let members) = memberSet,
              let lengths = parseIntegerClosedRange(lengthSyntax)
        else { return nil }
        return .setLiteral(formalSequenceExpressions(members: members, lengths: lengths))
    }

    private static func decodeAlgorithmDomainQuantifier(_ expression: ExprSyntax) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              name == "All",
              let domainSyntax = call.arguments.first?.expression,
              let domain = finiteAlgorithmDomain(domainSyntax),
              let closure = call.trailingClosure,
              closure.statements.count == 1,
              case .expr(let bodySyntax) = closure.statements.first?.item,
              let parameter = closureParameterNames(in: closure).first,
              closureParameterNames(in: closure).count == 1
        else { return nil }

        let binding = StateExpr.variable(parameter)
        let predicate: StateExpr?
        if let finished = bodySyntax.as(FunctionCallExprSyntax.self),
           finished.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Finished",
           let argument = finished.arguments.first?.expression,
           decodeTypedFacadeValue(argument, substitutions: [parameter: binding]) != nil {
            predicate = .equal(
                .functionApply(.variable("pc"), binding),
                .value(.string("Done"))
            )
        } else {
            predicate = decodeTypedFacadeValue(bodySyntax, substitutions: [parameter: binding])
        }
        guard let predicate else { return nil }
        let values = StateExpr.setLiteral(domain.values.map(StateExpr.value))
        return .forAll(values, parameter, predicate)
    }

    static func decodeTypedFacadeExpr(
        _ expression: ExprSyntax,
        substitutions: [String: StateExpr]
    ) -> StateExpr? {
        if let reference = expression.as(DeclReferenceExprSyntax.self),
           let substitution = substitutions[reference.baseName.text] {
            return substitution
        }
        if let subscriptCall = expression.as(SubscriptCallExprSyntax.self),
           subscriptCall.arguments.count == 1,
           let base = decodeTypedFacadeValue(subscriptCall.calledExpression, substitutions: substitutions),
           let selector = subscriptCall.arguments.first?.expression {
            if let fieldName = typedFieldName(selector) {
                return .recordAccess(base, fieldName)
            }
            guard let index = decodeTypedFacadeValue(selector, substitutions: substitutions) else { return nil }
            if let reference = subscriptCall.calledExpression.as(DeclReferenceExprSyntax.self),
               _algorithmTupleVariables.contains(reference.baseName.text) {
                return .tupleDynamicAccess(base, index)
            }
            return .functionApply(base, index)
        }
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let access = call.calledExpression.as(MemberAccessExprSyntax.self)
        else { return nil }

        if access.declName.baseName.text == "literal",
           let literalType = typedLiteralType(access.base) {
            switch literalType.name {
            case "Record":
                return decodeTypedRecordLiteral(call, substitutions: substitutions)
            case "SetExpr":
                return decodeTypedSetLiteral(call, substitutions: substitutions)
            case "Function":
                return decodeTypedFunctionLiteral(
                    call,
                    domainType: literalType.arguments.first,
                    substitutions: substitutions
                )
            default:
                return nil
            }
        }

        if access.declName.baseName.text == "mapping",
           let literalType = typedLiteralType(access.base),
           literalType.name == "Function",
           let domainType = literalType.arguments.first,
           let domain = _enumDomains[domainType],
           let closure = call.trailingClosure,
           let parameter = closureParameterNames(in: closure).first,
           closure.statements.count == 1,
           case .expr(let bodySyntax) = closure.statements.first?.item,
           let body = decodeTypedFacadeValue(
                bodySyntax,
                substitutions: [parameter: .variable("__pcal_function_key")]
           ) {
            return .functionLiteral(
                .setLiteral(domain.map(StateExpr.value)),
                "__pcal_function_key",
                body
            )
        }

        if access.declName.baseName.text == "ifThenElse",
           let base = access.base,
           base.description.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Expr<"),
           let conditionSyntax = call.arguments.first?.expression,
           let thenSyntax = call.arguments.first(where: { $0.label?.text == "then" })?.expression,
           let elseSyntax = call.arguments.first(where: { $0.label?.text == "else" })?.expression,
           let condition = decodeTypedFacadeValue(conditionSyntax, substitutions: substitutions),
           let thenValue = decodeTypedFacadeValue(thenSyntax, substitutions: substitutions),
           let elseValue = decodeTypedFacadeValue(elseSyntax, substitutions: substitutions) {
            return .ifThenElse(condition, thenValue, elseValue)
        }

        // Swift infers `Record<Schema>` from a surrounding `SetExpr` or
        // `Function` literal, so the source spelling may be `Record.literal`.
        // Its field entries retain enough syntax to decode independently.
        if access.declName.baseName.text == "literal",
           access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Record" {
            return decodeTypedRecordLiteral(call, substitutions: substitutions)
        }

        guard let baseSyntax = access.base,
              let base = decodeTypedFacadeValue(baseSyntax, substitutions: substitutions)
        else { return nil }

        switch access.declName.baseName.text {
        case "union":
            guard let otherSyntax = call.arguments.first?.expression,
                  let other = decodeTypedFacadeValue(otherSyntax, substitutions: substitutions)
            else { return nil }
            return .union(base, other)
        case "inserting", "removing":
            guard let elementSyntax = call.arguments.first?.expression,
                  let element = decodeTypedFacadeValue(elementSyntax, substitutions: substitutions)
            else { return nil }
            let singleton = StateExpr.setLiteral([element])
            return access.declName.baseName.text == "inserting"
                ? .union(base, singleton)
                : .setDifference(base, singleton)
        case "updating":
            break
        case "filtering":
            guard let closure = call.trailingClosure,
                  closure.statements.count == 1,
                  case .expr(let body) = closure.statements.first?.item,
                  let parameter = closureParameterNames(in: closure).first,
                  closureParameterNames(in: closure).count == 1,
                  let predicate = decodeTypedFacadeValue(
                    body,
                    substitutions: substitutions.merging([parameter: .variable(parameter)]) { _, replacement in replacement }
                  )
            else { return nil }
            return .setFilter(base, parameter, predicate)
        case "mapping":
            guard let closure = call.trailingClosure,
                  closure.statements.count == 1,
                  case .expr(let body) = closure.statements.first?.item,
                  let parameter = closureParameterNames(in: closure).first,
                  closureParameterNames(in: closure).count == 1,
                  let mapping = decodeTypedFacadeValue(
                    body,
                    substitutions: substitutions.merging([parameter: .variable(parameter)]) { _, replacement in replacement }
                  )
            else { return nil }
            return .setMap(mapping, parameter, base)
        case "at":
            guard let indexSyntax = call.arguments.first?.expression,
                  let index = decodeTypedFacadeValue(indexSyntax, substitutions: substitutions)
            else { return nil }
            return .tupleDynamicAccess(base, index)
        default:
            return nil
        }

        guard let selectorSyntax = call.arguments.first?.expression,
              let selector = typedUpdateSelector(selectorSyntax, substitutions: substitutions)
        else { return nil }

        if let closure = call.trailingClosure {
            guard closure.statements.count == 1,
                  case .expr(let body) = closure.statements.first?.item,
                  let parameter = closureParameterNames(in: closure).first,
                  closureParameterNames(in: closure).count == 1
            else { return nil }
            let selected = typedSelectedValue(base, selector: selectorSyntax, substitutions: substitutions)
            guard let selected,
                  let value = decodeTypedFacadeValue(
                    body,
                    substitutions: substitutions.merging([parameter: selected]) { _, replacement in replacement }
                  )
            else { return nil }
            return .except(base, selector, value)
        }

        guard let valueSyntax = call.arguments.first(where: { $0.label?.text == "to" })?.expression,
              let value = decodeTypedFacadeValue(valueSyntax, substitutions: substitutions)
        else { return nil }
        return .except(base, selector, value)
    }

    static func decodeTypedFacadeValue(
        _ expression: ExprSyntax,
        substitutions: [String: StateExpr]
    ) -> StateExpr? {
        // A typed function selector can be an explicit finite-domain enum
        // case (for example, `Process.p0`). Resolve it before the typed
        // facade treats member access as a record field or a property.
        if let member = expression.as(MemberAccessExprSyntax.self),
           let type = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
           let value = _enumPhases[type]?[member.declName.baseName.text] {
            return .value(value)
        }
        return decodeTypedFacadeExpr(expression, substitutions: substitutions) ?? decodeStateExpr(expression)
    }

    static func typedUpdateSelector(
        _ expression: ExprSyntax,
        substitutions: [String: StateExpr]
    ) -> StateExpr? {
        if let fieldName = typedFieldName(expression) {
            return .value(.string(fieldName))
        }
        return decodeTypedFacadeValue(expression, substitutions: substitutions)
    }

    static func typedSelectedValue(
        _ base: StateExpr,
        selector: ExprSyntax,
        substitutions: [String: StateExpr]
    ) -> StateExpr? {
        if let fieldName = typedFieldName(selector) {
            return .recordAccess(base, fieldName)
        }
        guard let index = decodeTypedFacadeValue(selector, substitutions: substitutions) else { return nil }
        return .functionApply(base, index)
    }

    static func typedFieldName(_ expression: ExprSyntax) -> String? {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              _enumPhases[base.baseName.text] == nil,
              member.declName.baseName.text != "finiteValues"
        else { return nil }
        return member.declName.baseName.text
    }

    static func typedLiteralType(_ expression: ExprSyntax?) -> (name: String, arguments: [String])? {
        guard let generic = expression?.as(GenericSpecializationExprSyntax.self),
              let base = generic.expression.as(DeclReferenceExprSyntax.self)
        else { return nil }
        return (
            base.baseName.text,
            generic.genericArgumentClause.arguments.map {
                $0.argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }

    static func decodeTypedRecordLiteral(
        _ call: FunctionCallExprSyntax,
        substitutions: [String: StateExpr]
    ) -> StateExpr? {
        var fields: [String: StateExpr] = [:]
        for argument in call.arguments {
            guard let entry = argument.expression.as(FunctionCallExprSyntax.self),
                  let entryName = entry.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
                  entryName == "init",
                  entry.arguments.count == 2,
                  let field = entry.arguments.first.flatMap({ typedFieldName($0.expression) }),
                  fields[field] == nil,
                  let value = entry.arguments.dropFirst().first.flatMap({ decodeTypedFacadeValue($0.expression, substitutions: substitutions) })
            else { return nil }
            fields[field] = value
        }
        return .recordLiteral(fields)
    }

    static func decodeTypedSetLiteral(
        _ call: FunctionCallExprSyntax,
        substitutions: [String: StateExpr]
    ) -> StateExpr? {
        let elements = call.arguments.compactMap { decodeTypedFacadeValue($0.expression, substitutions: substitutions) }
        guard elements.count == call.arguments.count else { return nil }
        return .setLiteral(elements)
    }

    static func decodeTypedFunctionLiteral(
        _ call: FunctionCallExprSyntax,
        domainType: String?,
        substitutions: [String: StateExpr]
    ) -> StateExpr? {
        guard let domainType,
              let domain = _enumDomains[domainType],
              !domain.isEmpty
        else { return nil }
        var pairs: [StateExpr] = []
        for argument in call.arguments {
            guard let entry = argument.expression.as(TupleExprSyntax.self),
                  entry.elements.count == 2,
                  let key = entry.elements.first.flatMap({ decodeTypedFacadeValue($0.expression, substitutions: substitutions) }),
                  let value = entry.elements.dropFirst().first.flatMap({ decodeTypedFacadeValue($0.expression, substitutions: substitutions) })
            else { return nil }
            pairs += [.equal(.variable("_typedFunctionEntry"), key), value]
        }
        return .functionLiteral(
            .setLiteral(domain.map(StateExpr.value)),
            "_typedFunctionEntry",
            .caseExpr(pairs, nil)
        )
    }

    static func decodeMethodCall(_ memberAccess: MemberAccessExprSyntax, _ call: FunctionCallExprSyntax) -> StateExpr? {
        let methodName = memberAccess.declName.baseName.text
        let args = Array(call.arguments)
        let base = memberAccess.base
        let selfExpr = base.flatMap { decodeStateExpr($0) }
        switch methodName {
        case "isIn", "contains", "union", "intersection", "subtracting", "isSubset", "applying",
             "filtering", "mapping", "appending", "concatenating", "integerDivided":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            switch methodName {
            case "isIn": return .in(selfExpr, argExpr)
            case "contains": return .in(argExpr, selfExpr)
            case "union": return .union(selfExpr, argExpr)
            case "intersection": return .intersection(selfExpr, argExpr)
            case "subtracting": return .setDifference(selfExpr, argExpr)
            case "isSubset": return .subset(selfExpr, argExpr)
            case "applying": return .functionApply(selfExpr, argExpr)
            case "filtering": return .setFilter(selfExpr, FreshVarName.fresh(), argExpr)
            case "mapping": return .setMap(argExpr, FreshVarName.fresh(), selfExpr)
            case "appending": return .tupleAppend(selfExpr, argExpr)
            case "concatenating": return .tupleConcatenate(selfExpr, argExpr)
            default: return .integerDivide(selfExpr, argExpr)
            }
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
            case "function", "functionLiteral": return exprs.count >= 2 ? .functionLiteral(exprs[0], FreshVarName.fresh(), exprs[1]) : nil
            case "for": return exprs.count >= 2 ? .forAll(exprs[0], FreshVarName.fresh(), exprs[1]) : nil
            case "exists": return exprs.count >= 2 ? .exists(exprs[0], FreshVarName.fresh(), exprs[1]) : nil
            case "choose": return exprs.count >= 2 ? .choose(exprs[0], FreshVarName.fresh(), exprs[1]) : nil
            case "any": return exprs.count >= 1 ? .choose(exprs[0], FreshVarName.fresh(), .value(.bool(true))) : nil
            default: return nil
            }
        case "firstMatch":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            var pairs: [StateExpr] = []
            var fallback: StateExpr?
            for arg in args {
                if arg.label?.text == "fallback" {
                    fallback = decodeStateExpr(arg.expression)
                } else if let tuple = arg.expression.as(TupleExprSyntax.self) {
                    for elem in tuple.elements { if let p = decodeStateExpr(elem.expression) { pairs.append(p) } }
                }
            }
            return .caseExpr(pairs, fallback)
        default:
            return nil
        }
    }

    static func decodeInfixExpr(_ elements: [ExprSyntax]) -> StateExpr? {
        guard !elements.isEmpty else { return nil }
        if elements.count == 1 {
            return decodeStateExpr(elements[0])
        }
        guard elements.count % 2 == 1 else { return nil }
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

    static func applyInfixOp(_ op: String, _ lhs: StateExpr, _ rhs: StateExpr) -> StateExpr? {
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

}

extension SpecParser {
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
            return nil
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let access = call.calledExpression.as(MemberAccessExprSyntax.self),
           let baseRef = access.base?.as(DeclReferenceExprSyntax.self),
           let elementSyntax = call.arguments.first?.expression,
           let element = decodeStateExpr(elementSyntax) {
            switch access.declName.baseName.text {
            case "inserting":
                return .assign(
                    baseRef.baseName.text,
                    .union(.variable(baseRef.baseName.text), .setLiteral([element]))
                )
            case "removing":
                return .assign(
                    baseRef.baseName.text,
                    .setDifference(.variable(baseRef.baseName.text), .setLiteral([element]))
                )
            default:
                break
            }
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

    static func decodeActionSequence(_ elements: [ExprSyntax]) -> ActionExpr? {
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

    static func unwrapSingleElementTuple(_ expression: ExprSyntax) -> ExprSyntax {
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

    static func decodeCollectionPredicate(_ call: FunctionCallExprSyntax) -> StateExpr? {
        guard let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              let collection = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let method = CollectionPredicateKind(rawValue: access.declName.baseName.text),
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

}
