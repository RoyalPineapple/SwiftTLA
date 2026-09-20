import Testing
@testable import SwiftTLA

struct CheckingContextTests {
    private struct Registers: Sendable {
        var firstFreeze = 999
        var secondFreeze = 999
    }

    @Test("checking levels start at zero and register writes persist between BFS levels")
    func preservesRunRegisters() throws {
        var context = CheckingContext(registers: Registers())
        #expect(context.level == 0)
        try context.advanceBreadthFirstLevel()
        #expect(context.level == 1)
        context.registers.firstFreeze = context.level + 1
        try context.advanceBreadthFirstLevel()
        #expect(context.level == 2)
        #expect(context.registers.firstFreeze == 2)
        #expect(context.registers.secondFreeze == 999)
        let independentRun = CheckingContext(registers: Registers())
        #expect(independentRun.level == 0)
        #expect(independentRun.registers.firstFreeze == 999)
    }

    @Test("generated checking and application calls share transitions and snapshots")
    func sharesGeneratedTransitions() throws {
        let machine = try ConvergingFrontiers.makeMachine(.init(node: 1))
        var context = CheckingContext(registers: try machine.initialCheckingRegisters())
        try context.advanceBreadthFirstLevel()
        let application = try machine.successors()
        let checking = try machine.successors(checking: &context)
        #expect(application.map(\.action) == checking.map(\.action))
        #expect(application.map { $0.machine.snapshot } == checking.map { $0.machine.snapshot })
        #expect(machine.snapshot == (try ConvergingFrontiers.makeMachine(.init(node: 1))).snapshot)
    }

    @Test("BFS shares registers across states, uses shortest discovery levels, and resets between runs")
    func threadsRunContext() throws {
        let initial = CheckingContextProbe(machine: try ConvergingFrontiers.makeMachine(.init(node: 1)))
        for _ in 0..<2 {
            let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 130)
            #expect(graph.transitions.count == 130)
            #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 130)
        }
    }
}
