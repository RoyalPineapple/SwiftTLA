// Example ID: generated-machine-nested-observable

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CounterScreenModel {
    static var spec: TLASpec {
        TLASpec("CounterScreenModel") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
    }

    @TLAObservable
    final class Observable {}
}

@MainActor
func runObservable() async throws {
    let observable = CounterScreenModel.Observable()
    observable.onAdvance = { before, after in
        assert(before.value == 0)
        assert(after.value == 1)
    }
    _ = try await observable.execute(.init(name: "advance"))
}
