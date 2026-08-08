import SwiftTLA

extension Example {
    public static let channel = Entry(
        id: "SpecifyingSystems/Channel",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/AsynchronousInterface/Channel.tla",
        upstreamCfg: "specifications/SpecifyingSystems/AsynchronousInterface/Channel.cfg",
        expectedDistinct: 12,
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
                        chan.becomes(Expr(StateExpr.except(
                            StateExpr.except(.variable("chan"), .value(.string("val")), "d1"),
                            .value(.string("rdy")), 1 - chan.rdy
                        ))))
                        || chan.becomes(Expr(StateExpr.except(
                            StateExpr.except(.variable("chan"), .value(.string("val")), "d2"),
                            .value(.string("rdy")), 1 - chan.rdy
                        ))))
                        || chan.becomes(Expr(StateExpr.except(
                            StateExpr.except(.variable("chan"), .value(.string("val")), "d3"),
                            .value(.string("rdy")), 1 - chan.rdy
                        ))))
                    )
                }
                Action("Rcv") {
                    chan.rdy != chan.ack
                        && chan.becomes(Expr(.except(chan, "ack", 1 - chan.ack)))
                }
            }
        }(),
        notes: "Same as AsynchInterface with single record variable `chan`. TLC = 12.",
    )

}
