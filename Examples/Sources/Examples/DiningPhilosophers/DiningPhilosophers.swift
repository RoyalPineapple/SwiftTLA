import SwiftTLA

/// Dining Philosophers (2 philosophers, 2 forks).
/// Models deadlock avoidance in Swift actor resource acquisition.
/// Each philosopher needs both forks to eat. Deadlock if both grab one fork each.
public struct DiningPhilosophers {
    public static var spec: TLASpec {
        TLASpec("DiningPhilosophers") {
            Extends("Integers")
            let fork0 = Var<Int>("fork0", value: 0) // 0=free, 1=taken by P0, 2=taken by P1
            let fork1 = Var<Int>("fork1", value: 0)
            let p0state = Var<Int>("p0state", value: 0) // 0=thinking, 1=hungry, 2=eating
            let p1state = Var<Int>("p1state", value: 0)

            Variable(fork0, 0); Variable(fork1, 0)
            Variable(p0state, 0); Variable(p1state, 0)

            // P0 tries to eat: needs both forks
            Action("P0_TakeFork0") { (p0state == 0) && (fork0 == 0) && fork0.becomes(1) }
            Action("P0_TakeFork1") { (p0state == 0) && (fork0 == 1) && (fork1 == 0) && fork1.becomes(1) && p0state.becomes(2) }
            Action("P0_Eat")       { (p0state == 2) && p0state.becomes(0) && fork0.becomes(0) && fork1.becomes(0) }

            // P1 tries to eat
            Action("P1_TakeFork1") { (p1state == 0) && (fork1 == 0) && fork1.becomes(2) }
            Action("P1_TakeFork0") { (p1state == 0) && (fork1 == 2) && (fork0 == 0) && fork0.becomes(2) && p1state.becomes(2) }
            Action("P1_Eat")       { (p1state == 2) && p1state.becomes(0) && fork0.becomes(0) && fork1.becomes(0) }

            // Deadlock detection: both hungry with one fork each
            Invariant("NoDeadlock") {
                !(fork0 == 1 && fork1 == 2) || (p0state == 2 || p1state == 2)
            }
        }
    }
}
