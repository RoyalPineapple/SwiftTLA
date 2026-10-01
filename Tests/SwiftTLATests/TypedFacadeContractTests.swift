import Testing

@testable import SwiftTLA

@Suite("Typed facade contracts")
struct TypedFacadeContractTests {
  typealias Packet = GeneratedSwiftRecord.Packet

  @Test("indexed writable locations remain readable through their assignment-target contract")
  func indexedAssignmentTargets() {
    func read<Target: AssignmentTarget>(_ target: Target) -> Expr<Target.Value> {
      target.expr
    }
    let cars = Var<Function<CarID, Int>>("cars")
    let concrete = cars[CarID.carA]
    let symbolic = cars[Expr(CarID.carB)]
    let concreteMatches: Bool = read(concrete).stateExpr == cars.expr[CarID.carA].stateExpr
    let symbolicMatches: Bool = read(symbolic).stateExpr == cars.expr[Expr(CarID.carB)].stateExpr
    #expect(concreteMatches)
    #expect(symbolicMatches)
  }

  @Test("Boolean expressions and literals compose temporal implications")
  func typedTemporalImplications() {
    let ready = Var<Bool>("ready")
    let completed = Expr<Bool>(true)
    #expect(ready.leadsTo(completed).map(\.stateExpr) == .leadsTo(.variable("ready"), .value(.bool(true))))
    #expect(completed.leadsTo(false).map(\.stateExpr) == .leadsTo(.value(.bool(true)), .value(.bool(false))))
    #expect(true.leadsTo(ready).map(\.stateExpr) == .leadsTo(.value(.bool(true)), .variable("ready")))
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
    let cars = Var<Function<CarID, Packet>>("cars")
    let calls = Var<SetExpr<PersonID>>("calls")

    #expect(
      cars[.carA].count.raw
        == .recordAccess(
          .functionApply(.variable("cars"), .value(.string("carA"))),
          "count"
        ))
    #expect(
      calls.inserting(.alice)
        == .assign(
          .named("calls"),
          .union(.variable("calls"), .setLiteral([.value(.string("alice"))]))
        ))

    let update = cars.updating(.carA) { car in
      Packet.expression(count: 2, ready: car.ready)
    }
    let expected = StateExpr.except(
      .variable("cars"),
      .value(.string("carA")),
      .recordLiteral(.init(orderedFields: [
        .init(name: "count", value: .int(2)),
        .init(name: "ready", value: .recordAccess(
          .functionApply(.variable("cars"), .value(.string("carA"))), "ready"))
      ]))
    )
    #expect(update.raw == expected)

    let value = try compiledValue(update.raw, values: [
      ("cars", .function([
        .string("carA"): .record(["count": .int(0), "ready": .bool(false)]),
        .string("carB"): .record(["count": .int(1), "ready": .bool(true)])
      ]))
    ])
    #expect(
      value
        == .function([
          .string("carA"): .record(["count": .int(2), "ready": .bool(false)]),
          .string("carB"): .record(["count": .int(1), "ready": .bool(true)])
        ]))
  }

  @Test("ordinary Swift record expressions are usable as set elements")
  func recordExpressionSetOperationsLowerAndEvaluate() throws {
    let closed = Packet.expression(count: 0, ready: false)
    let open = Packet.expression(count: 1, ready: true)
    let cars = Function<CarID, Packet>.literal((.carA, closed), (.carB, open))
    let calls = Var<SetExpr<Packet>>("calls")
    let literal = SetExpr<Packet>.literal(closed, open)

    #expect(
      closed.raw == .recordLiteral(.init(orderedFields: [
        .init(name: "count", value: .int(0)), .init(name: "ready", value: .bool(false))
      ])))
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
          .string("carA"): .record(["count": .int(0), "ready": .bool(false)]),
          .string("carB"): .record(["count": .int(1), "ready": .bool(true)])
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
    #expect(build.output.contains("InvalidTypedFacade.swift:18:"))
    #expect(build.output.contains("member 'person'"))
    #expect(build.output.contains("requires that 'StateExpr' conform to 'TypedExpression'"))
    let errors = build.output.split(separator: "\n").filter { $0.contains(": error:") }
    #expect(errors.contains {
      $0.contains("InvalidTypedFacade.swift:24:")
        && $0.contains("requires that 'TLAValue' conform to '_GeneratedRecordValue'")
    })
    let rejectedLines = [18, 135, 136, 138, 139, 140, 143, 144, 146, 147]
      + Array(123...133) + Array(23...26) + Array(28...41) + Array(43...58) + Array(60...71)
    for line in rejectedLines {
      #expect(errors.contains { $0.contains("InvalidTypedFacade.swift:\(line):") },
              "Expected the invalid operation on fixture line \(line) to be rejected. Compiler errors:\n\(errors.joined(separator: "\n"))")
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
      "parameter 'direction' has duplicate finite-domain values"
    ] {
      #expect(build.output.contains(expected))
    }

    let unknownField = try buildExternalConsumer("InvalidTypedDSLUnknownField")
    #expect(unknownField.status != 0)
    #expect(unknownField.output.contains("InvalidTypedDSLUnknownField.swift:26:"))
    #expect(unknownField.output.contains("Statement 1 could not be decoded"))
    #expect(unknownField.output.contains("Assign(cars[.one].person, to: 2)"))
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
