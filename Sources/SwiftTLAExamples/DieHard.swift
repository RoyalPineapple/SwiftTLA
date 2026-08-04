import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct DieHard {
    var jug3 = Var(0)
    var jug5 = Var(0)

    func fill3()   { jug3.becomes(3) }
    func fill5()   { jug5.becomes(5) }
    func empty3()  { jug3.becomes(0) }
    func empty5()  { jug5.becomes(0) }

    func pour3to5() {
        (jug3 + jug5 <= 5) && jug5.becomes(jug3 + jug5) && jug3.becomes(0) ||
        (!(jug3 + jug5 <= 5)) && jug5.becomes(5) && jug3.becomes(jug3 - (5 - jug5))
    }

    func pour5to3() {
        (jug3 + jug5 <= 3) && jug3.becomes(jug3 + jug5) && jug5.becomes(0) ||
        (!(jug3 + jug5 <= 3)) && jug3.becomes(3) && jug5.becomes(jug5 - (3 - jug3))
    }
}
