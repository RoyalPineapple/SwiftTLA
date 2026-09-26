import Testing
import SwiftTLA

struct NativePropertyIdentityTests {
    @Test("models without properties expose an empty typed identity set and formal projection")
    func hasNoSyntheticProperty() throws {
        #expect(NativePropertylessModel.Property.allCases.isEmpty)
        #expect(NativePropertylessModel.formalPropertyNames.isEmpty)
        let graph = try ReachabilityGraph(initialMachines: NativePropertylessModel.initialMachines(), maximumStates: 2)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.reachabilityResults.isEmpty)
        #expect(graph.temporalResults.isEmpty)
        #expect(graph.refinementFailures.isEmpty)
        #expect(try NativePropertylessModel.render().checkNames.isEmpty)
    }

    @Test("native checks retain model-owned properties without a validation scenario")
    func retainsPropertyIdentity() throws {
        typealias Model = NativePropertyIdentityModel
        let graph = try ReachabilityGraph(initialMachines: Model.initialMachines(), maximumStates: 2)
        #expect(Set(Model.Property.allCases) == [.Safe, .AtOne, .NeverOne])
        #expect(Model.reachabilityProperties == [.AtOne])
        let result: ReachabilityOutcome<Model.Snapshot> = try #require(graph.reachabilityResults[.AtOne])
        guard case .reached(let state) = result else {
            Issue.record("Expected the typed reachability witness")
            return
        }
        #expect(state.state.count == 1)
        #expect(graph.safetyViolations[state] == [.invariant(.Safe)])
        #expect(graph.temporalResults[.NeverOne]?.status == .violated)
        #expect(graph.transitions.count == 2)
        #expect(try graph.trace(to: state).map(\.action) == [nil, .advance])
        #expect(Set(Model.Property.allCases.map { Model.formalPropertyNames[$0]! }) == (try Model.render()).checkNames)
    }

    @Test("native property keys reject strings, missing cases, and foreign model identities")
    func rejectsForeignPropertyKeys() throws {
        let build = try buildExternalConsumer("InvalidModelProperty")
        #expect(build.status != 0)
        let errors = build.output.split(separator: "\n").filter { $0.contains(": error:") }
        for line in [24, 25, 26] {
            #expect(errors.contains { $0.contains("InvalidModelProperty.swift:\(line):") },
                "Missing property identity rejection: \(errors.joined(separator: "\n"))")
        }
    }
}
