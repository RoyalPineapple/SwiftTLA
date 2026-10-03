import Testing
@testable import SwiftTLA

struct FormalCollectionValueTests {
    @Test("formal collection values round-trip without host collection types")
    func roundTripsFormalValues() {
        let set = SetExpr<Int>(formalValue: .set([.int(1), .int(2)]))
        #expect(set?.elements.count == 2)
        #expect(set?.elements.contains(1) == true)
        #expect(set?.elements.contains(2) == true)

        let tuple = TupleExpr<Int>(formalValue: .tuple([.int(1), .int(2)]))
        #expect(tuple?.elements == [1, 2])
    }
}
