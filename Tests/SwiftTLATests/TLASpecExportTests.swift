import Testing
@testable import SwiftTLA

@Suite("TLA+ export")
struct TLASpecExportTests {
    @Test("export routes every format to its existing deterministic renderer")
    func exportsKnownFormats() {
        let counter = Var<Int>("counter", 0)
        let spec = TLASpec("Export Counter") {
            Variable(counter, 0)
            Action("increment") {
                counter.becomes(counter + 1)
            }
        }

        #expect(spec.export(.tla) == spec.tlaModule)
        #expect(spec.export(.cfg) == spec.tlaCfg)
    }

    @Test("export is repeatable and does not require external tools")
    func exportIsDeterministic() {
        let value = Var<Int>("value", 0)
        let spec = TLASpec("Deterministic Export") {
            Variable(value, 0)
            Action("stay") {
                value.stays
            }
        }

        #expect(spec.export(.tla) == spec.export(.tla))
        #expect(spec.export(.cfg) == spec.export(.cfg))
    }
}
