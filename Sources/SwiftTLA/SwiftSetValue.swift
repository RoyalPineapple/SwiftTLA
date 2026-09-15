extension Set: TLAValueType, TLAValueConvertible, TypedExpression, StateExprConvertible where Element: TLAValueType {
    public static var defaultValue: Self { [] }
    public static var formalValueShape: FormalValueShape { .set(Element.formalValueShape) }

    public var sourceIssue: SourceModelIssue? {
        if let issue = lazy.compactMap(\.sourceIssue).first { return issue }
        guard Set<TLAValue>(map(\.tlaValue)).count == count else {
            return .formalDeclaration(kind: "set", name: nil,
                problem: "distinct Swift members have the same formal value")
        }
        return nil
    }

    public var tlaValue: TLAValue { .set(Set<TLAValue>(map(\.tlaValue))) }

    public init?(formalValue: TLAValue) {
        guard case .set(let members) = formalValue else { return nil }
        self.init()
        for member in members {
            guard let value = Element(formalValue: member), value.sourceIssue == nil,
                  value.tlaValue == member, insert(value).inserted else { return nil }
        }
    }
}

extension Set: FormalSetValue where Element: TLAValueType {}
