import SwiftTLA
import Testing

@Suite struct MachineCollectionSemanticsTests {
    @Test("native sequence access and domains use one-based indices")
    func sequenceAccess() throws {
        #expect(try _NativeMachineOperations.sequenceElement([10, 20], at: 1) == 10)
        #expect(try _NativeMachineOperations.sequenceElement([10, 20], at: 2) == 20)
        #expect(try _NativeMachineOperations.sequenceHead([10, 20]) == 10)
        #expect(try _NativeMachineOperations.sequenceTail([10, 20]) == [20])
        #expect(try _NativeMachineOperations.sequenceTail([10]).isEmpty)
        #expect(_NativeMachineOperations.sequenceDomain([10, 20]) == [1, 2])
        #expect(_NativeMachineOperations.sequenceDomain([Int]()).isEmpty)
        for index in [Int.min, 0, 3, Int.max] {
            #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: index, count: 2)) {
                try _NativeMachineOperations.sequenceElement([10, 20], at: index)
            }
        }
        #expect(throws: NativeMachineEvaluationError.emptySequence) {
            try _NativeMachineOperations.sequenceHead([Int]())
        }
        #expect(throws: NativeMachineEvaluationError.emptySequence) {
            try _NativeMachineOperations.sequenceTail([Int]())
        }
    }

    @Test("native updates preserve sequence and function domains")
    func domainPreservingUpdates() throws {
        let sequence = [10, 20]
        #expect(_NativeMachineOperations.sequenceUpdated(sequence, at: 2, to: 30) == [10, 30])
        for index in [Int.min, 0, 3, Int.max] {
            #expect(_NativeMachineOperations.sequenceUpdated(sequence, at: index, to: 30) == sequence)
        }
        #expect(_NativeMachineOperations.sequenceUpdated([Int](), at: 1, to: 30).isEmpty)
        let function = ["one": 10, "two": 20]
        #expect(_NativeMachineOperations.functionDomain(function) == ["one", "two"])
        #expect(try _NativeMachineOperations.functionValue(function, at: "one") == 10)
        #expect(_NativeMachineOperations.functionUpdated(function, at: "two", to: 30) == ["one": 10, "two": 30])
        #expect(_NativeMachineOperations.functionUpdated(function, at: "three", to: 30) == function)
        #expect(throws: NativeMachineEvaluationError.functionArgumentOutsideDomain) {
            try _NativeMachineOperations.functionValue(function, at: "three")
        }
        #expect(sequence == [10, 20])
        #expect(function == ["one": 10, "two": 20])
    }
    @Test("finite native collections preserve empty domains and reject cardinality overflow")
    func finiteCollections() throws {
        #expect(try _NativeMachineOperations.integerRange(2, 1).isEmpty)
        #expect(try _NativeMachineOperations.integerRange(-1, 1) == [-1, 0, 1])
        #expect(try _NativeMachineOperations.integerRange(Int.min, Int.min) == [Int.min])
        #expect(try _NativeMachineOperations.integerRange(Int.max, Int.max) == [Int.max])
        for bounds in [(Int.min, Int.max), (0, Int.max)] {
            #expect(throws: NativeMachineEvaluationError.collectionCardinalityOverflow(.integerRange, operands: [bounds.0, bounds.1])) {
                try _NativeMachineOperations.integerRange(bounds.0, bounds.1)
            }
        }
        let subsets: Set<Set<Int>> = [[], [1], [2], [1, 2]]
        #expect(try _NativeMachineOperations.powerSet([1, 2]) == subsets)
        #expect(try _NativeMachineOperations.powerSet(Set<Int>()) == [[]])
        let oversized = Set(0..<(Int.bitWidth - 1))
        #expect(throws: NativeMachineEvaluationError.powerSetTooLarge(actualCount: oversized.count, maximumCount: Int.bitWidth - 2)) {
            try _NativeMachineOperations.powerSet(oversized)
        }
        let functions: Set<[Int: Bool]> = [
            [1: false, 2: false], [1: false, 2: true],
            [1: true, 2: false], [1: true, 2: true],
        ]
        #expect(try _NativeMachineOperations.functionSet([1, 2], [false, true]) == functions)
        #expect(try _NativeMachineOperations.functionSet(Set<Int>(), Set<Bool>()) == [[:]])
        #expect(try _NativeMachineOperations.functionSet([1], Set<Bool>()).isEmpty)
        #expect(throws: NativeMachineEvaluationError.collectionCardinalityOverflow(.functionSet, operands: [oversized.count, 2])) {
            try _NativeMachineOperations.functionSet(oversized, [false, true])
        }
    }

    @Test("native CHOOSE uses supplied structural order and rejects absent witnesses")
    func orderedChoice() throws {
        #expect(try _NativeMachineOperations.choose([3, 2, 1], satisfying: { $0 < 3 }) == 2)
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
            try _NativeMachineOperations.choose([1, 2], satisfying: { $0 > 2 })
        }
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
            try _NativeMachineOperations.choose([Int](), satisfying: { _ in true })
        }
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try _NativeMachineOperations.choose([1], satisfying: { _ in throw NativeMachineEvaluationError.noMatchingCase })
        }
    }

}
