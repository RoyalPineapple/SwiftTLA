import SwiftTLA

/// Missionaries and Cannibals: 3 missionaries and 3 cannibals must cross a river.
/// Boat carries 1-2 people. Cannibals must never outnumber missionaries on either bank.
public struct MissionariesAndCannibals {
    public static var spec: TLASpec {
        TLASpec("MissionariesAndCannibals") {
            Extends("Naturals")
            let ml = Var<Int>("ml", value: 3)   // missionaries left
            let cl = Var<Int>("cl", value: 3)   // cannibals left
            let boat = Var<Int>("boat", value: 0) // 0=left, 1=right

            Variable(ml, 3); Variable(cl, 3); Variable(boat, 0)

            // Move 1 missionary from left to right
            Action("Move1M_LR") {
                (boat == 0) && (ml >= 1) &&
                ((ml - 1 >= cl) || ml == 1) &&
                boat.becomes(1) && ml.becomes(ml - 1)
            }
            // Move 2 missionaries
            Action("Move2M_LR") {
                (boat == 0) && (ml >= 2) &&
                ((ml - 2 >= cl) || ml == 2) &&
                boat.becomes(1) && ml.becomes(ml - 2)
            }
            // Move 1 cannibal
            Action("Move1C_LR") {
                (boat == 0) && (cl >= 1) &&
                boat.becomes(1) && cl.becomes(cl - 1)
            }
            // Move 1M + 1C
            Action("Move1M1C_LR") {
                (boat == 0) && (ml >= 1) && (cl >= 1) &&
                ((ml - 1 >= cl - 1) || ml == 1) &&
                boat.becomes(1) && ml.becomes(ml - 1) && cl.becomes(cl - 1)
            }
            // Move 1M right to left
            Action("Move1M_RL") {
                (boat == 1) && boat.becomes(0) && ml.becomes(ml + 1)
            }
            Invariant("Valid") { ml >= 0 && cl >= 0 && ml <= 3 && cl <= 3 }
        }
    }
}
