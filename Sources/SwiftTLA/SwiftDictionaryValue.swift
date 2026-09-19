public protocol FormalDictionaryValue: TLAValueType {
    associatedtype Key: TLAValueType & Hashable
    associatedtype Value: TLAValueType
}

extension Dictionary: FormalDictionaryValue where Key: TLAValueType, Value: TLAValueType {}

extension TypedExpression where ExpressionValue: FormalDictionaryValue {
    public var keys: Expr<Set<ExpressionValue.Key>> { Expr(.domain(stateExpr)) }
}

extension Dictionary: TLAValueType, TLAValueConvertible, TypedExpression, StateExprConvertible
where Key: TLAValueType, Value: TLAValueType {
    public static var defaultValue: Self { [:] }
    public static var formalValueShape: FormalValueShape {
        .function(key: Key.formalValueShape, value: Value.formalValueShape)
    }

    public var sourceIssue: SourceModelIssue? {
        for (key, value) in self {
            if let issue = key.sourceIssue ?? value.sourceIssue { return issue }
        }
        guard Set(keys.map(\.tlaValue)).count == count else {
            return .formalDeclaration(kind: "dictionary", name: nil,
                problem: "distinct Swift keys have the same formal value")
        }
        return nil
    }

    public var tlaValue: TLAValue {
        .function(reduce(into: [:]) { $0[$1.key.tlaValue] = $1.value.tlaValue })
    }

    public init?(formalValue: TLAValue) {
        guard case .function(let entries) = formalValue else { return nil }
        self.init()
        for (rawKey, rawValue) in entries {
            guard let key = Key(formalValue: rawKey), key.preservesFormalValue(rawKey),
                  let value = Value(formalValue: rawValue), value.preservesFormalValue(rawValue),
                  updateValue(value, forKey: key) == nil else { return nil }
        }
    }
}
