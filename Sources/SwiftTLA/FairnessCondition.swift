public enum FairnessCondition: Hashable, Sendable, CustomStringConvertible {
    case weakFairness(String)
    case strongFairness(String)
    case weakFairnessNext
    case strongFairnessNext
    /// Fairness for one concrete finite parameterization of an action.
    /// Algorithm lowering uses this form so each process receives its own
    /// PlusCal-equivalent fairness obligation.
    case weakFairnessActionCall(FormalActionCall)
    case strongFairnessActionCall(FormalActionCall)

    public var description: String {
        switch self {
        case .weakFairness(let a): return "WF(\(a))"
        case .strongFairness(let a): return "SF(\(a))"
        case .weakFairnessNext: return "WF(Next)"
        case .strongFairnessNext: return "SF(Next)"
        case .weakFairnessActionCall(let action): return "WF(\(action))"
        case .strongFairnessActionCall(let action): return "SF(\(action))"
        }
    }

    internal var isStrong: Bool {
        switch self {
        case .strongFairness, .strongFairnessNext, .strongFairnessActionCall: true
        case .weakFairness, .weakFairnessNext, .weakFairnessActionCall: false
        }
    }
}
