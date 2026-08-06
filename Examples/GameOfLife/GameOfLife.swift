import SwiftTLA; import SwiftTLAMacros
@TLAModel public struct GameOfLife {
    static var spec: TLASpec { TLASpec("GameOfLife") {
        Extends("Naturals")
        let cells = Var<Int>("cells", value: 0); let gen = Var<Int>("gen", value: 0)
        Variable(cells, 0); Variable(gen, 0)
        Action("Evolve") { cells.becomes((cells + 1) % 8) && gen.becomes(gen + 1).when(gen < 10) }
        Invariant("Bounded") { gen >= 0 && gen <= 10 }
    }}
}
