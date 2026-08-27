import Testing

@testable import SwiftTLA

@Suite("Typed facade contracts")
struct TypedFacadeContractTests {
  enum CarID: String, CaseIterable, FiniteTLAValueDomain {
    case carA
    case carB

    static var defaultValue: Self { .carA }
    static let finiteValues = allCases
  }

  enum PersonID: String, CaseIterable, FiniteTLAValueDomain {
    case alice
    case bob

    static var defaultValue: Self { .alice }
    static let finiteValues = allCases
  }

  struct CarFields {
    let floor: Int
    let doorsOpen: Bool
  }

  enum CarSchema: TLARecordSchema {
    typealias Fields = CarFields
    static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
      let key = field as AnyKeyPath
      if key == \CarFields.floor { return "floor" }
      if key == \CarFields.doorsOpen { return "doorsOpen" }
      return nil
    }

    static let floor = field(\CarFields.floor)
    static let doorsOpen = field(\CarFields.doorsOpen)
    static let fields = [
      TLARecordFieldDeclaration(floor, default: 0),
      TLARecordFieldDeclaration(doorsOpen, default: false)
    ]
  }

  struct GarageFields {
    let car: Record<CarSchema>
    let owner: PersonID
  }

  enum GarageSchema: TLARecordSchema {
    typealias Fields = GarageFields

    static func fieldName<Value>(for field: KeyPath<GarageFields, Value>) -> String? {
      let key = field as AnyKeyPath
      if key == \GarageFields.car { return "car" }
      if key == \GarageFields.owner { return "owner" }
      return nil
    }

    static let car = field(\GarageFields.car)
    static let owner = field(\GarageFields.owner)
    static let fields = [
      TLARecordFieldDeclaration(car, default: Record<CarSchema>()),
      TLARecordFieldDeclaration(owner, default: PersonID.alice)
    ]
  }

  @Test("record decoding validates declared fields and nested values")
  func recordDecodingValidatesSchema() throws {
    #expect(Record<CarSchema>(formalValue: .record([
      "floor": .bool(false),
      "doorsOpen": .bool(false)
    ])) == nil)
    #expect(Record<CarSchema>(formalValue: .record(TLARecord([
      .init("floor", .int(0)),
      .init("floor", .int(1))
    ]))) == nil)
    #expect(Record<CarSchema>(formalValue: .record(["floor": .int(0)])) == nil)
    #expect(Record<CarSchema>(formalValue: .record([
      "floor": .int(0),
      "doorsOpen": .bool(false),
      "owner": .string("alice")
    ])) == nil)

    let formal: TLAValue = .record([
      "car": .record(["floor": .int(2), "doorsOpen": .bool(true)]),
      "owner": .string("bob")
    ])
    let garage = try #require(Record<GarageSchema>(formalValue: formal))
    #expect(garage.tlaValue == formal)
    #expect(garage.value(for: GarageSchema.owner) == .bob)
    #expect(garage.value(for: GarageSchema.car)?.value(for: CarSchema.floor) == 2)
  }

  @Test("typed reads, set mutation, and nested updates lower to typed expressions")
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
          .named("calls"),
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

    let result = try compiledValue(update.raw, values: [
      ("cars", .function([
        .string("carA"): .record(["floor": .int(0), "doorsOpen": .bool(false)]),
        .string("carB"): .record(["floor": .int(1), "doorsOpen": .bool(true)])
      ]))
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
      closed.raw == StateExpr.record(["floor": .value(.int(0)), "doorsOpen": .value(.bool(false))]))
    #expect(literal.raw == .setLiteral([closed.raw, open.raw]))
    #expect(
      calls.inserting(closed)
        == .assign(.named("calls"), .union(.variable("calls"), .setLiteral([closed.raw]))))
    #expect(
      calls.removing(closed)
        == .assign(.named("calls"), .setDifference(.variable("calls"), .setLiteral([closed.raw]))))
    #expect(calls.contains(closed) == .in(closed.raw, .variable("calls")))
    guard case .functionLiteral = cars.raw else {
      Issue.record("Expected the typed function literal to lower to StateExpr.functionLiteral")
      return
    }
    #expect(
      try compiledValue(cars.raw)
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

  @Test("typed facade compile-negative fixtures reject escape hatches")
  func invalidTypedFacadeUsesDoNotTypeCheck() throws {
    let result = try buildExternalConsumer("InvalidTypedFacade")

    #expect(result.status != 0)
    #expect(result.output.contains("TLAField"))
    #expect(result.output.contains("InvalidTypedFacade.swift:32:"))
    #expect(result.output.contains("member 'person'"))
    #expect(result.output.contains("no exact matches in call to instance method 'becomes'"))
    #expect(result.output.contains("candidate expects value of type 'TLAValue'"))
    #expect(result.output.contains("value of type 'Expr<TLAValue>' has no member 'becomes'"))
    for member in [
      "floor", "updated", "applying", "union", "intersection", "subtracting", "isSubset", "isIn",
      "cardinality", "isEmpty", "flattened", "subsets", "domain", "count", "head", "tail", "filtering",
      "mapping", "appending", "concatenating", "at", "integerDivided"
    ] {
      #expect(result.output.contains("'\(member)'"))
    }
  }

  @Test("typed DSL invalid fixture reports each source-local diagnostic")
  func invalidTypedDSLReportsSourceLocalDiagnostics() throws {
    let result = try buildExternalConsumer("InvalidTypedDSL")

    #expect(result.status != 0)
    for expected in [
      "InvalidTypedDSL.swift:41:",
      "parameter 'person' requires an explicitly written finite values array",
      "InvalidTypedDSL.swift:58:",
      "parameter 'car' requires a non-empty finite values array",
      "InvalidTypedDSL.swift:75:",
      "parameter 'direction' has duplicate finite-domain values",
      "InvalidTypedDSL.swift:96:",
      "Parameterized action 'unsupportedUpdate' contains an unsupported typed update; use a directly written finite enum case or schema field token."
    ] {
      #expect(result.output.contains(expected))
    }

    let unknownField = try buildExternalConsumer("InvalidTypedDSLUnknownField")
    #expect(unknownField.status != 0)
    #expect(unknownField.output.contains("InvalidTypedDSLUnknownField.swift:39:"))
    #expect(unknownField.output.contains("type 'CarSchema' has no member 'person'"))
  }

  @Test("formal AST construction is explicit")
  func formalASTConstructionIsExplicit() {
    let raw = Var<TLAValue>("raw")
    let expression = StateExpr.variable(raw.name)
    let action = ActionExpr.assign(.named(raw.name), expression.updated(at: 1, to: 2))

    #expect(
      action
        == .assign(
          .named("raw"),
          .except(.variable("raw"), .value(.int(1)), .value(.int(2)))
        ))
  }
}
