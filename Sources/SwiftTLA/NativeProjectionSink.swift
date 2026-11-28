/// Record members are evaluated in declaration order for diagnostics and byte order for capture.
@_documentation(visibility: internal)
public struct _NativeProjectionRecord: Sendable {
    public let names: [String]
    package let canonicalOrder: [Int]?

    public init(_ names: [String]) {
        self.names = names
        let tokens = names.compactMap(TLAStateProjection.Token.init(validating:))
        canonicalOrder = tokens.count == names.count && Set(tokens).count == names.count
            ? names.indices.sorted { names[$0].utf8.lexicographicallyPrecedes(names[$1].utf8) } : nil
    }
}

/// Generated code supplies the typed values. Each sink owns its representation.
@_documentation(visibility: internal)
public protocol _NativeProjectionSink: Sendable {
    mutating func projected(_ value: TLAValue) throws
    mutating func record(_ layout: _NativeProjectionRecord, _ field: (Int, inout Self) throws -> Void) throws
    mutating func members<C: Collection & Sendable>(_ members: C, _ write: (C.Element, inout Self) throws -> Void) throws where C.Element: Sendable
    mutating func constantFunction<S: Sequence, K, V>(_ entries: S, key: (K) throws -> TLAValue,
        value: (V, inout Self) throws -> Void) throws where S.Element == (key: K, value: V)
    mutating func field<T>(_ token: TLAStateProjection.Token, _ value: T, _ write: (T, inout Self) throws -> Void) throws
}

@_documentation(visibility: internal)
public struct _NativeProjectionCollector: _NativeProjectionSink {
    private var entries: [TLAStateProjection.Entry] = []
    private var value: TLAValue?

    public init() {}
    private static func project<T>(_ input: T, _ write: (T, inout Self) throws -> Void) throws -> TLAValue {
        var child = Self()
        try write(input, &child)
        guard let value = child.value else { throw TLAStateProjectionDiagnostic.invalidValue(path: "missing projected value") }
        return value
    }
    public mutating func projected(_ value: TLAValue) { self.value = value }
    public mutating func record(_ layout: _NativeProjectionRecord, _ field: (Int, inout Self) throws -> Void) throws {
        value = try .record(TLARecord(layout.names.enumerated().map { index, name in
            .init(name, try Self.project(index, field))
        }))
    }
    public mutating func members<C: Collection & Sendable>(_ members: C, _ write: (C.Element, inout Self) throws -> Void) throws where C.Element: Sendable {
        value = try TLAStateProjection.losslessSet(members) { try Self.project($0, write) }
    }
    public mutating func constantFunction<S: Sequence, K, V>(_ entries: S, key: (K) throws -> TLAValue,
        value write: (V, inout Self) throws -> Void) throws where S.Element == (key: K, value: V) {
        var result: [TLAValue: TLAValue] = [:]
        for entry in entries {
            let index = try key(entry.key)
            guard try result.updateValue(Self.project(entry.value, write), forKey: index) == nil else {
                throw TLAStateProjectionDiagnostic.invalidValue(path: "duplicate formal function key")
            }
        }
        value = .function(result)
    }
    public mutating func field<T>(_ token: TLAStateProjection.Token, _ value: T, _ write: (T, inout Self) throws -> Void) throws {
        entries.append(.init(token: token, value: try Self.project(value, write)))
    }
    public func projection() throws -> TLAStateProjection { try TLAStateProjection(validating: entries) }
}
