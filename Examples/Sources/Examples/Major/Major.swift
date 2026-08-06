import SwiftTLA

public struct Majority {
    public static var spec: TLASpec {
        TLASpec("Majority") {
            Extends("Integers")
            let cand = Var("cand", value: 0)
            let cnt = Var("cnt", value: 0)
            let i = Var("i", value: 1)
            Variable(cand, 0)
            Variable(cnt, 0)
            Variable(i, 1)
            Definition("Value == {1, 2, 3}")
            Definition("seq == <<1, 2, 1>>")
            Invariant("TypeOK") { i >= 1 && i <= 4 && cand >= 0 && cand <= 3 && cnt >= 0 && cnt <= 3 }
            Action("Next") {
                (i <= 3) && i.becomes(i + 1) &&
                (cnt == 0 && cand.becomes(i) && cnt.becomes(1) ||
                 cnt != 0 && cand == i && cnt.becomes(cnt + 1) ||
                 cnt != 0 && cand != i && cnt.becomes(cnt - 1))
            }
            DeadlockCheck()
        }
    }
}
