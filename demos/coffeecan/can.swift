struct CoffeeCan: Equatable, Hashable {
    var black: Int; var white: Int
    init(black: Int, white: Int) { self.black = black; self.white = white }
    static let initial = CoffeeCan(black: 5, white: 5)
    
    enum Action: CaseIterable { case bb, ww, bw }
    
    var availableActions: [Action] {
        var actions: [Action] = []
        if black >= 2 { actions.append(.bb) }
        if white >= 2 { actions.append(.ww) }
        if black >= 1 && white >= 1 { actions.append(.bw) }
        return actions
    }
    
    mutating func apply(_ action: Action) {
        switch action {
        case .bb: black -= 1
        case .ww: white -= 2; black += 1
        case .bw: white -= 1
        }
    }
    
    var parityPreserved: Bool { white % 2 == 5 % 2 }
}
