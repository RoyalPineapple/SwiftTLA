import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct OrderedIntTraversalPass: Sendable {
    package enum Step: String, CaseIterable { case expand }

    package static var spec: TLASpec {
        #spec("OrderedIntTraversalPass") { scope in
            let pending = scope.sharedVar(initial: TupleExpr<Pair<Int, Bool>>())
            let leftChild = scope.sharedVar(initial: 0)
            let rightChild = scope.sharedVar(initial: 0)
            Do(Step.expand) {
                When(pending.count > 0)
                Let(pending[pending.count]) { frame in
                    When(!frame.second())
                    Assign(pending, to: pending.prefix(length: pending.count - 1)
                        .appending(Pair<Int, Bool>.literal(frame.first(), true.expr))
                        .appending(Pair<Int, Bool>.literal(rightChild, false.expr))
                        .appending(Pair<Int, Bool>.literal(leftChild, false.expr)))
                }
            }
        }
    }
}
