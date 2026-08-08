/// Model checker built AS a TLASpec — composed with user spec, driven by SpecRuntime.
/// The checker lifecycle is a TLASpec. The BFS loop uses SpecRuntime to enumerate transitions.
public struct RuntimeChecker {
    public let checkerSpec: TLASpec
    public let composedSpec: TLASpec
    public let maxStates: Int

    public static func checkerSpec(maxStates: Int) -> TLASpec {
        let phase = Var<Int>("_phase")
        let explored = Var<Int>("_explored")
        let queued = Var<Int>("_queued")
        return TLASpec("RuntimeChecker") {
            Variable(phase, 0); Variable(explored, 0); Variable(queued, 1)
            Action("_Expand") {
                (phase == 0) && (explored < queued) && (explored < maxStates)
                    && explored.becomes(explored + 1) && queued.stays && phase.stays
            }
            Action("_Discover") {
                (phase == 0) && (explored < queued) && (explored < maxStates)
                    && explored.becomes(explored + 1) && queued.becomes(queued + 1)
                    && phase.stays
            }
            Action("_Complete") {
                (phase == 0) && ((explored >= queued) || (explored >= maxStates))
                    && phase.becomes(1)
            }
            Invariant("_PhaseValid") { phase >= 0 && phase <= 1 }
            Invariant("_ExploredOk") { explored <= maxStates }
        }
    }

    public init(userSpec: TLASpec, maxStates: Int = 100_000) {
        self.checkerSpec = Self.checkerSpec(maxStates: maxStates)
        self.composedSpec = checkerSpec.extending(userSpec)
        self.maxStates = maxStates
    }

    public func check() throws -> CheckResult {
        // Use ONLY the user spec for exploration. The checker spec is verified by @TLAModel.
        let runtime = SpecRuntime(spec: Self.userSpec(from: composedSpec))
        let fullRuntime = SpecRuntime(spec: composedSpec)
        let initialStates = runtime.initialStates()
        guard !initialStates.isEmpty else { return .error("No initial states") }

        var queue = initialStates
        var visited = Set<[String: TLAValue]>()
        var exploredCount = 0
        var head = 0

        while head < queue.count {
            guard exploredCount < maxStates else {
                return .depthExceeded(statesCount: exploredCount, limit: maxStates)
            }

            let current = queue[head]
            head += 1
            exploredCount += 1

            // Check user invariants using the full composed spec's invariants
            for inv in composedSpec.invariants {
                if inv.name.hasPrefix("_") { continue }
                let holds = try fullRuntime.check(inv.name, in: current)
                if !holds {
                    return .invariantViolated(invariant: inv.name, state: current, trace: [])
                }
            }

            let userActions = runtime.availableActions(in: current)
            for action in userActions {
                let result = try runtime.step(action, from: current)
                if case .ok(let next) = result {
                    if !visited.contains(next) {
                        visited.insert(next)
                        queue.append(next)
                    }
                }
            }
        }

        return .ok(statesCount: exploredCount)
    }

    /// Strip checker lifecycle variables from the composed spec to get the original user spec.
    private static func userSpec(from composed: TLASpec) -> TLASpec {
        TLASpec(name: composed.name,
                variables: composed.variables.filter { !$0.name.hasPrefix("_") },
                constants: composed.constants,
                actions: composed.actions.filter { !$0.name.hasPrefix("_") },
                invariants: composed.invariants.filter { !$0.name.hasPrefix("_") },
                temporalProperties: composed.temporalProperties,
                fairness: composed.fairness,
                assume: composed.assume,
                checkDeadlock: composed.checkDeadlock,
                definitions: composed.definitions,
                theorems: composed.theorems,
                extendsModules: composed.extendsModules,
                constraint: composed.constraint,
                recursiveDefs: composed.recursiveDefs,
                recursiveFuncs: composed.recursiveFuncs,
                symmetrySets: composed.symmetrySets)
    }
}
