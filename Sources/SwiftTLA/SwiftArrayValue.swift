extension Array: TLAValueType, TLAValueConvertible, TypedExpression, StateExprConvertible where Element: TLAValueType {
    public static var defaultValue: Self { [] }
    public static var formalValueShape: FormalValueShape { .sequence(Element.formalValueShape) }
    public var sourceIssue: SourceModelIssue? { lazy.compactMap(\.sourceIssue).first }
    public var tlaValue: TLAValue { .tuple(map(\.tlaValue)) }

    public init?(formalValue: TLAValue) {
        guard case .tuple(let members) = formalValue else { return nil }
        self.init()
        for member in members {
            guard let value = Element(formalValue: member), value.sourceIssue == nil,
                  value.tlaValue == member else { return nil }
            append(value)
        }
    }
}

extension Array: FormalTupleValue, FormalSequenceValue where Element: TLAValueType {}
