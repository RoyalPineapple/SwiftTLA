import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConvergingFrontiers {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ConvergingFrontiers") {
            Algorithm("ConvergingFrontiers", scoped: { scope in
                let node = scope.sharedVar(_name: "node", in: SetExpr<Int>.literal(1, 3))
                While(Step.advance, true) {
                    When(node <= 128)
                    If(node == 3 || node == 128) {
                        Assign(node, to: 256)
                    } else: {
                        Choose(0...1) { branch in
                            Assign(node, to: node * 2 + branch)
                        }
                    }
                }
            })
        }
    }
}
