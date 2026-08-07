import SwiftTLA

/// Lamport's Bakery mutual exclusion algorithm (N=2 processes).
/// Faithful translation of tlaplus/Examples Bakery-Boulangerie spec.
/// If this were Swift concurrency: two actors that must never overlap execution.
public struct Bakery {
    public static var spec: TLASpec {
        TLASpec("Bakery") {
            Extends("Integers")
            let num1 = Var<Int>("num1", value: 0); let num2 = Var<Int>("num2", value: 0)
            let flag1 = Var<Int>("flag1", value: 0); let flag2 = Var<Int>("flag2", value: 0)
            let pc1 = Var<Int>("pc1", value: 0); let pc2 = Var<Int>("pc2", value: 0)

            Variable(num1, 0); Variable(num2, 0)
            Variable(flag1, 0); Variable(flag2, 0)
            Variable(pc1, 0); Variable(pc2, 0)

            // Process 1
            Action("P1_Flag") { (pc1 == 0) && flag1.becomes(1) && pc1.becomes(1) }
            Action("P1_Num") { (pc1 == 1) && num1.becomes(1).when(num2 == 0) && flag1.becomes(0) && pc1.becomes(4) }
            Action("P1_Num2") { (pc1 == 1) && num1.becomes(num2 + 1).when(num2 > 0) && flag1.becomes(0) && pc1.becomes(4) }
            Action("P1_WaitF2") { (pc1 == 4) && (flag2 == 1) && pc1.becomes(5) }
            Action("P1_CheckN2") { (pc1 == 4) && (flag2 == 0) && (num2 == 0 && pc1.becomes(6) || num2 > 0 && (num1 < num2 || (num1 == num2 && 1 < 2)) && pc1.becomes(6)) }
            Action("P1_WaitDone") { (pc1 == 5) && (flag2 == 1) && pc1.becomes(5) }
            Action("P1_CheckDone") { (pc1 == 5) && (flag2 == 0) && (num2 == 0 && pc1.becomes(6) || num2 > 0 && (num1 < num2 || (num1 == num2 && 1 < 2)) && pc1.becomes(6)) }
            Action("P1_Critical") { (pc1 == 6) && pc1.becomes(7) }
            Action("P1_Exit") { (pc1 == 7) && num1.becomes(0) && pc1.becomes(0) }

            // Process 2
            Action("P2_Flag") { (pc2 == 0) && flag2.becomes(1) && pc2.becomes(1) }
            Action("P2_Num") { (pc2 == 1) && num2.becomes(1).when(num1 == 0) && flag2.becomes(0) && pc2.becomes(4) }
            Action("P2_Num2") { (pc2 == 1) && num2.becomes(num1 + 1).when(num1 > 0) && flag2.becomes(0) && pc2.becomes(4) }
            Action("P2_WaitF1") { (pc2 == 4) && (flag1 == 1) && pc2.becomes(5) }
            Action("P2_CheckN1") { (pc2 == 4) && (flag1 == 0) && (num1 == 0 && pc2.becomes(6) || num1 > 0 && (num2 < num1 || (num2 == num1 && 2 < 1)) && pc2.becomes(6)) }
            Action("P2_WaitDone") { (pc2 == 5) && (flag1 == 1) && pc2.becomes(5) }
            Action("P2_CheckDone") { (pc2 == 5) && (flag1 == 0) && (num1 == 0 && pc2.becomes(6) || num1 > 0 && (num2 < num1 || (num2 == num1 && 2 < 1)) && pc2.becomes(6)) }
            Action("P2_Critical") { (pc2 == 6) && pc2.becomes(7) }
            Action("P2_Exit") { (pc2 == 7) && num2.becomes(0) && pc2.becomes(0) }

            Invariant("MutualExclusion") { !(pc1 == 6 && pc2 == 6) }
        }
    }
}
