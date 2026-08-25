import Foundation
import Testing

struct TemporalSymmetryCommandContractTests {
  @Test("release qualification requires exact core conformance before the temporal gate")
  func releaseQualificationContract() throws {
    let root = projectRoot()
    let script = try String(contentsOf: root.appendingPathComponent("scripts/run_temporal_symmetry_support_gate.sh"))
    let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"))
    let releaseQualification = try String(contentsOf: root.appendingPathComponent("scripts/run_release_qualification.sh"))
    let releaseCheck = try String(contentsOf: root.appendingPathComponent("scripts/check_temporal_symmetry_release.sh"))
    let workflow = try String(contentsOf: root.appendingPathComponent(
      ".github/workflows/temporal-symmetry-conformance.yml"))

    #expect(script.contains("temporal-symmetry run"))
    #expect(script.contains("run_core_conformance.sh"))
    #expect(script.contains("coreConformanceExit"))
    #expect(script.contains("runs/$GATE_RUN_ID"))
    #expect(makefile.contains("temporal-symmetry-support-gate:"))
    #expect(makefile.contains("temporal-symmetry-release-check:"))
    #expect(releaseQualification.contains("make temporal-symmetry-release-check"))
    #expect(workflow.contains("make temporal-symmetry-release-check"))
    #expect(releaseCheck.contains("current-support-admission.json"))
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
