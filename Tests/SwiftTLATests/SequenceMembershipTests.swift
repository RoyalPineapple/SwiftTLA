import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SequenceMembershipTests {
    @Test("Generated sequence membership agrees with independently enumerated small domains")
    func agreesWithEnumeration() throws {
        for maximum in 0...3 {
            var members: Set<[Int: Int]> = []
            for count in 0...maximum {
                members.formUnion(try _NativeMachineOperations.functionSet(Set(0..<count), Set([0, 1])))
            }
            for length in 0...4 {
                for entry in 0...2 {
                    let configuration = try SequenceMembershipModel.Configuration(maximum: maximum, length: length, entry: entry)
                    var machine = try SequenceMembershipModel.makeMachine(configuration: configuration)
                    _ = try machine.send(.check)
                    #expect(machine.state.result == (length <= maximum && (length == 0 || entry < 2)))
                    #expect(machine.state.result == members.contains(machine.state.sequence))
                }
            }
        }
    }

    @Test("Sequence membership does not enumerate an exponential function space")
    func largeDomain() throws {
        var machine = try SequenceMembershipModel.makeMachine(configuration: .init(maximum: 100, length: 100, entry: 1))
        #expect(try machine.send(.check).after.result)
        let compilation = try SequenceMembershipModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "SequenceMembershipModel", program: program))
        let source = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(!source.contains("_NativeMachineOperations.functionSet("))
        #expect(try SequenceMembershipModel.render(configuration: .init(maximum: 100, length: 100, entry: 1))
            .tlaBundle.tla.contains("ZSeq"))
    }

    @Test("A zero-length bound still evaluates a failing candidate")
    func candidateFailure() throws {
        var machine = try SequenceMembershipModel.makeMachine(configuration: .init(maximum: 0, length: 0, entry: 0))
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.divisionByZero) { try machine.send(.candidateFailure) }
        #expect(machine.state == before)
    }

    @Test("Membership evaluates every selected set branch but retains lazy operator arguments")
    func domainFailure() throws {
        var unused = try SequenceMembershipModel.makeMachine(configuration: .init(maximum: 0, length: 0, entry: 0))
        #expect(try unused.send(.domainFailure).after.result)
        var required = try SequenceMembershipModel.makeMachine(configuration: .init(maximum: 1, length: 0, entry: 0))
        let before = required.state
        #expect(throws: NativeMachineEvaluationError.divisionByZero) { try required.send(.domainFailure) }
        #expect(required.state == before)
    }
}
