import Testing
import SwiftTLA
import SwiftTLAMacros
import UpstreamParity

struct NativeGraphExportTests {
    @Test("native graph export preserves safety and temporal failure categories")
    func retainsNativeFailures() throws {
        for initial in try FailingExportModel.initialMachines() {
            let native = try ReachabilityGraph(initialMachines: [initial], maximumStates: 3)
            let exported = try SwiftGraphExporter().export(native)
            #expect(!exported.isPassEligible)
            #expect(try exported.graph == CanonicalGraph(native))
            if initial.state.value == 0 {
                #expect(exported.outcome == .temporalViolation(property: "ReachesThree", reason: .violatingFairLasso))
                #expect(exported.graph.states.count == 1)
            } else {
                #expect(exported.outcome == .invariantViolation("BelowTwo"))
                #expect(exported.graph.states.count == 2)
                let trace = try #require(exported.trace)
                #expect(trace.steps.map(\.action) == ["Init", "advance"])
                let values = trace.steps.map { exported.graph.states[$0.state]?.bindings["value"] }
                #expect(values == [.integer(1), .integer(2)])
                let namedCase = try fixtureCase(testReferencePin(), renderedActions: [
                    RenderedAction(sourceName: "advance", arguments: [], renderedName: "ConcreteAdvance")
                ])
                let named = try SwiftGraphExporter().export(native, for: namedCase)
                #expect(named.outcome == exported.outcome)
                #expect(named.trace?.steps.map(\.action) == ["Init", "ConcreteAdvance"])
                #expect(Set(named.graph.edgeOccurrences.keys.map(\.action)) == ["ConcreteAdvance"])
            }
        }
    }
}

@TLAModel
private struct FailingExportModel {
    static var spec: TLASpec {
        #spec("FailingExport") { scope in
            let value = scope.sharedVar("value", in: 0...1)
            SwiftTLA.Action("advance") { value == 1 && value.becomes(2) }
            Invariant("BelowTwo") { value < 2 }
            Eventually("ReachesThree", value == 3)
        }
    }
}
