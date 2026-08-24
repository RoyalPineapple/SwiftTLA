import SwiftTLA
import SwiftTLAMacros

/// The single-record asynchronous channel from *Specifying Systems*.
///
/// The finite initial domain, record field names, and every channel transition
/// are authored in the SwiftTLA DSL. The generated machine is therefore a
/// typed view of the same model used for parity checking.
@TLAModel
public struct ChannelModel: Sendable {
    public enum Data: String, CaseIterable, FiniteTLAValueDomain {
        case d1
        case d2
        case d3

        public static var defaultValue: Self { .d1 }
        public static let finiteValues = allCases
        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public struct ChannelFields {
        public let value: Data
        public let ready: Int
        public let acknowledgement: Int
    }

    public enum ChannelSchema: TLARecordSchema {
        public typealias Fields = ChannelFields

        public static let fieldNames: Set<String> = ["val", "rdy", "ack"]
        public static let defaultRecord: TLAValue = .record([
            "val": .string(Data.d1.rawValue), "rdy": .int(0), "ack": .int(0)
        ])

        public static func fieldName<Value>(for field: KeyPath<ChannelFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \ChannelFields.value { return "val" }
            if key == \ChannelFields.ready { return "rdy" }
            if key == \ChannelFields.acknowledgement { return "ack" }
            return nil
        }

        public static let value = field(\ChannelFields.value)
        public static let ready = field(\ChannelFields.ready)
        public static let acknowledgement = field(\ChannelFields.acknowledgement)
    }

    public static var spec: TLASpec {
        #spec("Channel") { scope in
            Extends(.naturals)
            let channel = scope.sharedVar("channel", in: SetExpr<Record<ChannelSchema>>.literal(
                Record.literal(.init(ChannelSchema.value, .d1), .init(ChannelSchema.ready, 0), .init(ChannelSchema.acknowledgement, 0)),
                Record.literal(.init(ChannelSchema.value, .d1), .init(ChannelSchema.ready, 0), .init(ChannelSchema.acknowledgement, 1)),
                Record.literal(.init(ChannelSchema.value, .d1), .init(ChannelSchema.ready, 1), .init(ChannelSchema.acknowledgement, 0)),
                Record.literal(.init(ChannelSchema.value, .d1), .init(ChannelSchema.ready, 1), .init(ChannelSchema.acknowledgement, 1)),
                Record.literal(.init(ChannelSchema.value, .d2), .init(ChannelSchema.ready, 0), .init(ChannelSchema.acknowledgement, 0)),
                Record.literal(.init(ChannelSchema.value, .d2), .init(ChannelSchema.ready, 0), .init(ChannelSchema.acknowledgement, 1)),
                Record.literal(.init(ChannelSchema.value, .d2), .init(ChannelSchema.ready, 1), .init(ChannelSchema.acknowledgement, 0)),
                Record.literal(.init(ChannelSchema.value, .d2), .init(ChannelSchema.ready, 1), .init(ChannelSchema.acknowledgement, 1)),
                Record.literal(.init(ChannelSchema.value, .d3), .init(ChannelSchema.ready, 0), .init(ChannelSchema.acknowledgement, 0)),
                Record.literal(.init(ChannelSchema.value, .d3), .init(ChannelSchema.ready, 0), .init(ChannelSchema.acknowledgement, 1)),
                Record.literal(.init(ChannelSchema.value, .d3), .init(ChannelSchema.ready, 1), .init(ChannelSchema.acknowledgement, 0)),
                Record.literal(.init(ChannelSchema.value, .d3), .init(ChannelSchema.ready, 1), .init(ChannelSchema.acknowledgement, 1))
            ))

            Invariant("TypeInvariant") {
                (channel[ChannelSchema.value] == .d1
                    || channel[ChannelSchema.value] == .d2
                    || channel[ChannelSchema.value] == .d3)
                    && channel[ChannelSchema.ready] >= 0 && channel[ChannelSchema.ready] <= 1
                    && channel[ChannelSchema.acknowledgement] >= 0 && channel[ChannelSchema.acknowledgement] <= 1
            }

            SwiftTLA.Action("Send") {
                channel[ChannelSchema.ready] == channel[ChannelSchema.acknowledgement]
                    && (channel.becomes(Record<ChannelSchema>.literal(
                        .init(ChannelSchema.value, Data.d1),
                        .init(ChannelSchema.ready, 1 - channel[ChannelSchema.ready]),
                        .init(ChannelSchema.acknowledgement, channel[ChannelSchema.acknowledgement])
                    ))
                    || channel.becomes(Record<ChannelSchema>.literal(
                        .init(ChannelSchema.value, Data.d2),
                        .init(ChannelSchema.ready, 1 - channel[ChannelSchema.ready]),
                        .init(ChannelSchema.acknowledgement, channel[ChannelSchema.acknowledgement])
                    ))
                    || channel.becomes(Record<ChannelSchema>.literal(
                        .init(ChannelSchema.value, Data.d3),
                        .init(ChannelSchema.ready, 1 - channel[ChannelSchema.ready]),
                        .init(ChannelSchema.acknowledgement, channel[ChannelSchema.acknowledgement])
                    )))
            }

            SwiftTLA.Action("Rcv") {
                channel[ChannelSchema.ready] != channel[ChannelSchema.acknowledgement]
                    && channel.becomes(Record<ChannelSchema>.literal(
                        .init(ChannelSchema.value, channel[ChannelSchema.value]),
                        .init(ChannelSchema.ready, channel[ChannelSchema.ready]),
                        .init(ChannelSchema.acknowledgement, 1 - channel[ChannelSchema.acknowledgement])
                    ))
            }
        }
    }
}

extension Example {
    public static let channel = Entry(
        id: "SpecifyingSystems/Channel",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/AsynchronousInterface/Channel.tla",
        upstreamCfg: "specifications/SpecifyingSystems/AsynchronousInterface/Channel.cfg",
        expectedDistinct: 12,
        spec: ChannelModel.spec,
        notes: "Single-record channel, authored as typed records and a finite formal initial domain. TLC = 12."
    )
}
