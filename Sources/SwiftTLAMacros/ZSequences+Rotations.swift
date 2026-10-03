import SwiftTLA

extension ZSequences {
    @_TLARecordValue
    public struct Rotation<Element: TLAValueType>: Hashable, Sendable {
        public let shift: Int
        public let seq: ZeroBasedSequence<Element>
    }

    public static func rotations<Element: TLAValueType>(
        of sequence: some TypedExpression<ZeroBasedSequence<Element>>
    ) -> Expr<Set<Rotation<Element>>> {
        Expr(.recursiveCall("Rotations", [sequence.stateExpr]))
    }
}
