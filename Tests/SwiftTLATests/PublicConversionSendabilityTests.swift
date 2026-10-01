import SwiftTLA
import Testing

@Suite struct PublicConversionSendabilityTests {
    @Test("public formal conversion values are Sendable")
    func conversionProtocolsRequireSendable() {
        func requireSendable<Value: Sendable>(_: Value.Type) {}
        requireSendable((any StateExprConvertible).self)
        requireSendable((any TLAValueConvertible).self)
    }
}
