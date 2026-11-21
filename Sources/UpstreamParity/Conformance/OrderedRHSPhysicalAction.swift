import SwiftTLA

/// Reads the physical LET operands in a checked straight-line action declaration.
/// Tags distinguish an original variable from a preceding captured RHS value.
enum OrderedRHSPhysicalAction {
    struct Capture {
        let binding: String
        let rhs: String
        let plan: TLAValue
        let terms: [String]
        let starts: [Int]
        let guards: [String]
        let additionNodes: [Int]
    }

    struct Action {
        let captures: [Capture]
        let writes: [String: TLAValue]
    }

    private enum Node {
        case literal(Int)
        case read(TLAValue)
        case addition(Int, Int)
    }

    private enum Part {
        case token(String)
        case node(Int)
    }

    static func decode(in module: String, action: String, body: CompiledActionExpr,
                       fields: [CompiledVariableLayout], counter: CompiledVariableLayout, destination: String) -> Action? {
        let prefix = "\(action) == "
        let declarations = module.split(separator: "\n").filter { $0.hasPrefix(prefix) }
        guard declarations.count == 1, let declaration = declarations.first,
              let tokens = StraightLineRenderedActionCheck.tokens(String(declaration.dropFirst(prefix.count))) else {
            return nil
        }
        var bindings: [String: TLAValue] = Dictionary(uniqueKeysWithValues: fields.map {
            ($0.formalName, .tuple([.string("state"), .string($0.declaration.name)]))
        })
        let definitions = tokens.indices.filter { tokens[$0] == "LET" }
        var remaining = body
        if case .and(let assignments, .assign(let id, _)) = body, id == counter.id {
            remaining = assignments
        }
        var captures: [Capture] = []
        var continuation = 0
        for offset in definitions {
            guard case .define(_, _, let next) = remaining,
                  offset + 3 < tokens.count,
                  tokens[offset + 2] == "==",
                  let end = tokens[(offset + 3)...].firstIndex(of: "IN"),
                  let expression = expression(tokens[(offset + 3)..<end], bindings: bindings),
                  let guardParts = additionGuards(tokens, before: offset, count: expression.additionNodes.count),
                  bindings.updateValue(.tuple([.string("capture"), .int(captures.count + 1)]),
                                       forKey: tokens[offset + 1]) == nil else { return nil }
            var guards = Array(repeating: "TRUE", count: expression.terms.count)
            for (node, guardText) in zip(expression.additionNodes, guardParts) {
                guards[node - 1] = guardText
            }
            captures.append(.init(binding: tokens[offset + 1], rhs: tokens[(offset + 3)..<end].joined(separator: " "),
                plan: expression.plan, terms: expression.terms, starts: expression.starts,
                guards: guards, additionNodes: expression.additionNodes))
            remaining = next
            continuation = end + 1
        }
        guard !captures.isEmpty else { return nil }
        if case .define = remaining { return nil }
        guard let writes = writes(in: tokens[continuation...], fields: fields,
            bindings: bindings, counter: counter.formalName, destination: destination) else { return nil }
        return .init(captures: captures, writes: writes)
    }

    private static func writes(in tokens: ArraySlice<String>, fields: [CompiledVariableLayout],
                               bindings: [String: TLAValue], counter: String, destination: String) -> [String: TLAValue]? {
        let names = Dictionary(uniqueKeysWithValues: fields.map { ($0.formalName, $0.declaration.name) })
        var writes: [String: TLAValue] = [:]
        var writesControl = false
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            if token == "UNCHANGED" {
                guard index + 1 < tokens.endIndex, let field = names[tokens[index + 1]],
                      writes.updateValue(.tuple([.string("state"), .string(field)]), forKey: field) == nil else { return nil }
                index += 2
            } else if token.hasSuffix("'") {
                guard index + 2 < tokens.endIndex, tokens[index + 1] == "=" else { return nil }
                let name = String(token.dropLast())
                let value = tokens[index + 2]
                if name == counter {
                    guard !writesControl, value == destination else { return nil }
                    writesControl = true
                } else {
                    guard let field = names[name], let reference = bindings[value],
                          writes.updateValue(reference, forKey: field) == nil else { return nil }
                }
                index += 3
            } else {
                switch token {
                case "(", ")", "/\\", "TRUE", "ELSE", "FALSE": break
                default: return nil
                }
                index += 1
            }
        }
        return writesControl && writes.count == fields.count ? writes : nil
    }

    private struct Expression {
        let plan: TLAValue
        let terms: [String]
        let starts: [Int]
        let additionNodes: [Int]
    }

    private static func expression(_ input: ArraySlice<String>,
                                   bindings: [String: TLAValue]) -> Expression? {
        var nodes: [Node] = []
        var spans: [ClosedRange<Int>] = []
        var parts: [Part] = []
        var opens: [(part: Int, token: Int)] = []
        func append(_ node: Node, span: ClosedRange<Int>) {
            parts.append(.node(nodes.count))
            nodes.append(node)
            spans.append(span)
        }
        func literal(_ index: Int) -> Int? {
            if case .literal(let value) = nodes[index] { return value }
            return nil
        }

        for offset in input.indices {
            let token = input[offset]
            switch token {
            case "(":
                opens.append((parts.count, offset))
            case ")":
                guard let open = opens.popLast() else { return nil }
                let group = Array(parts[open.part...])
                parts.removeSubrange(open.part...)
                switch group.count {
                case 3:
                    guard case .node(let first) = group[0], case .token("+") = group[1],
                          case .node(let second) = group[2] else { return nil }
                    append(.addition(first, second), span: open.token...offset)
                case 5: // The normal renderer prints wide integer literals in base 10^9 chunks.
                    guard case .node(let high) = group[0], case .token("*") = group[1],
                          case .node(let radix) = group[2], literal(radix) == 1_000_000_000,
                          case .token(let operatorToken) = group[3], ["+", "-"].contains(operatorToken),
                          case .node(let low) = group[4], let lowValue = literal(low),
                          (0..<1_000_000_000).contains(lowValue), let highValue = literal(high) else { return nil }
                    let product = highValue.multipliedReportingOverflow(by: 1_000_000_000)
                    let wide = product.partialValue.addingReportingOverflow(operatorToken == "+" ? lowValue : -lowValue)
                    guard !product.overflow, !wide.overflow,
                          let canonical = StraightLineRenderedActionCheck.tokens(TLAValue.int(wide.partialValue).description),
                          input[open.token...offset].elementsEqual(canonical) else { return nil }
                    append(.literal(wide.partialValue), span: open.token...offset)
                default:
                    return nil
                }
            case "+", "*", "-":
                guard !opens.isEmpty else { return nil }
                parts.append(.token(token))
            default:
                if let value = Int(token), String(value) == token {
                    append(.literal(value), span: offset...offset)
                } else if let reference = bindings[token] {
                    append(.read(reference), span: offset...offset)
                } else {
                    return nil
                }
            }
        }
        guard opens.isEmpty, parts.count == 1, case .node(let root) = parts[0] else { return nil }

        var order: [Int] = []
        var pending = [root]
        while let index = pending.popLast() {
            order.append(index)
            if case .addition(let left, let right) = nodes[index] {
                pending.append(left)
                pending.append(right)
            }
        }

        var positions: [Int: Int] = [:]
        var kinds: [TLAValue] = [], literals: [TLAValue] = [], reads: [TLAValue] = []
        var left: [TLAValue] = [], right: [TLAValue] = []
        var terms: [String] = [], starts: [Int] = [], additionNodes: [Int] = []
        for index in order.reversed() {
            let position = kinds.count + 1
            terms.append(input[spans[index]].joined(separator: " "))
            switch nodes[index] {
            case .literal(let value):
                starts.append(position)
                kinds.append(.string("literal"))
                literals.append(.int(value))
                reads.append(.tuple([]))
                left.append(.int(0))
                right.append(.int(0))
            case .read(let reference):
                starts.append(position)
                kinds.append(.string("read"))
                literals.append(.int(0))
                reads.append(reference)
                left.append(.int(0))
                right.append(.int(0))
            case .addition(let first, let second):
                kinds.append(.string("add"))
                guard let lhs = positions[first], let rhs = positions[second] else { return nil }
                starts.append(starts[lhs - 1])
                additionNodes.append(position)
                literals.append(.int(0))
                reads.append(.tuple([]))
                left.append(.int(lhs))
                right.append(.int(rhs))
            }
            positions[index] = position
        }
        let plan = TLAValue.record(["count": .int(kinds.count), "kinds": .tuple(kinds), "literals": .tuple(literals),
            "reads": .tuple(reads), "left": .tuple(left), "right": .tuple(right)])
        return .init(plan: plan, terms: terms, starts: starts, additionNodes: additionNodes)
    }

    private static func additionGuards(_ tokens: [String], before definition: Int, count: Int) -> [String]? {
        guard definition >= 2, tokens[definition - 1] == "(" else { return nil }
        let then = definition - 2
        if count == 0 { return tokens[then] == "THEN" ? nil : [] }
        guard tokens[then] == "THEN" else { return nil }

        var depth = 0
        var start: Int?
        for index in tokens[..<then].indices.reversed() {
            switch tokens[index] {
            case ")": depth += 1
            case "(": depth -= 1
            case "IF" where depth == 0: start = index + 1
            default: break
            }
            if start != nil || depth < 0 { break }
        }
        guard let start, start < then else { return nil }
        let condition = tokens[start..<then]
        if count == 1 { return [condition.joined(separator: " ")] }

        var remainder = condition
        var guards: [String] = []
        while let split = conditional(remainder), split.no.elementsEqual(["FALSE"]) {
            guards.append(split.condition.joined(separator: " "))
            remainder = split.yes
        }
        guard guards.count == count, remainder.elementsEqual(["TRUE"]) else { return nil }
        return guards
    }

    private static func conditional(_ tokens: ArraySlice<String>)
        -> (condition: ArraySlice<String>, yes: ArraySlice<String>, no: ArraySlice<String>)? {
        guard tokens.count > 6, tokens.first == "(", tokens.last == ")",
              tokens[tokens.startIndex + 1] == "IF" else { return nil }
        var then: Int?
        var depth = 0
        for index in tokens.indices {
            switch tokens[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case "THEN" where depth == 1:
                guard then == nil else { return nil }
                then = index
            case "ELSE" where depth == 1:
                guard let then else { return nil }
                return (tokens[(tokens.startIndex + 2)..<then], tokens[(then + 1)..<index],
                        tokens[(index + 1)..<(tokens.endIndex - 1)])
            default: break
            }
        }
        return nil
    }

}
