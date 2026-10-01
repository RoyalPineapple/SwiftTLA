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
        #expect(action.bindings.map(\.literalMembers) == [
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
            "Parameterized action 'update' contains an unsupported typed update; use a statically named field or finite enum case."
        ])
        #expect(parsed.diagnostics.first?.source.contains("dynamicKeyPath") == true)
    }

    @Test func macroAcceptsLocalEnumFiniteDomainsInOrderedBindings() throws {
        #expect(TypedFacadeEnumDomainMacro.spec.actions.first?.bindings == [
            ActionParameter("person", values: TypedFacadeEnumDomainMacro.PersonID.finiteValues).actionBinding,
            ActionParameter("car", values: TypedFacadeEnumDomainMacro.CarID.finiteValues).actionBinding,
            ActionParameter("direction", values: TypedFacadeEnumDomainMacro.Direction.finiteValues).actionBinding
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
        { scope in
            let mode = scope.sharedVar(initial: CameraMode.idle)
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure, sourceTypes: .init(enums: [cameraModeDefinition]))
        #expect(parsed.variables.count == 1)
        let variable = try #require(parsed.variables.first)
        #expect(variable.name == "mode")
        #expect(variable.initialization == .value(.string("idle")))
        #expect(variable.generatedSwiftType == "CameraMode")
    }

}
