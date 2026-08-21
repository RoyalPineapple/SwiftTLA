public enum TemporalExpr: Hashable, Sendable, CustomStringConvertible {
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

extension TemporalExpr {
    var tlaModuleSource: String {
        switch self {
        case .always(let predicate): return "[]\(predicate.tlaModuleSource)"
        case .eventually(let predicate): return "<>\(predicate.tlaModuleSource)"
        case .alwaysEventually(let predicate): return "[]<>\(predicate.tlaModuleSource)"
        case .eventuallyAlways(let predicate): return "<>[]\(predicate.tlaModuleSource)"
        case .leadsTo(let lhs, let rhs): return "(\(lhs.tlaModuleSource) ~> \(rhs.tlaModuleSource))"
        }
    }
}

extension StateExprConvertible {
    public func leadsTo(_ q: some StateExprConvertible) -> TemporalExpr {
        .leadsTo(self.stateExpr, q.stateExpr)
    }
}

public enum FairnessCondition: Hashable, Sendable, CustomStringConvertible {
    case weakFairness(String)
    case strongFairness(String)
    /// Fairness for one concrete finite parameterization of an action.
    /// Algorithm lowering uses this form so each process receives its own
    /// PlusCal-equivalent fairness obligation.
    case weakFairnessActionCall(FormalActionCall)
    case strongFairnessActionCall(FormalActionCall)

    public var description: String {
        switch self {
        case .weakFairness(let a): return "WF(\(a))"
        case .strongFairness(let a): return "SF(\(a))"
        case .weakFairnessActionCall(let action): return "WF(\(action))"
        case .strongFairnessActionCall(let action): return "SF(\(action))"
        }
    }

    public func tlaForm(vars: String) -> String {
        switch self {
        case .weakFairness(let a): return "WF_\(vars)(\(a))"
        case .strongFairness(let a): return "SF_\(vars)(\(a))"
        case .weakFairnessActionCall(let action): return "WF_\(vars)(\(action))"
        case .strongFairnessActionCall(let action): return "SF_\(vars)(\(action))"
        }
    }

    internal var actionIdentity: String {
        switch self {
        case .weakFairness(let action), .strongFairness(let action): action
        case .weakFairnessActionCall(let action), .strongFairnessActionCall(let action): action.description
        }
    }

    internal var isStrong: Bool {
        switch self {
        case .strongFairness, .strongFairnessActionCall: true
        case .weakFairness, .weakFairnessActionCall: false
        }
    }
}
