import Testing
@testable import SwiftTLA

struct SequenceIndexConversionTests {
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
