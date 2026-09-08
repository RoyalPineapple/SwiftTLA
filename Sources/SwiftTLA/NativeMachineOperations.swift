/// A failed value operation while executing a generated Swift machine.
public enum NativeMachineEvaluationError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum IntegerOperation: String, Equatable, Sendable {
        case addition
        case subtraction
        case multiplication
        case division
        case negation
        case summation
    }

    public enum CollectionOperation: String, Equatable, Sendable {
        case integerRange
        case functionSet
    }

    case recursionDepthExceeded(Int)
    case noMatchingCase
    case noSatisfyingChoice
    case conflictingAssignment(variable: String)
    case collectionCardinalityOverflow(CollectionOperation, operands: [Int])
    case powerSetTooLarge(actualCount: Int, maximumCount: Int)
    case integerOverflow(IntegerOperation, operands: [Int])
    case divisionByZero
    case negativeModuloDivisor(Int)
    case indexOutOfBounds(index: Int, count: Int)
    case invalidSequenceDomain(keys: [Int])
    case emptySequence
    case functionArgumentOutsideDomain
    case tupleIndexOutsideDomain(Int)
    case recordFieldUnavailable(String)

    public var description: String {
        switch self {
        case .integerOverflow(let operation, let operands):
            return "Integer \(operation.rawValue) overflowed for \(operands.map(String.init).joined(separator: ", "))"
        case .recursionDepthExceeded(let limit): return "Recursive operator depth exceeds \(limit)"
        case .noMatchingCase: return "No CASE branch matched"
        case .noSatisfyingChoice: return "No value satisfies CHOOSE"
        case .conflictingAssignment(let variable): return "Conflicting assignments to \(variable)"
        case .collectionCardinalityOverflow(let operation, let operands):
            return "Collection \(operation.rawValue) cardinality overflowed for \(operands.map(String.init).joined(separator: ", "))"
        case .powerSetTooLarge(let actual, let maximum):
            return "Power set input has \(actual) elements; maximum representable input is \(maximum)"
        case .divisionByZero: return "Division by zero"
        case .negativeModuloDivisor(let divisor): return "Modulo requires a positive divisor; received \(divisor)"
        case .indexOutOfBounds(let index, let count): return "Index \(index) out of bounds (1..\(count))"
        case .invalidSequenceDomain(let keys): return "Sequence function requires domain 1...count; received \(keys)"
        case .emptySequence: return "Expected a nonempty sequence"
        case .functionArgumentOutsideDomain: return "Function argument is outside its domain"
        case .tupleIndexOutsideDomain(let index): return "Tuple index \(index) is outside its domain"
        case .recordFieldUnavailable(let field): return "Record field \(field) is unavailable"
        }
    }
}

/// Value operations emitted by the native machine generator.
@_documentation(visibility: internal)
public enum _NativeMachineOperations: Sendable {
    public static let maximumRecursiveDepth = 4_096

    public static func add(_ lhs: Int, _ rhs: Int) throws -> Int {
        try checked(lhs.addingReportingOverflow(rhs), operation: .addition, operands: [lhs, rhs])
    }

    public static func subtract(_ lhs: Int, _ rhs: Int) throws -> Int {
        try checked(lhs.subtractingReportingOverflow(rhs), operation: .subtraction, operands: [lhs, rhs])
    }

    public static func multiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        try checked(lhs.multipliedReportingOverflow(by: rhs), operation: .multiplication, operands: [lhs, rhs])
    }

    public static func divide(_ dividend: Int, _ divisor: Int) throws -> Int {
        guard divisor != 0 else { throw NativeMachineEvaluationError.divisionByZero }
        let quotient = try checked(
            dividend.dividedReportingOverflow(by: divisor), operation: .division, operands: [dividend, divisor]
        )
        // A nonzero remainder with opposite signs rounds the quotient down.
        // Such a quotient cannot be Int.min, so subtracting one is representable.
        return (dividend < 0) != (divisor < 0) && dividend % divisor != 0 ? quotient - 1 : quotient
    }

    public static func modulo(_ dividend: Int, _ divisor: Int) throws -> Int {
        guard divisor != 0 else { throw NativeMachineEvaluationError.divisionByZero }
        guard divisor > 0 else { throw NativeMachineEvaluationError.negativeModuloDivisor(divisor) }
        let remainder = dividend % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }

    public static func negate(_ operand: Int) throws -> Int {
        try checked(0.subtractingReportingOverflow(operand), operation: .negation, operands: [operand])
    }

    public static func sum(_ values: [Int]) throws -> Int {
        let operands = values.sorted()
        var negative = operands.filter { $0 < 0 }
        var nonnegative = operands.filter { $0 >= 0 }
        while let lhs = negative.last, let rhs = nonnegative.last {
            negative.removeLast()
            nonnegative.removeLast()
            // Opposite signs cannot overflow. Cancel them before summing values
            // of one sign, so an intermediate order cannot cause false overflow.
            let combined = lhs + rhs
            if combined < 0 { negative.append(combined) } else { nonnegative.append(combined) }
        }
        return try (negative + nonnegative).reduce(0) { total, value in
            try checked(total.addingReportingOverflow(value), operation: .summation, operands: operands)
        }
    }

    public static func integerRange(_ lower: Int, _ upper: Int) throws -> Set<Int> {
        guard lower <= upper else { return [] }
        let distance = upper.subtractingReportingOverflow(lower)
        guard !distance.overflow, !distance.partialValue.addingReportingOverflow(1).overflow else {
            throw NativeMachineEvaluationError.collectionCardinalityOverflow(.integerRange, operands: [lower, upper])
        }
        return Set(lower...upper)
    }

    public static func powerSet<Element: Hashable & Sendable>(_ values: Set<Element>) throws -> Set<Set<Element>> {
        guard values.count < Int.bitWidth - 1 else {
            throw NativeMachineEvaluationError.powerSetTooLarge(actualCount: values.count, maximumCount: Int.bitWidth - 2)
        }
        let members = Array(values)
        return Set((0..<(1 << members.count)).map { mask in
            Set(members.enumerated().compactMap { index, member in
                mask & (1 << index) == 0 ? nil : member
            })
        })
    }

    public static func functionSet<Key: Hashable & Sendable, Value: Hashable & Sendable>(
        _ domain: Set<Key>, _ range: Set<Value>
    ) throws -> Set<[Key: Value]> {
        // Preflight the complete product before materializing any partial functions.
        var cardinality = 1
        for _ in domain {
            let product = cardinality.multipliedReportingOverflow(by: range.count)
            guard !product.overflow else {
                throw NativeMachineEvaluationError.collectionCardinalityOverflow(.functionSet, operands: [domain.count, range.count])
            }
            cardinality = product.partialValue
        }
        var functions: [[Key: Value]] = [[:]]
        for key in domain {
            functions = functions.flatMap { partial in
                range.map { value in
                    var next = partial
                    next[key] = value
                    return next
                }
            }
        }
        return Set(functions)
    }

    /// The generator supplies structural order so CHOOSE remains deterministic.
    public static func choose<Element: Sendable>(
        _ orderedValues: [Element], satisfying predicate: (Element) throws -> Bool
    ) throws -> Element {
        for value in orderedValues where try predicate(value) { return value }
        throw NativeMachineEvaluationError.noSatisfyingChoice
    }

    public static func sequenceElements<Element: Sendable>(_ function: [Int: Element]) throws -> [Element] {
        try (0..<function.count).map { offset in
            guard let element = function[offset + 1] else {
                throw NativeMachineEvaluationError.invalidSequenceDomain(keys: function.keys.sorted())
            }
            return element
        }
    }

    public static func sequenceElement<Element: Sendable>(_ sequence: [Element], at index: Int) throws -> Element {
        guard index >= 1, index <= sequence.count else {
            throw NativeMachineEvaluationError.indexOutOfBounds(index: index, count: sequence.count)
        }
        return sequence[index - 1]
    }

    public static func sequenceRemoving<Element: Sendable>(_ sequence: [Element], at index: Int) throws -> [Element] {
        guard index >= 1, index <= sequence.count else {
            throw NativeMachineEvaluationError.indexOutOfBounds(index: index, count: sequence.count)
        }
        var result = sequence
        result.remove(at: index - 1)
        return result
    }

    public static func sequenceFunctionValue<Element: Sendable>(_ sequence: [Element], at index: Int) throws -> Element {
        do { return try sequenceElement(sequence, at: index) }
        catch NativeMachineEvaluationError.indexOutOfBounds {
            throw NativeMachineEvaluationError.tupleIndexOutsideDomain(index)
        }
    }

    public static func sequenceHead<Element: Sendable>(_ sequence: [Element]) throws -> Element {
        guard let first = sequence.first else { throw NativeMachineEvaluationError.emptySequence }
        return first
    }

    public static func sequenceTail<Element: Sendable>(_ sequence: [Element]) throws -> [Element] {
        guard !sequence.isEmpty else { throw NativeMachineEvaluationError.emptySequence }
        return Array(sequence.dropFirst())
    }

    public static func sequenceDomain<Element: Sendable>(_ sequence: [Element]) -> Set<Int> {
        Set(sequence.indices.map { $0 + 1 })
    }

    public static func sequenceUpdated<Element: Sendable>(_ sequence: [Element], at index: Int, to value: Element) -> [Element] {
        guard index >= 1, index <= sequence.count else { return sequence }
        var updated = sequence
        updated[index - 1] = value
        return updated
    }

    public static func functionValue<Key: Hashable & Sendable, Value: Sendable>(_ function: [Key: Value], at key: Key) throws -> Value {
        guard let value = function[key] else { throw NativeMachineEvaluationError.functionArgumentOutsideDomain }
        return value
    }

    public static func functionDomain<Key: Hashable & Sendable, Value: Sendable>(_ function: [Key: Value]) -> Set<Key> {
        Set(function.keys)
    }

    public static func functionUpdated<Key: Hashable & Sendable, Value: Sendable>(_ function: [Key: Value], at key: Key, to value: Value) -> [Key: Value] {
        guard function[key] != nil else { return function }
        var updated = function
        updated[key] = value
        return updated
    }

    private static func checked(
        _ result: (partialValue: Int, overflow: Bool),
        operation: NativeMachineEvaluationError.IntegerOperation,
        operands: @autoclosure () -> [Int]
    ) throws -> Int {
        guard !result.overflow else { throw NativeMachineEvaluationError.integerOverflow(operation, operands: operands()) }
        return result.partialValue
    }
}
