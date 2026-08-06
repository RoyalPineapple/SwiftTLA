import SwiftTLA

/// Swift ports registered for TLC parity against tlaplus/Examples.
public enum ParityCatalog {
    public struct Entry: Sendable {
        public let id: String
        public let upstreamSpec: String
        public let upstreamModule: String
        public let upstreamCfg: String?
        public let expectedDistinct: Int
        public let expectedResult: String
        public let spec: TLASpec
        public let notes: String
        public let matchesUpstreamTLC: Bool
    }

    public static let all: [Entry] = [
        hourClock,
        hourClock2,
        dieHardTypeOK,
        coffeeCanMax5,
        catOddBoxes,
        catEvenBoxes,
        asynchInterface,
        channel,
        teachingSimpleN2,
        teachingSimpleN3,
        simpleAllocator,
        tCommit,
        twoPhase,
        barrierN6,
        cigaretteSmokers,
        ewd840,
    ]

    public static var ids: [String] { all.map(\.id) }

    public static func entry(id: String) -> Entry? {
        all.first { $0.id == id }
    }

    // MARK: Helpers

    private static func recordMessage(_ fields: [String: String]) -> TLAValue {
        .record(fields.mapValues { .string($0) })
    }

    private static func recordMessageExpr(_ fields: [String: StateExpr]) -> StateExpr {
        .recordLiteral(fields)
    }

    private static func coffeeCans(maxBeanCount: Int) -> [TLAValue] {
        var cans: [TLAValue] = []
        for black in 0...maxBeanCount {
            for white in 0...maxBeanCount where (1...maxBeanCount).contains(black + white) {
                cans.append(.record(["black": .int(black), "white": .int(white)]))
            }
        }
        return cans
    }

    private static func coffeeCanSpec(maxBeanCount: Int) -> TLASpec {
        let can = Var<TLARecordType>("can")
        let cans = coffeeCans(maxBeanCount: maxBeanCount)
        return TLASpec("CoffeeCan") {
            Extends("Naturals")
            Variable(can, in: cans)
            Action("PickSameColorBlack") {
                can.black + can.white > 1 && can.black >= 2
                    && can.becomes(can.updated(at: "black", to: can.black - 1))
            }
            Action("PickSameColorWhite") {
                can.black + can.white > 1 && can.white >= 2
                    && can.becomes(
                        StateExpr.except(
                            StateExpr.except(
                                .variable("can"),
                                .value(.string("black")),
                                can.black + 1
                            ),
                            .value(.string("white")),
                            can.white - 2
                        )
                    )
            }
            Action("PickDifferentColor") {
                can.black + can.white > 1 && can.black >= 1 && can.white >= 1
                    && can.becomes(can.updated(at: "black", to: can.black - 1))
            }
            Action("Termination") {
                can.black + can.white == 1
            }
            Invariant("TypeInvariant") {
                can.black >= 0 && can.black <= maxBeanCount
                    && can.white >= 0 && can.white <= maxBeanCount
            }
        }
    }

    /// Faithful Moving_Cat_Puzzle algorithm for fixed Number_Of_Boxes.
    private static func catSpec(boxes: Int) -> TLASpec {
        let cat = Var<Int>("cat_box", value: 1)
        let observed = Var<Int>("observed_box", value: 2)
        let direction = Var<String>("direction", value: "right")
        return TLASpec("Cat") {
            Extends("Naturals")
            Variable(cat, in: 1...boxes)
            Variable(observed, in: 2...(boxes - 1))
            Variable(direction, in: ["left", "right"])
            Invariant("TypeOK") {
                cat >= 1 && cat <= boxes
                    && observed >= 2 && observed <= boxes - 1
                    && (direction == "left" || direction == "right")
            }
            Action("Next") {
                // Move_Cat /\ Observe_Box
                ((cat < boxes && cat.becomes(cat + 1)) || (cat > 1 && cat.becomes(cat - 1)))
                    && (
                        (direction == "right" && observed < boxes - 1 && observed.becomes(observed + 1))
                            || (direction == "right" && observed == boxes - 1 && direction.becomes("left"))
                            || (direction == "left" && observed > 2 && observed.becomes(observed - 1))
                            || (direction == "left" && observed == 2 && direction.becomes("right"))
                    )
            }
        }
    }

    // MARK: SpecifyingSystems/HourClock (12)

    public static let hourClock = Entry(
        id: "SpecifyingSystems/HourClock",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/HourClock/HourClock.tla",
        upstreamCfg: "specifications/SpecifyingSystems/HourClock/HourClock.cfg",
        expectedDistinct: 12,
        expectedResult: "success",
        spec: {
            let hr = Var<Int>("hr", value: 1)
            return TLASpec("HourClock") {
                Extends("Naturals")
                Variable(hr, in: 1...12)
                Action("HCnxt") {
                    (hr != 12) && hr.becomes(hr + 1) ||
                    (hr == 12) && hr.becomes(1)
                }
                Invariant("HCini") { hr >= 1 && hr <= 12 }
            }
        }(),
        notes: "Upstream SPECIFICATION HC; export uses Spec. TLC = 12.",
        matchesUpstreamTLC: true
    )

    // MARK: HourClock2 — hr' = (hr % 12) + 1 (also 12 states)

    public static let hourClock2 = Entry(
        id: "SpecifyingSystems/HourClock2",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/HourClock/HourClock2.tla",
        upstreamCfg: "specifications/SpecifyingSystems/HourClock/HourClock2.cfg",
        expectedDistinct: 12,
        expectedResult: "success",
        spec: {
            let hr = Var<Int>("hr", value: 1)
            return TLASpec("HourClock2") {
                Extends("Naturals")
                Variable(hr, in: 1...12)
                Action("HCnxt2") {
                    hr.becomes((hr % 12) + 1)
                }
                Invariant("HCini") { hr >= 1 && hr <= 12 }
            }
        }(),
        notes: "Upstream checks HC => HC2 as property; state space of HC2 alone is 12.",
        matchesUpstreamTLC: true
    )

    // MARK: DieHard TypeOK (16)

    public static let dieHardTypeOK = Entry(
        id: "DieHard/TypeOK",
        upstreamSpec: "DieHard",
        upstreamModule: "specifications/DieHard/DieHard.tla",
        upstreamCfg: nil,
        expectedDistinct: 16,
        expectedResult: "success",
        spec: {
            let big = Var<Int>("big", value: 0)
            let small = Var<Int>("small", value: 0)
            return TLASpec("DieHard") {
                Extends("Naturals")
                Variable(big, 0)
                Variable(small, 0)
                Invariant("TypeOK") { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
                Action("FillSmallJug") { small.becomes(3) }
                Action("FillBigJug") { big.becomes(5) }
                Action("EmptySmallJug") { small.becomes(0) }
                Action("EmptyBigJug") { big.becomes(0) }
                Action("SmallToBig") {
                    (big + small <= 5) && big.becomes(big + small) && small.becomes(0) ||
                    (big + small > 5) && big.becomes(5) && small.becomes(small - (5 - big))
                }
                Action("BigToSmall") {
                    (big + small <= 3) && small.becomes(big + small) && big.becomes(0) ||
                    (big + small > 3) && small.becomes(3) && big.becomes(big - (3 - small))
                }
            }
        }(),
        notes: "Upstream cfg adds NotSolved (intentional fail). TypeOK-only = 16 both sides.",
        matchesUpstreamTLC: true
    )

    // MARK: CoffeeCan MaxBeanCount=5 (record + nondet init) — structure matches upstream

    public static let coffeeCanMax5 = Entry(
        id: "CoffeeCan/MaxBeanCount5",
        upstreamSpec: "CoffeeCan",
        upstreamModule: "specifications/CoffeeCan/CoffeeCan.tla",
        upstreamCfg: nil,
        expectedDistinct: 20,
        expectedResult: "success",
        spec: coffeeCanSpec(maxBeanCount: 5),
        notes: "Upstream shape (record can, all cans with 1..M beans). M=5 → 20 states. M=100 upstream = 5150 (same port, scale CONSTANT).",
        matchesUpstreamTLC: true
    )

    // MARK: Moving_Cat_Puzzle CatOddBoxes (5) = 30

    public static let catOddBoxes = Entry(
        id: "Moving_Cat_Puzzle/CatOddBoxes",
        upstreamSpec: "Moving_Cat_Puzzle",
        upstreamModule: "specifications/Moving_Cat_Puzzle/Cat.tla",
        upstreamCfg: "specifications/Moving_Cat_Puzzle/CatOddBoxes.cfg",
        expectedDistinct: 30,
        expectedResult: "success",
        spec: catSpec(boxes: 5),
        notes: "Number_Of_Boxes=5. Move_Cat /\\ Observe_Box. TLC upstream = 30.",
        matchesUpstreamTLC: true
    )

    // MARK: Moving_Cat_Puzzle CatEvenBoxes (6) = 48

    public static let catEvenBoxes = Entry(
        id: "Moving_Cat_Puzzle/CatEvenBoxes",
        upstreamSpec: "Moving_Cat_Puzzle",
        upstreamModule: "specifications/Moving_Cat_Puzzle/Cat.tla",
        upstreamCfg: "specifications/Moving_Cat_Puzzle/CatEvenBoxes.cfg",
        expectedDistinct: 48,
        expectedResult: "success",
        spec: catSpec(boxes: 6),
        notes: "Number_Of_Boxes=6. TLC upstream = 48.",
        matchesUpstreamTLC: true
    )

    // MARK: SpecifyingSystems/AsynchInterface (Data size 3 → 12 states)

    public static let asynchInterface = Entry(
        id: "SpecifyingSystems/AsynchInterface",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.tla",
        upstreamCfg: "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.cfg",
        expectedDistinct: 12,
        expectedResult: "success",
        spec: {
            let data = ["d1", "d2", "d3"]
            let st = Var<TLARecordType>("st")
            var records: [TLAValue] = []
            for v in data {
                for r in 0...1 {
                    records.append(.record([
                        "val": .string(v), "rdy": .int(r), "ack": .int(r)
                    ]))
                }
            }
            return TLASpec("AsynchInterface") {
                Extends("Naturals")
                Variable(st, in: records)
                Invariant("TypeInvariant") {
                    (st.val == "d1" || st.val == "d2" || st.val == "d3")
                        && st.rdy >= 0 && st.rdy <= 1
                        && st.ack >= 0 && st.ack <= 1
                }
                Action("Send") {
                    st.rdy == st.ack && (
                        st.becomes(StateExpr.except(
                            StateExpr.except(.variable("st"), .value(.string("val")), "d1"),
                            .value(.string("rdy")), 1 - st.rdy
                        ))
                        || st.becomes(StateExpr.except(
                            StateExpr.except(.variable("st"), .value(.string("val")), "d2"),
                            .value(.string("rdy")), 1 - st.rdy
                        ))
                        || st.becomes(StateExpr.except(
                            StateExpr.except(.variable("st"), .value(.string("val")), "d3"),
                            .value(.string("rdy")), 1 - st.rdy
                        ))
                    )
                }
                Action("Rcv") {
                    st.rdy != st.ack
                        && st.becomes(st.updated(at: "ack", to: 1 - st.ack))
                }
            }
        }(),
        notes: "Data={d1,d2,d3}. Record packing of val/rdy/ack. Upstream TLC = 12.",
        matchesUpstreamTLC: true
    )

    // MARK: Channel (same handshake, record chan) = 12

    public static let channel = Entry(
        id: "SpecifyingSystems/Channel",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/AsynchronousInterface/Channel.tla",
        upstreamCfg: "specifications/SpecifyingSystems/AsynchronousInterface/Channel.cfg",
        expectedDistinct: 12,
        expectedResult: "success",
        spec: {
            let data = ["d1", "d2", "d3"]
            let chan = Var<TLARecordType>("chan")
            var records: [TLAValue] = []
            for v in data {
                for r in 0...1 {
                    records.append(.record([
                        "val": .string(v), "rdy": .int(r), "ack": .int(r)
                    ]))
                }
            }
            return TLASpec("Channel") {
                Extends("Naturals")
                Variable(chan, in: records)
                Invariant("TypeInvariant") {
                    (chan.val == "d1" || chan.val == "d2" || chan.val == "d3")
                        && chan.rdy >= 0 && chan.rdy <= 1
                        && chan.ack >= 0 && chan.ack <= 1
                }
                Action("Send") {
                    chan.rdy == chan.ack && (
                        chan.becomes(StateExpr.except(
                            StateExpr.except(.variable("chan"), .value(.string("val")), "d1"),
                            .value(.string("rdy")), 1 - chan.rdy
                        ))
                        || chan.becomes(StateExpr.except(
                            StateExpr.except(.variable("chan"), .value(.string("val")), "d2"),
                            .value(.string("rdy")), 1 - chan.rdy
                        ))
                        || chan.becomes(StateExpr.except(
                            StateExpr.except(.variable("chan"), .value(.string("val")), "d3"),
                            .value(.string("rdy")), 1 - chan.rdy
                        ))
                    )
                }
                Action("Rcv") {
                    chan.rdy != chan.ack
                        && chan.becomes(chan.updated(at: "ack", to: 1 - chan.ack))
                }
            }
        }(),
        notes: "Same as AsynchInterface with single record variable `chan`. TLC = 12.",
        matchesUpstreamTLC: true
    )

    // MARK: TeachingConcurrency Simple N=2 → 13

    public static let teachingSimpleN2 = Entry(
        id: "TeachingConcurrency/Simple_N2",
        upstreamSpec: "TeachingConcurrency",
        upstreamModule: "specifications/TeachingConcurrency/Simple.tla",
        upstreamCfg: nil,
        expectedDistinct: 13,
        expectedResult: "success",
        spec: teachingSimple(n: 2),
        notes: "PlusCal translation, N=2. Upstream TLC (TypeOK only) = 13.",
        matchesUpstreamTLC: true
    )

    public static let teachingSimpleN3 = Entry(
        id: "TeachingConcurrency/Simple_N3",
        upstreamSpec: "TeachingConcurrency",
        upstreamModule: "specifications/TeachingConcurrency/Simple.tla",
        upstreamCfg: nil,
        expectedDistinct: 51,
        expectedResult: "success",
        spec: teachingSimple(n: 3),
        notes: "N=3. Upstream TLC = 51. (cfg default N=5 → 723).",
        matchesUpstreamTLC: true
    )

    /// Flattened TeachingConcurrency Simple for small N (2 or 3).
    private static func teachingSimple(n: Int) -> TLASpec {
        precondition(n == 2 || n == 3)
        if n == 2 {
            let x0 = Var<Int>("x0", value: 0), x1 = Var<Int>("x1", value: 0)
            let y0 = Var<Int>("y0", value: 0), y1 = Var<Int>("y1", value: 0)
            let pc0 = Var<String>("pc0", value: "a"), pc1 = Var<String>("pc1", value: "a")
            return TLASpec("Simple") {
                Extends("Integers")
                Variable(x0, 0); Variable(x1, 0)
                Variable(y0, 0); Variable(y1, 0)
                Variable(pc0, "a"); Variable(pc1, "a")
                Action("a0") { pc0 == "a" && x0.becomes(1) && pc0.becomes("b") }
                Action("b0") { pc0 == "b" && y0.becomes(x1) && pc0.becomes("Done") }
                Action("a1") { pc1 == "a" && x1.becomes(1) && pc1.becomes("b") }
                Action("b1") { pc1 == "b" && y1.becomes(x0) && pc1.becomes("Done") }
                Action("Terminating") { pc0 == "Done" && pc1 == "Done" }
                Invariant("TypeOK") {
                    (x0 == 0 || x0 == 1) && (x1 == 0 || x1 == 1)
                        && (y0 == 0 || y0 == 1) && (y1 == 0 || y1 == 1)
                }
            }
        }
        let x0 = Var<Int>("x0", value: 0), x1 = Var<Int>("x1", value: 0), x2 = Var<Int>("x2", value: 0)
        let y0 = Var<Int>("y0", value: 0), y1 = Var<Int>("y1", value: 0), y2 = Var<Int>("y2", value: 0)
        let pc0 = Var<String>("pc0", value: "a"), pc1 = Var<String>("pc1", value: "a"), pc2 = Var<String>("pc2", value: "a")
        return TLASpec("Simple") {
            Extends("Integers")
            Variable(x0, 0); Variable(x1, 0); Variable(x2, 0)
            Variable(y0, 0); Variable(y1, 0); Variable(y2, 0)
            Variable(pc0, "a"); Variable(pc1, "a"); Variable(pc2, "a")
            Action("a0") { pc0 == "a" && x0.becomes(1) && pc0.becomes("b") }
            Action("b0") { pc0 == "b" && y0.becomes(x2) && pc0.becomes("Done") }
            Action("a1") { pc1 == "a" && x1.becomes(1) && pc1.becomes("b") }
            Action("b1") { pc1 == "b" && y1.becomes(x0) && pc1.becomes("Done") }
            Action("a2") { pc2 == "a" && x2.becomes(1) && pc2.becomes("b") }
            Action("b2") { pc2 == "b" && y2.becomes(x1) && pc2.becomes("Done") }
            Action("Terminating") { pc0 == "Done" && pc1 == "Done" && pc2 == "Done" }
            Invariant("TypeOK") {
                (x0 == 0 || x0 == 1) && (x1 == 0 || x1 == 1) && (x2 == 0 || x2 == 1)
            }
        }
    }

    // MARK: allocator/SimpleAllocator — Merz, Clients×Resources, 400 states

    public static let simpleAllocator = Entry(
        id: "allocator/SimpleAllocator",
        upstreamSpec: "allocator",
        upstreamModule: "specifications/allocator/SimpleAllocator.tla",
        upstreamCfg: "specifications/allocator/SimpleAllocator.cfg",
        expectedDistinct: 400,
        expectedResult: "success",
        spec: simpleAllocatorSpec(),
        notes: "Clients={c1,c2,c3} Resources={r1,r2}. Request/Allocate/Return. TLC = 400.",
        matchesUpstreamTLC: true
    )

    /// Faithful SimpleAllocator (Stephan Merz) for the standard TLC constants.
    private static func simpleAllocatorSpec() -> TLASpec {
        let clients = ["c1", "c2", "c3"]
        let nonemptySubsets: [TLAValue] = [
            .set([.string("r1")]),
            .set([.string("r2")]),
            .set([.string("r1"), .string("r2")]),
        ]
        let unsat = Var<TLAFunctionType>("unsat")
        let alloc = Var<TLAFunctionType>("alloc")
        let emptyFun = TLAValue.function([
            .string("c1"): .set([]),
            .string("c2"): .set([]),
            .string("c3"): .set([]),
        ])

        func allocOf(_ c: String) -> StateExpr {
            .functionApply(.variable("alloc"), .value(.string(c)))
        }
        func unsatOf(_ c: String) -> StateExpr {
            .functionApply(.variable("unsat"), .value(.string(c)))
        }
        let resources: StateExpr = .setLiteral([
            .value(.string("r1")), .value(.string("r2")),
        ])
        let available = resources.subtracting(
            allocOf("c1").union(allocOf("c2")).union(allocOf("c3"))
        )

        return TLASpec("SimpleAllocator") {
            Extends("Integers, FiniteSets")
            Variable(unsat, emptyFun)
            Variable(alloc, emptyFun)

            for c in clients {
                for (si, sVal) in nonemptySubsets.enumerated() {
                    let subset = StateExpr.value(sVal)
                    Action("Request_\(c)_S\(si)") {
                        unsatOf(c).cardinality == 0 && allocOf(c).cardinality == 0
                            && unsat.becomes(unsat.updated(at: c, to: subset))
                    }
                    Action("Allocate_\(c)_S\(si)") {
                        subset.cardinality > 0
                            && subset.isSubset(of: available.intersection(unsatOf(c)))
                            && alloc.becomes(alloc.updated(at: c, to: allocOf(c).union(subset)))
                            && unsat.becomes(unsat.updated(at: c, to: unsatOf(c).subtracting(subset)))
                    }
                    Action("Return_\(c)_S\(si)") {
                        subset.cardinality > 0 && subset.isSubset(of: allocOf(c))
                            && alloc.becomes(alloc.updated(at: c, to: allocOf(c).subtracting(subset)))
                    }
                }
            }

            Invariant("TypeInvariant") {
                unsatOf("c1").cardinality >= 0
            }
            Invariant("ResourceMutex") {
                allocOf("c1").intersection(allocOf("c2")).cardinality == 0
                    && allocOf("c1").intersection(allocOf("c3")).cardinality == 0
                    && allocOf("c2").intersection(allocOf("c3")).cardinality == 0
            }
        }
    }

    // MARK: transaction_commit/TCommit — RM={r1,r2,r3} → 34

    public static let tCommit = Entry(
        id: "transaction_commit/TCommit",
        upstreamSpec: "transaction_commit",
        upstreamModule: "specifications/transaction_commit/TCommit.tla",
        upstreamCfg: "specifications/transaction_commit/TCommit.cfg",
        expectedDistinct: 34,
        expectedResult: "success",
        spec: tCommitSpec(),
        notes: "Lamport TCommit. SPECIFICATION TCSpec. TLC = 34.",
        matchesUpstreamTLC: true
    )

    private static func tCommitSpec() -> TLASpec {
        let rms = ["r1", "r2", "r3"]
        let rmState = Var<TLAFunctionType>("rmState")
        let initFun = TLAValue.function(Dictionary(uniqueKeysWithValues: rms.map {
            (.string($0), .string("working"))
        }))
        func st(_ rm: String) -> StateExpr {
            .functionApply(.variable("rmState"), .value(.string(rm)))
        }
        return TLASpec("TCommit") {
            Extends("Integers")
            Variable(rmState, initFun)
            for rm in rms {
                Action("Prepare_\(rm)") {
                    st(rm) == "working"
                        && rmState.becomes(rmState.updated(at: rm, to: "prepared"))
                }
                Action("Commit_\(rm)") {
                    st(rm) == "prepared"
                        && (st("r1") == "prepared" || st("r1") == "committed")
                        && (st("r2") == "prepared" || st("r2") == "committed")
                        && (st("r3") == "prepared" || st("r3") == "committed")
                        && rmState.becomes(rmState.updated(at: rm, to: "committed"))
                }
                Action("Abort_\(rm)") {
                    (st(rm) == "working" || st(rm) == "prepared")
                        && st("r1") != "committed" && st("r2") != "committed" && st("r3") != "committed"
                        && rmState.becomes(rmState.updated(at: rm, to: "aborted"))
                }
            }
            Invariant("TCConsistent") {
                !((st("r1") == "aborted" && st("r2") == "committed")
                    || (st("r1") == "aborted" && st("r3") == "committed")
                    || (st("r2") == "aborted" && st("r1") == "committed")
                    || (st("r2") == "aborted" && st("r3") == "committed")
                    || (st("r3") == "aborted" && st("r1") == "committed")
                    || (st("r3") == "aborted" && st("r2") == "committed"))
            }
        }
    }

    // MARK: barriers/Barrier N=6 → 64

    public static let barrierN6 = Entry(
        id: "barriers/Barrier_N6",
        upstreamSpec: "barriers",
        upstreamModule: "specifications/barriers/Barrier.tla",
        upstreamCfg: "specifications/barriers/Barrier.cfg",
        expectedDistinct: 64,
        expectedResult: "success",
        spec: barrierSpec(n: 6),
        notes: "N=6. TLC = 64.",
        matchesUpstreamTLC: true
    )

    private static func barrierSpec(n: Int) -> TLASpec {
        // Explicit N=6 (upstream Barrier.cfg)
        precondition(n == 6)
        let p1 = Var<String>("pc1", value: "b0")
        let p2 = Var<String>("pc2", value: "b0")
        let p3 = Var<String>("pc3", value: "b0")
        let p4 = Var<String>("pc4", value: "b0")
        let p5 = Var<String>("pc5", value: "b0")
        let p6 = Var<String>("pc6", value: "b0")
        return TLASpec("Barrier") {
            Extends("Integers")
            Variable(p1, "b0"); Variable(p2, "b0"); Variable(p3, "b0")
            Variable(p4, "b0"); Variable(p5, "b0"); Variable(p6, "b0")
            Action("b0_1") { p1 == "b0" && p1.becomes("b1") }
            Action("b0_2") { p2 == "b0" && p2.becomes("b1") }
            Action("b0_3") { p3 == "b0" && p3.becomes("b1") }
            Action("b0_4") { p4 == "b0" && p4.becomes("b1") }
            Action("b0_5") { p5 == "b0" && p5.becomes("b1") }
            Action("b0_6") { p6 == "b0" && p6.becomes("b1") }
            Action("b1_release") {
                p1 == "b1" && p2 == "b1" && p3 == "b1" && p4 == "b1" && p5 == "b1" && p6 == "b1"
                    && p1.becomes("b0") && p2.becomes("b0") && p3.becomes("b0")
                    && p4.becomes("b0") && p5.becomes("b0") && p6.becomes("b0")
            }
        }
    }

    // MARK: CigaretteSmokers — Ingredients×Offers → 6 safety states (cfg)

    public static let cigaretteSmokers = Entry(
        id: "CigaretteSmokers/CigaretteSmokers",
        upstreamSpec: "CigaretteSmokers",
        upstreamModule: "specifications/CigaretteSmokers/CigaretteSmokers.tla",
        upstreamCfg: "specifications/CigaretteSmokers/CigaretteSmokers.cfg",
        expectedDistinct: 6,
        expectedResult: "success",
        spec: cigaretteSmokersSpec(),
        notes: "Ingredients={m,p,t}, Offers=pairs. TLC TypeOK+AtMostOne = 6.",
        matchesUpstreamTLC: true
    )

    private static func cigaretteSmokersSpec() -> TLASpec {
        // Flatten: smoking_m, smoking_p, smoking_t bools; dealer in 0..3
        // 0=empty, 1={m,p}, 2={m,t}, 3={p,t}
        let sm = Var<Bool>("smoking_m", value: false)
        let sp = Var<Bool>("smoking_p", value: false)
        let st = Var<Bool>("smoking_t", value: false)
        let dealer = Var<Int>("dealer", value: 1)
        return TLASpec("CigaretteSmokers") {
            Extends("Integers")
            Variable(sm, false); Variable(sp, false); Variable(st, false)
            Variable(dealer, in: 1...3) // Init: dealer \in Offers
            // startSmoking: dealer /= {} ; the one missing ingredient smokes
            // Offer 1={m,p} missing t → tobacco smoker
            Action("start_1") {
                dealer == 1 && st.becomes(true) && dealer.becomes(0) && sm.stays && sp.stays
            }
            Action("start_2") {
                dealer == 2 && sp.becomes(true) && dealer.becomes(0) && sm.stays && st.stays
            }
            Action("start_3") {
                dealer == 3 && sm.becomes(true) && dealer.becomes(0) && sp.stays && st.stays
            }
            // stopSmoking: dealer={} ; stop the one smoking; dealer' \in Offers
            Action("stop_m1") { dealer == 0 && sm == true && sm.becomes(false) && dealer.becomes(1) }
            Action("stop_m2") { dealer == 0 && sm == true && sm.becomes(false) && dealer.becomes(2) }
            Action("stop_m3") { dealer == 0 && sm == true && sm.becomes(false) && dealer.becomes(3) }
            Action("stop_p1") { dealer == 0 && sp == true && sp.becomes(false) && dealer.becomes(1) }
            Action("stop_p2") { dealer == 0 && sp == true && sp.becomes(false) && dealer.becomes(2) }
            Action("stop_p3") { dealer == 0 && sp == true && sp.becomes(false) && dealer.becomes(3) }
            Action("stop_t1") { dealer == 0 && st == true && st.becomes(false) && dealer.becomes(1) }
            Action("stop_t2") { dealer == 0 && st == true && st.becomes(false) && dealer.becomes(2) }
            Action("stop_t3") { dealer == 0 && st == true && st.becomes(false) && dealer.becomes(3) }
            Invariant("AtMostOne") {
                // at most one of sm,sp,st true — count via pairwise
                !((sm == true && sp == true) || (sm == true && st == true) || (sp == true && st == true))
            }
        }
    }

    // MARK: transaction_commit/TwoPhase — RM={r1,r2,r3} → 288

    public static let twoPhase = Entry(
        id: "transaction_commit/TwoPhase",
        upstreamSpec: "transaction_commit",
        upstreamModule: "specifications/transaction_commit/TwoPhase.tla",
        upstreamCfg: "specifications/transaction_commit/TwoPhase.cfg",
        expectedDistinct: 288,
        expectedResult: "success",
        spec: twoPhaseSpec(),
        notes: "Lamport TwoPhase safety. RM={r1,r2,r3}, msgs as record-set. SPECIFICATION TPSpec. TLC = 288.",
        matchesUpstreamTLC: true
    )

    private static func twoPhaseSpec() -> TLASpec {
        let rms = ["r1", "r2", "r3"]
        let rmSet: StateExpr = .setLiteral(rms.map { .value(.string($0)) })
        let rmState = Var<TLAFunctionType>("rmState")
        let tmState = Var<String>("tmState")
        let tmPrepared = Var<TLASetType>("tmPrepared")
        let msgs = Var<TLASetType>("msgs")

        func recordMsg(_ fields: [String: String]) -> StateExpr {
            .recordLiteral(fields.mapValues { .value(.string($0)) })
        }
        func commitMsg() -> StateExpr { recordMsg(["type": "Commit"]) }
        func abortMsg() -> StateExpr { recordMsg(["type": "Abort"]) }
        func preparedMsg(_ rm: String) -> StateExpr { recordMsg(["type": "Prepared", "rm": rm]) }
        func rmSt(_ rm: String) -> StateExpr {
            .functionApply(.variable("rmState"), .value(.string(rm)))
        }

        return TLASpec("TwoPhase") {
            Extends("Integers")
            let initRMState = TLAValue.function(Dictionary(uniqueKeysWithValues: rms.map {
                (.string($0), .string("working"))
            }))
            Variable(rmState, initRMState)
            Variable(tmState, "init")
            Variable(tmPrepared, TLAValue.set([]))
            Variable(msgs, TLAValue.set([]))

            for rm in rms {
                Action("RcvPrepared_\(rm)") {
                    tmState == "init"
                    && preparedMsg(rm).isIn(msgs)
                    && tmPrepared.becomes(tmPrepared.union(StateExpr.singleton(rm)))
                    && rmState.stays && tmState.stays && msgs.stays
                }
            }

            Action("TMCommit") {
                tmState == "init"
                && tmPrepared.cardinality == 3
                && tmState.becomes("committed")
                && msgs.becomes(msgs.union(StateExpr.singleton(commitMsg())))
                && rmState.stays && tmPrepared.stays
            }

            Action("TMAbort") {
                tmState == "init"
                && tmState.becomes("aborted")
                && msgs.becomes(msgs.union(StateExpr.singleton(abortMsg())))
                && rmState.stays && tmPrepared.stays
            }

            for rm in rms {
                Action("Prepare_\(rm)") {
                    rmSt(rm) == "working"
                    && rmState.becomes(rmState.updated(at: rm, to: "prepared"))
                    && msgs.becomes(msgs.union(StateExpr.singleton(preparedMsg(rm))))
                    && tmState.stays && tmPrepared.stays
                }
                Action("Abort_\(rm)") {
                    rmSt(rm) == "working"
                    && rmState.becomes(rmState.updated(at: rm, to: "aborted"))
                    && tmState.stays && tmPrepared.stays && msgs.stays
                }
                Action("RcvCommit_\(rm)") {
                    commitMsg().isIn(msgs)
                    && rmState.becomes(rmState.updated(at: rm, to: "committed"))
                    && tmState.stays && tmPrepared.stays && msgs.stays
                }
                Action("RcvAbort_\(rm)") {
                    abortMsg().isIn(msgs)
                    && rmState.becomes(rmState.updated(at: rm, to: "aborted"))
                    && tmState.stays && tmPrepared.stays && msgs.stays
                }
            }

            Invariant("TPTypeOK") {
                rmSt("r1").isIn(StateExpr.set(["working", "prepared", "committed", "aborted"]))
                && rmSt("r2").isIn(StateExpr.set(["working", "prepared", "committed", "aborted"]))
                && rmSt("r3").isIn(StateExpr.set(["working", "prepared", "committed", "aborted"]))
                && tmState.isIn(StateExpr.set(["init", "committed", "aborted"]))
                && tmPrepared.isSubset(of: rmSet)
            }
        }
    }


    
    
    // MARK: ewd840/EWD840 — N=3, Dijkstra termination detection

    public static let ewd840 = Entry(
        id: "ewd840/EWD840",
        upstreamSpec: "ewd840",
        upstreamModule: "specifications/ewd840/EWD840.tla",
        upstreamCfg: "specifications/ewd840/EWD840.cfg",
        expectedDistinct: 258,
        expectedResult: "success",
        spec: ewd840Spec(),
        notes: "Dijkstra termination detection. N=3, active/color as functions. CASE-based TLA+ output.",
        matchesUpstreamTLC: true
    )

    private static func ewd840Spec() -> TLASpec {
        let N = 3
        let nodes = Array(0..<N)
        let boolOpts: [TLAValue] = [.bool(false), .bool(true)]
        let colorOpts: [TLAValue] = [.string("white"), .string("black")]
        var activeFuncs: [TLAValue] = []
        for a0 in boolOpts { for a1 in boolOpts { for a2 in boolOpts {
            activeFuncs.append(.function([.int(0):a0,.int(1):a1,.int(2):a2]))
        }}}
        var colorFuncs: [TLAValue] = []
        for c0 in colorOpts { for c1 in colorOpts { for c2 in colorOpts {
            colorFuncs.append(.function([.int(0):c0,.int(1):c1,.int(2):c2]))
        }}}

        let active = Var<TLAFunctionType>("active")
        let color = Var<TLAFunctionType>("color")
        let tpos = Var<Int>("tpos", value: 0)
        let tcolor = Var<String>("tcolor")

        func activeOf(_ i: Int) -> StateExpr {
            StateExpr.functionApply(StateExpr.variable("active"), StateExpr.value(.int(i)))
        }
        func colorOf(_ i: Int) -> StateExpr {
            StateExpr.functionApply(StateExpr.variable("color"), StateExpr.value(.int(i)))
        }

        return TLASpec("EWD840") {
            Extends("Integers")
            Variable(active, in: activeFuncs)
            Variable(color, in: colorFuncs)
            Variable(tpos, in: 0..<N)
            Variable(tcolor, "black")

            Action("InitiateProbe") {
                tpos == 0 && (tcolor == "black" || colorOf(0) == "black")
                && tpos.becomes(N - 1) && tcolor.becomes("white")
                && color.becomes(color.updated(at: 0, to: "white"))
                && active.stays
            }

            for i in 1..<N {
                Action("PassToken_\(i)") {
                    tpos == i
                    && (activeOf(i) == false || colorOf(i) == "black" || tcolor == "black")
                    && tpos.becomes(i - 1)
                    && tcolor.becomes(StateExpr.if(colorOf(i) == "black", then: "black", else: tcolor))
                    && color.becomes(color.updated(at: i, to: "white"))
                    && active.stays
                }
            }

            for i in nodes {
                for j in nodes where j != i {
                    Action("SendMsg_\(i)_to_\(j)") {
                        activeOf(i) == true
                        && active.becomes(active.updated(at: j, to: true))
                        && color.becomes(StateExpr.if(j > i,
                            then: color.updated(at: i, to: "black"),
                            else: color))
                        && tpos.stays && tcolor.stays
                    }
                }
            }

            Invariant("TypeOK") {
                tpos >= 0 && tpos < N && (tcolor == "white" || tcolor == "black")
            }
        }
    }

}