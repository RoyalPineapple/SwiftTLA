import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite("Selected initial failure evidence")
struct InitialFailureEvidenceTests {
    @Test("A failure-only initializer retains native and actual TLA output for a proof without a graph")
    func preparesSelectedFailureProof() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swifttla-initial-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sha = String(repeating: "a", count: 40)
        let report = try InitialFailureEvidence.prepare(sourceSHA: sha, to: directory)
        #expect(report.schema == "swifttla.initial-failure-proof-v10")
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
        let sourceViews = "<<" + [
            "<<\"first\", [root |-> 1, kinds |-> <<\"literal\">>, literals |-> <<1>>, reads |-> <<\"first\">>, left |-> <<0>>, right |-> <<0>>]>>",
            "<<\"second\", [root |-> 1, kinds |-> <<\"add\", \"read\", \"literal\">>, literals |-> <<0, 0, 2>>, reads |-> <<\"second\", \"first\", \"second\">>, left |-> <<2, 0, 0>>, right |-> <<3, 0, 0>>]>>",
            "<<\"last\", [root |-> 1, kinds |-> <<\"add\", \"read\", \"literal\">>, literals |-> <<0, 0, ((7 * 1073741824 + 1073741823) * 1073741824 + 1073741823)>>, reads |-> <<\"last\", \"second\", \"last\">>, left |-> <<2, 0, 0>>, right |-> <<3, 0, 0>>]>>",
        ].joined(separator: ", ") + ">>"
        #expect(proofText.contains("SourceSyntaxViews == \(sourceViews)\n"))
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
            try InitialFailureEvidence.prepare(sourceSHA: "not-a-revision", to: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
