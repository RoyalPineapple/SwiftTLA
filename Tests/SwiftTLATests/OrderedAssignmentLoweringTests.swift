import Testing
@testable import SwiftTLA

@Suite("Ordered assignment lowering")
struct OrderedAssignmentLoweringTests {
    private enum Symbol: Equatable {
        case initial(String)
        case literal(TLAValue)
    }

    private enum InvalidShape: Error {
        case source
        case lowered
    }

    private func value(
        _ expression: StateExpr, state: [String: Symbol], bindings: [String: Symbol] = [:]
    ) throws -> Symbol {
        switch expression {
        case .variable(let name):
            if let bound = bindings[name] { return bound }
            guard let current = state[name] else { throw InvalidShape.source }
            return current
        case .value(let literal): return .literal(literal)
        default: throw InvalidShape.source
        }
    }

    private func initial(_ roots: [String]) -> [String: Symbol] {
        Dictionary(uniqueKeysWithValues: roots.map { ($0, .initial($0)) })
    }

    private func sourceResult(
        _ statements: [AlgorithmStatementModel], roots: [String]
    ) throws -> [String: Symbol] {
        var state = initial(roots)
        for statement in statements {
            guard case .set(let target, let expression) = statement,
                  case .root(let root) = target, state[root] != nil else { throw InvalidShape.source }
            state[root] = try value(expression, state: state)
        }
        return state
    }

    private func loweredResult(_ action: ActionExpr, roots: [String]) throws -> [String: Symbol] {
        let original = initial(roots)
        var writes: [String: Symbol] = [:]
        func visit(_ action: ActionExpr, bindings: [String: Symbol]) throws {
            switch action {
            case .define(let name, let expression, let body):
                guard bindings[name] == nil, original[name] == nil else { throw InvalidShape.lowered }
                var nested = bindings
                nested[name] = try value(expression, state: original, bindings: bindings)
                try visit(body, bindings: nested)
            case .and(let left, let right):
                try visit(left, bindings: bindings)
                try visit(right, bindings: bindings)
            case .guard_(.value(.bool(true))): break
            case .assign(.named(let root), let expression):
                guard original[root] != nil, writes[root] == nil else { throw InvalidShape.lowered }
                writes[root] = try value(expression, state: original, bindings: bindings)
            default: throw InvalidShape.lowered
            }
        }
        try visit(action, bindings: [:])
        return original.merging(writes) { _, written in written }
    }

    private func lower(_ statements: [AlgorithmStatementModel]) throws -> ActionExpr {
        let step = AtomicStep(model: .init(label: .init(name: "advance"), statements: statements))
        return try AlgorithmLowerer.lowerAtomicStep(step).action
    }

    @Test("Straight-line copy and literal assignments read the preceding complete state")
    func straightLineAssignmentsPreserveOrderedState() throws {
        let roots = ["x", "y", "z"]
        let statements: [AlgorithmStatementModel] = [
            .set(target: .root("x"), value: .variable("y")),
            .set(target: .root("y"), value: .variable("x")),
            .set(target: .root("x"), value: .value(.int(3))),
            .set(target: .root("z"), value: .variable("x")),
        ]
        for prefix in 0...statements.count {
            let source = Array(statements.prefix(prefix))
            #expect(try loweredResult(lower(source), roots: roots) == sourceResult(source, roots: roots))
        }
    }

    @Test("A stale pre-step read is rejected by the independent symbolic rule")
    func staleReadMutationChangesTheResult() throws {
        let roots = ["first", "second"]
        let step = try #require(GeneratedAtomicCopyProofModel.spec.sourceAtomicSteps.first)
        let source = step.model.statements
        let action = try AlgorithmLowerer.lowerAtomicStep(step).action
        guard case .define(let first, let read, .define(let second, _, let writes)) = action else {
            throw InvalidShape.lowered
        }
        let stale = ActionExpr.define(first, read, .define(second, .variable("first"), writes))
        #expect(try loweredResult(action, roots: roots) == sourceResult(source, roots: roots))
        #expect(try loweredResult(stale, roots: roots) != sourceResult(source, roots: roots))
    }
}
