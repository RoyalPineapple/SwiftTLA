import SwiftTLA
import SwiftTLAMacros

/// The asynchronous handshake from *Specifying Systems*.
@TLAModel
package struct AsynchInterfaceModel: Sendable {
    package enum Data: String, CaseIterable, FiniteTLAValueDomain {
        case d1, d2, d3

        package static var defaultValue: Self { .d1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package static var spec: TLASpec {
        #spec("AsynchInterface") { scope in
            Extends(.naturals)
            let val = scope.sharedVar("val", in: Data.all)
            let rdy = scope.sharedVar("rdy", in: 0...1)
            let ack = scope.sharedVar("ack", initial: rdy.expr)

            Invariant("TypeInvariant") {
                Data.all.contains(val) && rdy >= 0 && rdy <= 1 && ack >= 0 && ack <= 1
            }
            SwiftTLA.Action("Send") {
                rdy == ack
                    && (val.becomes(Data.d1) || val.becomes(Data.d2) || val.becomes(Data.d3))
                    && rdy.becomes(1 - rdy)
            }
            SwiftTLA.Action("Rcv") {
                rdy != ack && ack.becomes(1 - ack)
            }
        }
    }
}

extension Example {
    package static let asynchInterface = FiniteModelFixture(
        expectedDistinct: 12,
        maximumStateLimit: 50_000,
        spec: AsynchInterfaceModel.spec
    )
}
