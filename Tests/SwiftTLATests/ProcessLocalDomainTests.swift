import Testing
@testable import SwiftTLA

struct ProcessLocalDomainTests {
    @Test("each process chooses its initial local value independently")
    func independentInitialChoices() throws {
        let native = try IndependentLocalChoices.initialMachines()
        let nativeStates = try Set(native.map { try $0.formalProjection(of: $0.snapshot) })
        #expect(nativeStates.count == 16)
        let choice = try #require(TLAStateProjection.Token(validating: "choice"))
        let combinations = try Set(nativeStates.map { state -> [TLAValue] in
            guard case .function(let choices) = try #require(state.value(for: choice)) else {
                throw TLAStateProjectionDiagnostic.invalidValue(path: "choice")
            }
            return [try #require(choices[.int(1)]), try #require(choices[.int(2)])]
        })
        let subsets: [TLAValue] = [.set([]), .set([.int(1)]), .set([.int(2)]), .set([.int(1), .int(2)])]
        #expect(combinations == Set(subsets.flatMap { first in subsets.map { second in [first, second] } }))
        #expect(try IndependentLocalChoices.render().tlaBundle.tla.contains("choice \\in ["))
    }
}
