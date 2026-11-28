import Testing
@testable import SwiftTLA

@Suite("Sequence expression lowering preserves source structure")
struct SequenceExpressionLoweringContractTests {
    @Test("The real lowerer retains sequence reads and rejects a changed constructor or order")
    func actualConcatenationRetainsSourceOperands() throws {
        let compiled = try SequenceConcatenationMachine.spec.compile()
        let action = try #require(compiled.semantics.behavior.actions.first)
        var pending = [action.body]
        var concatenation: CompiledExpression?
        while let node = pending.popLast() {
            switch node {
            case .assign(_, let value), .define(_, let value, _):
                var expressions = [value]
                while let expression = expressions.popLast() {
                    if expression.operation == .tupleConcatenate { concatenation = expression }
                    expressions.append(contentsOf: expression.children)
                }
                if case .define(_, _, let body) = node { pending.append(body) }
            case .and(let left, let right), .or(let left, let right):
                pending.append(contentsOf: [left, right])
            case .ifElse(_, let yes, let no): pending.append(contentsOf: [yes, no])
            case .existsAction(_, _, let body): pending.append(body)
            default: break
            }
        }
        let result = try #require(concatenation)
        let operands = result.children
        #expect(operands.count == 2)
        guard operands.count == 2 else { return }
        let variables = Dictionary(uniqueKeysWithValues: compiled.layout.variables.map {
            ($0.id, $0.declaration.name)
        })
        guard case .stateVariable(let left) = operands[0].operation,
              case .stateVariable(let right) = operands[1].operation else {
            Issue.record("The actual concatenation must read its two source sequences")
            return
        }
        #expect(variables[left] == "front")
        #expect(variables[right] == "back")
        let source = StateExpr.tupleConcatenate(.variable("front"), .variable("back"))
        #expect(SequenceExpressionLoweringContract.matches(source: source,
            loweredOperands: operands, result: result))
        for mutation in [
            CompiledExpression(operation: .tupleAppend, children: operands),
            CompiledExpression(operation: .tupleConcatenate, children: Array(operands.reversed()))
        ] {
            #expect(!SequenceExpressionLoweringContract.matches(source: source,
                loweredOperands: operands, result: mutation))
        }
    }

    @Test("Each sequence edit retains its operation and ordered operands")
    func acceptedConstructors() {
        let sequence = StateExpr.variable("sequence")
        let argument = StateExpr.variable("argument")
        let left = CompiledExpression(operation: .checkingLevel, children: [])
        let right = CompiledExpression(operation: .checkingDiameter, children: [])
        let operands = [left, right]
        let cases: [(StateExpr, CompiledOperation)] = [
            (.tupleAppend(sequence, argument), .tupleAppend),
            (.tupleConcatenate(sequence, argument), .tupleConcatenate),
            (.tupleRemoving(sequence, argument), .tupleRemoving),
            (.tuplePrefix(sequence, argument), .tuplePrefix)
        ]
        for (source, operation) in cases {
            #expect(SequenceExpressionLoweringContract.matches(source: source,
                loweredOperands: operands,
                result: .init(operation: operation, children: operands)))
            #expect(!SequenceExpressionLoweringContract.matches(source: source,
                loweredOperands: operands,
                result: .init(operation: .tupleLength, children: operands)))
            #expect(!SequenceExpressionLoweringContract.matches(source: source,
                loweredOperands: operands,
                result: .init(operation: operation, children: [right, left])))
            #expect(!SequenceExpressionLoweringContract.matches(source: source,
                loweredOperands: operands,
                result: .init(operation: operation, children: [left])))
        }
    }
}
