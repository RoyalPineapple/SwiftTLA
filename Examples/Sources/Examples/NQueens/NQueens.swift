import SwiftTLA; import SwiftTLAMacros
@TLAModel public struct NQueens {
    static var spec: TLASpec { TLASpec("NQueens") {
        Extends("Naturals")
        let placed = Var<Int>("placed", value: 0); let row = Var<Int>("row", value: 0)
        Variable(placed, 0); Variable(row, 0)
        Action("Place") { row.becomes(row + 1).when(row < 4) && placed.becomes(placed + 1).when(placed < 4) }
        Invariant("Valid") { placed >= 0 && placed <= 4 && row >= 0 && row <= 4 }
    }}
}
