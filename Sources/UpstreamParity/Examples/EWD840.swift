import SwiftTLA

extension Example {
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

static func ewd840Spec() -> TLASpec {
        let N = 3
        let nodes = Array(0..<N)
        let boolOpts: [TLAValue] = [.bool(false), .bool(true)]
        let colorOpts: [TLAValue] = [.string("white"), .string("black")]
        var activeFuncs: [TLAValue] = []
        for a0 in boolOpts { for a1 in boolOpts { for a2 in boolOpts {
            activeFuncs.append(.function([.int(0): a0, .int(1): a1, .int(2): a2]))
        }}}
        var colorFuncs: [TLAValue] = []
        for c0 in colorOpts { for c1 in colorOpts { for c2 in colorOpts {
            colorFuncs.append(.function([.int(0): c0, .int(1): c1, .int(2): c2]))
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
