import SwiftTLA
import SwiftTLAMacros

/// Bounded external-admission witness for a procedure frame. It exercises a
/// typed parameter, procedure-local state, call, return, and generated model
/// surface without introducing legacy TLA+ authoring declarations.
@TLAModel
public struct K5ProcedureCallReturnWitness {
    public static var spec: TLASpec {
        #spec("K5ProcedureCallReturnWitness") {
            Algorithm("K5ProcedureCallReturnWitness") {
                let output = SharedVar(initial: 0)

                Procedure("addOffset", parameters: Int.self) { value in
                    let offset = LocalVar(initial: 2)
                    Do("apply") {
                        Assign(output, to: value.expr + offset.expr)
                        Return()
                    }
                }

                Do("start") { Call("addOffset", with: 5) }
                Do("done") { Stop() }
            }
        }
    }
}
