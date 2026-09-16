import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftTLAPlugin

func swiftRecordModel(target: String = "packet", replacement: String = "Packet(count: saved.count + 1, ready: true)") throws -> MacroCompilation {
    let source = Parser.parse(source: """
        struct RecordMachine {
            struct Packet: Hashable, Sendable { let count: Int; let ready: Bool }
            struct Other: Hashable, Sendable { let count: Int; let ready: Bool }
            enum Step: String, CaseIterable { case advance }
            static var spec: TLASpec {
                #spec("Records") { scope in
                    let packet = scope.sharedVar("packet", initial: Packet(count: 0, ready: false))
                    Algorithm("Records") {
                        Do(Step.advance) {
                            let saved = packet
                            Assign(\(target), to: \(replacement))
                            Stop()
                        }
                    }
                    Invariant("Bounded") { packet.count <= 1 }
                }
            }
        }
        """)
    let model = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
    return try TLASpecVerifier.parseAndVerify(model)
}
