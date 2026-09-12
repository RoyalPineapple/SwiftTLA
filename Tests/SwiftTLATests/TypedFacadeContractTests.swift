import Testing

@testable import SwiftTLA

@Suite("Typed facade contracts")
struct TypedFacadeContractTests {
  @Test("Boolean expressions and literals compose temporal implications")
  func typedTemporalImplications() {
    let ready = Var<Bool>("ready")
    let completed = Expr<Bool>(true)
    #expect(ready.leadsTo(completed) == .leadsTo(.variable("ready"), .value(.bool(true))))
    #expect(completed.leadsTo(false) == .leadsTo(.value(.bool(true)), .value(.bool(false))))
    #expect(true.leadsTo(ready) == .leadsTo(.value(.bool(true)), .variable("ready")))
  }

  @Test("Boolean literals compose on either side of typed comparisons", arguments: [false, true])
  func booleanLiteralComparisons(value: Bool) throws {
    let expression = Expr(value)
    let opposite: Bool = !value
    let predicates: [Expr<Bool>] = [
      expression == value, value == expression,
      expression != opposite, opposite != expression
    ]
    for predicate in predicates {
      #expect(try compiledValue(predicate.raw) == .bool(true))
    }
  }

  @Test("Integer-backed identities compare within their declared domain")
  func orderedIdentityPredicates() throws {
    enum Rank: Int, FiniteTLAValueDomain {
      case low = 1, high = 2
      static var defaultValue: Self { .low }
      static let finiteValues: [Self] = [.low, .high]
    }
    let low = Expr(Rank.low)
    let high = Expr(Rank.high)
    let ordered: Expr<Bool> = low < high && low <= high && high > low && high >= low
    #expect(try compiledValue(ordered.raw) == .bool(true))
    #expect(try compiledValue((high < low).raw) == .bool(false))
  }

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

  @Test("Conditional branches retain enum context for values and expressions")
  func conditionalBranchesAcceptEnumLiterals() throws {
    let person = PersonID.bob.expr
    let literalFirst = If(true, then: .alice, else: person)
    let literalLast = If(false, then: person, else: .alice)
    #expect(try compiledValue(literalFirst.stateExpr) == .string("alice"))
    #expect(try compiledValue(literalLast.stateExpr) == .string("alice"))
  }

  @Test("Collection expressions retain contextual enum literals")
  func collectionExpressionsAcceptEnumLiterals() throws {
    let empty = SetExpr<PersonID>().expr
    let inserted = empty.inserting(.alice)
    #expect(try compiledValue(inserted.stateExpr) == .set([.string("alice")]))
    #expect(try compiledValue(inserted.contains(.alice).stateExpr) == .bool(true))
    let sequence = TupleExpr<PersonID>().expr.appending(.alice)
    #expect(try compiledValue(sequence.stateExpr) == .tuple([.string("alice")]))
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

    let value = try compiledValue(update.raw, values: [
      ("cars", .function([
        .string("carA"): .record(["floor": .int(0), "doorsOpen": .bool(false)]),
        .string("carB"): .record(["floor": .int(1), "doorsOpen": .bool(true)])
      ]))
    ])
    #expect(
      value
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
    #expect(calls.contains(closed).raw == .in(closed.raw, .variable("calls")))
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
    let build = try buildExternalConsumer("InvalidTypedFacade")

    #expect(build.status != 0)
    #expect(build.output.contains("TLAField"))
    #expect(build.output.contains("InvalidTypedFacade.swift:32:"))
    #expect(build.output.contains("member 'person'"))
    #expect(build.output.contains("no exact matches in call to instance method 'becomes'"))
    #expect(build.output.contains("candidate expects value of type 'TLAValue'"))
    #expect(build.output.contains("value of type 'Expr<TLAValue>' has no member 'becomes'"))
    let errors = build.output.split(separator: "\n").filter { $0.contains(": error:") }
    let rejectedLines = [32, 33, 151, 152, 154, 155, 156, 159, 160, 162, 163] + Array(139...149) + Array(38...41) + Array(43...56) + Array(58...73) + Array(75...86)
    for line in rejectedLines {
      #expect(errors.contains { $0.contains("InvalidTypedFacade.swift:\(line):") },
              "Expected the invalid operation on fixture line \(line) to be rejected")
    }
  }

  @Test("typed DSL invalid fixture reports each source-local diagnostic")
  func invalidTypedDSLReportsSourceLocalDiagnostics() throws {
    let build = try buildExternalConsumer("InvalidTypedDSL")

    #expect(build.status != 0)
    for expected in [
      "InvalidTypedDSL.swift:27:",
      "parameter 'person' requires an explicitly written finite values array",
      "InvalidTypedDSL.swift:44:",
      "parameter 'car' requires a non-empty finite values array",
      "InvalidTypedDSL.swift:61:",
      "parameter 'direction' has duplicate finite-domain values",
      "InvalidTypedDSL.swift:98:",
      "Parameterized action 'unsupportedUpdate' contains an unsupported typed update; use a directly written finite enum case or schema field token."
    ] {
      #expect(build.output.contains(expected))
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
