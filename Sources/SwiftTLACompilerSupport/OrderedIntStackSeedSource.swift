import SwiftSyntax
import SwiftTLA

package struct OrderedIntStackSeedSource: Codable, Equatable, Sendable {
    package struct Push: Codable, Equatable, Sendable {
        package let source: String
        package let position: Int
        package let expanded: Bool
    }

    package struct Expansion: Codable, Equatable, Sendable {
        package let label: String
        package let stack: String
        package let left: String
        package let right: String
        package let local: String
        package let countFloor: Int
        package let lastIndex: String
        package let prefixDrop: Int
        package let localExpandedPosition: Int
        package let write: String
        package let frame: [String]
        package let pushes: [Push]

        fileprivate init(label: String, roots: [String], local: String, write: String,
                         frame: [String], pushes: [Push]) {
            self.label = label
            stack = roots[0]
            left = roots[1]
            right = roots[2]
            self.local = local
            countFloor = 0
            lastIndex = "count"
            prefixDrop = 1
            localExpandedPosition = 2
            self.write = write
            self.frame = frame.sorted()
            self.pushes = pushes
        }
    }

    package let authored: Expansion
    package let typed: Expansion
    package let formalFields: [String]
    package let fieldOrdinals: [Int]
    package let actionOrdinal: Int
    package let formalAction: String
    package let localOrdinal: Int

    private static let frameType = CompiledValueType.tuple([.int, .bool])
    private static let stackType = CompiledValueType.array(frameType)

    package static func authoredExpansion(_ closure: ClosureExprSyntax) -> Expansion? {
        let items = Array(closure.statements)
        guard items.count == 4, let scope = ModelSpecificationSyntax.parameterNames(in: closure).first,
              ModelSpecificationSyntax.parameterNames(in: closure).count == 1 else { return nil }
        let roots = items.prefix(3).compactMap { item -> String? in
            guard let declaration = item.item.as(VariableDeclSyntax.self), declaration.bindingSpecifier.text == "let",
                  declaration.bindings.count == 1, let binding = declaration.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  spelling(call.calledExpression) == [scope, ".", "sharedVar"],
                  call.arguments.count == 1, call.arguments.first?.label?.text == "initial",
                  call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else { return nil }
            return name
        }
        guard roots.count == 3, Set(roots).count == 3, !roots.contains("local"),
              let step = items[3].item.as(FunctionCallExprSyntax.self), spelling(step.calledExpression) == ["Do"],
              step.arguments.count == 1, let stepArgument = step.arguments.first, stepArgument.label == nil,
              let label = stepArgument.expression.as(MemberAccessExprSyntax.self),
              spelling(label.base) == ["Step"], let body = step.trailingClosure,
              body.signature == nil, step.additionalTrailingClosures.isEmpty
        else { return nil }

        let stack = roots[0]
        let steps = Array(body.statements)
        guard steps.count == 2,
              let positive = call(steps[0], named: "When", arguments: 1, closure: false),
              spelling(positive.arguments.first?.expression) == [stack, ".", "count", ">", "0"],
              let capture = call(steps[1], named: "Let", arguments: 1, closure: true),
              spelling(capture.arguments.first?.expression) == [stack, "[", stack, ".", "count", "]"],
              let scoped = capture.trailingClosure, scoped.signature?.capture == nil,
              ModelSpecificationSyntax.parameterNames(in: scoped).count == 1,
              let local = ModelSpecificationSyntax.parameterNames(in: scoped).first,
              !roots.contains(local), local != "local"
        else { return nil }

        let nested = Array(scoped.statements)
        guard nested.count == 2,
              let unexpanded = call(nested[0], named: "When", arguments: 1, closure: false),
              spelling(unexpanded.arguments.first?.expression) == ["!", local, ".", "second", "(", ")"],
              let assign = call(nested[1], named: "Assign", arguments: 2, closure: false),
              let target = assign.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let rhs = assign.arguments.last, rhs.label?.text == "to", target == stack,
              let pushes = authoredPushes(rhs.expression, stack: stack, local: local, roots: roots)
        else { return nil }
        return Expansion(label: label.declName.baseName.text, roots: roots, local: local, write: target,
                         frame: roots.filter { $0 != target }, pushes: pushes)
    }

    package static func check(_ closure: ClosureExprSyntax, program: CompiledProgram) -> Self? {
        guard let authored = authoredExpansion(closure),
              program.layout.actions.count == 1, let declaration = program.layout.actions.first,
              program.behavior.enabledActionIndices == [declaration.id.ordinal],
              program[declaration.id].bindings.isEmpty,
              program.layout.variables.count == 3
        else { return nil }
        let roots = [authored.stack, authored.left, authored.right]
        let fields = roots.compactMap { root in
            program.layout.variables.first { $0.declaration.name.utf8.elementsEqual(root.utf8) }
        }
        guard fields.count == 3, Set(fields.map(\.id)).count == 3,
              program.variableTypes[fields[0].id] == stackType,
              fields.dropFirst().allSatisfy({ program.variableTypes[$0.id] == .int })
        else { return nil }
        var collector = CompiledRows(program: program, fields: fields)
        guard collector.visit(program[declaration.id].body, localScope: nil, scope: [:]),
              let capture = collector.local, let write = collector.write, let pushes = collector.pushes,
              collector.operations == ["positive", "last", "unexpanded", "write"],
              collector.frame == Set(fields.dropFirst().map(\.id)),
              let local = program.binderNames[capture]
        else { return nil }
        let actual = Expansion(label: declaration.declaration.name, roots: fields.map(\.declaration.name),
            local: local, write: write, frame: fields.filter { collector.frame.contains($0.id) }.map(\.declaration.name),
            pushes: pushes)
        guard actual == authored else { return nil }
        return .init(authored: authored, typed: actual, formalFields: fields.map(\.formalName),
                     fieldOrdinals: fields.map(\.id.ordinal), actionOrdinal: declaration.id.ordinal,
                     formalAction: declaration.renderedName, localOrdinal: capture.ordinal)
    }

    private static func spelling(_ expression: ExprSyntax?) -> [String] {
        expression?.tokens(viewMode: .sourceAccurate).map(\.text) ?? []
    }

    private static func call(_ item: CodeBlockItemSyntax, named name: String, arguments: Int,
                             closure: Bool) -> FunctionCallExprSyntax? {
        guard let call = item.item.as(FunctionCallExprSyntax.self),
              spelling(call.calledExpression) == [name], call.arguments.count == arguments,
              call.arguments.first?.label == nil, (call.trailingClosure != nil) == closure,
              call.additionalTrailingClosures.isEmpty else { return nil }
        return call
    }

    private static func authoredPushes(_ rhs: ExprSyntax, stack: String, local: String,
                                       roots: [String]) -> [Push]? {
        var remaining = rhs
        var reversed: [Push] = []
        while let call = remaining.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "appending", let base = member.base {
            guard reversed.count < 3, call.arguments.count == 1, let argument = call.arguments.first,
                  argument.label == nil, call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
                  let pair = argument.expression.as(FunctionCallExprSyntax.self),
                  spelling(pair.calledExpression) == ["Pair", "<", "Int", ",", "Bool", ">", ".", "literal"],
                  pair.arguments.count == 2, pair.arguments.allSatisfy({ $0.label == nil }),
                  pair.trailingClosure == nil, pair.additionalTrailingClosures.isEmpty
            else { return nil }
            let operands = Array(pair.arguments)
            let value = spelling(operands[0].expression)
            let flag = spelling(operands[1].expression)
            guard flag == ["true", ".", "expr"] || flag == ["false", ".", "expr"] else { return nil }
            if value == [local, ".", "first", "(", ")"] {
                reversed.append(.init(source: "local", position: 1, expanded: flag[0] == "true"))
            } else if value.count == 1, roots.dropFirst().contains(value[0]) {
                reversed.append(.init(source: value[0], position: 0, expanded: flag[0] == "true"))
            } else { return nil }
            remaining = base
        }
        guard reversed.count == 3,
              spelling(remaining) == [stack, ".", "prefix", "(", "length", ":", stack, ".", "count", "-", "1", ")"]
        else { return nil }
        return Array(reversed.reversed())
    }

    private struct CompiledRows {
        let program: CompiledProgram
        let fields: [CompiledVariableLayout]
        var local: BinderID?
        var write: String?
        var frame: Set<VariableID> = []
        var operations: [String] = []
        var pushes: [Push]?

        mutating func visit(_ action: CompiledActionExpr, localScope: BinderID?, scope: [BinderID: [Push]]) -> Bool {
            switch action {
            case .and(let lhs, let rhs):
                return visit(lhs, localScope: localScope, scope: scope) && visit(rhs, localScope: localScope, scope: scope)
            case .guard_(let expression):
                if leaf(expression, .value(.boolean(true)), .bool) { return true }
                if node(expression, .greaterThan, .bool, 2),
                   count(expression.children[0]), leaf(expression.children[1], .value(.integer(0)), .int) {
                    operations.append("positive")
                    return true
                }
                if node(expression, .not, .bool, 1), let localScope,
                   projection(expression.children[0], position: 2, binder: localScope, type: .bool) {
                    operations.append("unexpanded")
                    return true
                }
                return false
            case .define(let binder, let expression, let body):
                if node(expression, .tupleDynamicAccess, frameType, 2),
                   sequence(expression.children[0]), count(expression.children[1]),
                   program.bindingTypes[binder] == frameType, local == nil {
                    local = binder
                    operations.append("last")
                    return visit(body, localScope: binder, scope: scope)
                }
                guard program.bindingTypes[binder] == stackType, let localScope,
                      let frames = appendRows(expression, localScope: localScope), scope.isEmpty else { return false }
                let before = operations.count
                guard visit(body, localScope: localScope, scope: [binder: frames]) else { return false }
                return Array(operations.dropFirst(before)) == ["write"]
            case .assign(let field, let expression):
                guard field == fields[0].id, write == nil, let localScope else { return false }
                let frames: [Push]?
                if expression.resultType == stackType, expression.children.isEmpty,
                   case .boundValue(let binding) = expression.operation {
                    frames = scope[binding]
                } else if scope.isEmpty {
                    frames = appendRows(expression, localScope: localScope)
                } else {
                    frames = nil
                }
                guard let frames else { return false }
                write = fields[0].declaration.name
                pushes = frames
                operations.append("write")
                return true
            case .unchanged(let id):
                return frame.insert(id).inserted
            default:
                return false
            }
        }

        func appendRows(_ expression: CompiledExpression, localScope: BinderID) -> [Push]? {
            var remaining = expression
            var reversed: [Push] = []
            while node(remaining, .tupleAppend, stackType, 2) {
                guard reversed.count < 3,
                      let frame = push(remaining.children[1], localScope: localScope) else { return nil }
                reversed.append(frame)
                remaining = remaining.children[0]
            }
            guard reversed.count == 3, node(remaining, .tuplePrefix, stackType, 2),
                  sequence(remaining.children[0]) else { return nil }
            let length = remaining.children[1]
            guard node(length, .subtract, .int, 2), count(length.children[0]),
                  leaf(length.children[1], .value(.integer(1)), .int) else { return nil }
            return Array(reversed.reversed())
        }

        func push(_ expression: CompiledExpression, localScope: BinderID) -> Push? {
            let pair: CompiledExpression
            if node(expression, .assertView(.tuple([.integer, .boolean])), frameType, 1) {
                pair = expression.children[0]
            } else {
                pair = expression
            }
            guard node(pair, .tupleLiteral, frameType, 2), pair.children[1].resultType == .bool,
                  pair.children[1].children.isEmpty,
                  case .value(.boolean(let flag)) = pair.children[1].operation
            else { return nil }
            let value = pair.children[0]
            if projection(value, position: 1, binder: localScope, type: .int) {
                return .init(source: "local", position: 1, expanded: flag)
            }
            guard value.resultType == .int, value.children.isEmpty, case .stateVariable(let id) = value.operation,
                  let field = fields.dropFirst().first(where: { $0.id == id }) else { return nil }
            return .init(source: field.declaration.name, position: 0, expanded: flag)
        }

        func sequence(_ expression: CompiledExpression) -> Bool {
            leaf(expression, .stateVariable(fields[0].id), stackType)
        }

        func count(_ expression: CompiledExpression) -> Bool {
            node(expression, .tupleLength, .int, 1) && sequence(expression.children[0])
        }

        func projection(_ expression: CompiledExpression, position: Int, binder: BinderID,
                        type: CompiledValueType) -> Bool {
            node(expression, .tupleAccess(position), type, 1)
                && leaf(expression.children[0], .boundValue(binder), frameType)
        }

        func leaf(_ expression: CompiledExpression, _ op: CompiledOperation, _ type: CompiledValueType) -> Bool {
            node(expression, op, type, 0)
        }

        func node(_ expression: CompiledExpression, _ op: CompiledOperation, _ type: CompiledValueType,
                  _ arity: Int) -> Bool {
            expression.operation == op && expression.resultType == type && expression.children.count == arity
        }
    }
}
