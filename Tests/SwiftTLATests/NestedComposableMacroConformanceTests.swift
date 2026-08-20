import Foundation
import SwiftTLA
import SwiftParser
import SwiftSyntax
import Testing

private enum AvailabilityEvaluationFailure: Error {
    case unavailable
}

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
        let graph = try ModelChecker(spec: spec).exploreGraph()
        let runtime = try SpecRuntime(spec: spec)

        for (sourceID, source) in graph.states {
            let checked = (graph.transitions[sourceID] ?? []).compactMap { transition -> (TLAActionInvocation, [String: TLAValue])? in
                guard let successor = graph.states[transition.target] else { return nil }
                return (transition.label.invocation, successor)
            }
            let runtimeSuccessors = try runtime.availableInvocations(in: source).flatMap { invocation in
                try runtime.successors(invocation, from: source).map { (invocation, $0) }
            }

            #expect(multiset(runtimeSuccessors) == multiset(checked))
            #expect(!runtimeSuccessors.contains { $0.1 == ["value": .int(3)] })
        }
    }

    @Test("Nested model and adapters expose matching protocol-generic observations")
    @MainActor
    func nestedSurfacesShareCanonicalExecution() async throws {
        let invocation = TLAActionInvocation(name: "advance")
        var model = NestedComposedCounter()
        var observable = NestedComposedCounter.Observable()
        var actor = NestedComposedCounter.Actor()

        let modelResult = try await executeAndObserve(&model, invocation: invocation)
        let observableResult = try await executeAndObserve(&observable, invocation: invocation)
        let actorResult = try await executeAndObserve(&actor, invocation: invocation)

        #expect(modelResult.before == observableResult.before)
        #expect(modelResult.before == actorResult.before)
        #expect(modelResult.after == observableResult.after)
        #expect(modelResult.after == actorResult.after)
        #expect(modelResult.before.availableInvocations == [invocation])
        #expect(modelResult.after.availableInvocations == [invocation])
    }

    @Test("Three-parameter invocation identity survives canonical and nested adapter execution")
    @MainActor
    func threeParameterIdentityRemainsDistinctAcrossNestedSurfaces() async throws {
        let first = TLAActionInvocation(name: "board", arguments: [.int(1), .int(10), .int(100)])
        let selected = TLAActionInvocation(name: "board", arguments: [.int(2), .int(20), .int(200)])
        let runtime = EndToEndThreeParameterActionMachine.runtime
        let initial = try #require(runtime.initialStates().first)
        let available = try runtime.availableInvocations(in: initial)
        let observable = ThreeParameterActionMachine.Observable()
        let actor = ThreeParameterActionMachine.Actor()

        #expect(first != selected)
        #expect(Set(available).count == 8)
        #expect(available.contains(first))
        #expect(available.contains(selected))
        #expect(try runtime.apply(selected, to: initial)["floor"] == .int(222))
        #expect(try await observable.execute(selected).action == .board(person: 2, elevator: 20, direction: 200))
        #expect(try await actor.execute(selected).action == .board(person: 2, elevator: 20, direction: 200))
    }

    @Test("Availability evaluation failures retain invocation context")
    func availabilityEvaluationFailureReportsTheEvaluatedInvocation() throws {
        let count = Var<Int>("count")
        let invocation = TLAActionInvocation(name: "advance")
        let spec = TLASpec("UnavailableAvailability") {
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1) }
        }
        let runtime = try SpecRuntime(spec: spec) { _, _, _ in
            throw AvailabilityEvaluationFailure.unavailable
        }
        let state = runtime.initialStates()[0]

        do {
            _ = try runtime.availableInvocations(in: state)
            Issue.record("Expected availability evaluation to fail")
        } catch let error as SpecRuntime.RuntimeError {
            guard case .enumerationFailed(let requested, let evaluated, _) = error else {
                Issue.record("Expected enumerationFailed, got \(error)")
                return
            }
            #expect(requested == nil)
            #expect(evaluated == invocation)
        } catch {
            Issue.record("Expected runtime error, got \(error)")
        }
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
        requireSendable(NestedComposedCounter.Variables.self)
        requireSendable(NestedComposedCounter.Actor.Variables.self)
        requireSendable(NestedComposedCounter.Observable.Variables.self)
        requireSendable(NestedComposedCounter.ActionLabel.self)
        requireSendable(NestedComposedCounter.TransitionResult.self)
        requireSendable(GeneratedSymmetricRuntime.self)
        requireSendable(TwoCarElevatorMachine.Observable.self)
        requireSendable(TLAMachineObservation.self)

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

    @Test("Generated public declarations retain guarded state and typed transition boundaries")
    func generatedPublicSurfaceDoesNotEmitLegacyOrRawStateInterfaces() throws {
        let generatedSources = [
            "Sources/SwiftTLAPlugin/MacroExpander.swift",
            "Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift",
            "Sources/SwiftTLAPlugin/MacroExpander+Generation.swift",
            "Sources/SwiftTLAPlugin/MacroExpander+Adapters.swift"
        ]

        for path in generatedSources {
            let source = try String(contentsOf: packageRoot().appendingPathComponent(path))
            #expect(publicApplicationSurfaceViolations(inGeneratorSource: source).isEmpty)
        }

        let multilineRawMap = """
        public func snapshot(
        ) -> [String:
          TLAValue] { let engine: [String: TLAValue] = [:]; _ = engine; return [] }
        """
        let transitionEvidenceResult = """
        public struct
        TransitionEvidence: Sendable {}
        """
        let transitionEvidenceResultSignature = """
        public func execute() -> TransitionEvidence { fatalError() }
        """
        let safeSurface = """
        public func tlaSnapshot() -> TLAStateProjectionResult { .unavailable(.invalidKey(path: "state")) }
        public struct TransitionResult: Sendable {}
        """
        let safeInternalFormalEngine = """
        public func tlaSnapshot() -> TLAStateProjectionResult {
          let formal: [String: TLAValue] = [:]
          _ = formal
          return .unavailable(.invalidKey(path: "state"))
        }
        """

        #expect(publicApplicationSurfaceViolations(inEmittedSource: multilineRawMap) == ["raw state map"])
        #expect(publicApplicationSurfaceViolations(inEmittedSource: transitionEvidenceResult) == ["transition evidence"])
        #expect(publicApplicationSurfaceViolations(inEmittedSource: transitionEvidenceResultSignature) == ["transition evidence"])
        #expect(publicApplicationSurfaceViolations(inEmittedSource: safeSurface).isEmpty)
        #expect(publicApplicationSurfaceViolations(inEmittedSource: safeInternalFormalEngine).isEmpty)
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
        #expect(result.output.contains("TLAStateProjectionResult"))
        #expect(result.output.contains("TransitionEvidence"))
    }

    @Test("External nested actor cannot expose raw generated state")
    func nestedActorRawStateAndLegacyEvidenceDoNotCompileExternally() throws {
        try assertExternalSurfaceIsForbidden(
            fixture: "InvalidNestedActorRawSurface",
            typeName: "NestedActorSurface.Actor",
            stateDiagnostic: "cannot convert value of type 'TLAStateProjectionResult'"
        )
    }

    @Test("External nested observable cannot expose raw generated state")
    func nestedObservableRawStateAndLegacyEvidenceDoNotCompileExternally() throws {
        try assertExternalSurfaceIsForbidden(
            fixture: "InvalidNestedObservableRawSurface",
            typeName: "NestedObservableSurface.Observable",
            stateDiagnostic: "cannot convert value of type 'TLAStateProjectionResult'"
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

    private func executeAndObserve<Machine: TLAMachineExecuting>(
        _ machine: inout Machine,
        invocation: TLAActionInvocation
    ) async throws -> (before: TLAMachineObservation, after: TLAMachineObservation) {
        let before = await machine.machineObservation()
        _ = try await machine.execute(invocation)
        return (before, await machine.machineObservation())
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}

    private func publicApplicationSurfaceViolations(inGeneratorSource source: String) -> [String] {
        Array(Set(MacroEmissionStringCollector.fragments(in: source)
            .flatMap(publicApplicationSurfaceViolations(inEmittedSource:))))
            .sorted()
    }

    private func publicApplicationSurfaceViolations(inEmittedSource source: String) -> [String] {
        let inspector = PublicGeneratedSurfaceInspector(viewMode: .sourceAccurate)
        inspector.walk(Parser.parse(source: source))
        return inspector.violations.sorted()
    }

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
        _ transitions: [(TLAActionInvocation, [String: TLAValue])]
    ) -> [String: Int] {
        Dictionary(
            transitions.map { ("\($0.0.description) -> \($0.1)", 1) },
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


private final class MacroEmissionStringCollector: SyntaxVisitor {
    private(set) var fragments: [String] = []

    static func fragments(in source: String) -> [String] {
        let collector = MacroEmissionStringCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        return collector.fragments
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        let fragment = node.segments.compactMap { segment -> String? in
            segment.as(StringSegmentSyntax.self)?.content.text
        }.joined()
        if fragment.contains("public") {
            fragments.append(fragment)
        }
        return .skipChildren
    }
}

private final class PublicGeneratedSurfaceInspector: SyntaxVisitor {
    private(set) var violations: Set<String> = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        inspect(modifiers: node.modifiers, signature: node.signature.description)
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPublic(node.modifiers) else { return .skipChildren }
        for binding in node.bindings {
            inspect(type: binding.typeAnnotation?.type.description ?? "")
        }
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        inspect(modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        inspect(modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        inspect(modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        inspect(modifiers: node.modifiers, name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        inspect(modifiers: node.modifiers, name: node.name.text)
        if isPublic(node.modifiers) {
            inspect(type: node.initializer.value.description)
        }
        return .skipChildren
    }

    private func inspect(modifiers: DeclModifierListSyntax, signature: String) {
        guard isPublic(modifiers) else { return }
        inspect(type: signature)
    }

    private func inspect(modifiers: DeclModifierListSyntax, name: String) {
        guard isPublic(modifiers) else { return }
        if name == "TransitionEvidence" {
            violations.insert("transition evidence")
        }
    }

    private func inspect(type: String) {
        let normalized = type.filter { !$0.isWhitespace }
        if normalized.contains("[String:TLAValue]") {
            violations.insert("raw state map")
        }
        if normalized.contains("TransitionEvidence") {
            violations.insert("transition evidence")
        }
    }

    private func isPublic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.public) }
    }
}
