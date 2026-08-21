import SwiftTLA
import SwiftTLAMacros

/// The asynchronous-interface record from *Specifying Systems*.
///
/// The value, ready, and acknowledgement fields are formal record fields, so
/// the authored model and generated state machine share their names and types.
@TLAModel
public struct AsynchInterfaceModel: Sendable {
    public enum Data: String, CaseIterable, FiniteDomainKey {
        case d1
        case d2
        case d3

        public static var defaultValue: Self { .d1 }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "examples.asynch-interface.data")
        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public struct InterfaceFields {
        public let value: Data
        public let ready: Int
        public let acknowledgement: Int
    }

    public enum InterfaceSchema: TLARecordSchema {
        public typealias Fields = InterfaceFields

        public static let fieldNames: Set<String> = ["val", "rdy", "ack"]
        public static let defaultRecord: TLAValue = .record([
            "val": .string(Data.d1.rawValue), "rdy": .int(0), "ack": .int(0),
        ])

        public static func fieldName<Value>(for field: KeyPath<InterfaceFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \InterfaceFields.value { return "val" }
            if key == \InterfaceFields.ready { return "rdy" }
            if key == \InterfaceFields.acknowledgement { return "ack" }
            return nil
        }

        public static let value = field(\InterfaceFields.value)
        public static let ready = field(\InterfaceFields.ready)
        public static let acknowledgement = field(\InterfaceFields.acknowledgement)
    }

    public static var spec: TLASpec {
        #spec("AsynchInterface") {
            Extends(.naturals)
            let interface = SharedVar("interface", in: SetExpr<Record<InterfaceSchema>>.literal(
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

            Action("Send") {
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

            Action("Rcv") {
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
    public static let asynchInterface = Entry(
        id: "SpecifyingSystems/AsynchInterface",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.tla",
        upstreamCfg: "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.cfg",
        expectedDistinct: 12,
        spec: AsynchInterfaceModel.spec,
        notes: "Asynchronous interface record, authored as a typed record and finite formal initial domain. TLC = 12."
    )
}
