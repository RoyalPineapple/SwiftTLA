import Observation

@Observable
public final class TLAObservable: @unchecked Sendable {
    public private(set) var state: [String: TLAValue]
    public private(set) var history: [String]
    public private(set) var availableActions: [String]
    private var runtime: TLARuntime

    public init(spec: TLASpec) {
        let r = TLARuntime(spec: spec)
        self.runtime = r
        self.state = r.state
        self.history = r.history
        self.availableActions = r.availableActions
    }

    public func apply(_ action: String) {
        runtime.apply(action)
        state = runtime.state
        history = runtime.history
        availableActions = runtime.availableActions
    }

    public func reset() {
        runtime.reset()
        state = runtime.state
        history = runtime.history
        availableActions = runtime.availableActions
    }
}
