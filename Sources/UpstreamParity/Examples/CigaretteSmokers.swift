import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct CigaretteSmokersModel: Sendable {
    package static var spec: TLASpec {
        #spec("CigaretteSmokers") { scope in
            Extends(.integers)
            let smokingM = scope.sharedVar("smokingM", initial: false)
            let smokingP = scope.sharedVar("smokingP", initial: false)
            let smokingT = scope.sharedVar("smokingT", initial: false)
            let dealer = scope.sharedVar("dealer", in: 1...3)
            SwiftTLA.Action("start_1") {
                dealer == 1 && smokingT.becomes(true) && dealer.becomes(0) && smokingM.stays && smokingP.stays
            }
            SwiftTLA.Action("start_2") {
                dealer == 2 && smokingP.becomes(true) && dealer.becomes(0) && smokingM.stays && smokingT.stays
            }
            SwiftTLA.Action("start_3") {
                dealer == 3 && smokingM.becomes(true) && dealer.becomes(0) && smokingP.stays && smokingT.stays
            }
            SwiftTLA.Action("stop_m1") { dealer == 0 && smokingM == true && smokingM.becomes(false) && dealer.becomes(1) }
            SwiftTLA.Action("stop_m2") { dealer == 0 && smokingM == true && smokingM.becomes(false) && dealer.becomes(2) }
            SwiftTLA.Action("stop_m3") { dealer == 0 && smokingM == true && smokingM.becomes(false) && dealer.becomes(3) }
            SwiftTLA.Action("stop_p1") { dealer == 0 && smokingP == true && smokingP.becomes(false) && dealer.becomes(1) }
            SwiftTLA.Action("stop_p2") { dealer == 0 && smokingP == true && smokingP.becomes(false) && dealer.becomes(2) }
            SwiftTLA.Action("stop_p3") { dealer == 0 && smokingP == true && smokingP.becomes(false) && dealer.becomes(3) }
            SwiftTLA.Action("stop_t1") { dealer == 0 && smokingT == true && smokingT.becomes(false) && dealer.becomes(1) }
            SwiftTLA.Action("stop_t2") { dealer == 0 && smokingT == true && smokingT.becomes(false) && dealer.becomes(2) }
            SwiftTLA.Action("stop_t3") { dealer == 0 && smokingT == true && smokingT.becomes(false) && dealer.becomes(3) }
            Invariant("AtMostOne") {
                !(smokingM == true && smokingP == true)
                !(smokingM == true && smokingT == true)
                !(smokingP == true && smokingT == true)
            }
        }
    }
}

extension Example {
    package static let cigaretteSmokers = Entry(
        id: "CigaretteSmokers/CigaretteSmokers",
        upstreamSpec: "CigaretteSmokers",
        upstreamModule: "specifications/CigaretteSmokers/CigaretteSmokers.tla",
        upstreamCfg: "specifications/CigaretteSmokers/CigaretteSmokers.cfg",
        expectedDistinct: 6,
        spec: CigaretteSmokersModel.spec,
        notes: "Ingredients={m,p,t}, Offers=pairs. TLC TypeOK+AtMostOne = 6.",
    )
}
