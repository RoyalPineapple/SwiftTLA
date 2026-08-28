import SwiftTLA
import SwiftTLAMacros

/// The single-record asynchronous channel from *Specifying Systems*.
///
/// The finite initial domain, record field names, and every channel transition
/// are authored in the SwiftTLA DSL. The generated machine is therefore a
/// typed view of the same model used for parity checking.
@TLAModel
package struct ChannelModel: Sendable {
    package enum Data: String, CaseIterable, FiniteTLAValueDomain {
        case d1
        case d2
        case d3

        package static var defaultValue: Self { .d1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .string(rawValue) }
    }

    package struct ChannelFields {
        package let value: Data
        package let ready: Int
        package let acknowledgement: Int
    }

    package enum ChannelSchema: TLARecordSchema {
        package typealias Fields = ChannelFields

        package static let fields: [TLARecordFieldDeclaration<Self>] = [
            .init(value, default: Data.d1),
            .init(ready, default: 0),
            .init(acknowledgement, default: 0),
        ]

        package static func fieldName<Value>(for field: KeyPath<ChannelFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \ChannelFields.value { return "val" }
            if key == \ChannelFields.ready { return "rdy" }
            if key == \ChannelFields.acknowledgement { return "ack" }
            return nil
        }

        package static let value = field(\ChannelFields.value)
        package static let ready = field(\ChannelFields.ready)
        package static let acknowledgement = field(\ChannelFields.acknowledgement)
    }

    package static var spec: TLASpec {
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
    package static let channel = FiniteModelFixture(
        expectedDistinct: 12,
        maximumStateLimit: 50_000,
        spec: ChannelModel.spec,
    )
}
