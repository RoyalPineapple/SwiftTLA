import Foundation
import Testing
@testable import SwiftTLA

@Suite("TLA value coding")
struct TLAValueCodingTests {
    @Test("tagged values round trip nested values and reject malformed input")
    func taggedValuesRoundTripAndRejectMalformedInput() throws {
        let value: TLAValue = .function([
            .tuple([.int(1), .string("one")]): .record([
                "nested": .set([.bool(true), .constant("N")])
            ])
        ])
        let encoded = try JSONEncoder().encode(value)

        #expect(try JSONDecoder().decode(TLAValue.self, from: encoded) == value)
        #expect(throws: TLAValueCodingError.unknownTag("other")) {
            _ = try JSONDecoder().decode(TLAValue.self, from: Data(#"{"version":1,"tag":"other"}"#.utf8))
        }
        #expect(throws: TLAValueCodingError.malformedValue("int")) {
            _ = try JSONDecoder().decode(TLAValue.self, from: Data(#"{"version":1,"tag":"int"}"#.utf8))
        }
        #expect(throws: TLAValueCodingError.malformedValue("int")) {
            _ = try JSONDecoder().decode(TLAValue.self, from: Data(#"{"version":1,"tag":"int","value":1,"extra":true}"#.utf8))
        }
    }
}
