import SwiftTLA
import SwiftTLAMacros

/// The asynchronous-interface record from *Specifying Systems*.
///
/// The value, ready, and acknowledgement fields are formal record fields, so
/// the authored model and generated state machine share their names and types.
@TLAModel
package struct AsynchInterfaceModel: Sendable {
    package enum Data: String, CaseIterable, FiniteTLAValueDomain {
        case d1
        case d2
        case d3

        package static var defaultValue: Self { .d1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .string(rawValue) }
    }

    package struct InterfaceFields {
        package let value: Data
        package let ready: Int
        package let acknowledgement: Int
    }

    package enum InterfaceSchema: TLARecordSchema {
        package typealias Fields = InterfaceFields

        package static let fields: [TLARecordFieldDeclaration<Self>] = [
            .init(value, default: Data.d1),
            .init(ready, default: 0),
            .init(acknowledgement, default: 0),
        ]

        package static func fieldName<Value>(for field: KeyPath<InterfaceFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \InterfaceFields.value { return "val" }
            if key == \InterfaceFields.ready { return "rdy" }
            if key == \InterfaceFields.acknowledgement { return "ack" }
            return nil
        }

        package static let value = field(\InterfaceFields.value)
        package static let ready = field(\InterfaceFields.ready)
        package static let acknowledgement = field(\InterfaceFields.acknowledgement)
    }

    package static var spec: TLASpec {
        #spec("AsynchInterface") { scope in
            Extends(.naturals)
            let interface = scope.sharedVar("interface", in: SetExpr<Record<InterfaceSchema>>.literal(
                Record.literal(.init(InterfaceSchema.value, .d1), .init(InterfaceSchema.ready, 0), .init(InterfaceSchema.acknowledgement, 0)),
                Record.literal(.init(InterfaceSchema.value, .d1), .init(InterfaceSchema.ready, 0), .init(InterfaceSchema.acknowledgement, 1)),
                Record.literal(.init(InterfaceSchema.value, .d1), .init(InterfaceSchema.ready, 1), .init(InterfaceSchema.acknowledgement, 0)),
                Record.literal(.init(InterfaceSchema.value, .d1), .init(InterfaceSchema.ready, 1), .init(InterfaceSchema.acknowledgement, 1)),
                Record.literal(.init(InterfaceSchema.value, .d2), .init(InterfaceSchema.ready, 0), .init(InterfaceSchema.acknowledgement, 0)),
                Record.literal(.init(InterfaceSchema.value, .d2), .init(InterfaceSchema.ready, 0), .init(InterfaceSchema.acknowledgement, 1)),
                Record.literal(.init(InterfaceSchema.value, .d2), .init(InterfaceSchema.ready, 1), .init(InterfaceSchema.acknowledgement, 0)),
                Record.literal(.init(InterfaceSchema.value, .d2), .init(InterfaceSchema.ready, 1), .init(InterfaceSchema.acknowledgement, 1)),
                Record.literal(.init(InterfaceSchema.value, .d3), .init(InterfaceSchema.ready, 0), .init(InterfaceSchema.acknowledgement, 0)),
                Record.literal(.init(InterfaceSchema.value, .d3), .init(InterfaceSchema.ready, 0), .init(InterfaceSchema.acknowledgement, 1)),
                Record.literal(.init(InterfaceSchema.value, .d3), .init(InterfaceSchema.ready, 1), .init(InterfaceSchema.acknowledgement, 0)),
                Record.literal(.init(InterfaceSchema.value, .d3), .init(InterfaceSchema.ready, 1), .init(InterfaceSchema.acknowledgement, 1))
            ))

            Invariant("TypeInvariant") {
                (interface[InterfaceSchema.value] == .d1
                    || interface[InterfaceSchema.value] == .d2
                    || interface[InterfaceSchema.value] == .d3)
                    && interface[InterfaceSchema.ready] >= 0 && interface[InterfaceSchema.ready] <= 1
                    && interface[InterfaceSchema.acknowledgement] >= 0 && interface[InterfaceSchema.acknowledgement] <= 1
            }

            SwiftTLA.Action("Send") {
                interface[InterfaceSchema.ready] == interface[InterfaceSchema.acknowledgement]
                    && (interface.becomes(Record<InterfaceSchema>.literal(
                        .init(InterfaceSchema.value, Data.d1),
                        .init(InterfaceSchema.ready, 1 - interface[InterfaceSchema.ready]),
                        .init(InterfaceSchema.acknowledgement, interface[InterfaceSchema.acknowledgement])
                    ))
                    || interface.becomes(Record<InterfaceSchema>.literal(
                        .init(InterfaceSchema.value, Data.d2),
                        .init(InterfaceSchema.ready, 1 - interface[InterfaceSchema.ready]),
                        .init(InterfaceSchema.acknowledgement, interface[InterfaceSchema.acknowledgement])
                    ))
                    || interface.becomes(Record<InterfaceSchema>.literal(
                        .init(InterfaceSchema.value, Data.d3),
                        .init(InterfaceSchema.ready, 1 - interface[InterfaceSchema.ready]),
                        .init(InterfaceSchema.acknowledgement, interface[InterfaceSchema.acknowledgement])
                    )))
            }

            SwiftTLA.Action("Rcv") {
                interface[InterfaceSchema.ready] != interface[InterfaceSchema.acknowledgement]
                    && interface.becomes(Record<InterfaceSchema>.literal(
                        .init(InterfaceSchema.value, interface[InterfaceSchema.value]),
                        .init(InterfaceSchema.ready, interface[InterfaceSchema.ready]),
                        .init(InterfaceSchema.acknowledgement, 1 - interface[InterfaceSchema.acknowledgement])
                    ))
            }
        }
    }
}

extension Example {
    package static let asynchInterface = Entry(
        id: "SpecifyingSystems/AsynchInterface",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.tla",
        upstreamCfg: "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.cfg",
        expectedDistinct: 12,
        maximumStateLimit: 50_000,
        spec: AsynchInterfaceModel.spec,
        notes: "Asynchronous interface record, authored as a typed record and finite formal initial domain. TLC = 12."
    )
}
