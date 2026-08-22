import Foundation
import Testing
import UpstreamParity

@Suite("Core support admission")
struct CoreSupportAdmissionTests {
  @Test("an exact declared case is admitted with its current evidence")
  func exactDeclaredCaseIsAdmitted() throws {
    let gateRunID = UUID()
    let entry = try CoreSupportAdmissionEntry(
      supportID: "counter-state-space",
      decision: .admitted,
      reasonCodes: [],
      mandatoryCaseIDs: ["counter"],
      evidence: [try evidenceReference()],
      caseRunCorrelations: [try correlation(caseID: "counter", gateRunID: gateRunID)])

    let admission = try CoreSupportAdmission(gateRunID: gateRunID, entries: [entry])

    #expect(admission.finalExitClass == .success)
    #expect(admission.counts.admitted == 1)
    #expect(admission.counts.nonExact == 0)
  }

  @Test("a non-exact comparison blocks admission")
  func nonExactComparisonBlocksAdmission() throws {
    let entry = try CoreSupportAdmissionEntry(
      supportID: "counter-transition-relation",
      decision: .blocked,
      reasonCodes: [.nonExactComparison],
      mandatoryCaseIDs: ["counter"])

    let admission = try CoreSupportAdmission(gateRunID: UUID(), entries: [entry])

    #expect(admission.finalExitClass == .blocked)
    #expect(admission.counts.nonExact == 1)
  }

  @Test("the support surface requires every declared case")
  func supportSurfaceRequiresDeclaredCases() throws {
    let entry = try CoreSupportSurfaceEntry(
      id: "counter-state-space",
      behavior: "counter state space",
      category: .stateSpace,
      finiteBounds: try CoreFiniteBounds(summary: "one state", limits: ["states": 1]),
      mandatoryCaseIDs: ["counter"],
      requestedStatus: .requested)
    let surface = try CoreSupportSurface(entries: [entry])

    #expect(throws: ConformanceGovernanceError.unknownCaseID("counter")) {
      try surface.validate(caseIDs: [])
    }
  }

  private func evidenceReference() throws -> CoreEvidenceReference {
    try .init(path: "run/comparison.json", sha256: String(repeating: "0", count: 64))
  }

  private func correlation(caseID: String, gateRunID: UUID) throws -> CoreSupportCaseRunCorrelation {
    try .init(
      caseID: caseID,
      gateRunID: gateRunID,
      swiftRunID: gateRunID,
      tlcRunID: gateRunID,
      comparisonRunID: gateRunID)
  }
}
