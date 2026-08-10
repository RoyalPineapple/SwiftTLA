import SwiftTLA

extension Example {
    public static let cigaretteSmokers = Entry(
        id: "CigaretteSmokers/CigaretteSmokers",
        upstreamSpec: "CigaretteSmokers",
        upstreamModule: "specifications/CigaretteSmokers/CigaretteSmokers.tla",
        upstreamCfg: "specifications/CigaretteSmokers/CigaretteSmokers.cfg",
        expectedDistinct: 6,
        spec: cigaretteSmokersSpec(),
        notes: "Ingredients={m,p,t}, Offers=pairs. TLC TypeOK+AtMostOne = 6.",
    )

    static func cigaretteSmokersSpec() -> TLASpec {
        TLASpec("CigaretteSmokers") {
            Extends("Integers")
            let sm = Var<Bool>("smoking_m")
            let sp = Var<Bool>("smoking_p")
            let st = Var<Bool>("smoking_t")
            let dealer = Var<Int>("dealer")
            Variable(sm, false); Variable(sp, false); Variable(st, false)
            Variable(dealer, in: 1...3)
            Action("start_1") {
                dealer == 1 && st.becomes(true) && dealer.becomes(0) && sm.stays && sp.stays
            }
            Action("start_2") {
                dealer == 2 && sp.becomes(true) && dealer.becomes(0) && sm.stays && st.stays
            }
            Action("start_3") {
                dealer == 3 && sm.becomes(true) && dealer.becomes(0) && sp.stays && st.stays
            }
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
                !(sm == true && sp == true)
                !(sm == true && st == true)
                !(sp == true && st == true)
            }
        }
    }
}
