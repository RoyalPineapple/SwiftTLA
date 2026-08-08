import SwiftTLA

/// Conway's Game of Life — N=4 grid. Single initial state (all dead).
/// Upstream: specifications/GameOfLife/GameOfLife.tla

extension Example {
    public static let gameOfLife = Entry(
        id: "GameOfLife/N4",
        upstreamSpec: "GameOfLife",
        upstreamModule: "specifications/GameOfLife/GameOfLife.tla",
        upstreamCfg: "specifications/GameOfLife/GameOfLife.cfg",
        expectedDistinct: 2,
        spec: gameOfLifeSpec(),
        notes: "N=4 grid. Single init (all dead). Conway's rules.",
    )
}

private func gameOfLifeSpec() -> TLASpec {
    let N = 4
    let grid = Var<TLAFunctionType>("grid")
    let positions = (1...N).flatMap { x in (1...N).map { y in (x, y) } }

    func pos(_ x: Int, _ y: Int) -> StateExpr { .tupleLiteral([.int(x), .int(y)]) }

    func nextValue(_ x: Int, _ y: Int) -> StateExpr {
        var terms: [StateExpr] = []
        for dx in -1...1 {
            for dy in -1...1 where !(dx == 0 && dy == 0) {
                let nx = x + dx, ny = y + dy
                if (1...N).contains(nx) && (1...N).contains(ny) {
                    terms.append(StateExpr.ifThenElse(grid.applying(pos(nx, ny)), .int(1), .int(0)))
                }
            }
        }
        let score = terms.dropFirst().reduce(terms[0]) { StateExpr.add($0, $1) }
        let alive = grid.applying(pos(x, y))
        return (alive && (score >= 2 && score <= 3)) || (!alive && score == 3)
    }

    let nextExpr: StateExpr = {
        var expr: StateExpr = grid.stateExpr
        for (x, y) in positions {
            expr = .except(expr, pos(x, y), nextValue(x, y))
        }
        return expr
    }()

    // Start with a blinker (3 horizontal cells) — oscillates with period 2
    var initCells: [TLAValue: TLAValue] = [:]
    for (x, y) in positions {
        let alive = (x == 2 && y == 2) || (x == 2 && y == 3) || (x == 2 && y == 4)
        initCells[.tuple([.int(x), .int(y)])] = .bool(alive)
    }
    let initFunc: TLAValue = .function(Dictionary(uniqueKeysWithValues: initCells.map { ($0.key, $0.value) }))

    return TLASpec("GameOfLife") {
        Extends("Integers")

        Variable(grid, initFunc)

        Invariant("TypeOK") {
            for (x, y) in positions {
                StateExpr.in(grid.applying(pos(x, y)), .setLiteral([.bool(false), .bool(true)]))
            }
        }

        Action("Next") {
            grid.becomes(Expr(nextExpr))
        }
    }
}
