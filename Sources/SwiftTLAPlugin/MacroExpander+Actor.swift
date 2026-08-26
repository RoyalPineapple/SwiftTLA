import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateActorMembers(model: MacroCompilation) -> [DeclSyntax] {
        let typeName = model.typeName
        let collections = model.compilation.machineSurfacePlan.symmetricCollections
        let collectionParameters = collections.map {
            "\($0.formalName): [\($0.elementType).ID]"
        }.joined(separator: ", ")
        let appendedCollectionParameters = collectionParameters.isEmpty
            ? ""
            : ", \(collectionParameters)"
        let collectionArguments = collections.map {
            "\($0.formalName): \($0.formalName)"
        }.joined(separator: ", ")
        let actionMembers = model.compilation.machineSurfacePlan.actions.isEmpty ? "" : """

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
