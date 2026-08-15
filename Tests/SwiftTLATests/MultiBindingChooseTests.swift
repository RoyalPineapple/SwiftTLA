import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@Suite("PlusCal multi-binding Choose")
struct MultiBindingChooseTests {
    @Test("two ordered ranges lower to nested existential choices and enumerate their product")
    func lowersAndEnumeratesOrderedRanges() throws {
        let algorithm = Algorithm("PairChoice") {
            let selected = SharedVar("selected", initial: 0)
            selected
            Each(MultiBindingChooseModel.Node.all) { _ in
                Do("choose") {
                    Choose(1...2, 10...11) { first, second in
                        Assign(selected, to: first.expr * 100 + second.expr)
                    }
                }
            }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let action = try #require(spec.actions.first { $0.name == "choose" })
        let successors = try actionInvocations(action).flatMap {
            try ActionEnumerator.enumerate($0.body, from: initial, varNames: spec.variables.map(\.name))
        }
        #expect(Set(successors.compactMap { $0["selected"] }) == [.int(110), .int(111), .int(210), .int(211)])
        #expect(action.body.description.contains("\\E"))
    }

    @Test("macro parser produces the same nested choice model as the builder")
    func parserBuilderFidelity() {
        MultiBindingChooseModel._checkParserTree()
    }
}

@TLAModel
private struct MultiBindingChooseModel {
    enum Node: Int, CaseIterable, FiniteDomainKey {
        case only = 0
        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.multi-binding-choose.node")
    }

    static var spec: TLASpec {
        #spec("MultiBindingChoose") {
            Algorithm("MultiBindingChoose") {
                let selected = SharedVar(initial: 0)
                Each(Node.all) { _ in
                    Do("choose") {
                        Choose(1...2, 10...11) { first, second in
                            Assign(selected, to: first.expr * 100 + second.expr)
                        }
                    }
                }
            }
        }
    }
}
