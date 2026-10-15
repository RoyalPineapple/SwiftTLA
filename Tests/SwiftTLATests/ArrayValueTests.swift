import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ArrayValueTests {
    @Test("injective choices compose directly with ordinary Swift array expressions")
    func injectiveSequenceUsesArray() {
        let values = Set<Int>([1, 2]).expr
        let sequence: Expr<[Int]> = InjectiveSequence(from: values)
        let appended: Expr<[Int]> = [0].expr.concatenating(sequence)
        #expect(sequence.stateExpr == .choose(
            .functionSet(.integerRange(.int(1), .cardinality(values.stateExpr)), values.stateExpr),
            "f", .operatorApplication(.reference("IsInjective", arity: 1), [.value(.variable("f"))])))
        #expect(appended.stateExpr == .tupleConcatenate([0].expr.stateExpr, sequence.stateExpr))
    }

    @Test("sequence domains and set expressions compose without collection adapters")
    func collectionComposition() throws {
        let domain: Expr<SetExpr<[Int]>> = Sequences(of: Set<Int>([1, 2]), lengths: 1...1)
        let values = Set<[Int]>([[1]]).expr
        let union: Expr<Set<[Int]>> = values.union(domain)
        let intersection: Expr<Set<[Int]>> = values.intersection(domain)
        let difference: Expr<Set<[Int]>> = values.subtracting(domain)
        #expect(try compiledValue(union.stateExpr) == .set([.tuple([.int(1)]), .tuple([.int(2)])]))
        #expect(try compiledValue(intersection.stateExpr) == .set([.tuple([.int(1)])]))
        #expect(try compiledValue(difference.stateExpr) == .set([]))
        #expect(try compiledValue(values.isSubset(of: domain).stateExpr) == .bool(true))
        #expect(try compiledValue(domain.isSubset(of: values).stateExpr) == .bool(false))
    }

    @Test("Swift arrays preserve ordered repeated values at the formal boundary")
    func preservesValues() throws {
        let values = [2, 1, 2]
        #expect(values.tlaValue == .tuple([.int(2), .int(1), .int(2)]))
        #expect([Int](formalValue: values.tlaValue) == values)
        #expect([Int](formalValue: .tuple([])) == [])
        #expect([Int](formalValue: .tuple([.string("2")])) == nil)
        #expect([Int](formalValue: .set([.int(2)])) == nil)
        let appended: Expr<[Int]> = values.expr.appending(3)
        let concatenated: Expr<[Int]> = values.expr.concatenating([3].expr)
        #expect(try compiledValue(appended.stateExpr) == .tuple([.int(2), .int(1), .int(2), .int(3)]))
        #expect(try compiledValue(concatenated.stateExpr) == compiledValue(appended.stateExpr))
        #expect(try compiledValue(values.expr.head().stateExpr) == .int(2))
        #expect(try compiledValue(values.expr.at(2.expr).stateExpr) == .int(1))
        #expect(try compiledValue(Fold(values.expr, startingWith: 0) { value, sum in value + sum }.stateExpr) == .int(5))
        let parser = ParserSession()
        let literal: ExprSyntax = "Array<Int>([2, 1, 2])"
        #expect(parser.decodeTypedFacadeValue(literal, scope: .empty) == .tupleLiteral([.int(2), .int(1), .int(2)]))
    }

    @Test("array configuration and native operations preserve ordinary Swift state and nominal members")
    func generatedArrays() throws {
        let row = try #require(TLAStateProjection.Token(validating: "row"))
        let scenarios = try ArrayValueMachine.validationScenarios()
        #expect(scenarios.count == 2)
        #expect(Set(scenarios.map(\.configuration.input)) == Set([[Int](), [2, 1, 2]]))
        for scenario in scenarios {
            var machine = try #require(scenario.initialMachines().first)
            let choices: [ArrayValueMachine.Choice] = machine.state.choices
            #expect(choices == [.one, .two, .one])
            let expected = scenario.configuration.input + [3]
            _ = try machine.send(.adopt)
            #expect(machine.state.row == expected)
            #expect(try machine.formalProjection(of: machine.snapshot).value(for: row)
                == .tuple(expected.map(TLAValue.int)))
            _ = try machine.send(.remove)
            #expect(machine.state.row == Array(expected.dropFirst()))
            _ = try machine.send(.select)
            #expect(machine.state.row == expected.dropFirst().filter { $0 != 2 })
            let graph = try scenario.explore(maximumStates: 20)
            #expect(graph.safetyViolations.isEmpty)
            #expect(graph.transitions.keys.contains(machine.snapshot))
            #expect(try scenario.render().checkNames == ["Shape"])
        }
    }

    @Test("an appended sequence element can be read by a later generated step")
    func appendedElementRead() throws {
        var machine = try ArrayAppendReadMachine.makeMachine()
        #expect(machine.state.sequence.isEmpty)
        #expect(machine.state.result == 0)
        #expect(try machine.send(.push).after.sequence == [42])
        #expect(try machine.send(.pop).after.result == 42)

        let graph = try ReachabilityGraph(
            initialMachines: ArrayAppendReadMachine.initialMachines(), maximumStates: 10)
        #expect(graph.transitions.count == 3)
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 3)
        #expect(graph.safetyViolations.isEmpty)
        #expect(try ArrayAppendReadMachine.render().tlaBundle.tla.contains("sequence[1]"))
    }

    @Test("an array read outside its domain fails in both generated checking paths")
    func arrayReadOutsideDomain() throws {
        let compilation = try ArrayReadOutsideDomainMachine.spec.compile()
        let sequenceID = try #require(compilation.layout.testVariableID(named: "sequence"))
        let action = try #require(compilation.semantics.behavior.actions.first)
        guard case .define(_, let read, _) = action.body else {
            Issue.record("The read must lower to one ordered binding")
            return
        }
        #expect(read.operation == .tupleDynamicAccess)
        #expect(read.children.map(\.operation) == [
            .stateVariable(sequenceID), .value(.integer(1))
        ])
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        #expect(throws: EvalError.indexOutOfBounds(1, 0)) {
            try runtime.successors(for: action.id, from: initial)
        }

        var machine = try ArrayReadOutsideDomainMachine.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: 1, count: 0)) {
            try machine.send(.read)
        }
        #expect(machine.state == before)

        let rendered = try ArrayReadOutsideDomainMachine.render()
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/ArrayReadOutsideDomainMachine.tla")
            .standardizedFileURL
        let expectedTLA = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(rendered.tlaBundle.root.tla == expectedTLA)
        let unguardedTLA = rendered.tlaBundle.root.tla.replacingOccurrences(
            of: "IF (IF (1 \\in DOMAIN (sequence)) THEN TRUE ELSE FALSE)",
            with: "IF TRUE")
        #expect(unguardedTLA != rendered.tlaBundle.root.tla)
        #expect(unguardedTLA != expectedTLA)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("ArrayValueFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .first { $0.name.text == "ArrayReadOutsideDomainMachine" })
        var emitter = NativeSwiftEmitter(model: try TLASpecVerifier.parseAndVerify(declaration))
        let visitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let swiftProofInput = proofInput.deletingLastPathComponent()
            .appendingPathComponent("GeneratedSequenceIndexFailureSwiftVisitor.txt")
        let expectedVisitor = try String(contentsOf: swiftProofInput, encoding: .utf8)
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map(\.text)
        }
        #expect(tokens(visitor.description) == tokens(expectedVisitor))
        let uncheckedSwift = visitor.description.replacingOccurrences(
            of: "_NativeMachineOperations.sequenceElement(_sequenceValue, at: _sequenceIndex)",
            with: "_sequenceValue[_sequenceIndex]")
        #expect(uncheckedSwift != visitor.description)
        #expect(tokens(uncheckedSwift) != tokens(expectedVisitor))
        #expect(rendered.intrinsicInvariantNames.contains("__SwiftTLAEvaluationOK"))
    }

    @Test("sequence edits preserve success and out-of-bounds failure on both outputs")
    func sequenceEditBounds() throws {
        let machines = try SequenceEditBoundsMachine.initialMachines()
        #expect(machines.count == 2)
        let valid = try #require(machines.first { $0.state.position == 2 })
        let invalid = try #require(machines.first { $0.state.position == 3 })
        let removed = try #require(valid.successors(for: .remove).first)
        let prefix = try #require(valid.successors(for: .prefix).first)
        #expect(removed.state.row == [4])
        #expect(prefix.state.row == [4, 5])
        for action in [SequenceEditBoundsMachine.Action.remove, .prefix] {
            #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: 3, count: 2)) {
                try invalid.successors(for: action)
            }
        }
        #expect(invalid.state.row == [4, 5])

        let rendered = try SequenceEditBoundsMachine.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let declarations = rendered.tlaBundle.root.tla.split(separator: "\n")
        let remove = try #require(declarations.first { $0.hasPrefix("remove ==") })
        let sequencePrefix = try #require(declarations.first { $0.hasPrefix("prefix ==") })
        #expect(remove.contains("position \\in DOMAIN (row)"))
        #expect(sequencePrefix.contains("position <= Len(row)"))
        #expect(remove.contains("ELSE FALSE"))
        #expect(sequencePrefix.contains("ELSE FALSE"))
        #expect(declarations.filter { $0.hasPrefix("__SwiftTLASequenceIndexOutOfBoundsFailure") }.count == 2)
    }

    @Test("sequence reads use one-based indices and report the complete failure payload")
    func sequenceReadOperation() throws {
        let values = [4, 5]
        #expect(try _NativeMachineOperations.sequenceElement(values, at: 1) == 4)
        #expect(try _NativeMachineOperations.sequenceElement(values, at: 2) == 5)
        #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: 0, count: 2)) {
            try _NativeMachineOperations.sequenceElement(values, at: 0)
        }
        #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: 3, count: 2)) {
            try _NativeMachineOperations.sequenceElement(values, at: 3)
        }
    }

    @Test("head and tail of an empty sequence report the same failure in both outputs")
    func emptySequenceOperations() throws {
        #expect(try _NativeMachineOperations.sequenceHead([4, 5]) == 4)
        #expect(try _NativeMachineOperations.sequenceTail([4, 5]) == [5])
        let compilation = try EmptySequenceReadMachine.spec.compile()
        let sequenceID = try #require(compilation.layout.testVariableID(named: "sequence"))
        let actions = compilation.semantics.behavior.actions
        #expect(actions.count == 2)
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        for (action, operation) in zip(actions, [CompiledOperation.tupleHead, .tupleTail]) {
            guard case .define(_, let read, _) = action.body else {
                Issue.record("The sequence read must lower to one ordered binding")
                return
            }
            #expect(read.operation == operation)
            #expect(read.children.map(\.operation) == [.stateVariable(sequenceID)])
            #expect(throws: EvalError.emptySequence) {
                try runtime.successors(for: action.id, from: initial)
            }
        }
        var machine = try EmptySequenceReadMachine.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.emptySequence) {
            try machine.send(.readHead)
        }
        #expect(throws: NativeMachineEvaluationError.emptySequence) {
            try machine.send(.readTail)
        }
        #expect(machine.state == before)

        let rendered = try EmptySequenceReadMachine.render()
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/EmptySequenceReadMachine.tla")
            .standardizedFileURL
        let expectedTLA = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(rendered.tlaBundle.root.tla == expectedTLA)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("ArrayValueFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .first { $0.name.text == "EmptySequenceReadMachine" })
        var emitter = NativeSwiftEmitter(model: try TLASpecVerifier.parseAndVerify(declaration))
        let visitors = try emitter.machineMembers().compactMap { $0.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text.hasPrefix("_visitUpdates") }
        #expect(visitors.count == 2)
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map(\.text)
        }
        for visitor in visitors {
            let name: String
            switch visitor.name.text {
            case "_visitUpdates0": name = "GeneratedEmptySequenceHeadSwiftVisitor.txt"
            case "_visitUpdates1": name = "GeneratedEmptySequenceTailSwiftVisitor.txt"
            default:
                Issue.record("Unexpected generated action visitor: \(visitor.name.text)")
                return
            }
            let expected = try String(contentsOf: proofInput.deletingLastPathComponent()
                .appendingPathComponent(name), encoding: .utf8)
            #expect(tokens(visitor.description) == tokens(expected))
        }
        #expect(rendered.intrinsicInvariantNames.contains("__SwiftTLAEvaluationOK"))
    }
}
