import Testing
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ArrayValueTests {
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
        for scenario in try ArrayValueMachine.validationScenarios() {
            var machine = try #require(scenario.initialMachines().first)
            let choices: [ArrayValueMachine.Choice] = machine.state.choices
            #expect(choices == [.one, .two, .one])
            let expected = scenario.configuration.input + [3]
            _ = try machine.send(.adopt)
            #expect(machine.state.row == expected)
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
}
