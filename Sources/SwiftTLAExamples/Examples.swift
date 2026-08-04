import SwiftTLA

public struct ExampleDescription: Hashable, Identifiable {
    public var id: String { name }
    public let name: String; public let spec: TLASpec; public let expectedStates: Int
    public let source: String; public let about: String
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func == (a: ExampleDescription, b: ExampleDescription) -> Bool { a.name == b.name }
}

public enum Examples {
    public static let all: [ExampleDescription] = [
        .init(name: "Lock", spec: Lock.spec, expectedStates: 2, source: "internal", about: "Lock"),
    ]
}
