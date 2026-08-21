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
                Do(TestControlLabel.choose) {
                    Choose(1...2, 10...11) { first, second in
                        Assign(selected, to: first.expr * 100 + second.expr)
                    }
                }
            }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
        let compilation = try spec.compile()
        let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        let choose = try #require(compilation.layout.actionID(named: "choose"))
        let successors = try CompiledRuntime(compilation: compilation).successors(for: choose, from: initial).map(\.state)
        let selected = try #require(compilation.layout.variableID(named: "selected"))
        let values = try Set(successors.map { try $0.value(for: selected).rendered(using: compilation.layout) })
        #expect(values == [.int(110), .int(111), .int(210), .int(211)])
        let action = try #require(spec.actions.first { $0.name == "choose" })
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
        static var defaultValue: Self { .only }
        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.multi-binding-choose.node")
    }

    static var spec: TLASpec {
        #spec("MultiBindingChoose") {
            Algorithm("MultiBindingChoose") {
                let selected = SharedVar("selected", initial: 0)
                Each(Node.all) { _ in
                    Do(TestControlLabel.choose) {
                        Choose(1...2, 10...11) { first, second in
                            Assign(selected, to: first.expr * 100 + second.expr)
                        }
                    }
                }
            }
        }
    }
}
