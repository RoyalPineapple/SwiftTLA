import SwiftTLA

/// Tortoise and Hare: Floyd's cycle detection algorithm.
/// Two pointers move at different speeds through a linked list of N nodes.
public struct TortoiseHare {
    public static var spec: TLASpec {
        TLASpec("TortoiseHare") {
            Extends("Naturals")
            let t = Var<Int>("tortoise", value: 0)
            let h = Var<Int>("hare", value: 0)
            Variable(t, 0); Variable(h, 0)
            Action("Step") {
                t.becomes((t + 1) % 6) && h.becomes((h + 2) % 6)
            }
            Invariant("InRange") { t >= 0 && t < 6 && h >= 0 && h < 6 }
        }
    }
}
