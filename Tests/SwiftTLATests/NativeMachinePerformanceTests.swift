import Testing
@testable import SwiftTLA
import SwiftTLAMacros
#if canImport(Darwin)
import Darwin
#endif

@TLAModel
private struct MeasuredExecutionCounter {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("MeasuredExecutionCounter") {
            Algorithm("MeasuredExecutionCounter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                While(Step.advance, true) {
                    Assign(count, to: count + 1)
                }
            })
        }
    }
}

@Suite struct NativeMachinePerformanceTests {
    @Test("native construction and execution report bounded comparative measurements")
    func constructionAndExecutionMeasurements() throws {
        let constructionCount = 16
        let operationCount = 128
        let compilation = try MeasuredExecutionCounter.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let action = try #require(compilation.layout.actions.first { $0.declaration.name == "advance" }?.id)
        let count = try #require(compilation.layout.variables.first { $0.declaration.name == "count" }?.id)
        let initial = try #require(try runtime.initialStates().first)

        // Warm each path before measuring. These are diagnostics, never admission
        // thresholds: host load, build configuration and optimizer affect timings.
        for _ in 0..<3 {
            var native = try MeasuredExecutionCounter.makeMachine()
            _ = try native.enabledActions()
            _ = try native.send(.advance)
            let warmCompilation = try MeasuredExecutionCounter.spec.compile()
            let warmRuntime = CompiledRuntime(compilation: warmCompilation)
            let warmInitial = try #require(try warmRuntime.initialStates().first)
            _ = try warmRuntime.successors(from: warmInitial)
            _ = try runtime.initialStates()
            _ = try runtime.successors(for: action, from: initial)
        }

        // Reserve only the outer retention buffers before timing. Every constructed
        // machine/runtime/state stays alive through the after-allocation snapshot,
        // then is exercised outside the timed region by a non-inlined consumer.
        do {
            var machines: [MeasuredExecutionCounter] = []
            machines.reserveCapacity(constructionCount)
            let completed = try measure("generated makeMachine + retain", iterations: constructionCount) {
                machines.append(try MeasuredExecutionCounter.makeMachine())
                return 1
            }
            #expect(completed == constructionCount)
            #expect(try consumeMachines(machines) == constructionCount)
            withExtendedLifetime(machines) {}
        }
        do {
            var constructions: [(runtime: CompiledRuntime, states: [CompiledState])] = []
            constructions.reserveCapacity(constructionCount)
            let completed = try measure("formal compile + runtime + initialStates + retain", iterations: constructionCount) {
                let compiled = try MeasuredExecutionCounter.spec.compile()
                let constructedRuntime = CompiledRuntime(compilation: compiled)
                constructions.append((constructedRuntime, try constructedRuntime.initialStates()))
                return 1
            }
            #expect(completed == constructionCount)
            #expect(try consumeFormalConstructions(constructions) == constructionCount)
            withExtendedLifetime(constructions) {}
        }
        do {
            var constructions: [(runtime: CompiledRuntime, states: [CompiledState])] = []
            constructions.reserveCapacity(constructionCount)
            let completed = try measure("formal precompiled initialStates + retain", iterations: constructionCount) {
                constructions.append((runtime, try runtime.initialStates()))
                return 1
            }
            #expect(completed == constructionCount)
            #expect(try consumeFormalConstructions(constructions) == constructionCount)
            withExtendedLifetime(constructions) {}
        }

        var native = try MeasuredExecutionCounter.makeMachine()
        let nativeTransitions = try measure("generated send", iterations: operationCount) {
            try native.send(.advance).after.count
        }
        var formal = initial
        let formalTransitions = try measure("formal precompiled successors + selection", iterations: operationCount) {
            let successors = try runtime.successors(for: action, from: formal)
            guard successors.count == 1, let successor = successors.first else {
                Issue.record("The measured action must have exactly one successor")
                return -1
            }
            formal = successor.state
            guard case .integer(let value) = try formal.value(for: count) else {
                Issue.record("The measured counter must remain an integer")
                return -1
            }
            return value
        }
        #expect(nativeTransitions == operationCount * (operationCount + 1) / 2)
        #expect(formalTransitions == nativeTransitions)
        #expect(native.state.count == operationCount)
        #expect(try formal.value(for: count) == .integer(operationCount))

        let nativeEnabled = try measure("generated enabledActions", iterations: operationCount) {
            try native.enabledActions().count
        }
        let formalEnabled = try measure("formal precompiled successor enumeration", iterations: operationCount) {
            try runtime.successors(from: formal).count
        }
        #expect(nativeEnabled == operationCount)
        #expect(formalEnabled == nativeEnabled)
    }

    @inline(never)
    private func consumeMachines(_ machines: [MeasuredExecutionCounter]) throws -> Int {
        try machines.reduce(0) { checksum, stored in
            var machine = stored
            #expect(machine.state.count == 0)
            return checksum + (try machine.send(.advance).after.count)
        }
    }

    @inline(never)
    private func consumeFormalConstructions(
        _ constructions: [(runtime: CompiledRuntime, states: [CompiledState])]
    ) throws -> Int {
        try constructions.reduce(0) { checksum, construction in
            let initial = try #require(construction.states.count == 1 ? construction.states.first : nil)
            let layout = construction.runtime.compilation.layout
            let action = try #require(layout.actions.first { $0.declaration.name == "advance" }?.id)
            let count = try #require(layout.variables.first { $0.declaration.name == "count" }?.id)
            #expect(try initial.value(for: count) == .integer(0))
            let successors = try construction.runtime.successors(for: action, from: initial)
            let successor = try #require(successors.count == 1 ? successors.first : nil)
            guard case .integer(let value) = try successor.state.value(for: count) else {
                Issue.record("Constructed formal counters must have integer state")
                return -1
            }
            return checksum + value
        }
    }

    @inline(never)
    private func measure(_ label: String, iterations: Int, operation: () throws -> Int) throws -> Int {
        let clock = ContinuousClock()
        #if canImport(Darwin)
        var before = malloc_statistics_t()
        malloc_zone_statistics(malloc_default_zone(), &before)
        #endif
        let start = clock.now
        var checksum = 0
        for _ in 0..<iterations { checksum += try operation() }
        let elapsed = start.duration(to: clock.now)
        #if canImport(Darwin)
        var after = malloc_statistics_t()
        malloc_zone_statistics(malloc_default_zone(), &after)
        #endif
        print("Machine measurement: \(label); operations=\(iterations); elapsed=\(elapsed); perOperation=\(elapsed / iterations); checksum=\(checksum)")
        #if canImport(Darwin)
        print("Default malloc zone live snapshots for \(label): blocks=\(before.blocks_in_use)->\(after.blocks_in_use), bytes=\(before.size_in_use)->\(after.size_in_use). These are process-wide retained allocations, not allocation totals or peaks; other tests and allocator caching may affect them.")
        #endif
        return checksum
    }
}
