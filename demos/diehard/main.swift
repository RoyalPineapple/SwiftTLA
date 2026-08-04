var puzzle = DieHard.initial
let solution: [DieHard.Action] = [.fill5, .pour5to3, .empty3, .pour5to3, .fill5, .pour5to3]
for step in solution {
    puzzle.apply(step)
    print("jug3=\(puzzle.jug3) jug5=\(puzzle.jug5)")
}
print("Found jug5=4!")
