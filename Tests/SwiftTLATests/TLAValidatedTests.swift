import Foundation
import SwiftTLA
import SwiftTLAMacros
import Testing

@TLAValidated
struct ValidatedSimple {
    static var spec: TLASpec {
        TLASpec("ValidatedSimple") {
            let flag = Var("flag", false)
            Variable(flag)
            Action("toggle") { flag == false && flag.becomes(true) }
        }
    }
}

@TLAValidated
actor ValidatedActor {
    static var spec: TLASpec {
        TLASpec("ValidatedActor") {
            let flag = Var("flag", false)
            Variable(flag)
            Action("toggle") { flag == false && flag.becomes(true) }
        }
    }
}

@TLAValidated
class ValidatedClass {
    static var spec: TLASpec {
        TLASpec("ValidatedClass") {
            let flag = Var("flag", false)
            Variable(flag)
            Action("toggle") { flag == false && flag.becomes(true) }
        }
    }
}

@Suite(.serialized)
struct TLAValidatedTests {
    @Test("@TLAValidated adds TLAModelType conformance on struct")
    func structConforms() {
        let _: any TLAModelType = ValidatedSimple()
    }

    @Test("@TLAValidated adds TLAModelType conformance on actor")
    func actorConforms() async {
        let _: any TLAModelType = ValidatedActor()
    }

    @Test("@TLAValidated adds TLAModelType conformance on class")
    func classConforms() {
        let _: any TLAModelType = ValidatedClass()
    }

    @Test("@TLAValidated generates no runtime members on struct")
    func structHasNoGeneratedMembers() {
        let mirror = Mirror(reflecting: ValidatedSimple())
        let labels = mirror.children.map { $0.label ?? "" }
        #expect(!labels.contains("_state"))
        #expect(!labels.contains("runtime"))
    }

    @Test("@TLAValidated generates no runtime members on actor")
    func actorHasNoGeneratedMembers() async {
        let mirror = Mirror(reflecting: ValidatedActor())
        let labels = mirror.children.map { $0.label ?? "" }
        #expect(!labels.contains("_state"))
        #expect(!labels.contains("runtime"))
    }

    @Test("@TLAValidated generates no runtime members on class")
    func classHasNoGeneratedMembers() {
        let mirror = Mirror(reflecting: ValidatedClass())
        let labels = mirror.children.map { $0.label ?? "" }
        #expect(!labels.contains("_state"))
        #expect(!labels.contains("runtime"))
    }

    @Test("@TLAModel regression: generates runtime members")
    func tlaModelRegression() {
        var model = RegressionModel()
        let mirror = Mirror(reflecting: model)
        let labels = mirror.children.map { $0.label ?? "" }
        #expect(labels.contains("_state"))
        model.applytoggle()
        #expect(model.flag == true)
        _ = type(of: model).runtime
    }

    @Test("@TLAActor regression: generates runtime members")
    func tlaActorRegression() async {
        let actor = RegressionActor()
        let mirror = Mirror(reflecting: actor)
        let labels = mirror.children.map { $0.label ?? "" }
        #expect(labels.contains("_state"))
        _ = type(of: actor).runtime
    }

    @Test("Invalid @TLAValidated spec emits compile-time diagnostic")
    func invalidSpecFailsMacroTimeCheck() throws {
        let root = FileManager.default.currentDirectoryPath
        let fixture = URL(fileURLWithPath: root)
            .appendingPathComponent("Tests/Fixtures/InvalidValidatedMacro")
        let result = try runSwift(["swift", "build", "--package-path", fixture.path])
        #expect(result.status != 0)
        #expect(result.output.contains("failed to receive result from plugin"))
    }

    private func runSwift(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftTLA-validated-fixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let outputURL = scratch.appendingPathComponent("output.txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments + ["--scratch-path", scratch.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        try output.close()

        let outputString = String(data: try Data(contentsOf: outputURL), encoding: .utf8) ?? ""
        return (process.terminationStatus, outputString)
    }
}

@TLAModel
struct RegressionModel {
    static var spec: TLASpec {
        TLASpec("RegressionModel") {
            let flag = Var("flag", false)
            Variable(flag)
            Action("toggle") { flag == false && flag.becomes(true) }
        }
    }
}

@TLAActor
actor RegressionActor {
    static var spec: TLASpec {
        TLASpec("RegressionActor") {
            let flag = Var("flag", false)
            Variable(flag)
            Action("toggle") { flag == false && flag.becomes(true) }
        }
    }
}
