import Foundation
import Testing
@testable import UpstreamParity

struct PrintedValueEvidenceTests {
    @Test("printed TLC values require complete, typed records")
    func rejectsIncompleteOrChangedOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("evaluations.bin")
        let printed = "<<1, 3, 9, 27>>"
        let value = Array(printed.utf8)
        var complete = Data("STLAOUT1".utf8)
        complete.append(1)
        complete.append(1)
        complete.append(contentsOf: [0, 0, 0, UInt8(value.count)])
        complete.append(contentsOf: value)
        complete.append(contentsOf: [2, 0, 0, 0, 0, 0, 0, 0, 1])
        try complete.write(to: output)

        let captured = try TLCEvaluationOutput(reading: output)
        #expect(captured.values == [.tuple([.integer(1), .integer(3), .integer(9), .integer(27)])])

        try Data(complete.dropLast(9)).write(to: output)
        #expect(throws: TLCEvaluationOutputError.malformed("missing completion footer")) {
            try TLCEvaluationOutput(reading: output)
        }

        complete[complete.count - 1] = 2
        try complete.write(to: output)
        #expect(throws: TLCEvaluationOutputError.malformed("completion footer")) {
            try TLCEvaluationOutput(reading: output)
        }
    }
}
