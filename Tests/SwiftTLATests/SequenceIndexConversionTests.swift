import Testing
@testable import SwiftTLA

struct SequenceIndexConversionTests {
    @Test("typed conversions preserve ordinary arrays through generated transitions and checking")
    func generatedConversions() throws {
        var renderedModules: Set<String> = []
        var importedModules: Set<String> = []
        let scenarios = try SequenceIndexConversionMachine.validationScenarios()
        #expect(scenarios.count == 3)
        for scenario in scenarios {
            var machine = try #require(scenario.initialMachines().first)
            var expected = scenario.configuration.input
            let graph = try scenario.explore(maximumStates: 10)
            #expect(graph.safetyViolations.isEmpty)
            for _ in 0...expected.count {
                let zero: [Int: Int] = machine.state.zero
                let one: [Int] = machine.state.one
                let empty: [Int] = machine.state.empty
                let members: [SequenceIndexConversionMachine.Element] = machine.state.members
                let rootMembers: [SequenceIndexConversionMachine.Element] = machine.state.rootMembers
                #expect(zero == Dictionary(uniqueKeysWithValues: expected.enumerated().map { ($0.offset, $0.element) }))
                #expect(one == expected)
                #expect(empty.isEmpty)
                #expect(members == [.second, .first, .second])
                #expect(rootMembers == members)
                let before = machine.snapshot
                let transition = try machine.send(.rotate)
                #expect(transition.after == machine.state)
                #expect(try #require(graph.transitions[before]).contains {
                    $0.action == .rotate && $0.target == machine.snapshot
                })
                expected = Array(expected.dropFirst()) + Array(expected.prefix(1))
            }
            let rendered = try scenario.render()
            renderedModules.insert(rendered.tlaBundle.tla)
            #expect(rendered.tlaBundle.imports.map(\.name) == ["ZSequences"])
            let imported = try #require(rendered.tlaBundle.imports.first).tla
            importedModules.insert(imported)
            #expect(imported.contains("ZSeqFromSeq("))
            #expect(imported.contains("SeqFromZSeq("))
            #expect(rendered.tlaBundle.tla.contains(
                "__SwiftTLAParameter0 == \(scenario.configuration.input.tlaValue)"))
        }
        #expect(renderedModules.count == scenarios.count)
        #expect(importedModules.count == 1)
    }

    @Test("typed conversion expressions retain array shape at the formal boundary")
    func typedExpressionRoundTrip() throws {
        let consumer = TLASpec("TypedSequenceIndexConversion") {
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 3))
        }
        let functions = try FormalModuleClosure.resolve(root: consumer).linkedOperators.recursiveFunctions
        for input in [[], [7], [3, 1, 3]] as [[Int]] {
            let zero: Expr<ZeroBasedSequence<Int>> = ZSequences.zeroBased(from: input.expr)
            let one: Expr<[Int]> = ZSequences.oneBased(from: zero)
            #expect(try compiledValue(one.stateExpr, recursiveFunctions: functions) == input.tlaValue)
        }
    }

    @Test("sequence index conversion preserves empty inputs, order, and element identity")
    func preservesValuesInBothDirections() throws {
        let consumer = TLASpec("SequenceIndexConversion") {
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 0))
        }
        let functions = try FormalModuleClosure.resolve(root: consumer).linkedOperators.recursiveFunctions
        let inputs: [[TLAValue]] = [
            [], [.int(7)], [.int(3), .int(-1), .int(3)],
            [.bool(false), .bool(true)],
            [.string("node"), .string(""), .string("é")],
            [.constant("node"), .constant("other"), .constant("node")]
        ]
        for elements in inputs {
            let oneBased = StateExpr.value(.tuple(elements))
            let zeroBased = StateExpr.value(elements.isEmpty ? .tuple([]) : .function(
                Dictionary(uniqueKeysWithValues: elements.enumerated().map { (.int($0.offset), $0.element) })
            ))
            let convertedZero = StateExpr.recursiveCall("ZSeqFromSeq", [oneBased])
            let convertedOne = StateExpr.recursiveCall("SeqFromZSeq", [zeroBased])
            for equality in [
                StateExpr.equal(convertedZero, zeroBased),
                .equal(convertedOne, oneBased),
                .equal(.recursiveCall("SeqFromZSeq", [convertedZero]), oneBased),
                .equal(.recursiveCall("ZSeqFromSeq", [convertedOne]), zeroBased)
            ] {
                #expect(try compiledValue(equality, recursiveFunctions: functions) == .bool(true))
            }
            #expect(try compiledValue(.domain(convertedZero), recursiveFunctions: functions)
                == .set(Set(elements.indices.map { .int($0) })))
            #expect(try compiledValue(.domain(convertedOne), recursiveFunctions: functions)
                == .set(Set(elements.indices.map { .int($0 + 1) })))
        }
    }
}
