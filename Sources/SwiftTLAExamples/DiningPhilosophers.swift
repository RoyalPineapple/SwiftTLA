import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct DiningPhilosophers {
    var fork0 = Var(0)
    var fork1 = Var(0)
    var fork2 = Var(0)
    var state0 = Var(0)
    var state1 = Var(0)
    var state2 = Var(0)
    let thinking = 0; let hungry = 1; let eating = 2

    func getHungry0() { state0.becomes(hungry).when(state0 == thinking) }
    func getHungry1() { state1.becomes(hungry).when(state1 == thinking) }
    func getHungry2() { state2.becomes(hungry).when(state2 == thinking) }

    func eat0() {
        state0.becomes(eating).when(state0 == hungry && fork0 == 0 && fork1 == 0) &&
        fork0.becomes(1) && fork1.becomes(1)
    }
    func eat1() {
        state1.becomes(eating).when(state1 == hungry && fork1 == 0 && fork2 == 0) &&
        fork1.becomes(1) && fork2.becomes(1)
    }
    func eat2() {
        state2.becomes(eating).when(state2 == hungry && fork2 == 0 && fork0 == 0) &&
        fork2.becomes(1) && fork0.becomes(1)
    }

    func putDown0() {
        state0.becomes(thinking).when(state0 == eating) &&
        fork0.becomes(0) && fork1.becomes(0)
    }
    func putDown1() {
        state1.becomes(thinking).when(state1 == eating) &&
        fork1.becomes(0) && fork2.becomes(0)
    }
    func putDown2() {
        state2.becomes(thinking).when(state2 == eating) &&
        fork2.becomes(0) && fork0.becomes(0)
    }

    var noAdjacentEating: StateExpr {
        !(state0 == eating && state1 == eating) &&
        !(state1 == eating && state2 == eating) &&
        !(state2 == eating && state0 == eating)
    }

    var forkExclusive: StateExpr {
        (fork0 < 2) && (fork1 < 2) && (fork2 < 2)
    }
}
