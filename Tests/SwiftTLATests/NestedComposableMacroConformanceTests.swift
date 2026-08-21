import Foundation
import SwiftTLA
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
        let graph = try ModelChecker(compilation: try spec.compile()).exploreGraph()
        let compilation = try spec.compile()

        for (sourceID, source) in graph.states {
            let checked = (graph.transitions[sourceID] ?? []).compactMap { transition -> (action: String, arguments: [TLAValue], state: TLAStateProjection)? in
                guard let successor = graph.states[transition.target] else { return nil }
                return (transition.label.action, transition.label.arguments, successor)
            }
            let state = try CompiledState(projection: source, compilation: compilation)
            let runtimeSuccessors = try CompiledRuntime(compilation: compilation)
                .successors(from: state)
                .map { successor in
                    (
                        action: compilation.layout.actions[successor.action.ordinal].declaration.name,
                        arguments: successor.arguments,
                        state: try successor.state.projection(using: compilation.layout)
                    )
                }

            #expect(multiset(runtimeSuccessors) == multiset(checked))
            let value = try #require(TLAStateProjection.Token(validating: "value"))
            #expect(runtimeSuccessors.contains { $0.state.value(for: value) == .int(3) } == false)
        }
    }

    @Test("Nested model and adapters expose matching typed observations")
    @MainActor
    func nestedSurfacesShareCanonicalExecution() async throws {
        var model = try NestedComposedCounter.makeMachine()
        let live = try NestedComposedCounter.makeLive()
        let observable = try await NestedComposedCounter.Observable(live: live)
        let actor = NestedComposedCounter.Actor(live: live)

        let modelBefore = try await model.machineObservation()
        _ = try model.apply(.advance)
        let modelAfter = try await model.machineObservation()
        _ = try await observable.apply(.advance)
        _ = try await actor.apply(.advance)
        #expect(modelBefore.state.count == 0)
        #expect(modelAfter.state.count == 1)
        #expect(modelBefore.availableActions == [.advance])
        #expect(modelAfter.availableActions == [.advance])
        #expect(observable.state.count == 1)
        #expect(await actor.state.count == 1)
    }

    @Test("Three-parameter invocation identity survives canonical and nested adapter execution")
    @MainActor
    func threeParameterIdentityRemainsDistinctAcrossNestedSurfaces() async throws {
        let first = EndToEndThreeParameterActionMachine.ActionLabel.board(person: 1, elevator: 10, direction: 100)
        let selected = EndToEndThreeParameterActionMachine.ActionLabel.board(person: 2, elevator: 20, direction: 200)
        let available = try EndToEndThreeParameterActionMachine.makeMachine().availableActions()
        let live = try ThreeParameterActionMachine.makeLive()
        let observable = try await ThreeParameterActionMachine.Observable(live: live)
        let actor = ThreeParameterActionMachine.Actor(live: live)

        #expect(first != selected)
        #expect(Set(available).count == 8)
        #expect(available.contains(first))
        #expect(available.contains(selected))
        var machine = try EndToEndThreeParameterActionMachine.makeMachine()
        let result = try machine.apply(.board(person: 2, elevator: 20, direction: 200))
        #expect(result.after.floor == 222)
        #expect((try await observable.apply(.board(person: 2, elevator: 20, direction: 200))).action == .board(person: 2, elevator: 20, direction: 200))
        #expect((try await actor.apply(.board(person: 2, elevator: 20, direction: 200)).action) == .board(person: 2, elevator: 20, direction: 200))
    }

    @Test("Invalid nested macro composition emits enclosure diagnostics")
    func invalidNestedMacroCompositionDoesNotTypeCheck() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidNestedMacroComposition")
        let result = try runSwift(["build", "--package-path", fixture.path])

        #expect(result.status != 0)
        #expect(result.output.contains("@TLAActor and @TLAObservable require an enclosing @TLAModel"))
        #expect(result.output.contains("Adapter must be enclosed by exactly one @TLAModel"))
        #expect(result.output.contains("Nested adapters require an enclosing @TLAModel struct"))
    }

    @Test("Generated macro surfaces are structurally Sendable without unchecked conformance")
    @MainActor
    func generatedMacroSurfacesAreSendable() throws {
        requireSendable(NestedComposedCounter.self)
        requireSendable(NestedComposedCounter.Actor.self)
        requireSendable(NestedComposedCounter.Observable.self)
        requireSendable(NestedComposedCounter.ActionLabel.self)
        requireSendable(NestedComposedCounter.TransitionResult.self)
        requireSendable(GeneratedSymmetricRuntime.self)
        requireSendable(TwoCarElevatorMachine.Observable.self)

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

    @Test("Model macro rejects arbitrary instance state")
    func modelWithInstanceStoredStateDoesNotTypeCheck() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidModelStoredState")
        let result = try runSwift(["build", "--package-path", fixture.path])

        #expect(result.status != 0)
        #expect(result.output.contains("@TLAModel models cannot declare instance stored properties"))
    }

    @Test("Model macro rejects dynamic formal module names")
    func modelWithDynamicFormalModuleNameDoesNotTypeCheck() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidDynamicModelName")
        let result = try runSwift(["build", "--package-path", fixture.path])

        #expect(result.status != 0)
        #expect(result.output.contains("must be a string literal; dynamic names cannot form a stable compilation identity"))
    }

    @Test("Model macro rejects observer-backed instance state")
    func modelWithObservedInstanceStateDoesNotTypeCheck() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidObservedModelState")
        let result = try runSwift(["build", "--package-path", fixture.path])

        #expect(result.status != 0)
        #expect(result.output.contains("@TLAModel models cannot declare instance stored properties"))
    }

    @Test("Model-owned observable executes typed transitions under strict concurrency")
    func modelOwnedObservableExecutesAsSendable() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/StandaloneObservableSendable")
        let result = try runSwift(["run", "--package-path", fixture.path])

        #expect(result.status == 0)
    }

    @Test("External clients compile against generated typed application surfaces")
    func generatedTypedSurfaceCompilesExternally() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/GeneratedTypedSurface")
        let result = try runSwift(["run", "--package-path", fixture.path])

        #expect(result.status == 0)
    }

    @Test("External clients cannot use raw state maps or transition evidence")
    func generatedRawStateAndTransitionEvidenceDoNotCompileExternally() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidGeneratedRawSurface")
        let result = try runSwift(["build", "--package-path", fixture.path])

        #expect(result.status != 0)
        #expect(result.output.contains("has no member 'tlaSnapshot'"))
        #expect(result.output.contains("TransitionEvidence"))
    }

    @Test("External nested actor cannot expose raw generated state")
    func nestedActorRawStateAndTransitionEvidenceDoNotCompileExternally() throws {
        try assertExternalSurfaceIsForbidden(
            fixture: "InvalidNestedActorRawSurface",
            typeName: "NestedActorSurface.Actor",
            stateDiagnostic: "has no member 'tlaSnapshot'"
        )
    }

    @Test("External nested observable cannot expose raw generated state")
    func nestedObservableRawStateAndTransitionEvidenceDoNotCompileExternally() throws {
        try assertExternalSurfaceIsForbidden(
            fixture: "InvalidNestedObservableRawSurface",
            typeName: "NestedObservableSurface.Observable",
            stateDiagnostic: "has no member 'tlaSnapshot'"
        )
    }

    @Test("Standalone actor declaration is rejected")
    func standaloneActorDeclarationDoesNotCompileExternally() throws {
        try assertExternalSurfaceIsForbidden(
            fixture: "InvalidStandaloneActorRawSurface",
            typeName: "StandaloneActorSurface",
            stateDiagnostic: "@TLAActor and @TLAObservable require an enclosing @TLAModel",
            requiresGeneratedSurfaceRejection: false
        )
    }

    @Test("Standalone observable declaration is rejected")
    func standaloneObservableDeclarationDoesNotCompileExternally() throws {
        try assertExternalSurfaceIsForbidden(
            fixture: "InvalidStandaloneObservableRawSurface",
            typeName: "StandaloneObservableSurface",
            stateDiagnostic: "@TLAActor and @TLAObservable require an enclosing @TLAModel",
            requiresGeneratedSurfaceRejection: false
        )
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}

    private func assertExternalSurfaceIsForbidden(
        fixture: String,
        typeName: String,
        stateDiagnostic: String,
        requiresGeneratedSurfaceRejection: Bool = true
    ) throws {
        let package = packageRoot().appendingPathComponent("Tests/Fixtures/\(fixture)")
        let result = try runSwift(["build", "--package-path", package.path])

        #expect(result.status != 0)
        #expect(result.output.contains(stateDiagnostic))
        if requiresGeneratedSurfaceRejection {
            #expect(result.output.contains("\(typeName).TransitionEvidence"))
        }
    }

    private func multiset(
        _ transitions: [(action: String, arguments: [TLAValue], state: TLAStateProjection)]
    ) -> [String: Int] {
        Dictionary(
            transitions.map { ("\($0.action):\($0.arguments) -> \($0.state)", 1) },
            uniquingKeysWith: +
        )
    }

    private func runSwift(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftTLA-invalid-nested-macro-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift"] + arguments + ["--scratch-path", scratch.path]
        let outputURL = scratch.appendingPathComponent("output.log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        try output.synchronize()
        let outputData = try Data(contentsOf: outputURL)

        return (
            process.terminationStatus,
            String(data: outputData, encoding: .utf8) ?? ""
        )
    }
}
