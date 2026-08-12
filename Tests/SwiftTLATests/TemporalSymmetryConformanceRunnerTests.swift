import Foundation
import Testing
import UpstreamParity
import SwiftTLA

struct TemporalSymmetryConformanceRunnerTests {
  @Test("the runner validates pinned fixtures and retains bounded Swift preparation records")
  func retainsBoundedSwiftPreparationRecords() throws {
    let root = projectRoot()
    let casesURL = root.appendingPathComponent("Verification/TemporalSymmetryConformance/cases.json")
    let cases = try JSONDecoder().decode(TemporalSymmetryCasesV1.self, from: Data(contentsOf: casesURL))
    let output = root.appendingPathComponent(".build/temporal-symmetry-runner-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: output) }

    let gateRunID = UUID()
    let records = try TemporalSymmetryConformanceRunnerV1().run(
      TemporalSymmetryConformanceRunnerInputV1(
        cases: cases, gateRunID: gateRunID, projectRoot: root, outputDirectory: output))

    #expect(records.count == cases.cases.count)
    #expect(records.allSatisfy { $0.gateRunID == gateRunID })
    let prepared = records.filter { $0.status == .prepared }
    #expect(prepared.count == 10)
    #expect(prepared.allSatisfy { $0.diagnosticCode == "awaiting-pinned-tlc-comparison" })
    #expect(prepared.filter { $0.caseID.hasPrefix("temporal-") }.allSatisfy { $0.swiftGraphStateCount == 3 })
    #expect(Set(prepared.filter { $0.caseID.hasPrefix("symmetry-single") }.compactMap(\.swiftGraphStateCount)) == [4, 8, 16])
    #expect(records.first { $0.caseID == "symmetry-scope-5-unsupported" }?.status == .unavailable)
    for record in records {
      let retained = output.appendingPathComponent(record.caseID).appendingPathComponent("case-run.json")
      #expect(FileManager.default.fileExists(atPath: retained.path))
      #expect(try JSONDecoder().decode(TemporalSymmetryCaseRunV1.self, from: Data(contentsOf: retained)) == record)
    }
  }

  @Test("independent temporal matrix mappings preserve bounded fairness outcomes")
  func temporalMatrixMappingsPreserveFairnessBoundary() throws {
    let cases = try registeredCases()
    let expected: [String: Bool] = [
      "temporal-always-none": false,
      "temporal-eventually-none": false,
      "temporal-always-eventually-none": false,
      "temporal-eventually-always-weak": false,
      "temporal-leads-to-strong": false,
      "temporal-weak-fairness-boundary": false,
      "temporal-strong-fairness-boundary": false,
    ]
    for declaredCase in cases.cases where declaredCase.kind == .temporal {
      let model = try #require(TemporalSymmetryModelCatalogV1.model(for: declaredCase))
      let result = try ModelChecker(spec: model.spec, maxStates: model.maxStates).checkLiveness()
      let isSatisfied: Bool
      if case .ok = result.underlyingOutcome { isSatisfied = true } else { isSatisfied = false }
      #expect(isSatisfied == expected[declaredCase.id])
    }
  }

  private func registeredCases() throws -> TemporalSymmetryCasesV1 {
    try JSONDecoder().decode(
      TemporalSymmetryCasesV1.self,
      from: Data(contentsOf: projectRoot().appendingPathComponent("Verification/TemporalSymmetryConformance/cases.json")))
  }

  private func projectRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
