public enum FairnessCondition: Hashable, Sendable, CustomStringConvertible {
    indirect case projected(FairnessCondition, StateExpr)
    case weakFairness(String)
    case strongFairness(String)
    case weakFairnessNext
    case strongFairnessNext
    /// Fairness for one concrete finite parameterization of an action.
    case weakFairnessActionCall(FormalActionCall)
    case strongFairnessActionCall(FormalActionCall)
    /// One obligation for each argument tuple in the action's immutable domains.
    case weakFairnessEachAction(String)
    case strongFairnessEachAction(String)
    /// One obligation over any invocation of the listed actions.
    case weakFairnessActionGroup([String])
    case strongFairnessActionGroup([String])
    /// One process-member obligation over the disjunction of its atomic steps.
    case weakFairnessEachActionGroup([String])
    case strongFairnessEachActionGroup([String])

    public var description: String {
        switch self {
        case .projected(let condition, let projection): return "\(condition) on \(projection)"
        case .weakFairness(let a): return "WF(\(a))"
        case .strongFairness(let a): return "SF(\(a))"
        case .weakFairnessNext: return "WF(Next)"
        case .strongFairnessNext: return "SF(Next)"
        case .weakFairnessActionCall(let action): return "WF(\(action))"
        case .strongFairnessActionCall(let action): return "SF(\(action))"
        case .weakFairnessEachAction(let action): return "Each(WF(\(action)))"
        case .strongFairnessEachAction(let action): return "Each(SF(\(action)))"
        case .weakFairnessActionGroup(let actions): return "WF(\(actions.joined(separator: " \\/ ")))"
        case .strongFairnessActionGroup(let actions): return "SF(\(actions.joined(separator: " \\/ ")))"
        case .weakFairnessEachActionGroup(let actions): return "Each(WF(\(actions.joined(separator: " \\/ "))))"
        case .strongFairnessEachActionGroup(let actions): return "Each(SF(\(actions.joined(separator: " \\/ "))))"
        }
    }

    internal var isStrong: Bool {
        switch self {
        case .projected(let condition, _): condition.isStrong
        case .strongFairness, .strongFairnessNext, .strongFairnessActionCall, .strongFairnessEachAction,
             .strongFairnessActionGroup, .strongFairnessEachActionGroup: true
        case .weakFairness, .weakFairnessNext, .weakFairnessActionCall, .weakFairnessEachAction,
             .weakFairnessActionGroup, .weakFairnessEachActionGroup: false
        }
    }
}
