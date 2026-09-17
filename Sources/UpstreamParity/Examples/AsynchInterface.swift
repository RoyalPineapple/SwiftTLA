import SwiftTLA
import SwiftTLAMacros

/// The asynchronous handshake from *Specifying Systems*.
@TLAModel
package struct AsynchInterfaceModel: Sendable {
    package enum Datum: String, CaseIterable, FiniteTLAValueDomain {
        case d1, d2, d3
        case ap1 = "d1_OF_DATUM", ap2 = "d2_OF_DATUM"

        package static var defaultValue: Self { .d1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .d1, .d2, .d3: .constant(rawValue)
            case .ap1, .ap2: .string(rawValue)
            }
        }
    }

    package enum Step: String, CaseIterable { case Send, Rcv }

    package static var spec: TLASpec {
        #spec("AsynchInterface") { scope in
            Extends(.naturals)
            let Data = scope.parameter(as: Set<Datum>.self, in: Set<Set<Datum>>([
                Set<Datum>([Datum.d1, Datum.d2, Datum.d3]), Set<Datum>([Datum.ap1, Datum.ap2])
            ]))
            let val = scope.sharedVar(in: Data)
            let rdy = scope.sharedVar(in: 0...1)
            let ack = scope.sharedVar(initial: rdy)
            let TypeInvariant = Invariant()

            Do(Step.Send) {
                When(rdy == ack)
                With(Data) { datum in
                    Assign(val, to: datum)
                }
                Assign(rdy, to: 1 - rdy)
            }
            Do(Step.Rcv) {
                When(rdy != ack)
                Assign(ack, to: 1 - ack)
            }
            TypeInvariant {
                Data.contains(val) && rdy >= 0 && rdy <= 1 && ack >= 0 && ack <= 1
            }
            Validation("Upstream") { Bind(Data, to: Set<Datum>([Datum.d1, Datum.d2, Datum.d3])) }
            Validation("APAsynchInterface") { Bind(Data, to: Set<Datum>([Datum.ap1, Datum.ap2])) }
        }
    }
}
