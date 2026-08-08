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
                        st.becomes(Expr(StateExpr.except(
                            StateExpr.except(.variable("st"), .value(.string("val")), "d1"),
                            .value(.string("rdy")), 1 - st.rdy
                        ))))
                        || st.becomes(Expr(StateExpr.except(
                            StateExpr.except(.variable("st"), .value(.string("val")), "d2"),
                            .value(.string("rdy")), 1 - st.rdy
                        ))))
                        || st.becomes(Expr(StateExpr.except(
                            StateExpr.except(.variable("st"), .value(.string("val")), "d3"),
                            .value(.string("rdy")), 1 - st.rdy
                        ))))
                    )
                }
                Action("Rcv") {
                    st.rdy != st.ack
                        && st.becomes(Expr(.except(st, "ack", 1 - st.ack)))
                }
            }
        }(),
        notes: "Data={d1,d2,d3}. Record packing of val/rdy/ack. Upstream TLC = 12.",
    )

}
