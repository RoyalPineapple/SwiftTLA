import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct NominalFunctionInitialization {
    enum Key: Int, FiniteTLAValueDomain {
        case first = 1, second = 2
        static var defaultValue: Self { .first }
        static let finiteValues: [Self] = [.first, .second]
    }
    enum Step: String, CaseIterable { case idle }
    static var spec: TLASpec {
        #spec("NominalFunctionInitialization") {
            Algorithm("NominalFunctionInitialization", scoped: { scope in
                let counts = scope.sharedVar("counts", initial: Function<Key, Int>.literal((.first, 7), (.second, 9)))
                let flags = scope.sharedVar("flags", initial: Function<Key, Bool>.literal((.first, false), (.second, true)))
                Do(Step.idle) { Skip() }
            })
        }
    }
}

@Suite("Function initializer binders retain contextual enum representation")
struct NativeFunctionBindingContextTests {
    @Test("Literal function branches compare keys in their declared native representation")
    func functionInitializersMatchFormalValues() throws {
        let machine = try NominalFunctionInitialization.makeMachine()
        #expect(machine.state.counts == [.first: 7, .second: 9])
        #expect(machine.state.flags == [.first: false, .second: true])
        let compilation = try NominalFunctionInitialization.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let formal = try #require(try runtime.initialStates().first)
        let counts = try #require(compilation.layout.testVariableID(named: "counts"))
        let flags = try #require(compilation.layout.testVariableID(named: "flags"))
        #expect(try formal.value(for: counts) == .function([.integer(1): .integer(7), .integer(2): .integer(9)]))
        #expect(try formal.value(for: flags) == .function([.integer(1): .boolean(false), .integer(2): .boolean(true)]))
    }
}
