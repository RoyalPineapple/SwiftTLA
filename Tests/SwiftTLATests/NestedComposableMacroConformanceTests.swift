import Foundation
@testable import SwiftTLA
import Testing

@Suite(.serialized)
struct NestedComposableMacroConformanceTests {
    @Test("Runtime successor relation preserves parameterized nondeterministic checked edges")
    func runtimeSuccessorsPreserveEveryCheckedParameterizedSuccessor() throws {
        let value = Var<Int>("value")
        let spec = TLASpec("ConstrainedParameterizedChoice") {
            Variable(value, 0)
            Action("choose", parameters: [ActionParameter("branch", values: [1, 2])]) {
                choose(value, from: StateExpr.set([1, 2, 3]))
            }
            Constraint(value <= 2)
        }
        let compilation = try spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)
        ).explore()
        let graph = exploration.graph

        for sourceID in graph.states.keys {
            let checked = try (graph.transitions[sourceID] ?? []).compactMap { transition -> (action: String, arguments: [TLAValue], state: TLAStateProjection)? in
                guard let successor = graph.states[transition.target] else { return nil }
                return (
                    transition.label.action,
                    try transition.label.formalArguments(using: compilation.layout),
                    successor
                )
            }
            let state = try #require(exploration.compiledStates[sourceID])
            let runtimeSuccessors = try CompiledRuntime(compilation: compilation)
                .successors(from: state)
                .map { successor in
                    (
                        action: compilation.layout.actions[successor.action.ordinal].declaration.name,
                        arguments: try successor.arguments.map { try $0.rendered(using: compilation.layout) },
                        state: try successor.state.projection(using: compilation.layout)
                    )
                }

            #expect(multiset(runtimeSuccessors) == multiset(checked))
            let value = try #require(TLAStateProjection.Token(validating: "value"))
            #expect(runtimeSuccessors.contains { $0.state.value(for: value) == .int(3) } == false)
        }
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
        requireSendable(GeneratedSymmetricMachine.self)

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
        #expect(build.output.contains("'_storage' is inaccessible due to 'private' protection level"))
        #expect(build.output.contains("'machine' is inaccessible due to 'private' protection level"))
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}

    private func multiset(
        _ transitions: [(action: String, arguments: [TLAValue], state: TLAStateProjection)]
    ) -> [String: Int] {
        Dictionary(
            transitions.map { ("\($0.action):\($0.arguments) -> \($0.state)", 1) },
            uniquingKeysWith: +
        )
    }

}
