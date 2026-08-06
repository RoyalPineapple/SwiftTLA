import SwiftTLA

// Die Hard 3: measure exactly 4 gallons using a 5-gallon and 3-gallon jug.
// Upstream: specifications/DieHard/DieHard.tla
// Port: 1:1 faithful translation. Safety only (TypeOK). 16 states.

extension Example {
    static let dieHardTypeOK = Entry(
        id: "DieHard/TypeOK",
        upstreamSpec: "DieHard",
        upstreamModule: "specifications/DieHard/DieHard.tla",
        upstreamCfg: nil,
        expectedDistinct: 16,
        expectedResult: "success",
        spec: dieHardSpec(),
        notes: "Upstream cfg adds NotSolved (intentional fail). TypeOK-only = 16.",
        matchesUpstreamTLC: true
    )
}

private func dieHardSpec() -> TLASpec {
    // ---------- VARIABLES ----------
    // big:   gallons of water in the 5-gallon jug.  Range: 0..5
    // small: gallons of water in the 3-gallon jug.  Range: 0..3
    let big   = Var<Int>("big",   value: 0)
    let small = Var<Int>("small", value: 0)

    return TLASpec("DieHard") {
        Extends("Naturals")

        // ---------- INITIAL PREDICATE ----------
        // Both jugs start empty.
        Variable(big,   0)
        Variable(small, 0)

        // ---------- TYPE INVARIANT ----------
        Invariant("TypeOK") {
            big   >= 0 && big   <= 5
            && small >= 0 && small <= 3
        }

        // ---------- ACTIONS ----------
        // Fill a jug completely.
        Action("FillSmallJug")  { small.becomes(3) }
        Action("FillBigJug")    { big.becomes(5)   }

        // Empty a jug completely.
        Action("EmptySmallJug") { small.becomes(0) }
        Action("EmptyBigJug")   { big.becomes(0)   }

        // Pour small into big.  Two cases: all fits, or big gets full.
        Action("SmallToBig") {
            (big + small <= 5) && big.becomes(big + small) && small.becomes(0)
            ||
            (big + small > 5)  && big.becomes(5) && small.becomes(small - (5 - big))
        }

        // Pour big into small.  Two cases: all fits, or small gets full.
        Action("BigToSmall") {
            (big + small <= 3) && small.becomes(big + small) && big.becomes(0)
            ||
            (big + small > 3)  && small.becomes(3) && big.becomes(big - (3 - small))
        }
    }
}
