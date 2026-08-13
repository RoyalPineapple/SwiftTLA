import Foundation
import Testing

struct TemporalSymmetryCommandContractTests {
  @Test("the local support gate retains a current core context and runs the temporal gate")
  func localGateContract() throws {
    let root = projectRoot()
    let script = try String(contentsOf: root.appendingPathComponent("scripts/run_temporal_symmetry_support_gate.sh"))
    let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"))
    let localCI = try String(contentsOf: root.appendingPathComponent("scripts/run_ci_locally.sh"))
    let releaseCheck = try String(contentsOf: root.appendingPathComponent("scripts/check_temporal_symmetry_release.sh"))
    let workflow = try String(contentsOf: root.appendingPathComponent(
      ".github/workflows/temporal-symmetry-conformance.yml"))

    #expect(script.contains("temporal-symmetry run"))
    #expect(script.contains("--core-admission"))
    #expect(script.contains("--core-report-id"))
    #expect(script.contains("CURRENT_CORE_REPORT"))
    #expect(script.contains("coreGateRunID"))
    #expect(script.contains("coreReportSHA256"))
    #expect(script.contains("runs/$GATE_RUN_ID"))
    #expect(makefile.contains("temporal-symmetry-support-gate:"))
    #expect(makefile.contains("temporal-symmetry-release-check:"))
    #expect(localCI.contains("make temporal-symmetry-release-check"))
    #expect(workflow.contains("make temporal-symmetry-release-check"))
    #expect(releaseCheck.contains("support-admission.json"))
    #expect(releaseCheck.contains(".finalExitClass == \"unavailable\""))
    #expect(releaseCheck.contains("TemporalSymmetryRegisterTests"))
    #expect(workflow.contains("exit 0"))
    #expect(workflow.contains("exit 1"))
    #expect(workflow.contains("exit 2"))
  }

  private func projectRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
