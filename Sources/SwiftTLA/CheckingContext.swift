/// Run-owned data that does not participate in model-state identity.
public struct CheckingContext<Registers: Sendable>: Sendable {
    public var registers: Registers
    public private(set) var level: Int = 0

    public init(registers: Registers) {
        self.registers = registers
    }

    package mutating func advanceBreadthFirstLevel() throws {
        let (next, overflow) = level.addingReportingOverflow(1)
        guard !overflow else { throw ExplorationError.levelOverflow }
        level = next
    }
}
