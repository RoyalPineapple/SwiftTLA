@testable import SwiftTLA
@testable import SwiftTLAPlugin

func checkingRegisterDeclarationSpec() throws -> TLASpec {
    SpecParser.parseSpecClosure(named: "InitializedCheckingRegisters", try parseSpecTestClosure("""
        { scope in
            let initialFreeze = scope.parameter(as: Int.self, in: 0...999)
            let firstFreeze = scope.checkingRegister(as: Int.self, initial: initialFreeze)
            let found = scope.checkingRegister(as: Bool.self, initial: false)
            let value = scope.sharedVar(initial: 0)
        }
        """))
}
