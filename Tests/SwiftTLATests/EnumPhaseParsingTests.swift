import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct EnumPhaseParsingTests {
    @Test func enumFactsDoNotLeakFromOneParseIntoTheNextDecoderCall() throws {
        let closure = try parseSpecTestClosure("""
        {
            Invariant("idleOnly") { mode == CameraMode.idle }
        }
        """)

        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure, sourceTypes: .init(enums: [cameraModeDefinition]))
        #expect(parsed.invariants.first?.body == .equal(.variable("mode"), .value(.string("idle"))))
        #expect(
            SpecParser.decodeStateExpr(try parseSpecTestExpression("CameraMode.idle"))
                == .recordAccess(.variable("CameraMode"), "idle")
        )
    }

    @Test func parseQualifiedEnumCaseInInvariant() throws {
        let source = """
        {
            Invariant("idleOnly") {
                mode == CameraMode.idle
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure, sourceTypes: .init(enums: [cameraModeDefinition]))
        #expect(parsed.invariants.count == 1)
        #expect(parsed.invariants[0].body == .equal(.variable("mode"), .value(.string("idle"))))
    }

    @Test func parseEnumAssignment() throws {
        let source = """
        {
            Action("test") {
                mode.becomes(CameraMode.live)
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure, sourceTypes: .init(enums: [cameraModeDefinition]))
        #expect(parsed.actions.count == 1)
        #expect(parsed.actions[0].body == .assign(.named("mode"), .value(.string("live"))))
    }

    @Test("qualified formal Action parses as an action declaration")
    func parsesQualifiedFormalAction() throws {
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", try parseSpecTestClosure("""
        {
            SwiftTLA.Action("advance") {
                count.becomes(count + 1)
            }
        }
        """))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.actions == [
            .init(
                name: "advance",
                body: .assign(.named("count"), .add(.variable("count"), .value(.int(1))))
            )
        ])
    }

    @Test func parsesVariadicActionParametersInDeclarationOrder() throws {
        let source = """
        {
            Action("transfer", parameters: [
                ActionParameter("source", values: [1, 2]),
                ActionParameter("destination", values: [10, 20]),
                ActionParameter("amount", values: [100, 200])
            ]) {
                floor.becomes(1)
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.actions.count == 1)
        let action = try #require(parsed.actions.first)
        #expect(action.bindings.map(\.name) == ["source", "destination", "amount"])
        #expect(action.bindings.map(\.values) == [
            [.int(1), .int(2)], [.int(10), .int(20)], [.int(100), .int(200)]
        ])
        #expect(action.bindings.map(\.generatedSwiftType) == ["Int", "Int", "Int"])
        #expect(action.body == .assign(.named("floor"), .value(.int(1))))
    }

    @Test func declaredActionParametersRetainSourceAndFormalNames() throws {
        let parsed = SpecParser.parseSpecClosure(named: "Parameters", try parseSpecTestClosure("""
        {
            let choice = ActionParameter("selection", values: [1, 2])
            Action("choose", parameters: [choice]) {
                result.becomes(choice.expr + 1)
            }
        }
        """))
        #expect(parsed.diagnostics.isEmpty)
        let action = try #require(parsed.actions.first)
        #expect(action.bindings.map(\.name) == ["selection"])
        #expect(action.bindings.map(\.generatedSwiftType) == ["Int"])
        #expect(action.body == .assign(.named("result"), .add(.variable("selection"), .int(1))))
    }

    @Test func mutableActionParameterDeclarationsAreRejected() throws {
        let parsed = SpecParser.parseSpecClosure(named: "Parameters", try parseSpecTestClosure("""
        {
            var choice = ActionParameter("selection", values: [1, 2])
        }
        """))
        #expect(parsed.diagnostics.contains { $0.message.contains("must be declared once with let") })
    }

    @Test func parsesParameterizedActionLocalBindingsInLexicalScope() throws {
        let source = """
        {
            Action("pass", parameters: [
                ActionParameter("from", values: [1, 2]),
                ActionParameter("to", values: [1, 2]),
                ActionParameter("round", values: [1, 2])
            ]) {
                let from = Expr<Int>(.variable("from"))
                let to = Expr<Int>(.variable("to"))
                let round = Expr<Int>(.variable("round"))
                leader == from && leader.becomes(to + round)
            }
        }
        """

        let parsed = SpecParser.parseSpecClosure(named: "Parsed", try parseSpecTestClosure(source))

        try #require(parsed.diagnostics.isEmpty)
        #expect(parsed.actions[0].bindings.map(\.name) == ["from", "to", "round"])
        #expect(parsed.actions[0].body == .and(
            .guard_(.equal(.variable("leader"), .variable("from"))),
            .assign(.named("leader"), .add(.variable("to"), .variable("round")))
        ))
    }

    @Test func diagnosesInvalidDomainsAtEveryParameterPosition() throws {
        let source = """
        {
            Action("transfer", parameters: [
                ActionParameter("source", values: sourceIDs),
                ActionParameter("destination", values: []),
                ActionParameter("amount", values: [1, 1])
            ]) {
                floor.becomes(1)
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)
        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Parameterized action 'transfer' parameter 'source' requires an explicitly written finite values array.",
            "Parameterized action 'transfer' parameter 'destination' requires a non-empty finite values array.",
            "Parameterized action 'transfer' parameter 'amount' has duplicate finite-domain values."
        ])
    }

    @Test func normalizesTypedFacadeAndEnumDomainsToBuilderAST() throws {
        let source = """
        {
            let floor = Var<Int>("floor")
            let cars = Var<Function<CarID, Record<CarSchema>>>("cars")
            let calls = Var<SetExpr<Record<CarSchema>>>("calls")
            Variable(floor, 0)
            Variable(cars, Function<CarID, Record<CarSchema>>.literal(
                (CarID.carA, Record<CarSchema>.literal(
                    .init(CarSchema.floor, 0),
                    .init(CarSchema.doorsOpen, false)
                )),
                (CarID.carB, Record<CarSchema>.literal(
                    .init(CarSchema.floor, 1),
                    .init(CarSchema.doorsOpen, true)
                ))
            ))
            Variable(calls, SetExpr<Record<CarSchema>>())
            Action("move", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                cars.becomes(cars.updating(.carA) { car in
                    car.updating(CarSchema.floor, to: 2)
                })
            }
            Action("readCar") {
                floor.becomes(cars[CarID.carA][CarSchema.floor])
            }
            Action("initialize") {
                cars.becomes(Function<CarID, Record<CarSchema>>.literal(
                    (CarID.carA, Record<CarSchema>.literal(
                        .init(CarSchema.floor, 0),
                        .init(CarSchema.doorsOpen, false)
                    )),
                    (CarID.carB, Record<CarSchema>.literal(
                        .init(CarSchema.floor, 1),
                        .init(CarSchema.doorsOpen, true)
                    ))
                ))
            }
            Action("insertCall") {
                calls.inserting(Record<CarSchema>.literal(
                    .init(CarSchema.floor, 0),
                    .init(CarSchema.doorsOpen, false)
                ))
            }
            Action("removeCall") {
                calls.removing(Record<CarSchema>.literal(
                    .init(CarSchema.floor, 0),
                    .init(CarSchema.doorsOpen, false)
                ))
            }
            Action("containsCall") {
                calls.contains(Record<CarSchema>.literal(
                    .init(CarSchema.floor, 0),
                    .init(CarSchema.doorsOpen, false)
                )) && floor.becomes(1)
            }
        }
        """
        let enums = [
            parserTestEnum("PersonID", cases: ["alice": .string("alice"), "bob": .string("bob")]),
            parserTestEnum("CarID", cases: ["carA": .string("carA"), "carB": .string("carB")]),
            parserTestEnum(
                "Direction",
                cases: ["up": .string("up"), "down": .string("down")],
                finiteValues: [.string("up"), .string("down")]
            )
        ]
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed",
            closure,
            sourceTypes: .init(records: ["CarSchema": [
                .init(sourceName: "floor", name: "floor", swiftType: "Int"),
                .init(sourceName: "doorsOpen", name: "doorsOpen", swiftType: "Bool")
            ]], enums: enums)
        )

        let floor = Var<Int>("floor")
        let cars = Var<Function<TestCarID, Record<TestCarSchema>>>("cars")
        let calls = Var<SetExpr<Record<TestCarSchema>>>("calls")
        let closed = Record<TestCarSchema>.literal(
            .init(TestCarSchema.floor, 0),
            .init(TestCarSchema.doorsOpen, false)
        )
        let open = Record<TestCarSchema>.literal(
            .init(TestCarSchema.floor, 1),
            .init(TestCarSchema.doorsOpen, true)
        )
        let bindings = [
            ActionParameter("person", values: TestPersonID.finiteValues).actionBinding,
            ActionParameter("car", values: TestCarID.finiteValues).actionBinding,
            ActionParameter("direction", values: TestDirection.finiteValues).actionBinding
        ]
        let builderActions: [(String, ActionExpr, [ActionBinding])] = [
            ("move", cars.becomes(cars.updating(.carA) { car in
                car.updating(TestCarSchema.floor, to: 2)
            }), bindings),
            ("readCar", floor.becomes(cars[.carA][TestCarSchema.floor]), []),
            ("initialize", cars.becomes(
                Function<TestCarID, Record<TestCarSchema>>.literal((.carA, closed), (.carB, open))), []),
            ("insertCall", calls.inserting(closed), []),
            ("removeCall", calls.removing(closed), []),
            ("containsCall", calls.contains(closed) && floor.becomes(1), [])
        ]

        #expect(parsed.diagnostics.isEmpty)
        #expect(Set(parsed.variables.map(\.name)) == ["floor", "cars", "calls"])
        #expect(parsed.actions.count == builderActions.count)
        #expect(parsed.actions[0].bindings.map(\.generatedSwiftType) == ["PersonID", "CarID", "Direction"])
        for (parsedAction, builtAction) in zip(parsed.actions, builderActions) {
            #expect(parsedAction.name == builtAction.0)
            #expect(parsedAction.body == builtAction.1)
            #expect(parsedAction.bindings.map(\.name) == builtAction.2.map(\.name))
            #expect(parsedAction.bindings.map(\.values) == builtAction.2.map(\.values))
        }
    }

    @Test func diagnosesUnsupportedTypedUpdateAtItsSource() throws {
        let source = """
        {
            Action("update", parameters: [
                ActionParameter("person", values: ["alice", "bob"])
            ]) {
                car.becomes(car.updating(CarSchema.field(dynamicKeyPath), to: 2))
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Parameterized action 'update' contains an unsupported typed update; use a directly written finite enum case or schema field token."
        ])
        #expect(parsed.diagnostics.first?.source.contains("dynamicKeyPath") == true)
    }

    @Test func macroAcceptsLocalEnumFiniteDomainsInOrderedBindings() throws {
        #expect(TypedFacadeEnumDomainMacro.spec.actions.first?.bindings == [
            ActionBinding(name: "person", values: [.string("alice"), .string("bob")]),
            ActionBinding(name: "car", values: [.string("carA"), .string("carB")]),
            ActionBinding(name: "direction", values: [.string("up"), .string("down")])
        ])
    }

    @Test("macro parser and result builder produce one generated surface identity")
    func macroParserAndResultBuilderShareGeneratedSurfaceIdentity() throws {
        let compilation = try TypedFacadeEnumDomainMacro.spec.compile()

        #expect(compilation.description.identity == compilation.identity)
        _ = try TypedFacadeEnumDomainMacro.makeMachine()
    }

    @Test("Invariant diagnostics identify a failed statement after valid local bindings", arguments: ["var mutable = 0", "UnsupportedPredicate()"])
    func invariantDiagnosticsRetainFailureLocation(_ statement: String) throws {
        let source = """
        {
            Invariant("bad") {
                let value = Expr<Int>(1)
                value == 1
                \(statement)
            }
        }
        """
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", try parseSpecTestClosure(source))
        #expect(parsed.invariants.isEmpty)
        let diagnostic = try #require(parsed.diagnostics.first)
        #expect(diagnostic.source == statement)
        let range = try #require(source.range(of: statement))
        #expect(diagnostic.sourceSpan.location == .utf8Offset(source[..<range.lowerBound].utf8.count))
    }

    @Test func rejectsUnsupportedInvariantSource() throws {
        let source = """
        {
            Invariant("bad") {
                mode == CameraMode.unknown
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure, sourceTypes: .init(enums: [cameraModeDefinition]))
        #expect(parsed.invariants.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Invariant 'bad' contains an unsupported invariant expression."
        ])
    }

    @Test func parseEnumInvariant() throws {
        let source = """
        {
            Invariant("notError") {
                mode != CameraMode.error
            }
        }
        """
        let enums = [
            parserTestEnum("CameraMode", cases: ["idle": .string("idle"), "error": .string("error")])
        ]
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure, sourceTypes: .init(enums: enums))
        #expect(parsed.invariants.count == 1)
        #expect(parsed.invariants[0].body == .notEqual(.variable("mode"), .value(.string("error"))))
    }

    @Test func parseInitializedEnumVar() throws {
        let source = """
        {
            let mode = Var<CameraMode>(CameraMode.idle)
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure, sourceTypes: .init(enums: [cameraModeDefinition]))
        #expect(parsed.variables.count == 1)
        #expect(parsed.variables[0].name == "mode")
        #expect(parsed.variables[0].initialization == .value(.string("idle")))
        #expect(parsed.variables[0].generatedSwiftType == "CameraMode")
    }

}
