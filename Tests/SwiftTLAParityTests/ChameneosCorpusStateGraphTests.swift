import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct ChameneosCorpusStateGraphTests {
    @Test("Chameneos native and formal execution agree throughout the complete bounded graph")
    func nativeGraphMatchesFormalGraph() throws {
        let fixture = Example.chameneosM4N4
        let compilation = try fixture.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let formalInitial = try runtime.initialStates()
        try #require(formalInitial.count == 81)
        try #require(compilation.semantics.behavior.actions.count == 1)
        #expect(Set(compilation.semantics.behavior.invariants.map(\.name)) == ["TypeOK", "SumMet"])
        let conservation = try #require(compilation.semantics.behavior.invariants.first { $0.name == "SumMet" })
        let meetings = try #require(compilation.layout.variables.first { $0.declaration.name == "numMeetings" }?.id)
        let inconsistent = try formalInitial[0].updating(meetings, to: .integer(4))
        #expect(try !runtime.invariantHolds(conservation, in: inconsistent))
        let initialProjections = try formalInitial.map { ($0, try $0.projection(using: compilation.layout)) }
        var pending: [(CompiledState, ChameneosModel)] = try ChameneosModel.initialMachines().map { machine in
            let projection = try formalProjection(of: machine.state)
            let formal = try #require(initialProjections.first { $0.1 == projection }?.0)
            return (formal, machine)
        }
        #expect(Set(pending.map(\.0)) == Set(formalInitial))
        #expect(Set(pending.map { $0.1.state }).count == 81)
        var visited: Set<CompiledState> = []
        var nativeStates: Set<ChameneosModel.State> = []
        while let (state, machine) = pending.popLast() {
            guard visited.insert(state).inserted else { continue }
            try #require(visited.count <= fixture.maximumStateLimit)
            #expect(nativeStates.insert(machine.state).inserted)
            #expect(try machine.violatedInvariants().isEmpty)
            for invariant in compilation.semantics.behavior.invariants {
                #expect(try runtime.invariantHolds(invariant, in: state))
            }
            let successors = try runtime.successors(from: state)
            let expected = try Dictionary(grouping: successors) { successor in
                try #require(successor.arguments.count == 1)
                let argument = try successor.arguments[0].rendered(using: compilation.layout)
                return try #require(ChameneosModel.Creature(formalValue: argument))
            }
            let enabled = try machine.enabledActions()
            #expect(Set(enabled) == Set(expected.keys.map { .Meet(cid: $0) }))
            for creature in ChameneosModel.Creature.allCases {
                let action = ChameneosModel.Action.Meet(cid: creature)
                let candidates = expected[creature] ?? []
                #expect(try machine.isEnabled(action) == !candidates.isEmpty)
                var next = machine
                guard let successor = candidates.first else {
                    #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try next.send(action) }
                    #expect(next.state == machine.state)
                    continue
                }
                try #require(candidates.count == 1)
                let transition = try next.send(action)
                #expect(transition.before == machine.state)
                #expect(transition.after == next.state)
                #expect(try formalProjection(of: next.state) == successor.state.projection(using: compilation.layout))
                pending.append((successor.state, next))
            }
        }
        #expect(visited.count == fixture.expectedDistinct)
        #expect(nativeStates.count == visited.count)
    }

    private func formalProjection(of state: ChameneosModel.State) throws -> TLAStateProjection {
        let fields: [(String, TLAValue)] = [
            ("chameneoses", .function(Dictionary(uniqueKeysWithValues: state.chameneoses.map { creature, value in
                (creature.tlaValue, .tuple([value.first.tlaValue, .int(value.second)]))
            }))),
            ("meetingPlace", .int(state.meetingPlace)),
            ("numMeetings", .int(state.numMeetings))
        ]
        return try TLAStateProjection(validating: fields.map { name, value in
            .init(token: try #require(TLAStateProjection.Token(validating: name)), value: value)
        })
    }
}
