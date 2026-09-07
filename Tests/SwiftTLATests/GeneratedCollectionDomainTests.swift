import Testing
@testable import SwiftTLA

@Suite struct GeneratedCollectionDomainTests {
    private struct Device: Identifiable, Sendable { let id: Int }

    @Test("generated collection decoding rejects extra formal members before committing")
    func rejectsUndeclaredMembers() throws {
        let devices = SymmetricCollectionVar<Device, Int>("devices")
        let declaration = SymmetricCollection(devices, verificationScope: 1, initial: 0)
        let specification = TLASpec("CollectionDomain") {
            declaration
            SwiftTLA.Action("extend") {
                ActionExpr.assign(.named("devices"), .functionLiteral(
                    .union(.domain(.variable("devices")), .setLiteral([.value(.string("undeclared"))])),
                    "member",
                    .ifThenElse(
                        .in(.variable("member"), .domain(.variable("devices"))),
                        .functionApply(.variable("devices"), .variable("member")),
                        .int(2)
                    )
                ))
            }
        }
        var storage = try _GeneratedMachineStorage<[Int: Int], Int>(
            compilation: specification.compile(), initial: nil,
            stateDecoder: { try $0.decodeCollection(applicationMembers: [1]) },
            actionDecoders: [{ _ in 0 }], actionValidator: { _ in }
        )
        #expect(storage.state == [1: 0])
        #expect(throws: GeneratedMachineStateDiagnostic.self) { try storage.send(0) }
        #expect(storage.state == [1: 0])
    }
}
