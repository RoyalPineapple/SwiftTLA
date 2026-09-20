import Testing
import SwiftParser
import SwiftSyntax
import SwiftBasicFormat
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct CandidateTraversalTests {
    @Test("Checked enum views retain token boundaries in nested candidate continuations")
    func formatsNestedCheckedViews() throws {
        let compilation = try TLASpec("CheckedCandidate") { Var("value", 0) }.compile()
        let types = SourceTypeResolver(metadata: .init(enums: [
            .init(typeName: "Member", cases: [(name: "one", value: .int(1)), (name: "two", value: .int(2))])
        ]))
        let program = try CompiledProgram(inputs: types.resolve(in: compilation))
        let emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "CheckedCandidate", program: program))
        let view = try emitter.checkedView("member", from: .int, to: .named("Member"))
        #expect(view.contains("in\nswitch value"))
        let source = "visit { outer in\nvisit { inner in\nlet checked = \(view)\n}\n}"
        let formatted = Parser.parse(source: source).formatted().description
        #expect(!formatted.contains("inswitch"))
        #expect(!Parser.parse(source: formatted).hasError)
    }

    @Test("Generated choices finish each candidate before advancing the outer choice")
    func visitsCandidatesInOrder() throws {
        let machine = try OrderedCandidateChoices.makeMachine()
        let successors = try machine.successors()
        #expect(successors.map { $0.machine.state.first * 10 + $0.machine.state.second } == [11, 12, 22])
        #expect(successors.allSatisfy { $0.machine.state.previous == 0 })
        #expect(machine.state.first == 0)
        var context = CheckingContext(registers: try machine.initialCheckingRegisters())
        let checking = try machine.successors(checking: &context)
        #expect(checking.map { $0.machine.snapshot } == successors.map { $0.machine.snapshot })
        let selected = try #require(successors.last?.machine)
        #expect(try selected.successors().allSatisfy { $0.machine.state.previous == 2 })
    }

    @Test("Generated conjunctions pass each partial candidate to their continuation")
    func emitsCandidateContinuation() throws {
        let compilation = try OrderedCandidateChoices.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "OrderedCandidateChoices", program: program))
        let action = try #require(program.behavior.actions.first)
        let generated = try emitter.actionFunctions(action.body)
        #expect(generated.contains("updates, { candidate in try _actionPart"))
        #expect(!generated.contains("flatMap"))
        #expect(!generated.contains("-> [_Updates]"))
        #expect(generated.contains("try _actionPart0(_Updates()) { candidates.append($0) }"))
        #expect(!Parser.parse(source: "func updates() throws -> [_Updates] {\n\(generated)\n}").hasError)
    }
}
