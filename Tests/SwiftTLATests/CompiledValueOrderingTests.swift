@testable import SwiftTLA
import Testing

struct CompiledValueOrderingTests {
    @Test("Nested values remain distinct from delimiter-shaped strings")
    func orderingIsStructural() {
        let nested = CompiledValue.tuple([.string("a"), .string("b")])
        let delimiterShaped = CompiledValue.tuple([.string("a,string:b")])

        #expect(nested != delimiterShaped)
        #expect(nested < delimiterShaped || delimiterShaped < nested)
    }
}
