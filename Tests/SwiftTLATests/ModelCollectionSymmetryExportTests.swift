@testable import SwiftTLA
import Testing

struct ModelCollectionSymmetryExportTests {
  private struct Device: Identifiable {
    let id: Int
  }

  @Test("TLA and CFG declare symmetric members as TLC model values")
  func collectionsEmitModelValueSymmetryBundle() throws {
    let members = CollectionVar<Device, Int>("devicePhases")
    let spec = TLASpec("DevicePhases") {
      ModelCollection(members, verificationScope: 2, initial: 0)
      Symmetry(members)
    }

    let bundle = try spec.compile().render().tlaBundle
    #expect(bundle.tla.contains("CONSTANTS DevicePhasesMember0, DevicePhasesMember1"))
    #expect(bundle.tla.contains("DevicePhasesKeys == {DevicePhasesMember0, DevicePhasesMember1}"))
    #expect(bundle.tla.contains("SymmdevicePhases == Permutations({DevicePhasesMember0, DevicePhasesMember1})"))
    #expect(bundle.tla.contains("devicePhases = [__tla_fn_0 \\in {DevicePhasesMember0, DevicePhasesMember1} |-> 0]"))
    #expect(bundle.cfg.contains("CONSTANT DevicePhasesMember0 = DevicePhasesMember0"))
    #expect(bundle.cfg.contains("CONSTANT DevicePhasesMember1 = DevicePhasesMember1"))
    #expect(bundle.cfg.contains("SYMMETRY SymmdevicePhases"))
    #expect(bundle.tla.contains("\"DevicePhasesMember0\"") == false)
  }

  @Test("Compiled symmetric collections retain their declared variable identity")
  func collectionUsesCompiledVariableIdentity() throws {
    let devices = CollectionVar<Device, Int>("devices")
    let compilation = try TLASpec("DeviceIdentity") {
      ModelCollection(devices, verificationScope: 2, initial: 0)
      Symmetry(devices)
    }.compile()

    let variable = try #require(compilation.layout.variables.first { $0.declaration.name == devices.name })
    let collection = try #require(variable.collection)
    let symmetry = try #require(compilation.semantics.symmetrySets.first)
    #expect(collection.members.count == 2)
    #expect(symmetry.values == Set(collection.members))
  }
}
