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
            let chan = Var<TLAValue>("chan")
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
                    (StateExpr.recordAccess(chan.stateExpr, "val") == "d1"
                        || StateExpr.recordAccess(chan.stateExpr, "val") == "d2"
                        || StateExpr.recordAccess(chan.stateExpr, "val") == "d3")
                        && StateExpr.recordAccess(chan.stateExpr, "rdy") >= 0 && StateExpr.recordAccess(chan.stateExpr, "rdy") <= 1
                        && StateExpr.recordAccess(chan.stateExpr, "ack") >= 0 && StateExpr.recordAccess(chan.stateExpr, "ack") <= 1
                }
                Action("Send") {
                    StateExpr.recordAccess(chan.stateExpr, "rdy") == StateExpr.recordAccess(chan.stateExpr, "ack") && (
                        .assign(chan.name, chan.stateExpr
                            .updated(at: "val", to: "d1")
                            .updated(at: "rdy", to: StateExpr.subtract(.int(1), StateExpr.recordAccess(chan.stateExpr, "rdy"))))
                        || .assign(chan.name, chan.stateExpr
                            .updated(at: "val", to: "d2")
                            .updated(at: "rdy", to: StateExpr.subtract(.int(1), StateExpr.recordAccess(chan.stateExpr, "rdy"))))
                        || .assign(chan.name, chan.stateExpr
                            .updated(at: "val", to: "d3")
                            .updated(at: "rdy", to: StateExpr.subtract(.int(1), StateExpr.recordAccess(chan.stateExpr, "rdy"))))
                    )
                }
                Action("Rcv") {
                    StateExpr.recordAccess(chan.stateExpr, "rdy") != StateExpr.recordAccess(chan.stateExpr, "ack")
                        && .assign(chan.name, chan.stateExpr
                            .updated(at: "ack", to: StateExpr.subtract(.int(1), StateExpr.recordAccess(chan.stateExpr, "ack"))))
                }
            }
        }(),
        notes: "Same as AsynchInterface with single record variable `chan`. TLC = 12.",
    )

}
