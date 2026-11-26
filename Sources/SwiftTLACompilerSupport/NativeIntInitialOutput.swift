import SwiftSyntax
import SwiftTLA

package let nativeIntTypeTokens = ["SwiftTLA", ".", "TLAValue", ".", "IntegerLiteralType"]

package func nativeVariableSlots(_ layout: CompiledLayout) -> [VariableID: String] {
    Dictionary(uniqueKeysWithValues: layout.variables.map { variable in
        let stem = String(variable.declaration.name.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 65...90, 97...122, 48...57, 95: Character(String(scalar))
            default: "_"
            }
        })
        return (variable.id, "_value_\(stem)_\(variable.id.ordinal)")
    })
}

package enum NativeIntInitialStep: Equatable, Sendable {
    case integer(Int)
    case slot(String)
    case add(Int, Int)
}

@discardableResult
package func verifyOrderedIntInitialExpression(_ declaration: DeclSyntax?, named name: String,
                                       expression: CompiledExpression,
                                       slots: [VariableID: String]) throws -> [NativeIntInitialStep] {
    func invalid() -> CompilationDiagnostic {
        CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native._initialStates.expression.\(name)",
            expected: "the compiled Int expression's ordered reads and checked additions",
            actual: "the generated Swift initializer has another value or evaluation order",
            nextSafeAction: "Report this native initialization generation failure.")
    }
    var expected: [NativeIntInitialStep] = []
    var values: [Int] = []
    var pending = [(expression, false)]
    while let (node, expanded) = pending.popLast() {
        guard node.resultType == .int else { throw invalid() }
        let step: NativeIntInitialStep
        switch node.operation {
        case .add:
            guard node.children.count == 2 else { throw invalid() }
            if !expanded {
                pending.append((node, true))
                pending.append((node.children[1], false))
                pending.append((node.children[0], false))
                continue
            }
            guard values.count >= 2 else { throw invalid() }
            let right = values.removeLast()
            step = .add(values.removeLast(), right)
        case .stateVariable(let id):
            guard node.children.isEmpty, let slot = slots[id] else { throw invalid() }
            step = .slot(slot)
        case .value(.integer(let integer)):
            guard node.children.isEmpty else { throw invalid() }
            step = .integer(integer)
        default: throw invalid()
        }
        values.append(expected.count)
        expected.append(step)
    }
    guard values == [expected.count - 1] else { throw invalid() }
    let tokens = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) } ?? []
    let binding = ["let", name, ":"] + nativeIntTypeTokens + ["="]
    let starts = tokens.indices.filter { index in
        index + binding.count <= tokens.count &&
            Array(tokens[index..<(index + binding.count)]) == binding
    }
    guard starts.count == 1, let start = starts.first else { throw invalid() }
    let rhsStart = start + binding.count
    let reads = Dictionary(uniqueKeysWithValues: slots.values.map { ([$0], $0) })
    guard let decoded = decodeNativeOrderedIntExpression(tokens[rhsStart...], reads: reads),
          decoded.steps == expected,
          let following = tokens.dropFirst(rhsStart + decoded.consumed).first,
          ["if", "let", "result", "}", "evaluatingInitializerOrdinal"].contains(following) else {
        throw invalid()
    }
    return decoded.steps
}

/// Decodes the physically emitted Int leaf or ordered postorder closure.
/// A returned step is an index in the existing checked expression plan.
package func decodeNativeOrderedIntExpression(
    _ tokens: ArraySlice<String>, reads: [[String]: String],
    projections: [(sourceType: [String], reads: [[String]: String], cases: [String: Int])] = []
) -> (steps: [NativeIntInitialStep], consumed: Int,
      projectedReads: [(step: Int, read: String, cases: [String: Int])])? {
    var cursor = tokens.startIndex
    var projectedReads: [(step: Int, read: String, cases: [String: Int])] = []
    func take(_ pattern: [String]) -> Bool {
        guard tokens[cursor...].starts(with: pattern, by: { $0.utf8.elementsEqual($1.utf8) }) else { return false }
        cursor += pattern.count
        return true
    }
    func arithmeticIndex() -> Int? {
        guard let name = tokens[cursor...].first, name.hasPrefix("_arithmetic"),
              let index = Int(name.dropFirst("_arithmetic".count)), index >= 0,
              name == "_arithmetic\(index)" else { return nil }
        cursor += 1
        return index
    }
    let readPatterns = reads.keys.sorted { $0.count > $1.count }
    func readLeaf(at step: Int) -> NativeIntInitialStep? {
        for projection in projections {
            guard let decoded = decodeNativeIntReadProjection(tokens[cursor...],
                sourceType: projection.sourceType, reads: projection.reads) else { continue }
            let cases = Dictionary(uniqueKeysWithValues: decoded.cases.map { ($0.key, $0.value) })
            guard cases == projection.cases else { return nil }
            cursor += decoded.consumed
            projectedReads.append((step, decoded.read, cases))
            return .slot(decoded.read)
        }
        if take(["SwiftTLA", ".", "_nativeIntMinimum", "(", ")"]) { return .integer(Int.min) }
        let negative = take(["-"])
        if let spelling = tokens[cursor...].first, let integer = Int((negative ? "-" : "") + spelling),
           spelling == String(integer.magnitude), negative == (integer < 0), integer != Int.min {
            cursor += 1
            return .integer(integer)
        }
        guard !negative, let pattern = readPatterns.first(where: take), let read = reads[pattern] else { return nil }
        return .slot(read)
    }
    if !take(["(", "try", "{", "(", ")", "throws", "->"] + nativeIntTypeTokens + ["in"]) {
        guard let leaf = readLeaf(at: 0) else { return nil }
        return ([leaf], cursor - tokens.startIndex, projectedReads)
    }
    var steps: [NativeIntInitialStep] = []
    var stack: [Int] = []
    while take(["let", "_arithmetic\(steps.count)", ":"] + nativeIntTypeTokens + ["="]) {
        let step: NativeIntInitialStep
        if take(["try", "SwiftTLA", ".", "_nativeIntAdd", "("]) {
            guard let left = arithmeticIndex(), take([","]), let right = arithmeticIndex(), take([")"]),
                  stack.suffix(2).elementsEqual([left, right]) else { return nil }
            stack.removeLast(2)
            step = .add(left, right)
        } else {
            guard let leaf = readLeaf(at: steps.count) else { return nil }
            step = leaf
        }
        stack.append(steps.count)
        steps.append(step)
    }
    let root = steps.count - 1
    guard steps.count >= 3, stack == [root],
          take(["return", "_arithmetic\(root)", "}", "(", ")", ")"]) else { return nil }
    return (steps, cursor - tokens.startIndex, projectedReads)
}

/// Decode an emitted integer projection separately from its compiled domain check.
package func decodeNativeIntReadProjection(
    _ tokens: ArraySlice<String>, sourceType: [String], reads: [[String]: String]
) -> (read: String, cases: [(key: String, value: Int)], consumed: Int)? {
    var cursor = tokens.startIndex
    func take(_ pattern: [String]) -> Bool {
        guard tokens[cursor...].starts(with: pattern, by: { $0.utf8.elementsEqual($1.utf8) }) else { return false }
        cursor += pattern.count
        return true
    }
    let prefix = ["(", "{", "(", "value", ":"] + sourceType + [")", "->"]
        + nativeIntTypeTokens + ["in", "switch", "value", "{"]
    guard !sourceType.isEmpty, take(prefix) else { return nil }
    var cases: [(key: String, value: Int)] = []
    var keys: Set<String> = []
    while take(["case", "."]) {
        guard let key = tokens[cursor...].first, keys.insert(key).inserted else { return nil }
        cursor += 1
        guard take([":", "return"]),
              let decoded = decodeNativeOrderedIntExpression(tokens[cursor...], reads: [:]),
              decoded.steps.count == 1,
              case .integer(let value) = decoded.steps[0] else { return nil }
        cursor += decoded.consumed
        cases.append((key, value))
    }
    guard !cases.isEmpty, take(["}", "}", ")", "("]),
          let operand = reads.keys.sorted(by: { $0.count > $1.count }).first(where: take),
          let read = reads[operand], take([")"]) else { return nil }
    return (read, cases, cursor - tokens.startIndex)
}
