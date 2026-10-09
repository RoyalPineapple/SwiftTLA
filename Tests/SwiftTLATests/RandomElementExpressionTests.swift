import Testing
@testable import SwiftTLA

struct RandomElementExpressionTests {
    @Test("random selection returns a member and rejects an empty domain")
    func finiteDomain() throws {
        #expect(try evaluateClosed(RandomElement(from: SetExpr<Int>.literal(7)).stateExpr) == .int(7))
        #expect(throws: NativeMachineEvaluationError.emptyRandomElementDomain) {
            try _NativeMachineOperations.randomElement(from: Set<Int>())
        }
    }

    @Test("level-dependent random guard uses generated Swift and renders TLC RandomElement")
    func generatedGuard() throws {
        let machine = try CheckingLevelRandomElementModel.makeMachine()
        var context = CheckingContext(registers: try machine.initialCheckingRegisters())
        try context.advanceLevel()
        let successors = try machine.successors(checking: &context)
        #expect(successors.count == 1)
        #expect(successors.first?.machine.state.value == 1)
        let tla = try CheckingLevelRandomElementModel.render().tlaBundle.tla
        #expect(tla.contains("RandomElement(1..TLCGet(\"level\"))"))
    }
}
