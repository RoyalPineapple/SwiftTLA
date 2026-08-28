import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@Suite("PlusCal multi-binding Choose")
struct MultiBindingChooseTests {
    @Test("two ordered ranges lower to nested existential choices and enumerate their product")
    func lowersAndEnumeratesOrderedRanges() throws {
        let algorithm = Algorithm("PairChoice", scoped: { scope in
            let selected = scope.sharedVar("selected", initial: 0)
            Each(MultiBindingChooseModel.Node.all) { _ in
                Do(TestControlLabel.choose) {
                    Choose(1...2, 10...11) { first, second in
                        Assign(selected, to: first.expr * 100 + second.expr)
                    }
                }
            }
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        let compilation = try spec.compile()
        let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        let choose = try #require(compilation.layout.testActionID(named: "choose"))
        let successors = try CompiledRuntime(compilation: compilation).successors(for: choose, from: initial).map(\.state)
        let selected = try #require(compilation.layout.testVariableID(named: "selected"))
        let values = try Set(successors.map { try $0.value(for: selected).rendered(using: compilation.layout) })
        #expect(values == [.int(110), .int(111), .int(210), .int(211)])
        #expect(compilation.renderedTLAModuleBundle().tla.contains("\\E"))
    }

    @Test("macro parser produces the same nested choice model as the builder")
    func parserBuilderFidelity() {
    }
}

@TLAModel
private struct MultiBindingChooseModel {
    enum Step: String, CaseIterable { case choose }

    enum Node: Int, CaseIterable, FiniteTLAValueDomain {
        case only = 0
        static var defaultValue: Self { .only }
        static let finiteValues = allCases
    }

    static var spec: TLASpec {
        #spec("MultiBindingChoose") {
            Algorithm("MultiBindingChoose", scoped: { scope in
                let selected = scope.sharedVar("selected", initial: 0)
                Each(Node.all) { _ in
                    Do(Step.choose) {
                        Choose(1...2, 10...11) { first, second in
                            Assign(selected, to: first.expr * 100 + second.expr)
                        }
                    }
                }
            })
        }
    }
}
