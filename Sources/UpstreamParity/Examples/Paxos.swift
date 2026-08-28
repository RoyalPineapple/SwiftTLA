import SwiftTLA
import SwiftTLAMacros

package struct PaxosModel: Sendable {
    package enum Acceptor: String, CaseIterable, FiniteTLAValueDomain {
        case only = "a1"

        package static var defaultValue: Self { .only }
        package static let finiteValues = allCases
    }

    package enum PaxosValue: String, CaseIterable, FiniteTLAValueDomain {
        case none = "None"
        case proposed = "v1"

        package static var defaultValue: Self { .none }
        package static let finiteValues = allCases
    }

    private enum MessageKind: String, TLAValueType {
        case phase1a = "1a"
        case phase1b = "1b"
        case phase2a = "2a"
        case phase2b = "2b"

        static var defaultValue: Self { .phase1a }
    }

    private struct Message: TLAValueType, Hashable, Sendable {
        private enum Field: String {
            case kind = "type"
            case acceptor = "acc"
            case ballot = "bal"
            case maximumBallot = "mbal"
            case value = "val"
            case maximumValue = "mval"
        }

        private let record: TLARecord

        private init(record: TLARecord) {
            self.record = record
        }

        static var defaultValue: Self {
            Self(record: TLARecord([
                .init(Field.kind.rawValue, MessageKind.phase1a.tlaValue),
                .init(Field.ballot.rawValue, .int(0)),
            ]))
        }

        init?(formalValue: TLAValue) {
            guard case .record(let record) = formalValue else { return nil }
            let fields = Set(record.fields.compactMap { Field(rawValue: $0.name) })
            guard fields.count == record.fields.count,
                  let kind = Self.value(MessageKind.self, for: .kind, in: record)
            else { return nil }
            switch kind {
            case .phase1a:
                guard fields == [.kind, .ballot],
                      Self.value(Int.self, for: .ballot, in: record) != nil
                else { return nil }
            case .phase1b:
                guard fields == [.kind, .acceptor, .ballot, .maximumBallot, .maximumValue],
                      Self.value(Acceptor.self, for: .acceptor, in: record) != nil,
                      Self.value(Int.self, for: .ballot, in: record) != nil,
                      Self.value(Int.self, for: .maximumBallot, in: record) != nil,
                      Self.value(PaxosValue.self, for: .maximumValue, in: record) != nil
                else { return nil }
            case .phase2a:
                guard fields == [.kind, .ballot, .value],
                      Self.value(Int.self, for: .ballot, in: record) != nil,
                      Self.value(PaxosValue.self, for: .value, in: record) != nil
                else { return nil }
            case .phase2b:
                guard fields == [.kind, .acceptor, .ballot, .value],
                      Self.value(Acceptor.self, for: .acceptor, in: record) != nil,
                      Self.value(Int.self, for: .ballot, in: record) != nil,
                      Self.value(PaxosValue.self, for: .value, in: record) != nil
                else { return nil }
            }
            self.record = record
        }

        var tlaValue: TLAValue { .record(record) }

        static func phase1a(_ ballot: Int) -> Expr<Self> {
            expression([.kind: .value(MessageKind.phase1a.tlaValue), .ballot: .int(ballot)])
        }

        static func phase1b(
            _ ballot: Int,
            maximumBallot: Expr<Int>,
            value: Expr<PaxosValue>
        ) -> Expr<Self> {
            expression([
                .kind: .value(MessageKind.phase1b.tlaValue),
                .acceptor: .value(Acceptor.only.tlaValue),
                .ballot: .int(ballot),
                .maximumBallot: maximumBallot.raw,
                .maximumValue: value.raw,
            ])
        }

        static func phase2a(_ ballot: Int) -> Expr<Self> {
            expression([
                .kind: .value(MessageKind.phase2a.tlaValue),
                .ballot: .int(ballot),
                .value: .value(PaxosValue.proposed.tlaValue),
            ])
        }

        static func phase2b(_ ballot: Int) -> Expr<Self> {
            expression([
                .kind: .value(MessageKind.phase2b.tlaValue),
                .acceptor: .value(Acceptor.only.tlaValue),
                .ballot: .int(ballot),
                .value: .value(PaxosValue.proposed.tlaValue),
            ])
        }

        private static func expression(_ fields: [Field: StateExpr]) -> Expr<Self> {
            Expr(.record(Dictionary(uniqueKeysWithValues: fields.map { ($0.rawValue, $1) })))
        }

        private static func value<Value: TLAValueType>(
            _: Value.Type,
            for field: Field,
            in record: TLARecord
        ) -> Value? {
            record.value(named: field.rawValue).flatMap(Value.init(formalValue:))
        }
    }

    package static var spec: TLASpec {
        #spec("Paxos") { scope in
            Extends(.integers)

            let maxBal = scope.sharedVar(
                "maxBal",
                initial: Function<Acceptor, Int>.mapping { _ in -1 }
            )
            let maxVBal = scope.sharedVar(
                "maxVBal",
                initial: Function<Acceptor, Int>.mapping { _ in -1 }
            )
            let maxVal = scope.sharedVar(
                "maxVal",
                initial: Function<Acceptor, PaxosValue>.mapping { _ in PaxosValue.none }
            )
            let messages = scope.sharedVar("msgs", initial: SetExpr<Message>())

            let addMessage: (Expr<Message>) -> ActionExpr = { message in
                messages.becomes(messages.expr.inserting(message))
            }

            Invariant("TypeOK") {
                let ballots = SetExpr<Int>.literal(-1, 0, 1)
                let values = SetExpr<PaxosValue>.literal(.none, .proposed)
                ballots.contains(maxBal[.only])
                    && ballots.contains(maxVBal[.only])
                    && values.contains(maxVal[.only])
            }

            Invariant("Inv") {
                StateExpr.ifThenElse(
                    maxVBal[.only] == -1,
                    maxVal[.only] == PaxosValue.none,
                    .value(.bool(true))
                )
            }

            SwiftTLA.Action("Phase1a_0") {
                addMessage(Message.phase1a(0)) && maxBal.stays && maxVBal.stays && maxVal.stays
            }
            SwiftTLA.Action("Phase1a_1") {
                addMessage(Message.phase1a(1)) && maxBal.stays && maxVBal.stays && maxVal.stays
            }

            SwiftTLA.Action("Phase1b_a1_0") {
                messages.contains(Message.phase1a(0)) && 0 > maxBal[.only]
                    && maxBal.becomes(maxBal.updating(.only, to: 0))
                    && addMessage(Message.phase1b(0, maximumBallot: maxVBal[.only], value: maxVal[.only]))
                    && maxVBal.stays && maxVal.stays
            }
            SwiftTLA.Action("Phase1b_a1_1") {
                messages.contains(Message.phase1a(1)) && 1 > maxBal[.only]
                    && maxBal.becomes(maxBal.updating(.only, to: 1))
                    && addMessage(Message.phase1b(1, maximumBallot: maxVBal[.only], value: maxVal[.only]))
                    && maxVBal.stays && maxVal.stays
            }

            SwiftTLA.Action("Phase2a_0_v1") {
                StateExpr.not(messages.contains(Message.phase2a(0)))
                    && addMessage(Message.phase2a(0))
                    && maxBal.stays && maxVBal.stays && maxVal.stays
            }
            SwiftTLA.Action("Phase2a_1_v1") {
                StateExpr.not(messages.contains(Message.phase2a(1)))
                    && addMessage(Message.phase2a(1))
                    && maxBal.stays && maxVBal.stays && maxVal.stays
            }

            SwiftTLA.Action("Phase2b_a1_0") {
                messages.contains(Message.phase2a(0)) && 0 >= maxBal[.only]
                    && maxBal.becomes(maxBal.updating(.only, to: 0))
                    && maxVBal.becomes(maxVBal.updating(.only, to: 0))
                    && maxVal.becomes(maxVal.updating(.only, to: PaxosValue.proposed))
                    && addMessage(Message.phase2b(0))
            }
            SwiftTLA.Action("Phase2b_a1_1") {
                messages.contains(Message.phase2a(1)) && 1 >= maxBal[.only]
                    && maxBal.becomes(maxBal.updating(.only, to: 1))
                    && maxVBal.becomes(maxVBal.updating(.only, to: 1))
                    && maxVal.becomes(maxVal.updating(.only, to: PaxosValue.proposed))
                    && addMessage(Message.phase2b(1))
            }
        }
    }
}

extension Example {
    package static let paxosSmall = FiniteModelFixture(
        expectedDistinct: 81,
        maximumStateLimit: 50_000,
        spec: PaxosModel.spec,
    )
}
