import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    func actorMembers() -> [DeclSyntax] {
        let typeName = model.typeName
        let collections = model.api.collections
        let collectionParameters = collections.map {
            "\($0.swiftIdentifier) \($0.membersIdentifier): [\($0.elementType).ID]"
        }.joined(separator: ", ")
        let appendedCollectionParameters = collectionParameters.isEmpty
            ? ""
            : ", \(collectionParameters)"
        let collectionArguments = collections.map {
            "\($0.swiftIdentifier): \($0.membersIdentifier)"
        }.joined(separator: ", ")
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

                public init(\(collectionParameters)) throws {
                    machine = try \(typeName).makeMachine(\(collectionArguments))
                }

                public init(_ initial: State\(appendedCollectionParameters)) throws {
                    machine = try \(typeName).makeMachine(initial\(collectionArguments.isEmpty ? "" : ", \(collectionArguments)"))
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
