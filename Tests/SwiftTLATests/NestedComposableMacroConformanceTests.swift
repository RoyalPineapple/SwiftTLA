import Foundation
@testable import SwiftTLA
import Testing

@Suite(.serialized)
struct NestedComposableMacroConformanceTests {
    @Test("Parameterized execution retains every choice while exploration applies constraints")
    func parameterizedChoicesRetainRawAndConstrainedEdges() throws {
        let graph = try ReachabilityGraph(
            initialMachines: ConstrainedParameterizedChoice.initialMachines(), maximumStates: 4)
        #expect(Set(graph.transitions.keys.map(\.state.value)) == [0, 1, 2])
        #expect(graph.safetyViolations.isEmpty)

        var pending = try ConstrainedParameterizedChoice.initialMachines()
        var visited: Set<ConstrainedParameterizedChoice.Snapshot> = []
        while let machine = pending.popLast() {
            guard visited.insert(machine.snapshot).inserted else { continue }
            let raw = try machine.successors()
            #expect(raw.count == 6)
            let rawEdges = raw.map { ($0.action, $0.machine.state.value) }
            for branch in [1, 2] {
                for selected in 1...3 {
                    #expect(rawEdges.contains { $0.0 == .choose(branch: branch) && $0.1 == selected })
                }
            }
            #expect(rawEdges.filter { $0.1 == 3 }.count == 2)

            let retained = rawEdges.filter { $0.1 <= 2 }
            let checked = try #require(graph.transitions[machine.snapshot])
            #expect(checked.count == 4)
            #expect(retained.count == checked.count)
            for edge in retained {
                #expect(checked.contains { $0.action == edge.0 && $0.target.state.value == edge.1 })
            }
            pending.append(contentsOf: raw.filter { $0.machine.state.value <= 2 }.map(\.machine))
        }
        #expect(visited.count == 3)
    }

    @Test("Nested machine and actor expose matching typed execution")
    func nestedMachineAndActorShareExecution() async throws {
        var machine = try NestedComposedCounter.makeMachine()
        let actor = try NestedComposedCounter.Actor()

        let machineBefore = machine.state
        _ = try machine.send(.advance)
        let machineAfter = machine.state
        _ = try await actor.send(.advance)
        #expect(machineBefore.count == 0)
        #expect(machineAfter.count == 1)
        #expect(try machine.enabledActions() == [.advance])
        #expect((await actor.state).count == 1)
    }

    @Test("Three-parameter action identity survives value and actor execution")
    func threeParameterIdentityRemainsDistinctAcrossExecutionSurfaces() async throws {
        let first = EndToEndThreeParameterActionMachine.Action.transfer(source: 1, destination: 10, amount: 100)
        let selected = EndToEndThreeParameterActionMachine.Action.transfer(source: 2, destination: 20, amount: 200)
        let available = try EndToEndThreeParameterActionMachine.makeMachine().enabledActions()
        let actor = try ThreeParameterActionMachine.Actor()

        #expect(first != selected)
        #expect(Set(available).count == 8)
        #expect(available.contains(first))
        #expect(available.contains(selected))
        var machine = try EndToEndThreeParameterActionMachine.makeMachine()
        let transition = try machine.send(.transfer(source: 2, destination: 20, amount: 200))
        #expect(transition.after.value == 222)
        let acted = try await actor.send(.transfer(source: 2, destination: 20, amount: 200))
        #expect(acted.action == .transfer(source: 2, destination: 20, amount: 200))
    }

    @Test("Generated application surfaces are structurally Sendable without unchecked conformance")
    @MainActor
    func generatedApplicationSurfacesAreSendable() throws {
        requireSendable(NestedComposedCounter.self)
        requireSendable(NestedComposedCounter.Actor.self)
        requireSendable(NestedComposedCounter.Action.self)
        requireSendable(NestedComposedCounter.Transition.self)
        requireSendable(ConfiguredLocalFamilyModel.self)

        for ownedDirectory in ["Sources", "Tests"] {
            let directory = packageRoot().appendingPathComponent(ownedDirectory)
            let sourceFiles = try #require(FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            ))
            for case let sourceFile as URL in sourceFiles
                where sourceFile.pathExtension == "swift" && !sourceFile.pathComponents.contains(".build") {
                let source = try String(contentsOf: sourceFile)
                let uncheckedAttribute = "@un" + "checked"
                #expect(!source.contains(uncheckedAttribute))
            }
        }
    }

    @Test("@TLAModel rejects arbitrary instance state")
    func modelWithInstanceStoredStateDoesNotTypeCheck() throws {
        let build = try buildExternalConsumer("InvalidModelStoredState")

        #expect(build.status != 0)
        #expect(build.output.contains("@TLAModel models cannot declare instance stored properties"))
    }

    @Test("@TLAModel rejects dynamic formal module names")
    func modelWithDynamicFormalModuleNameDoesNotTypeCheck() throws {
        let build = try buildExternalConsumer("InvalidDynamicModelName")

        #expect(build.status != 0)
        #expect(build.output.contains("requires a literal module name"))
    }

    @Test("@TLAModel requires a value-semantic struct host")
    func modelMacroRejectsReferenceAndActorHosts() throws {
        for fixture in ["InvalidModelClassHost", "InvalidModelActorHost"] {
            let build = try buildExternalConsumer(fixture)

            #expect(build.status != 0)
            #expect(build.output.contains("@TLAModel requires a struct"))
        }
    }

    @Test("@TLAModel rejects observer-backed instance state")
    func modelWithObservedInstanceStateDoesNotTypeCheck() throws {
        let build = try buildExternalConsumer("InvalidObservedModelState")

        #expect(build.status != 0)
        #expect(build.output.contains("@TLAModel models cannot declare instance stored properties"))
    }

    @Test("External clients compile against generated typed application surfaces")
    func generatedTypedSurfaceCompilesExternally() throws {
        let execution = try runExternalConsumer("GeneratedTypedSurface")

        #expect(execution.status == 0)
    }

    @Test("generated storage is private to generated declarations")
    func generatedStorageIsPrivate() throws {
        let build = try buildExternalConsumer("InvalidGeneratedStorageAccess")

        #expect(build.status != 0)
        #expect(build.output.contains("'_execution' is inaccessible due to 'private' protection level"))
        #expect(build.output.contains("'machine' is inaccessible due to 'private' protection level"))
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
