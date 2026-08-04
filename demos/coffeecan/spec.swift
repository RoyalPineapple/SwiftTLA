import SwiftTLA

let bk = Var<Int>("black"); let wt = Var<Int>("white")
let maxB = 5
let coffeeCan = TLASpec("CoffeeCan") {
    Variable(bk, maxB); Variable(wt, maxB)
    Act("BB") { (bk >= 2) && (bk.next == bk - 1) && (wt.next == wt) }
    Act("WW") { (wt >= 2) && (wt.next == wt - 2) && (bk.next == bk + 1) }
    Act("BW") { (bk >= 1) && (wt >= 1) && (wt.next == wt - 1) && (bk.next == bk) }
    Invariant("WhiteParity") { (wt % 2) == (maxB % 2) }
}
