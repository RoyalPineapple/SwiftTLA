import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct UnboundedLocalRecursionFixture: Sendable {
    static var spec: TLASpec {
        #spec("UnboundedLocalRecursionFixture") {
            Assume(LetRec("SumTo", taking: Int.self,
                { (recursion: LocalRecursion<Int, Int>, number: WithValue<Int>) in
                    If(number == 0, then: 0,
                        else: number.expr + recursion(number.expr - 1))
                }, in: { recursion in recursion(4) == 10 }))
            Validation("sum") {}.checkingDeadlock(false)
        }
    }
}
