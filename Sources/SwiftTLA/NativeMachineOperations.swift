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
    case checkingContextRequired
    case noSatisfyingChoice
    case collectionCardinalityOverflow(CollectionOperation, operands: [Int])
    case powerSetTooLarge(actualCount: Int, maximumCount: Int)
    case nonEnumerableSequenceDomain
    case nonEnumerableIntegerDomain
    case integerOverflow(IntegerOperation, operands: [Int])
    case divisionByZero
    case negativeModuloDivisor(Int)
    case indexOutOfBounds(index: Int, count: Int)
    case invalidSequenceDomain(keys: [Int])
    case emptySequence
    case functionArgumentOutsideDomain
    case tupleIndexOutsideDomain(Int)
    case recordFieldUnavailable(_NativeString)
    case invalidRandomSubsetCount(Int)
    case emptyRandomElementDomain

    /// Execution limits and missing context do not establish a model failure.
    @_documentation(visibility: internal)
    public var isModelEvaluationFailure: Bool {
        switch self {
        case .nonEnumerableIntegerDomain, .nonEnumerableSequenceDomain,
             .collectionCardinalityOverflow, .powerSetTooLarge,
             .recursionDepthExceeded, .checkingContextRequired:
            false
        case .noMatchingCase, .noSatisfyingChoice, .integerOverflow,
             .divisionByZero, .negativeModuloDivisor, .indexOutOfBounds,
             .invalidSequenceDomain, .emptySequence, .functionArgumentOutsideDomain,
             .tupleIndexOutsideDomain, .recordFieldUnavailable,
             .invalidRandomSubsetCount, .emptyRandomElementDomain:
            true
        }
    }

    public var description: String {
        switch self {
        case .integerOverflow(let operation, let operands):
            return "Integer \(operation.rawValue) overflowed for \(operands.map(String.init).joined(separator: ", "))"
        case .recursionDepthExceeded(let limit): return "Recursive operator depth exceeds \(limit)"
        case .noMatchingCase: return "No CASE branch matched"
        case .checkingContextRequired: return "This expression requires a checking run context"
        case .noSatisfyingChoice: return "No value satisfies CHOOSE"
        case .collectionCardinalityOverflow(let operation, let operands):
            return "Collection \(operation.rawValue) cardinality overflowed for \(operands.map(String.init).joined(separator: ", "))"
        case .powerSetTooLarge(let actual, let maximum):
            return "Power set input has \(actual) elements; maximum representable input is \(maximum)"
        case .nonEnumerableSequenceDomain:
            return "Seq over a nonempty set cannot be exhaustively enumerated"
        case .nonEnumerableIntegerDomain:
            return "The mathematical integer domain cannot be exhaustively enumerated"
        case .divisionByZero: return "Division by zero"
        case .negativeModuloDivisor(let divisor): return "Modulo requires a positive divisor; received \(divisor)"
        case .indexOutOfBounds(let index, let count): return "Index \(index) out of bounds (1..\(count))"
        case .invalidSequenceDomain(let keys): return "Sequence function requires domain 1...count; received \(keys)"
        case .emptySequence: return "Expected a nonempty sequence"
        case .functionArgumentOutsideDomain: return "Function argument is outside its domain"
        case .tupleIndexOutsideDomain(let index): return "Tuple index \(index) is outside its domain"
        case .recordFieldUnavailable(let field): return "Record field \(field) is unavailable"
        case .invalidRandomSubsetCount(let count): return "RandomSubset requires a nonnegative count; received \(count)"
        case .emptyRandomElementDomain: return "RandomElement requires a nonempty domain"
        }
    }
}

/// A generated action failed while evaluating a successor, before committing state.
public struct MachineActionEvaluationFailure<Action: Hashable & Sendable>: Error, Equatable, Sendable {
    public let action: Action
    public let reason: NativeMachineEvaluationError

    public init(action: Action, reason: NativeMachineEvaluationError) {
        self.action = action
        self.reason = reason
    }
}

/// A reached initial failure with an immutable prefix for formal projection.
public struct InitialEvaluationFailure: Sendable {
    public enum Site: Equatable, Sendable {
        case initializer(Int)
        case selectedInvariant

        var initializerOrdinal: Int? {
            if case .initializer(let ordinal) = self { return ordinal }
            return nil
        }
    }

    public let site: Site
    public let failure: NativeMachineEvaluationError
    private let projectBefore: @Sendable () throws -> TLAStateProjection

    public init(site: Site, failure: NativeMachineEvaluationError,
                projectingBefore: @escaping @Sendable () throws -> TLAStateProjection) {
        self.site = site
        self.failure = failure
        self.projectBefore = projectingBefore
    }

    /// Convert the captured prefix only at the formal evidence boundary.
    public func formalBindingsBeforeFailure() throws -> TLAStateProjection {
        try projectBefore()
    }
}

/// Successful alternatives and the model failures encountered while visiting initial branches.
public struct InitialEvaluationOutcomes<State: Sendable>: Sendable {
    public let states: [State]
    public let failures: [InitialEvaluationFailure]

    public var firstFailure: NativeMachineEvaluationError? { failures.first?.failure }
    public var firstFailureInitializerOrdinal: Int? { failures.first?.site.initializerOrdinal }

    public init(states: [State], failures: [InitialEvaluationFailure]) {
        self.states = states
        self.failures = failures
    }
}

/// Keep generated outcome construction in library scope, away from caller initializers.
@_documentation(visibility: internal)
public func _nativeInitialOutcomes<State: Sendable>(
    states: [State], failures: [InitialEvaluationFailure]
) -> InitialEvaluationOutcomes<State> {
    InitialEvaluationOutcomes(states: states, failures: failures)
}

/// Keep generated outcome reads and conversion outside caller specializations.
@_documentation(visibility: internal)
public func _mapNativeInitialOutcomes<Source: Sendable, Result: Sendable>(
    _ outcomes: InitialEvaluationOutcomes<Source>, _ transform: (Source) -> Result
) -> InitialEvaluationOutcomes<Result> {
    _nativeInitialOutcomes(states: _mapNativeOutcomes(outcomes.states, transform), failures: outcomes.failures)
}

/// Keep generated first-failure selection and state reads in library scope.
@_documentation(visibility: internal)
public func _completeNativeInitialOutcomes<State: Sendable>(
    _ outcomes: InitialEvaluationOutcomes<State>
) throws -> [State] {
    if let failure = outcomes.firstFailure { throw failure }
    return outcomes.states
}

/// Bind generated addition in library scope, away from caller extensions.
@_documentation(visibility: internal)
public func _nativeIntAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
    try _NativeMachineOperations.add(lhs, rhs)
}

/// Keep generated collection mutation in library scope, away from caller overloads.
@_documentation(visibility: internal)
public func _appendNativeOutcome<Outcome: Sendable>(_ outcomes: inout [Outcome], _ outcome: Outcome) {
    outcomes.append(outcome)
}

/// Keep generated state conversion in library scope, away from caller overloads.
@_documentation(visibility: internal)
public func _mapNativeOutcomes<Source: Sendable, Result: Sendable>(
    _ outcomes: [Source], _ transform: (Source) -> Result
) -> [Result] {
    outcomes.map(transform)
}

/// Select one generated outcome without calling caller collection overloads.
@_documentation(visibility: internal)
public func _singleNativeOutcome<Outcome: Sendable>(
    _ outcomes: [Outcome], missing: GeneratedMachineError, ambiguous: GeneratedMachineError
) throws -> Outcome {
    guard let first = outcomes.first else { throw missing }
    guard outcomes.count == 1 else { throw ambiguous }
    return first
}

/// Keep formal token indexing in library scope, away from caller subscripts.
@_documentation(visibility: internal)
public func _nativeFormalProjectionToken(
    _ tokens: [TLAStateProjection.Token], at index: Int
) -> TLAStateProjection.Token {
    tokens[index]
}

/// Keep generated failure sites independent of caller Optional operations.
@_documentation(visibility: internal)
public func _nativeInitialFailureSite(_ ordinal: Int?) -> InitialEvaluationFailure.Site {
    guard let ordinal else { return .selectedInvariant }
    return .initializer(ordinal)
}

/// Keep generated Int selection independent of caller Boolean and equality overloads.
@_documentation(visibility: internal)
public func _nativeIntInitialMatches(_ selected: Int?, _ value: Int) -> Bool {
    guard let selected else { return true }
    return selected == value
}

/// Handle a model failure within one initial branch without abandoning other branches.
/// Enumeration, capacity, call-depth and missing-context errors propagate without a completed branch result.
@_documentation(visibility: internal)
public func _visitNativeInitialBranch(
    _ visit: () throws -> Void,
    onEvaluationFailure: (NativeMachineEvaluationError) -> Void
) throws {
    do {
        try visit()
    } catch let failure as NativeMachineEvaluationError {
        guard failure.isModelEvaluationFailure else { throw failure }
        onEvaluationFailure(failure)
    } catch let failure as EvalError {
        guard let native = failure.nativeFailure else { throw failure }
        guard native.isModelEvaluationFailure else { throw failure }
        onEvaluationFailure(native)
    }
}

/// Value operations emitted by the native machine generator.
@_documentation(visibility: internal)
public enum _NativeMachineOperations: Sendable {
    public typealias StateHasher = Swift.Hasher

    public static let maximumRecursiveDepth = 4_096

    @inlinable
    public static func mergeUpdate<Value: Equatable & Sendable>(
        _ current: inout Value?, _ incoming: Value?,
        equivalent: @Sendable (Value, Value) -> Bool = { $0 == $1 }
    ) -> Bool {
        guard let incoming else { return true }
        if let current, !equivalent(current, incoming) { return false }
        current = incoming
        return true
    }

    public static func initialCandidates<Value: Sendable>(
        selecting selected: Value?, enumerate: () throws -> [Value], contains: (Value) throws -> Bool
    ) throws -> [Value] {
        if let selected { return try contains(selected) ? [selected] : [] }
        return try enumerate()
    }

    public static func checkedProjection<Source: TLAValueType, Target: TLAValueType>(
        _ source: Source
    ) throws -> Target {
        let formal = source.tlaValue
        guard let target = Target(formalValue: formal), target.preservesFormalValue(formal) else {
            throw TLAStateProjectionDiagnostic.invalidValue(path: String(reflecting: Target.self))
        }
        return target
    }

    public static func integerSet() throws -> Set<Int> {
        throw NativeMachineEvaluationError.nonEnumerableIntegerDomain
    }

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
        guard let bounds = try integerRangeBounds(lower, upper) else { return [] }
        return Set(bounds)
    }

    public static func integerRangeBounds(_ lower: Int, _ upper: Int) throws -> ClosedRange<Int>? {
        guard lower <= upper else { return nil }
        let distance = upper.subtractingReportingOverflow(lower)
        guard !distance.overflow, !distance.partialValue.addingReportingOverflow(1).overflow else {
            throw NativeMachineEvaluationError.collectionCardinalityOverflow(.integerRange, operands: [lower, upper])
        }
        return lower...upper
    }

    public static func sequenceSet<Element: Hashable & Sendable>(_ values: Set<Element>) throws -> Set<[Element]> {
        try sequenceSet(values, forming: Set<[Element]>.self)
    }

    public static func sequenceSet<Values: Collection & Sendable, Result: SetAlgebra & Sendable>(
        _ values: Values, forming: Result.Type
    ) throws -> Result where Values.Element: Sendable, Result.Element == [Values.Element] {
        guard values.isEmpty else { throw NativeMachineEvaluationError.nonEnumerableSequenceDomain }
        return Result([[]])
    }

    public static func powerSet<Element: Hashable & Sendable>(_ values: Set<Element>) throws -> Set<Set<Element>> {
        try powerSet(values, forming: Set<Set<Element>>.self)
    }

    public static func powerSet<Values: Collection & SetAlgebra & Sendable, Result: SetAlgebra & Sendable>(
        _ values: Values, forming: Result.Type
    ) throws -> Result where Result.Element == Values {
        guard values.count < Int.bitWidth - 1 else {
            throw NativeMachineEvaluationError.powerSetTooLarge(actualCount: values.count, maximumCount: Int.bitWidth - 2)
        }
        let members = Array(values)
        return Result((0..<(1 << members.count)).map { mask in
            Values(members.enumerated().compactMap { index, member in
                mask & (1 << index) == 0 ? nil : member
            })
        })
    }

    public static func functionSet<Key: Hashable & Sendable, Value: Hashable & Sendable>(
        _ domain: Set<Key>, _ range: Set<Value>
    ) throws -> Set<[Key: Value]> {
        try functionSet(domain, range, forming: Set<[Key: Value]>.self)
    }

    public static func functionSet<Domain: Collection & Sendable, Range: Collection & Sendable, Result: SetAlgebra & Sendable>(
        _ domain: Domain, _ range: Range, forming: Result.Type
    ) throws -> Result where Domain.Element: Sendable, Range.Element: Sendable,
        Result.Element: _NativeFunctionStorage & Sendable,
        Result.Element.Key == Domain.Element, Result.Element.Value == Range.Element {
        try validateFunctionSetCardinality(domainCount: domain.count, rangeCount: range.count)
        var functions: [Result.Element] = [.init()]
        for key in domain {
            functions = functions.flatMap { partial in
                range.map { value in
                    var next = partial
                    next.updateValue(value, forKey: key)
                    return next
                }
            }
        }
        return Result(functions)
    }

    public static func randomSubset<Element: Hashable & Sendable>(
        upTo count: Int, from values: Set<Element>
    ) throws -> Set<Element> {
        try validateRandomSubsetCount(count)
        return Set(values.shuffled().prefix(count))
    }

    public static func randomSubset<Identity: _NativeSetIdentity>(
        upTo count: Int, from values: _NativeSet<Identity>
    ) throws -> _NativeSet<Identity> {
        try validateRandomSubsetCount(count)
        return _NativeSet(values.shuffled().prefix(count))
    }

    public static func randomSubsetInitialSupport<Identity: _NativeSetIdentity>(
        upTo count: Int, from values: _NativeSet<Identity>
    ) throws -> _NativeSet<Identity> {
        try validateRandomSubsetCount(count)
        return count == 0 ? [] : values
    }

    public static func randomElement<Identity: _NativeSetIdentity>(
        from values: _NativeSet<Identity>
    ) throws -> Identity.Element {
        guard let value = values.randomElement() else {
            throw NativeMachineEvaluationError.emptyRandomElementDomain
        }
        return value
    }

    public static func randomSubsetInitialSupport<Element: Hashable & Sendable>(
        upTo count: Int, from values: Set<Element>
    ) throws -> Set<Element> {
        try validateRandomSubsetCount(count)
        return count == 0 ? [] : values
    }

    public static func randomFunctionInitialSupport<Key: Hashable & Sendable, Value: Hashable & Sendable>(
        upTo count: Int, from domain: Set<Key>, to range: Set<Value>
    ) throws -> Set<[Key: Value]> {
        try randomFunctionInitialSupport(upTo: count, from: domain, to: range, forming: Set<[Key: Value]>.self)
    }

    public static func randomFunctionInitialSupport<Domain: Collection & Sendable, Range: Collection & Sendable, Result: SetAlgebra & Sendable>(
        upTo count: Int, from domain: Domain, to range: Range, forming: Result.Type
    ) throws -> Result where Domain.Element: Sendable, Range.Element: Sendable,
        Result.Element: _NativeFunctionStorage & Sendable,
        Result.Element.Key == Domain.Element, Result.Element.Value == Range.Element {
        try validateRandomSubsetCount(count)
        guard count > 0 else { return Result() }
        let maximum = 1_000_000
        var cardinality = 1
        for _ in domain {
            let product = cardinality.multipliedReportingOverflow(by: range.count)
            if product.overflow {
                throw ExplorationError.initialStateLimitExceeded(
                    actualCount: Int.max, maximumCount: maximum)
            }
            cardinality = product.partialValue
        }
        guard cardinality <= maximum else {
            throw ExplorationError.initialStateLimitExceeded(
                actualCount: cardinality, maximumCount: maximum)
        }
        return try functionSet(domain, range, forming: forming)
    }

    public static func validateRandomSubsetCount(_ count: Int) throws {
        guard count >= 0 else { throw NativeMachineEvaluationError.invalidRandomSubsetCount(count) }
    }

    public static func randomElement<Element: Hashable & Sendable>(
        from values: Set<Element>
    ) throws -> Element {
        guard let value = values.randomElement() else {
            throw NativeMachineEvaluationError.emptyRandomElementDomain
        }
        return value
    }

    public static func randomFunctionSubset<Key: Hashable & Sendable, Value: Hashable & Sendable>(
        upTo count: Int, from domain: Set<Key>, to range: Set<Value>
    ) throws -> Set<[Key: Value]> {
        try randomFunctionSubset(upTo: count, from: domain, to: range, forming: Set<[Key: Value]>.self)
    }

    public static func randomFunctionSubset<Domain: Collection & Sendable, Range: Collection & Sendable, Result: SetAlgebra & Collection & Sendable>(
        upTo count: Int, from domain: Domain, to range: Range, forming: Result.Type
    ) throws -> Result where Domain.Element: Sendable, Range.Element: Sendable,
        Result.Element: _NativeFunctionStorage & Sendable,
        Result.Element.Key == Domain.Element, Result.Element.Value == Range.Element {
        try validateRandomSubsetCount(count)
        guard count > 0 else { return Result() }
        guard !domain.isEmpty else { return Result([Result.Element()]) }
        guard !range.isEmpty else { return Result() }

        var cardinality = 1
        var exceedsCount = false
        for _ in domain {
            let product = cardinality.multipliedReportingOverflow(by: range.count)
            if product.overflow {
                exceedsCount = true
                break
            }
            cardinality = product.partialValue
            if cardinality > count {
                exceedsCount = true
                break
            }
        }
        if !exceedsCount {
            return try functionSet(domain, range, forming: forming)
        }

        let keys = Array(domain)
        let values = Array(range)
        var chosen = Result()
        while chosen.count < count {
            try Task<Never, Never>.checkCancellation()
            var function = Result.Element()
            for key in keys { function.updateValue(values.randomElement()!, forKey: key) }
            chosen.insert(function)
        }
        return chosen
    }

    /// Reject unrepresentable cardinalities before enumeration allocates the function space.
    public static func validateFunctionSetCardinality(domainCount: Int, rangeCount: Int) throws {
        var cardinality = 1
        for _ in 0..<domainCount {
            let product = cardinality.multipliedReportingOverflow(by: rangeCount)
            guard !product.overflow else {
                throw NativeMachineEvaluationError.collectionCardinalityOverflow(
                    .functionSet, operands: [domainCount, rangeCount])
            }
            cardinality = product.partialValue
        }
    }

    /// Visit independent alternatives, retaining successes and the first model failure.
    /// Execution limits propagate without visiting later alternatives.
    public static func visitAlternatives<Alternative: Sendable, Update: Sendable>(
        _ alternatives: [Alternative],
        emit: (Update) throws -> Void,
        visit: (Alternative, (Update) throws -> Void) throws -> Void
    ) throws {
        var firstFailure: NativeMachineEvaluationError?
        for alternative in alternatives {
            var updates: [Update] = []
            do {
                try visit(alternative) { updates.append($0) }
            } catch let failure as NativeMachineEvaluationError where failure.isModelEvaluationFailure {
                if firstFailure == nil { firstFailure = failure }
            }
            for update in updates { try emit(update) }
        }
        if let firstFailure { throw firstFailure }
    }

    public static func visitConditional(
        _ condition: () throws -> Bool,
        ifTrue: () throws -> Void,
        ifFalse: () throws -> Void
    ) throws {
        let selected = try condition()
        if selected { try ifTrue() } else { try ifFalse() }
    }

    public static func booleanAnd(_ left: () throws -> Bool, _ right: () throws -> Bool) throws -> Bool {
        guard try left() else { return false }
        return try right()
    }

    public static func booleanOr(_ left: () throws -> Bool, _ right: () throws -> Bool) throws -> Bool {
        if try left() { return true }
        return try right()
    }

    public static func booleanNot(_ value: () throws -> Bool) throws -> Bool {
        !(try value())
    }

    public static func booleanIf(
        _ condition: () throws -> Bool,
        ifTrue: () throws -> Bool,
        ifFalse: () throws -> Bool
    ) throws -> Bool {
        if try condition() { return try ifTrue() }
        return try ifFalse()
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

    public static func sequenceAppend<Element: Sendable>(_ sequence: [Element], _ element: Element) -> [Element] {
        var result = sequence
        result.append(element)
        return result
    }

    public static func sequenceConcatenate<Element: Sendable>(_ left: [Element], _ right: [Element]) -> [Element] {
        var result = left
        result.append(contentsOf: right)
        return result
    }

    public static func sequenceRemoving<Element: Sendable>(_ sequence: [Element], at index: Int) throws -> [Element] {
        guard index >= 1, index <= sequence.count else {
            throw NativeMachineEvaluationError.indexOutOfBounds(index: index, count: sequence.count)
        }
        var result = sequence
        result.remove(at: index - 1)
        return result
    }

    public static func sequencePrefix<Element: Sendable>(_ sequence: [Element], length: Int) throws -> [Element] {
        guard length <= sequence.count else {
            throw NativeMachineEvaluationError.indexOutOfBounds(index: length, count: sequence.count)
        }
        return Array(sequence.prefix(Swift.max(0, length)))
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

    public static func functionValue<KeyIdentity: _NativeSetIdentity, ValueIdentity: _NativeSetIdentity>(
        _ function: _NativeDictionary<KeyIdentity, ValueIdentity>, at key: KeyIdentity.Element
    ) throws -> ValueIdentity.Element {
        guard let value = function[key] else { throw NativeMachineEvaluationError.functionArgumentOutsideDomain }
        return value
    }

    public static func functionDomain<Key: Hashable & Sendable, Value: Sendable>(_ function: [Key: Value]) -> Set<Key> {
        Set(function.keys)
    }

    public static func functionDomain<KeyIdentity: _NativeSetIdentity, ValueIdentity: _NativeSetIdentity>(
        _ function: _NativeDictionary<KeyIdentity, ValueIdentity>
    ) -> _NativeSet<KeyIdentity> {
        function.keys
    }

    public static func functionUpdated<Key: Hashable & Sendable, Value: Sendable>(_ function: [Key: Value], at key: Key, to value: Value) -> [Key: Value] {
        guard function[key] != nil else { return function }
        var updated = function
        updated[key] = value
        return updated
    }

    public static func functionUpdated<KeyIdentity: _NativeSetIdentity, ValueIdentity: _NativeSetIdentity>(
        _ function: _NativeDictionary<KeyIdentity, ValueIdentity>, at key: KeyIdentity.Element,
        to value: ValueIdentity.Element
    ) -> _NativeDictionary<KeyIdentity, ValueIdentity> {
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
