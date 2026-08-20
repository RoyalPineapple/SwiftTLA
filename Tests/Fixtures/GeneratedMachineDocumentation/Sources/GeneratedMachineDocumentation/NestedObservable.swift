// Example ID: generated-machine-nested-observable

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CounterScreenModel {
    enum Process: String, FiniteDomainKey {
        case only

        static let formalDomain: [Process] = [.only]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "documentation.observable.process")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Step: String, PlusCalLabel {
        case advance
    }

    static var spec: TLASpec {
        #spec("CounterScreenModel") {
            Algorithm("CounterScreenModel") {
                let value = SharedVar(initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            }
        }
    }

    @TLAObservable
    final class Observable {}
}

@MainActor
func runObservable() async throws {
    let owner = try TLALiveMachineOwner.create(for: CounterScreenModel.self)
    let observable = try await CounterScreenModel.Observable(handle: owner.handle)
    observable.onAdvance = { before, after in
        assert(before.value == 0)
        assert(after.value == 1)
    }
    let result = await observable.execute(CounterScreenModel.Observable.ActionLabel.advance.toInvocation())
    guard case .committed = result else { return }
}
