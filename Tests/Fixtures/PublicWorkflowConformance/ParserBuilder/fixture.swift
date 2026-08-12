{
    let x = Var<Int>("x", 0)
    Variable(x)
    Action("advance") { x.becomes(1) }
    Invariant("withinBounds") { x <= 1 }
}
