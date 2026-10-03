import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    func actorMembers() -> [DeclSyntax] {
        let typeName = model.typeName
        let configurationParameters = machineParameters
        let appendedConfigurationParameters = configurationParameters.isEmpty
            ? ""
            : ", \(configurationParameters)"
        let configurationArguments = machineArguments
        let actionMembers = model.api.actions.isEmpty ? "" : """

                public func isEnabled(_ action: Action) throws -> Bool {
                    try machine.isEnabled(action)
                }

                public func enabledActions() throws -> [Action] {
                    try machine.enabledActions()
                }

                public func send(_ action: Action) throws -> Transition {
                    try machine.send(action)
                }
                """
        return [
            DeclSyntax(stringLiteral: """
            public actor Actor {
                private var machine: \(typeName)

                public init(\(configurationParameters)) throws {
                    machine = try \(typeName).makeMachine(\(configurationArguments))
                }

                public init(_ initial: State\(appendedConfigurationParameters)) throws {
                    machine = try \(typeName).makeMachine(initial\(configurationArguments.isEmpty ? "" : ", \(configurationArguments)"))
                }

                public var state: State {
                    machine.state
                }

                \(actionMembers)
            }
            """)
        ]
    }
}
