import Foundation
import Testing

@testable import SwiftTLA
import UpstreamParity

@Suite("Multi-car elevator typed DSL")
struct MultiCarElevatorDSLTests {
  enum CarID: String, CaseIterable, FiniteTLAValueDomain {
    case carA
    case carB

    static let finiteValues = allCases
  }

  enum PersonID: String, CaseIterable, FiniteTLAValueDomain {
    case alice
    case bob

    static let finiteValues = allCases
  }

  struct CarFields {
    let floor: Int
    let doorsOpen: Bool
  }

  enum CarSchema: TLARecordSchema {
    typealias Fields = CarFields
    static let fieldNames: Set<String> = ["floor", "doorsOpen"]

    static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
      let key = field as AnyKeyPath
      if key == \CarFields.floor { return "floor" }
      if key == \CarFields.doorsOpen { return "doorsOpen" }
      return nil
    }

    static let floor = field(\CarFields.floor)
    static let doorsOpen = field(\CarFields.doorsOpen)
  }

  @Test("typed reads, set mutation, and nested update lower to the existing AST")
  func typedFacadeLowersAndEvaluates() throws {
    let cars = Var<Function<CarID, Record<CarSchema>>>("cars")
    let calls = Var<SetExpr<PersonID>>("calls")

    #expect(
      cars[.carA][CarSchema.floor].raw
        == .recordAccess(
          .functionApply(.variable("cars"), .value(.string("carA"))),
          "floor"
        ))
    #expect(
      calls.inserting(.alice)
        == .assign(
          "calls",
          .union(.variable("calls"), .setLiteral([.value(.string("alice"))]))
        ))

    let update = cars.updating(.carA) { car in
      car.updating(CarSchema.floor, to: 2)
    }
    let expected = StateExpr.except(
      .variable("cars"),
      .value(.string("carA")),
      .except(
        .functionApply(.variable("cars"), .value(.string("carA"))),
        .value(.string("floor")),
        .value(.int(2))
      )
    )
    #expect(update.raw == expected)

    let result = try update.raw.evaluate(in: [
      "cars": .function([
        .string("carA"): .record(["floor": .int(0), "doorsOpen": .bool(false)]),
        .string("carB"): .record(["floor": .int(1), "doorsOpen": .bool(true)])
      ])
    ])
    #expect(
      result
        == .function([
          .string("carA"): .record(["floor": .int(2), "doorsOpen": .bool(false)]),
          .string("carB"): .record(["floor": .int(1), "doorsOpen": .bool(true)])
        ]))
  }

  @Test("typed record expressions are usable as set elements")
  func recordExpressionSetOperationsLowerAndEvaluate() throws {
    let closed = Record<CarSchema>.literal(
      .init(CarSchema.floor, 0),
      .init(CarSchema.doorsOpen, false)
    )
    let open = Record<CarSchema>.literal(
      .init(CarSchema.floor, 1),
      .init(CarSchema.doorsOpen, true)
    )
    let cars = Function<CarID, Record<CarSchema>>.literal((.carA, closed), (.carB, open))
    let calls = Var<SetExpr<Record<CarSchema>>>("calls")
    let literal = SetExpr<Record<CarSchema>>.literal(closed, open)

    #expect(
      closed.raw == .recordLiteral(["floor": .value(.int(0)), "doorsOpen": .value(.bool(false))]))
    #expect(literal.raw == .setLiteral([closed.raw, open.raw]))
    #expect(
      calls.inserting(closed)
        == .assign("calls", .union(.variable("calls"), .setLiteral([closed.raw]))))
    #expect(
      calls.removing(closed)
        == .assign("calls", .setDifference(.variable("calls"), .setLiteral([closed.raw]))))
    #expect(calls.contains(closed) == .in(closed.raw, .variable("calls")))
    guard case .functionLiteral = cars.raw else {
      Issue.record("Expected the typed function literal to lower to StateExpr.functionLiteral")
      return
    }
    #expect(
      try cars.raw.evaluate(in: [:])
        == .function([
          .string("carA"): .record(["floor": .int(0), "doorsOpen": .bool(false)]),
          .string("carB"): .record(["floor": .int(1), "doorsOpen": .bool(true)])
        ]))
  }

  @Test("finite string domains choose a declared default")
  func finiteDomainDefaultIsValidatedAndUsable() {
    #expect(CarID.defaultValue == .carA)
    #expect(PersonID.defaultValue == .alice)
    #expect(CarID.tlaValues == [.string("carA"), .string("carB")])
  }

  @Test("finite function indexes reject values omitted from the declared domain")
  func omittedFiniteDomainValueIsRejectedBeforeLowering() throws {
    let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidTypedFacadeRuntime")
    let result = try runSwift(["run", "--package-path", fixture.path])

    #expect(result.status != 0)
    #expect(result.output.contains("not declared by OmittedID.finiteValues"))
  }

  @Test("typed facade compile-negative fixtures reject escape hatches")
  func invalidTypedFacadeUsesDoNotTypeCheck() throws {
    let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidTypedFacade")
    let result = try runSwift(["build", "--package-path", fixture.path])

    #expect(result.status != 0)
    #expect(result.output.contains("TLAField"))
    #expect(result.output.contains("InvalidTypedFacade.swift:30:"))
    #expect(result.output.contains("member 'person'"))
    #expect(result.output.contains("no exact matches in call to instance method 'becomes'"))
    #expect(result.output.contains("candidate expects value of type 'TLAValue'"))
    #expect(result.output.contains("value of type 'Expr<TLAValue>' has no member 'becomes'"))
    for member in [
      "floor", "updated", "applying", "union", "intersection", "subtracting", "isSubset", "isIn",
      "cardinality", "isEmpty", "flattened", "subsets", "domain", "count", "head", "tail", "filtering",
      "mapping", "appending", "concatenating", "at", "integerDivided"
    ] {
      #expect(
        result.output.contains("value of type 'Var<TLAValue>' has no member '\(member)'"))
      #expect(
        result.output.contains("value of type 'Expr<TLAValue>' has no member '\(member)'"))
    }
  }

  @Test("typed elevator invalid fixture reports each source-local diagnostic")
  func invalidTypedElevatorDSLReportsSourceLocalDiagnostics() throws {
    let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidTypedElevatorDSL")
    let result = try runSwift([
      "build", "--package-path", fixture.path, "--target", "InvalidTypedElevatorDSL"
    ])

    #expect(result.status != 0)
    for expected in [
      "InvalidTypedElevatorDSL.swift:40:",
      "parameter 'person' requires an explicitly written finite values array",
      "InvalidTypedElevatorDSL.swift:57:",
      "parameter 'car' requires a non-empty finite values array",
      "InvalidTypedElevatorDSL.swift:74:",
      "parameter 'direction' has duplicate finite-domain values",
      "InvalidTypedElevatorDSL.swift:94:",
      "Parameterized action 'unsupportedUpdate' contains an unsupported typed update; use a directly written finite enum case or schema field token."
    ] {
      #expect(result.output.contains(expected))
    }

    let unknownField = try runSwift([
      "build", "--package-path", fixture.path, "--target", "InvalidTypedElevatorDSLUnknownField"
    ])
    #expect(unknownField.status != 0)
    #expect(unknownField.output.contains("InvalidTypedElevatorDSLUnknownField.swift:35:"))
    #expect(unknownField.output.contains("type 'CarSchema' has no member 'person'"))
  }

  @Test("explicit core AST boundaries remain available to untyped callers")
  func explicitCoreASTBoundariesRemainAvailable() {
    let raw = Var<TLAValue>("raw")
    let expression = StateExpr.variable(raw.name)
    let action = ActionExpr.assign(raw.name, expression.updated(at: 1, to: 2))

    #expect(
      action
        == .assign(
          "raw",
          .except(.variable("raw"), .value(.int(1)), .value(.int(2)))
        ))
  }

  @Test("bounded elevator builder and macro fixtures preserve the complete typed model")
  func boundedElevatorFixtureChecksAndExports() throws {
    let builder = MultiCarElevator.builderSpec
    let macro = MultiCarElevatorMacroFixture.spec

    #expect(normalize(builder) == normalize(macro))

    let checker = ModelChecker(spec: MultiCarElevatorModel.spec, maxStates: 30_000)
    guard case .ok(let stateCount) = try checker.check() else {
      Issue.record("Bounded MultiCarElevator safety model did not complete successfully")
      return
    }
    #expect(stateCount == 3_276)

    #expect(wrapperLines(in: macro.tlaModule) == expectedWrapperLines)
  }

  private func normalize(_ spec: TLASpec) -> ParsedSpecModel {
    ParsedSpecModel(
      variables: spec.variables.map { ($0.name, $0.initial) },
      actions: spec.actions.map { ($0.name, $0.body, $0.bindings) },
      invariants: spec.invariants.map { ($0.name, $0.body) }
    )
  }

  private func wrapperLines(in tla: String) -> [String] {
    tla.split(separator: "\n").map(String.init).filter { line in
      line.contains("__") && line.contains(" == ")
    }
  }

  private var expectedWrapperLines: [String] {
    let people: [TLAValue] = [.string("alice"), .string("bob")]
    let cars: [TLAValue] = [.string("carA"), .string("carB")]
    let floors: [TLAValue] = [.int(0), .int(1), .int(2)]
    let directions: [TLAValue] = [.string("up"), .string("down")]
    let actionDomains: [(String, [[TLAValue]])] = [
      ("request", [people, floors, directions]),
      ("assign", [people, cars, directions]),
      ("move", [cars, directions, floors]),
      ("openDoor", [cars, floors, directions]),
      ("board", [people, cars, floors]),
      ("closeDoor", [cars, floors, directions]),
      ("completeRide", [people, cars, floors])
    ]
    return actionDomains.flatMap { name, domains in
      cartesianValues(domains).map { indices, values in
        let suffix = indices.map(String.init).joined(separator: "_")
        let arguments = values.map(\.description).joined(separator: ", ")
        return "\(name)__\(suffix) == \(name)(\(arguments))"
      }
    }
  }

  private func cartesianValues(_ domains: [[TLAValue]]) -> [([Int], [TLAValue])] {
    guard let first = domains.first else { return [([], [])] }
    return first.enumerated().flatMap { index, value in
      cartesianValues(Array(domains.dropFirst())).map { indices, values in
        ([index] + indices, [value] + values)
      }
    }
  }

  private func runSwift(_ arguments: [String]) throws -> (status: Int32, output: String) {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftTLA-typed-facade-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift"] + arguments + ["--scratch-path", scratch.path]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return (
      process.terminationStatus,
      String(data: outputData, encoding: .utf8) ?? ""
    )
  }

  private func packageRoot() -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      directory.deleteLastPathComponent()
    }
    return directory
  }
}
