import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct DieHard {
    static var spec: TLASpec {
        TLASpec("DieHard") {
            let jug3 = Var(0)
            let jug5 = Var(0)
            Action("fill3")  { jug3.becomes(3) }
            Action("fill5")  { jug5.becomes(5) }
            Action("empty3") { jug3.becomes(0) }
            Action("empty5") { jug5.becomes(0) }
            Action("pour3to5") {
                (jug3 + jug5 <= 5) && jug5.becomes(jug3 + jug5) && jug3.becomes(0) ||
                (!(jug3 + jug5 <= 5)) && jug5.becomes(5) && jug3.becomes(jug3 - (5 - jug5))
            }
            Action("pour5to3") {
                (jug3 + jug5 <= 3) && jug3.becomes(jug3 + jug5) && jug5.becomes(0) ||
                (!(jug3 + jug5 <= 3)) && jug3.becomes(3) && jug5.becomes(jug5 - (3 - jug3))
            }
        }
    }
}
