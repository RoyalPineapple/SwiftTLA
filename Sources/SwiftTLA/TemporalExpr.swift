public enum TemporalExpr: Hashable, Codable, Sendable, CustomStringConvertible {
    case always(StateExpr)
    case eventually(StateExpr)
    case alwaysEventually(StateExpr)
    case eventuallyAlways(StateExpr)
    case leadsTo(StateExpr, StateExpr)

    public var description: String {
        switch self {
        case .always(let p): return "[](\(p))"
        case .eventually(let p): return "<>(\(p))"
        case .alwaysEventually(let p): return "[]<>(\(p))"
        case .eventuallyAlways(let p): return "<>[](\(p))"
        case .leadsTo(let p, let q): return "(\(p) ~> \(q))"
        }
    }
}

public enum FairnessCondition: Hashable, Codable, Sendable, CustomStringConvertible {
    case weakFairness(String)
    case strongFairness(String)

    public var description: String {
        switch self {
        case .weakFairness(let a): return "WF(\(a))"
        case .strongFairness(let a): return "SF(\(a))"
        }
    }
}
