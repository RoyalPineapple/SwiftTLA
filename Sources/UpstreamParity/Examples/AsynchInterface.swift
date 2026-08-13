import SwiftTLA

extension Example {
    public static let asynchInterface = Entry(
        id: "SpecifyingSystems/AsynchInterface",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.tla",
        upstreamCfg: "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.cfg",
        expectedDistinct: 12,
        spec: {
            let data = ["d1", "d2", "d3"]
            let st = Var<TLAValue>("st")
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
                    (StateExpr.recordAccess(st.stateExpr, "val") == "d1"
                        || StateExpr.recordAccess(st.stateExpr, "val") == "d2"
                        || StateExpr.recordAccess(st.stateExpr, "val") == "d3")
                        && StateExpr.recordAccess(st.stateExpr, "rdy") >= 0 && StateExpr.recordAccess(st.stateExpr, "rdy") <= 1
                        && StateExpr.recordAccess(st.stateExpr, "ack") >= 0 && StateExpr.recordAccess(st.stateExpr, "ack") <= 1
                }
                Action("Send") {
                    StateExpr.recordAccess(st.stateExpr, "rdy") == StateExpr.recordAccess(st.stateExpr, "ack") && (
                        .assign(st.name, st.stateExpr
                            .updated(at: "val", to: "d1")
                            .updated(at: "rdy", to: StateExpr.subtract(.int(1), StateExpr.recordAccess(st.stateExpr, "rdy"))))
                        || .assign(st.name, st.stateExpr
                            .updated(at: "val", to: "d2")
                            .updated(at: "rdy", to: StateExpr.subtract(.int(1), StateExpr.recordAccess(st.stateExpr, "rdy"))))
                        || .assign(st.name, st.stateExpr
                            .updated(at: "val", to: "d3")
                            .updated(at: "rdy", to: StateExpr.subtract(.int(1), StateExpr.recordAccess(st.stateExpr, "rdy"))))
                    )
                }
                Action("Rcv") {
                    StateExpr.recordAccess(st.stateExpr, "rdy") != StateExpr.recordAccess(st.stateExpr, "ack")
                        && .assign(st.name, st.stateExpr
                            .updated(at: "ack", to: StateExpr.subtract(.int(1), StateExpr.recordAccess(st.stateExpr, "ack"))))
                }
            }
        }(),
        notes: "Data={d1,d2,d3}. Record packing of val/rdy/ack. Upstream TLC = 12.",
    )

}
