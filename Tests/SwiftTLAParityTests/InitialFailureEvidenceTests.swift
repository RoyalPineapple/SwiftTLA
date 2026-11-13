import Foundation
import Testing
import SwiftTLA
@testable import SwiftTLAPlugin
@testable import UpstreamParity

@Suite("Selected initial failure evidence")
struct InitialFailureEvidenceTests {
    @Test("A failure-only initializer retains native and actual TLA output for a proof without a graph")
    func preparesSelectedFailureProof() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swifttla-initial-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sha = String(repeating: "a", count: 40)
        let compilation = try CheckedAdditionPrefixInitialModel.spec.compile()
        let inputs = try CompiledTypeInputs(compilation: compilation,
            types: CompiledTypeContext(enums: .init(), formalNames: [:])) { _ in .int }
        let program = try CompiledProgram(inputs: inputs)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "CheckedAdditionPrefixInitialModel", program: program))
        let nativeSource = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        let report = try InitialFailureEvidence.prepare(sourceSHA: sha, nativeSource: nativeSource, to: directory)
        #expect(report.schema == "swifttla.initial-failure-proof-v11")
        #expect(report.result == "prepared")
        #expect(report.sourceSHA == sha)
        #expect(!report.graphCompared)
        #expect(report.site == 3)
        #expect(report.kind == "integerOverflow.addition")
        #expect(report.operands == [3, Int.max])

        let native = try Data(contentsOf: directory.appendingPathComponent("native-initial-failure.json"))
        struct NativeFailures: Decodable {
            struct Failure: Decodable {
                struct Binding: Decodable {
                    let name: String
                    let value: TLAValue
                }
                let site: Int
                let kind: String
                let operands: [Int]
                let before: [Binding]
            }
            let failures: [Failure]
        }
        let failures = try JSONDecoder().decode(NativeFailures.self, from: native).failures
        #expect(failures.count == 1)
        let failure = try #require(failures.first)
        #expect(failure.site == 3)
        #expect(failure.kind == "integerOverflow.addition")
        #expect(failure.operands == [3, Int.max])
        #expect(failure.before.map(\.name) == ["first", "pc", "second"])
        #expect(failure.before.count == 3)
        #expect(failure.before.first { $0.name == "first" }?.value == .int(1))
        #expect(failure.before.first { $0.name == "second" }?.value == .int(3))
        #expect(failure.before.first { $0.name == "pc" }?.value == .string("stay"))
        let generated = directory.appendingPathComponent("generated-tla")
        let module = try Data(contentsOf: generated.appendingPathComponent("\(report.module).tla"))
        let checkModule = try Data(contentsOf: generated.appendingPathComponent("\(report.checkModule).tla"))
        let checkConfiguration = try Data(contentsOf: generated.appendingPathComponent("\(report.checkModule).cfg"))
        let proof = try Data(contentsOf: generated.appendingPathComponent("SwiftTLAInitialFailureProof.tla"))
        #expect(report.nativeSHA256 == SHA256.hex(native))
        #expect(report.moduleSHA256 == SHA256.hex(module))
        #expect(report.checkModuleSHA256 == SHA256.hex(checkModule))
        #expect(report.checkConfigurationSHA256 == SHA256.hex(checkConfiguration))
        #expect(report.proofSHA256 == SHA256.hex(proof))
        #expect(try JSONDecoder().decode(InitialFailureEvidenceReport.self,
            from: Data(contentsOf: directory.appendingPathComponent("preparation.json"))).result == "prepared")
        let proofText = try String(contentsOf: generated.appendingPathComponent("SwiftTLAInitialFailureProof.tla"),
            encoding: .utf8)
        #expect(proofText.contains("InitialFailurePrecedesGraph"))
        #expect(proofText.contains("1073741824"))
        #expect(proofText.contains("ExpectedBefore == <<[name |-> \"first\", value |-> 1], [name |-> \"pc\", value |-> \"stay\"], [name |-> \"second\", value |-> 3]>>"))
        #expect(proofText.contains("before |-> ExpectedBefore"))
        #expect(proofText.contains("ExpectedFailures == {ExpectedFailure}"))
        #expect(proofText.contains("THEOREM CompleteFailureEvents =="))
        #expect(proofText.contains("__SwiftTLAInitialFailureEvents = ExpectedFailures"))
        let plans = "<<" + [
            "<<\"first\", [count |-> 1, kinds |-> <<\"literal\">>, literals |-> <<1>>, reads |-> <<\"first\">>, left |-> <<0>>, right |-> <<0>>]>>",
            "<<\"second\", [count |-> 3, kinds |-> <<\"read\", \"literal\", \"add\">>, literals |-> <<0, 2, 0>>, reads |-> <<\"first\", \"second\", \"second\">>, left |-> <<0, 0, 1>>, right |-> <<0, 0, 2>>]>>",
            "<<\"last\", [count |-> 3, kinds |-> <<\"read\", \"literal\", \"add\">>, literals |-> <<0, ((7 * 1073741824 + 1073741823) * 1073741824 + 1073741823), 0>>, reads |-> <<\"second\", \"last\", \"last\">>, left |-> <<0, 0, 1>>, right |-> <<0, 0, 2>>]>>",
        ].joined(separator: ", ") + ">>"
        #expect(proofText.contains("SourceInitializers == \(plans)\n"))
        #expect(proofText.contains("LoweredInitializers == \(plans)\n"))
        #expect(proofText.contains("NativeInitializers == \(plans)\n"))
        #expect(report.nativeInitializersSHA256 == SHA256.hex(Data(plans.utf8)))
        #expect(report.nativeSourceSHA256 == SHA256.hex(Data(nativeSource.utf8)))
        #expect(try String(contentsOf: directory.appendingPathComponent("native-initial-source.swift"),
            encoding: .utf8) == nativeSource)
        let sourceViews = "<<" + [
            "<<\"first\", [root |-> 1, kinds |-> <<\"literal\">>, literals |-> <<1>>, reads |-> <<\"first\">>, left |-> <<0>>, right |-> <<0>>]>>",
            "<<\"second\", [root |-> 1, kinds |-> <<\"add\", \"read\", \"literal\">>, literals |-> <<0, 0, 2>>, reads |-> <<\"second\", \"first\", \"second\">>, left |-> <<2, 0, 0>>, right |-> <<3, 0, 0>>]>>",
            "<<\"last\", [root |-> 1, kinds |-> <<\"add\", \"read\", \"literal\">>, literals |-> <<0, 0, ((7 * 1073741824 + 1073741823) * 1073741824 + 1073741823)>>, reads |-> <<\"last\", \"second\", \"last\">>, left |-> <<2, 0, 0>>, right |-> <<3, 0, 0>>]>>",
        ].joined(separator: ", ") + ">>"
        #expect(proofText.contains("SourceSyntaxViews == \(sourceViews)\n"))
        #expect(proofText.contains("SourceSyntaxOrigins == <<<<1>>, <<2, 3, 1>>, <<2, 3, 1>>>>\n"))
        #expect(proofText.contains("SourceSyntaxIndices == <<<<1>>, <<3, 1, 2>>, <<3, 1, 2>>>>\n"))
        #expect(report.sourceInitializersSHA256 == SHA256.hex(Data(plans.utf8)))
        #expect(report.loweredInitializersSHA256 == SHA256.hex(Data(plans.utf8)))
        #expect(report.sourceCompilationIdentity == (try CheckedAdditionPrefixInitialModel.spec.compile()).identity.description)
        #expect(proofText.contains("THEOREM SourceInitializersMatchLoweredIR =="))
        #expect(proofText.contains("THEOREM InitializerPlansInvokeCheckedExpressionParent =="))
        #expect(proofText.contains("ProofInitialization!Expressions!PartialOrderedIntExpressionsPreserveValueAndFailure"))
        let layout = "<<" + [
            "[declaration |-> \"pc\", name |-> \"pc\", ordinal |-> 0, origin |-> \"programCounter\"]",
            "[declaration |-> \"first\", name |-> \"first\", ordinal |-> 1, origin |-> \"source\"]",
            "[declaration |-> \"second\", name |-> \"second\", ordinal |-> 2, origin |-> \"source\"]",
            "[declaration |-> \"last\", name |-> \"last\", ordinal |-> 3, origin |-> \"source\"]",
        ].joined(separator: ", ") + ">>"
        let order = "<<0, 1, 2, 3>>"
        let prefixes = "<<<<>>, <<0>>, <<1, 0>>, <<1, 0, 2>>>>"
        #expect(proofText.contains("ActualLayout == \(layout)\n"))
        #expect(proofText.contains("ActualInitializationOrder == \(order)\n"))
        #expect(proofText.contains("ActualPrefixOrders == \(prefixes)\n"))
        #expect(report.layoutSHA256 == SHA256.hex(Data(layout.utf8)))
        #expect(report.initializationOrderSHA256 == SHA256.hex(Data(order.utf8)))
        #expect(report.prefixOrdersSHA256 == SHA256.hex(Data(prefixes.utf8)))
        #expect(proofText.contains("THEOREM ActualPrefixRecordsInvokeInitializationDecoder =="))
        #expect(proofText.contains("ProofInitialization!RenderedInitialPrefixAndSiteDecodingRetainsEveryIdentity"))
        let seeds = "<<[ordinal |-> 0, value |-> \"stay\"]>>"
        #expect(proofText.contains("ActualControlSeeds == \(seeds)\n"))
        let preparation = try #require(JSONSerialization.jsonObject(with:
            Data(contentsOf: directory.appendingPathComponent("preparation.json"))) as? [String: Any])
        #expect(preparation["controlSeedsSHA256"] as? String == SHA256.hex(Data(seeds.utf8)))
        #expect(proofText.contains("ProofInitialization!InitializationHistoriesNeedOnlyReachableChildAgreement"))
        #expect(proofText.contains("ProofInitialization!DeterministicReachableInitializersConstructTheirOrderedObservations"))
        let helper = "SwiftTLA._nativeIntAdd(_arithmetic0, _arithmetic1)"
        try #require(nativeSource.components(separatedBy: helper).count == 3)
        let rebound = nativeSource.replacingOccurrences(of: helper,
            with: "SwiftTLA._NativeMachineOperations.add(_arithmetic0, _arithmetic1)")
        try #require(rebound != nativeSource)
        #expect(throws: CompilationDiagnostic.self) {
            try InitialFailureEvidence.prepare(sourceSHA: sha, nativeSource: rebound,
                to: directory.appendingPathComponent("rejected"))
        }
        let retainedFailures = "SwiftTLA._nativeInitialOutcomes(states: result, failures: failures)"
        try #require(nativeSource.components(separatedBy: retainedFailures).count == 2)
        let droppedFailures = nativeSource.replacingOccurrences(of: retainedFailures,
            with: "SwiftTLA._nativeInitialOutcomes(states: result, failures: [])")
        try #require(droppedFailures != nativeSource)
        do {
            _ = try InitialFailureEvidence.prepare(sourceSHA: sha, nativeSource: droppedFailures,
                to: directory.appendingPathComponent("dropped-failures"))
            Issue.record("The native source erased failures but its proof input was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._initialStates.completeIntOutput")
        }
        let retainedOutcomes = "SwiftTLA._mapNativeInitialOutcomes(outcome)"
        try #require(nativeSource.components(separatedBy: retainedOutcomes).count == 2)
        let erasedOutcomes = nativeSource.replacingOccurrences(of: retainedOutcomes,
            with: "SwiftTLA._mapNativeInitialOutcomes(SwiftTLA.InitialEvaluationOutcomes<Snapshot>(states: [], failures: []))")
        try #require(erasedOutcomes != nativeSource)
        do {
            _ = try InitialFailureEvidence.prepare(sourceSHA: sha, nativeSource: erasedOutcomes,
                to: directory.appendingPathComponent("erased-public-outcomes"))
            Issue.record("The public native outcome adapter erased failures but its proof input was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.initialConstruction")
        }
        let firstToken = "SwiftTLA._nativeFormalProjectionToken(validating: \"first\")!"
        let secondToken = "SwiftTLA._nativeFormalProjectionToken(validating: \"second\")!"
        try #require(nativeSource.components(separatedBy: firstToken).count == 2)
        try #require(nativeSource.components(separatedBy: secondToken).count == 2)
        let swappedTokens = nativeSource.replacingOccurrences(of: firstToken, with: "__swappedToken__")
            .replacingOccurrences(of: secondToken, with: firstToken)
            .replacingOccurrences(of: "__swappedToken__", with: secondToken)
        try #require(swappedTokens != nativeSource)
        do {
            _ = try InitialFailureEvidence.prepare(sourceSHA: sha, nativeSource: swappedTokens,
                to: directory.appendingPathComponent("swapped-tokens"))
            Issue.record("A permuted formal token table was accepted as initialization proof input")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.formalProjection")
        }
        for (index, change) in [
            (firstToken, "SwiftTLA.TLAStateProjection.Token(validating: \"first\")!",
             1, "native.formalProjection"),
            ("SwiftTLA._nativeFormalInt(snapshot.state.first)", "SwiftTLA._nativeFormalInt(snapshot.state.second)",
             1, "native.formalProjection"),
            ("SwiftTLA._nativeFormalInt(snapshot.state.second)", "SwiftTLA._nativeFormalInt(0)",
             1, "native.formalProjection"),
            ("switch snapshot._value_pc_0 {\ncase .location0: return SwiftTLA._nativeFormalString(\"stay\")",
             "switch snapshot._value_pc_0 {\ncase .location0: return SwiftTLA._nativeFormalString(\"changed\")",
             1, "native.formalProjection"),
            ("switch snapshot._value_pc_0 {\ncase .location0: return SwiftTLA._nativeFormalString(\"stay\")",
             "switch snapshot._value_pc_0 {\ncase .location0: return .string(\"stay\")",
             1, "native.formalProjection"),
            ("switch _value_pc_0 {\ncase .location0: return SwiftTLA._nativeFormalString(\"stay\")",
             "switch _value_pc_0 {\ncase .location0: return .string(\"stay\")",
             3, "native._initialStates.completeIntOutput"),
        ].enumerated() {
            let (original, replacement, occurrences, path) = change
            try #require(nativeSource.components(separatedBy: original).count == occurrences + 1)
            let changedProjection = nativeSource.replacingOccurrences(of: original, with: replacement)
            try #require(changedProjection != nativeSource)
            do {
                _ = try InitialFailureEvidence.prepare(sourceSHA: sha, nativeSource: changedProjection,
                    to: directory.appendingPathComponent("changed-projection-\(index)"))
                Issue.record("A changed projection or prefix was accepted as initialization proof input: \(index)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == path)
            }
        }
        #expect(proofText.contains("THEOREM CompleteInitializationMatchesActualOutputs =="))
        #expect(proofText.contains("ResolvedInitializers == \(plans)\n"))
        #expect(preparation["resolvedInitializersSHA256"] as? String == SHA256.hex(Data(plans.utf8)))
        let resolvedTypes = "<<" + [
            "[ordinal |-> 0, type |-> \"_ControlLocation\"]",
            "[ordinal |-> 1, type |-> \"Int\"]",
            "[ordinal |-> 2, type |-> \"Int\"]",
            "[ordinal |-> 3, type |-> \"Int\"]",
        ].joined(separator: ", ") + ">>"
        #expect(proofText.contains("ResolvedVariableTypes == \(resolvedTypes)\n"))
        #expect(preparation["resolvedVariableTypesSHA256"] as? String == SHA256.hex(Data(resolvedTypes.utf8)))
        #expect(proofText.contains("THEOREM LoweredInitializersMatchResolvedIR =="))
        let sourceControl = "\"stay\""
        #expect(proofText.contains("SourceInitialControl == \(sourceControl)\n"))
        #expect(preparation["sourceInitialControlSHA256"] as? String == SHA256.hex(Data(sourceControl.utf8)))
        #expect(proofText.contains("THEOREM SourceInitialControlMatchesResolvedIR =="))
    }

    @Test("Invalid source provenance is refused before output")
    func rejectsInvalidRevision() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swifttla-invalid-revision-\(UUID().uuidString)")
        #expect(throws: InitialFailureEvidenceError.invalidSourceSHA) {
            try InitialFailureEvidence.prepare(sourceSHA: "not-a-revision", nativeSource: "", to: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
