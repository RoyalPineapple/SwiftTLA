struct DieHard: Equatable, Hashable {
    var jug3: Int; var jug5: Int
    init(jug3: Int, jug5: Int) { self.jug3 = jug3; self.jug5 = jug5 }
    static let initial = DieHard(jug3: 0, jug5: 0)
    
    enum Action: String, CaseIterable { case fill3, fill5, empty3, empty5, pour3to5, pour5to3 }
    
    var transitions: [(Action, DieHard)] {
        switch (jug3, jug5) {
        case (0,0): return [(.fill3, DieHard(jug3: 3, jug5: 0)), (.fill5, DieHard(jug3: 0, jug5: 5))]
        case (3,0): return [(.fill5, DieHard(jug3: 3, jug5: 5)), (.empty3, DieHard(jug3: 0, jug5: 0)), (.pour3to5, DieHard(jug3: 0, jug5: 3))]
        case (0,5): return [(.fill3, DieHard(jug3: 3, jug5: 5)), (.empty5, DieHard(jug3: 0, jug5: 0)), (.pour5to3, DieHard(jug3: 3, jug5: 2))]
        case (3,5): return [(.empty3, DieHard(jug3: 0, jug5: 5)), (.empty5, DieHard(jug3: 3, jug5: 0))]
        case (0,3): return [(.fill3, DieHard(jug3: 3, jug5: 3)), (.fill5, DieHard(jug3: 0, jug5: 5)), (.empty5, DieHard(jug3: 0, jug5: 0)), (.pour5to3, DieHard(jug3: 3, jug5: 0))]
        case (3,2): return [(.fill5, DieHard(jug3: 3, jug5: 5)), (.empty3, DieHard(jug3: 0, jug5: 2)), (.empty5, DieHard(jug3: 3, jug5: 0)), (.pour3to5, DieHard(jug3: 0, jug5: 5))]
        case (3,3): return [(.fill5, DieHard(jug3: 3, jug5: 5)), (.empty3, DieHard(jug3: 0, jug5: 3)), (.empty5, DieHard(jug3: 3, jug5: 0)), (.pour3to5, DieHard(jug3: 1, jug5: 5))]
        case (0,2): return [(.fill3, DieHard(jug3: 3, jug5: 2)), (.fill5, DieHard(jug3: 0, jug5: 5)), (.empty5, DieHard(jug3: 0, jug5: 0)), (.pour5to3, DieHard(jug3: 2, jug5: 0))]
        case (1,5): return [(.fill3, DieHard(jug3: 3, jug5: 5)), (.empty3, DieHard(jug3: 0, jug5: 5)), (.empty5, DieHard(jug3: 1, jug5: 0)), (.pour5to3, DieHard(jug3: 3, jug5: 3))]
        case (2,0): return [(.fill3, DieHard(jug3: 3, jug5: 0)), (.fill5, DieHard(jug3: 2, jug5: 5)), (.empty3, DieHard(jug3: 0, jug5: 0)), (.pour3to5, DieHard(jug3: 0, jug5: 2))]
        case (1,0): return [(.fill3, DieHard(jug3: 3, jug5: 0)), (.fill5, DieHard(jug3: 1, jug5: 5)), (.empty3, DieHard(jug3: 0, jug5: 0)), (.pour3to5, DieHard(jug3: 0, jug5: 1))]
        case (2,5): return [(.fill3, DieHard(jug3: 3, jug5: 5)), (.empty3, DieHard(jug3: 0, jug5: 5)), (.empty5, DieHard(jug3: 2, jug5: 0)), (.pour5to3, DieHard(jug3: 3, jug5: 4))]
        case (0,1): return [(.fill3, DieHard(jug3: 3, jug5: 1)), (.fill5, DieHard(jug3: 0, jug5: 5)), (.empty5, DieHard(jug3: 0, jug5: 0)), (.pour5to3, DieHard(jug3: 1, jug5: 0))]
        case (3,4): return [(.fill5, DieHard(jug3: 3, jug5: 5)), (.empty3, DieHard(jug3: 0, jug5: 4)), (.empty5, DieHard(jug3: 3, jug5: 0)), (.pour3to5, DieHard(jug3: 2, jug5: 5))]
        case (3,1): return [(.fill5, DieHard(jug3: 3, jug5: 5)), (.empty3, DieHard(jug3: 0, jug5: 1)), (.empty5, DieHard(jug3: 3, jug5: 0)), (.pour3to5, DieHard(jug3: 0, jug5: 4))]
        case (0,4): return [(.fill3, DieHard(jug3: 3, jug5: 4)), (.fill5, DieHard(jug3: 0, jug5: 5)), (.empty5, DieHard(jug3: 0, jug5: 0)), (.pour5to3, DieHard(jug3: 3, jug5: 1))]
        default: return []
        }
    }
    
    var availableActions: [Action] { transitions.map(\.0) }
    mutating func apply(_ action: Action) { if let n = transitions.first(where: { $0.0 == action })?.1 { self = n } }
}
