import Testing
@testable import SwiftTLA

@Suite("Boolean value composition")
struct BooleanValueKernelTests {
    @Test("Conjunction skips a false right branch and preserves selected failures")
    func conjunction() throws {
        var visits: [String] = []
        let skipped = try _NativeMachineOperations.booleanAnd({
            visits.append("left")
            return false
        }, {
            visits.append("right")
            throw NativeMachineEvaluationError.divisionByZero
        })
        #expect(!skipped)
        #expect(visits == ["left"])

        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.booleanAnd({ true }, {
                throw NativeMachineEvaluationError.divisionByZero
            })
        }
        var rightRan = false
        #expect(throws: NativeMachineEvaluationError.negativeModuloDivisor(-1)) {
            try _NativeMachineOperations.booleanAnd({
                throw NativeMachineEvaluationError.negativeModuloDivisor(-1)
            }, {
                rightRan = true
                return true
            })
        }
        #expect(!rightRan)
        #expect(try _NativeMachineOperations.booleanAnd({ true }, { true }))
    }

    @Test("Disjunction skips a true right branch and preserves selected failures")
    func disjunction() throws {
        var visits: [String] = []
        let skipped = try _NativeMachineOperations.booleanOr({
            visits.append("left")
            return true
        }, {
            visits.append("right")
            throw NativeMachineEvaluationError.divisionByZero
        })
        #expect(skipped)
        #expect(visits == ["left"])

        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.booleanOr({ false }, {
                throw NativeMachineEvaluationError.divisionByZero
            })
        }
        var rightRan = false
        #expect(throws: NativeMachineEvaluationError.negativeModuloDivisor(-1)) {
            try _NativeMachineOperations.booleanOr({
                throw NativeMachineEvaluationError.negativeModuloDivisor(-1)
            }, {
                rightRan = true
                return false
            })
        }
        #expect(!rightRan)
        let falseValue = try _NativeMachineOperations.booleanOr({ false }, { false })
        #expect(!falseValue)
    }

    @Test("Negation evaluates one operand and preserves its failure")
    func negation() throws {
        var visits = 0
        #expect(try _NativeMachineOperations.booleanNot {
            visits += 1
            return false
        })
        #expect(visits == 1)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.booleanNot {
                throw NativeMachineEvaluationError.divisionByZero
            }
        }
    }

    @Test("Conditional evaluates only the selected value branch")
    func conditional() throws {
        for selected in [false, true] {
            var visits: [String] = []
            let result = try _NativeMachineOperations.booleanIf({
                visits.append("condition")
                return selected
            }, ifTrue: {
                visits.append("yes")
                return true
            }, ifFalse: {
                visits.append("no")
                return false
            })
            #expect(result == selected)
            #expect(visits == ["condition", selected ? "yes" : "no"])
        }
        var selectedBranchRan = false
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.booleanIf({
                throw NativeMachineEvaluationError.divisionByZero
            }, ifTrue: {
                selectedBranchRan = true
                return true
            }, ifFalse: {
                selectedBranchRan = true
                return false
            })
        }
        #expect(!selectedBranchRan)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.booleanIf({ true }, ifTrue: {
                throw NativeMachineEvaluationError.divisionByZero
            }, ifFalse: { false })
        }
    }
}
