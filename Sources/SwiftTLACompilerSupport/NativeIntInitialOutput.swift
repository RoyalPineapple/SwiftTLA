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
    var cursor = start + binding.count
    func take(_ pattern: [String]) -> Bool {
        guard cursor + pattern.count <= tokens.count,
              Array(tokens[cursor..<(cursor + pattern.count)]) == pattern else { return false }
        cursor += pattern.count
        return true
    }
    func arithmeticIndex() -> Int? {
        guard cursor < tokens.count, tokens[cursor].hasPrefix("_arithmetic"),
              let index = Int(tokens[cursor].dropFirst("_arithmetic".count)) else { return nil }
        cursor += 1
        return index
    }
    func readStep(available: Int) -> NativeIntInitialStep? {
        if take(["try", "SwiftTLA", ".", "_nativeIntAdd", "("]) {
            guard let left = arithmeticIndex(), take([","]), let right = arithmeticIndex(),
                  take([")"]), left < available, right < available else { return nil }
            return .add(left, right)
        }
        guard cursor < tokens.count else { return nil }
        if take(["SwiftTLA", ".", "_nativeIntMinimum", "(", ")"]) { return .integer(Int.min) }
        let negative = take(["-"])
        if cursor < tokens.count, let integer = Int((negative ? "-" : "") + tokens[cursor]) {
            cursor += 1
            return .integer(integer)
        }
        if !negative, cursor < tokens.count, slots.values.contains(tokens[cursor]) {
            let slot = tokens[cursor]
            cursor += 1
            return .slot(slot)
        }
        return nil
    }
    var decoded: [NativeIntInitialStep] = []
    if case .add = expression.operation {
        guard take(["(", "try", "{", "(", ")", "throws", "->"] + nativeIntTypeTokens + ["in"]) else { throw invalid() }
        for (index, step) in expected.enumerated() {
            guard take(["let", "_arithmetic\(index)", ":"] + nativeIntTypeTokens + ["="]),
                  let actual = readStep(available: index), actual == step else { throw invalid() }
            decoded.append(actual)
        }
        guard take(["return", "_arithmetic\(expected.count - 1)", "}", "(", ")", ")"]) else {
            throw invalid()
        }
    } else {
        guard expected.count == 1, let actual = readStep(available: 0), actual == expected[0] else { throw invalid() }
        decoded.append(actual)
    }
    guard cursor < tokens.count, ["if", "let", "result", "}", "evaluatingInitializerOrdinal"].contains(tokens[cursor]) else {
        throw invalid()
    }
    return decoded
}
