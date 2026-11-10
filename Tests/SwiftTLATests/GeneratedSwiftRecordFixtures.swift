import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedSwiftRecord {
    struct Packet: Hashable, Sendable {
        let count: Int
        let ready: Bool

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.ready == rhs.ready }
        func hash(into hasher: inout Hasher) { hasher.combine(ready) }
    }

    struct UnusedHelper {
        let value: Int
        init(value: Int) { self.value = value + 1 }
    }

    typealias Swift = UnusedHelper
    typealias Array = UnusedHelper

    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("GeneratedSwiftRecord") { scope in
            let packet = scope.sharedVar(_name: "packet", initial: Packet(count: 0, ready: false))
            let previousCount = scope.sharedVar(_name: "previousCount", initial: -1)
            let history = scope.sharedVar(initial: [Packet(count: 0, ready: false)])
            let archive = scope.sharedVar(initial: SetExpr<Packet>(
                Packet(count: 0, ready: false), Packet(count: 1, ready: false)
            ))
            let lookup = scope.sharedVar(initial: Dictionary<Packet, Int>.mapping(over: archive) { value in value.count })
            let generatedSwiftRecord = Algorithm(label: "GeneratedSwiftRecord") {
                Each(Set<Int>([0]), scoped: { _, process in
                    let localPacket = process.localVar(initial: Packet(count: 0, ready: false))
                    Do(Step.advance) {
                        let saved = packet
                        When(saved.count == 0)
                        With(IntRange(1, through: 2)) { input in
                            Assign(packet, to: Packet.expression(count: input, ready: true))
                            Assign(history, to: SequenceMapping(length: 1) { _ in
                                Packet.expression(count: input, ready: true)
                            })
                            With(IntRange(1, through: 2)) { hidden in
                                Assign(localPacket, to: Packet.expression(count: hidden, ready: false))
                            }
                        }
                        Assign(archive, to: archive.union(SetExpr<Packet>(Packet(count: 1, ready: false))))
                        Assign(lookup[Packet(count: 0, ready: false)], to: lookup[Packet(count: 0, ready: false)] + 1)
                        Assign(previousCount, to: saved.count)
                        Stop()
                    }
                })
            }
            generatedSwiftRecord
            Invariant("RecordCardinality") {
                SetExpr<Packet>(Packet(count: 1, ready: false), Packet(count: 2, ready: false),
                    Packet(count: 1, ready: false)).cardinality == 2
                    && Subsets(of: archive).cardinality == 4
                    && Functions(from: IntRange(0, through: 0), to: archive).cardinality == 2
                    && Functions(from: archive, to: SetExpr<Int>.literal(0, 1)).cardinality == 4
                    && lookup.keys.cardinality == 2
                    && lookup[Packet(count: 1, ready: false)] == 1
            }
            Invariant("RecordForAll") {
                !ForAll(in: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { $0.count == 1 }
                    && !ForAll(in: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { $0.count == 2 }
                    && ForAll(in: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { $0.count > 0 }
            }
            Invariant("RecordExists") {
                Exists(in: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { $0.count == 1 }
                    && Exists(in: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { $0.count == 2 }
                    && !Exists(in: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { $0.count == 3 }
            }
            Invariant("RecordMapping") {
                SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false)).mapping { $0.count }.cardinality == 2
                    && SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false)).mapping { _ in 1 }.cardinality == 1
            }
            Invariant("RecordSelection") {
                Select(from: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { candidate in candidate.count == 1 } == Packet(count: 1, ready: false)
                    && Select(from: SetExpr<Packet>(Packet(count: 1, ready: false), Packet(count: 2, ready: false))) { $0.count == 2 } == Packet(count: 2, ready: false)
            }
            Invariant("RecordFilterDomain") {
                SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false)).filtering { value in value.count > 0 }.cardinality == 2
                    && SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false)).filtering { value in value.count > 2 }.isEmpty
                    && archive.filtering { value in value.count > 0 }.cardinality == 1
            }
            Invariant("RecordMapDomain") {
                IntRange(1, through: 3).mapping { value in Packet.expression(count: value % 2, ready: false) }.cardinality == 2
                    && IntRange(1, through: 3).mapping { _ in Packet(count: 1, ready: false) }.cardinality == 1
                    && archive.mapping { value in Packet.expression(count: value.count + 1, ready: false) }.cardinality == 2
            }
            Invariant("RecordUnionDomain") {
                SetExpr<Packet>.literal(Packet(count: 1, ready: false)).union(SetExpr<Packet>.literal(Packet(count: 2, ready: false))).cardinality == 2
                    && SetExpr<Packet>.literal(Packet(count: 1, ready: false)).union(SetExpr<Packet>.literal(Packet(count: 1, ready: false))).cardinality == 1
            }
            Invariant("RecordIntersectionDomain") {
                SetExpr<Packet>.literal(Packet(count: 1, ready: false)).intersection(SetExpr<Packet>.literal(Packet(count: 2, ready: false))).isEmpty
                    && SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false)).intersection(SetExpr<Packet>.literal(Packet(count: 2, ready: false))).mapping { value in value.count }.cardinality == 1
            }
            Invariant("RecordDifferenceDomain") {
                SetExpr<Packet>.literal(Packet(count: 1, ready: false)).subtracting(SetExpr<Packet>.literal(Packet(count: 2, ready: false))).cardinality == 1
                    && SetExpr<Packet>.literal(Packet(count: 1, ready: false)).subtracting(SetExpr<Packet>.literal(Packet(count: 1, ready: false))).isEmpty
            }
            Invariant("RecordFlattenedDomain") {
                IntRange(1, through: 2).flatMapping { value in
                    SetExpr<Packet>.literal(Packet.expression(count: value, ready: false), Packet.expression(count: value + 1, ready: false))
                }.cardinality == 3
                    && IntRange(1, through: 2).flatMapping { _ in SetExpr<Packet>.literal(Packet(count: 1, ready: false)) }.cardinality == 1
            }
            Invariant("RecordConditionalDomain") {
                If(packet.count == 0,
                    then: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false)),
                    else: If(packet.count != 0,
                        then: SetExpr<Packet>.literal(Packet(count: 3, ready: false), Packet(count: 4, ready: false)),
                        else: SetExpr<Packet>.literal(Packet.expression(count: Expr<Int>(1) / (packet.count - packet.count), ready: false)))).cardinality == 2
                    && If(packet.count == 0,
                        then: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 1, ready: false)),
                        else: SetExpr<Packet>.literal()).cardinality == If(packet.count == 0, then: 1, else: 0)
            }
            Invariant("OrderedCaseSelection") {
                Expr<Int>(StateExpr.firstMatch(
                    (when: (packet.count >= 0).stateExpr, then: Expr(1).stateExpr),
                    (when: (packet.count >= 0).stateExpr, then: SwiftTLA.Expr(2).stateExpr),
                    fallback: Expr(0).stateExpr)) == 1
                    && Expr(Packet(count: 7, ready: false)).count == 7
                    && SwiftTLA.Expr(Packet(count: 7, ready: false)).count == 7
                    && Expr<Packet>(packet.stateExpr).count == packet.count
                    && Expr([1, 2]).count == 2
                    && Expr([0: 1]).keys.cardinality == 1
                    && SwiftTLA.Expr([0: 1]).keys.cardinality == 1
                    && Expr<[Int: Int]>([0: 1]).keys.cardinality == 1
                    && Expr<[Packet]>(history.stateExpr).head().count == packet.count
                    && Expr([0: Packet(count: 7, ready: false)])[0].count == 7
            }
            Invariant("RecordSymbolicDomain") {
                Functions(from: IntRange(0, through: 99), to: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false)))
                    .union(Functions(from: IntRange(0, through: 99), to: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))))
                    .contains(Dictionary<Int, Packet>.mapping(over: IntRange(0, through: 99)) { _ in Packet(count: 1, ready: false) })
                    && !Functions(from: IntRange(0, through: 99), to: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false)))
                    .union(Functions(from: IntRange(0, through: 99), to: SetExpr<Packet>.literal(Packet(count: 1, ready: false), Packet(count: 2, ready: false))))
                    .contains(Dictionary<Int, Packet>.mapping(over: IntRange(0, through: 99)) { _ in Packet(count: 3, ready: false) })
            }
            Invariant("Bounded") {
                packet.count <= 1 && archive.cardinality == 2
                    && If(packet.ready,
                        then: packet != Packet(count: 9, ready: true)
                            && SequenceMapping(length: 1) { _ in packet } != [Packet(count: 9, ready: true)],
                        else: !(packet == Packet(count: 9, ready: false)))
            }
        }
    }
}
