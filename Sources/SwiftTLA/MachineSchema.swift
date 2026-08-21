import Foundation

/// A generated description of a machine for tools.
///
/// The macro emits `MachineSchema` from `MachineSurfacePlan` with the typed
/// `State` and `ActionLabel` declarations.
public struct MachineSchema: Sendable, Equatable, Codable {
    public struct Display: Sendable, Equatable, Codable {
        public let name: String

        public init(name: String) {
            self.name = name
        }
    }

    /// Recursive structural schema for values that cross the formal boundary.
    public indirect enum Value: Sendable, Equatable, Codable {
        case integer
        case boolean
        case string
        case set(element: Value)
        case tuple(elements: [Value])
        case record(fields: [RecordField])
        case function(key: Value, value: Value)
        case constant
        /// The declaration has no representative value from which to infer a
        /// deeper shape. Tools must still render the formal value safely.
        case opaque
    }

    public struct RecordField: Sendable, Equatable, Codable {
        public let id: String
        public let display: Display
        public let value: Value

        public init(id: String, display: Display, value: Value) {
            self.id = id
            self.display = display
            self.value = value
        }
    }

    public struct Field: Sendable, Equatable, Codable {
        /// Stable formal identifier used in projections and invocations.
        public let id: String
        public let display: Display
        public let value: Value
        /// The generated Swift-facing type, useful as a display hint only.
        public let swiftType: String

        public init(id: String, display: Display, value: Value, swiftType: String) {
            self.id = id
            self.display = display
            self.value = value
            self.swiftType = swiftType
        }
    }

    public struct Action: Sendable, Equatable, Codable {
        public let id: String
        public let display: Display
        public let parameters: [Field]

        public init(id: String, display: Display, parameters: [Field]) {
            self.id = id
            self.display = display
            self.parameters = parameters
        }
    }

    public let model: Display
    public let state: [Field]
    public let actions: [Action]

    public init(
        model: Display,
        state: [Field],
        actions: [Action]
    ) {
        self.model = model
        self.state = state
        self.actions = actions
    }
}

/// A generated machine that publishes the schema emitted by its macro expansion.
public protocol TLAMachineSchemaProviding: Sendable {
    static var machineSchema: MachineSchema { get }
}
