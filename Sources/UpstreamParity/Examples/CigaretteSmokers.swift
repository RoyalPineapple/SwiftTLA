import SwiftTLA

extension Example {
    public static let cigaretteSmokers = Entry(
        id: "CigaretteSmokers/CigaretteSmokers",
        upstreamSpec: "CigaretteSmokers",
        upstreamModule: "specifications/CigaretteSmokers/CigaretteSmokers.tla",
        upstreamCfg: "specifications/CigaretteSmokers/CigaretteSmokers.cfg",        spec: cigaretteSmokersSpec(),
        notes: "Ingredients={m,p,t}, Offers=pairs. TLC TypeOK+AtMostOne = 6.",
    )

static func cigaretteSmokersSpec() -> TLASpec {
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

}
