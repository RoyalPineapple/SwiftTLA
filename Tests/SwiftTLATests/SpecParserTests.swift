import Testing
import SwiftSyntax
import SwiftParser
import SwiftTLA
import SwiftTLAMacros

// Proves SpecParser's compact decoder produces the same AST as the runtime
// builder for every expression form in the DSL. Each test parses a source
// string and compares the result to the equivalent value built through
// Swift's type system (operator overloads and method calls).

// MARK: - Helpers

private func parseExpression(_ source: String) -> ExprSyntax {
    Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
}

@Suite(.serialized) struct AlgorithmBuilderParsingTests {
    @Test("Algorithm Each Do syntax lowers through the ordinary parser AST")
    func parsesBoundedAlgorithm() {
        let source = """
        {
            Algorithm("Counter") {
                let count = SharedVar(initial: 0)
                Each(Node.all) { node in
                    Do("increment") {
                        Await(count < 2)
                        Assign(count, to: count + 1)
                    }
                }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDomains: ["Node": [.string("left"), .string("right")]]
        )

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.map(\.name) == ["count", "pc"])
        #expect(parsed.actions.map(\.name) == ["increment", "Terminating"])
        #expect(parsed.actions.first?.bindings == [
            ActionBinding(name: "process", values: [.string("left"), .string("right")])
        ])
        #expect(parsed.actions.first?.bindingSwiftTypes == ["process": "Node"])
    }

    @Test("Algorithm parser rejects declarations it does not lower")
    func rejectsUnsupportedAlgorithmDeclaration() {
        let source = """
        {
            Algorithm("Unsupported") {
                UnsupportedAlgorithmConstruct()
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.actions.isEmpty)
        #expect(
            parsed.diagnostics.first?.message
                == "Unsupported Algorithm declaration 'UnsupportedAlgorithmConstruct()'. Supported declarations are SharedVar, Each, Do, and While."
        )
    }

    @Test("parser lowers the mechanical PlusCal statements through the shared IR")
    func parsesMechanicalPlusCalStatements() {
        let source = """
        {
            Algorithm("Counter") {
                let count = SharedVar(initial: 0)
                Each(Node.all, fairness: .strong) { node in
                    While("increment", count < 2) {
                        When(count >= 0)
                        With(Node.all) { choice in
                            Assert(choice == node)
                            Assign(count, to: count + 1)
                        }
                    }
                }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDomains: ["Node": [.string("left"), .string("right")]]
        )

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.invariants.map(\.name) == ["__pcal_assert_increment_0_0", "__pcal_assert_increment_0_1"])
        #expect(parsed.fairness == [
            .strongFairnessInvocation(.init(name: "increment", arguments: [.string("left")])),
            .strongFairnessInvocation(.init(name: "increment", arguments: [.string("right")]))
        ])
    }

    @Test("parsed Algorithm actions match runtime-builder normalization")
    func parserTreeMatchesRuntimeAlgorithm() {
        let source = """
        {
            Algorithm("Counter") {
                let count = SharedVar(initial: 0)
                Each(Node.all) { _ in
                    Do("increment") {
                        Await(count < 2)
                        Assign(count, to: count + 1)
                    }
                }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDomains: ["Node": [.string("left"), .string("right")]]
        )
        let runtime = TLASpec("Counter") {
            Algorithm("Counter") {
                let count = SharedVar("count", initial: 0)
                count
                Each(ParserNode.all) { _ in
                    Do("increment") {
                        Await(count < 2)
                        Assign(count, to: count + 1)
                    }
                }
            }
        }
        let runtimeTree = ParsedSpecModel(
            variables: runtime.variables.map { ($0.name, $0.initial, $0.initialSet) },
            actions: runtime.actions.map { ($0.name, $0.body, $0.bindings) },
            invariants: runtime.invariants.map { ($0.name, $0.body) }
        )
        let parserTree = ParsedSpecModel(
            variables: parsed.variables.map { ($0.name, $0.initial, $0.initialSet) },
            actions: parsed.actions.map { ($0.name, $0.body, $0.bindings) },
            invariants: parsed.invariants
        )
        #expect(parserTree == runtimeTree)
    }
}

private enum ParserNode: String, FiniteDomainKey {
    case left
    case right

    static let formalDomain: [ParserNode] = [.left, .right]
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.parser-node")

    var tlaValue: TLAValue { .string(rawValue) }
}

// MARK: - StateExpr: literals

@Suite(.serialized) struct StateExprLiteralTests {
    @Test func parseInts() {
        #expect(SpecParser.decodeStateExpr(parseExpression("0")) == .value(.int(0)))
        #expect(SpecParser.decodeStateExpr(parseExpression("42")) == .value(.int(42)))
    }

    @Test func parseBools() {
        #expect(SpecParser.decodeStateExpr(parseExpression("true")) == .value(.bool(true)))
        #expect(SpecParser.decodeStateExpr(parseExpression("false")) == .value(.bool(false)))
    }

    @Test func parseStrings() {
        #expect(SpecParser.decodeStateExpr(parseExpression("\"hello\"")) == .value(.string("hello")))
        #expect(SpecParser.decodeStateExpr(parseExpression("\"left\"")) == .value(.string("left")))
        #expect(SpecParser.decodeStateExpr(parseExpression("\"\"")) == .value(.string("")))
    }
}

// MARK: - StateExpr: variables

@Suite(.serialized) struct StateExprVariableTests {
    @Test func parseVariableReferences() {
        #expect(SpecParser.decodeStateExpr(parseExpression("x")) == .variable("x"))
        #expect(SpecParser.decodeStateExpr(parseExpression("count")) == .variable("count"))
        #expect(SpecParser.decodeStateExpr(parseExpression("direction")) == .variable("direction"))
    }
}

@Suite(.serialized) struct SpecVariableDeclarationParsingTests {
    @Test func plainVarDeclarationIsParsedWithoutGenericSpecialization() {
        let source = """
        {
            let counter = Var("counter", 0)
            Variable(counter, in: 0...1)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.count == 1)
        guard parsed.variables.count == 1 else { return }
        #expect(parsed.variables[0].name == "counter")
        #expect(parsed.variables[0].initial == .set([.int(0), .int(1)]))
        #expect(parsed.variables[0].initialSet == .setLiteral([.value(.int(0)), .value(.int(1))]))
        #expect(parsed.variables[0].swiftTypeName == "Int")
    }

    @Test func oneArgumentVariableReferencesPreserveBindingMetadataAndOrder() {
        let source = """
        {
            let queued = Var("queued", TLAValue.set([]))
            Variable(queued)
            let phase = Var("phase", 0)
            Variable(phase)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.count == 2)
        #expect(parsed.variables[0].name == "queued")
        #expect(parsed.variables[0].initial == .set([]))
        #expect(parsed.variables[0].swiftTypeName == "TLAValue")
        #expect(parsed.variables[1].name == "phase")
        #expect(parsed.variables[1].initial == .int(0))
        #expect(parsed.variables[1].swiftTypeName == "Int")
    }

    @Test func finiteVariableDomainsCompareAsFormalSets() {
        let parsed = ParsedSpecModel(
            variables: [(
                name: "counter",
                initial: .set([.int(0), .int(1)]),
                initialSet: .setLiteral([.int(0), .int(1)])
            )],
            actions: [],
            invariants: []
        )
        let built = ParsedSpecModel(
            variables: [(
                name: "counter",
                initial: .set([.int(0), .int(1)]),
                initialSet: .setLiteral([.int(1), .int(0)])
            )],
            actions: [],
            invariants: []
        )

        #expect(_tlaAlphaEquivalent(parsed, built))
    }

    @Test func oneArgumentVariableRejectsUnboundReference() {
        let source = """
        {
            Variable(missing)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == ["Variable 'missing' is not bound by a prior Var declaration"])
    }

    @Test func variableReferenceRejectsMalformedDeclaration() {
        let source = """
        {
            let phase = Var("phase", 0)
            Variable(phase, bogus: 1)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.map(\.message) == ["Malformed Variable declaration"])
    }
}

// MARK: - StateExpr: arithmetic operators

@Suite(.serialized) struct StateExprArithmeticTests {
    @Test func parseArithmetic() {
        #expect(SpecParser.decodeStateExpr(parseExpression("x + 5")) == StateExpr.add(.variable("x"), .value(.int(5))))
        #expect(SpecParser.decodeStateExpr(parseExpression("x - 3")) == StateExpr.subtract(.variable("x"), .value(.int(3))))
        #expect(SpecParser.decodeStateExpr(parseExpression("x * 2")) == StateExpr.multiply(.variable("x"), .value(.int(2))))
        #expect(SpecParser.decodeStateExpr(parseExpression("x / 4")) == StateExpr.divide(.variable("x"), .value(.int(4))))
        #expect(SpecParser.decodeStateExpr(parseExpression("x % 7")) == StateExpr.modulo(.variable("x"), .value(.int(7))))
    }
}

// MARK: - StateExpr: comparison operators

@Suite(.serialized) struct StateExprComparisonTests {
    @Test func parseComparisons() {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.decodeStateExpr(parseExpression("x == y")) == StateExpr.equal(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x != y")) == StateExpr.notEqual(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x < y")) == StateExpr.lessThan(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x <= y")) == StateExpr.lessOrEqual(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x > y")) == StateExpr.greaterThan(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x >= y")) == StateExpr.greaterOrEqual(x, y))
    }
}

// MARK: - StateExpr: logical and prefix operators

@Suite(.serialized) struct StateExprLogicalPrefixTests {
    @Test func parseLogical() {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.decodeStateExpr(parseExpression("x && y")) == StateExpr.and(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x || y")) == StateExpr.or(x, y))
    }

    @Test func parsePrefix() {
        let x: StateExpr = .variable("x")
        #expect(SpecParser.decodeStateExpr(parseExpression("!x")) == StateExpr.not(x))
        #expect(SpecParser.decodeStateExpr(parseExpression("-x")) == StateExpr.negate(x))
    }

    @Test func parseParenthesized() {
        #expect(SpecParser.decodeStateExpr(parseExpression("(x)")) == .variable("x"))
    }
}

// MARK: - StateExpr: range operator

@Suite(.serialized) struct StateExprRangeTests {
    @Test func parseRangeOperator() {
        #expect(SpecParser.decodeStateExpr(parseExpression("1...3")) == StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))]))
        #expect(SpecParser.decodeStateExpr(parseExpression("0...2")) == StateExpr.setLiteral([.value(.int(0)), .value(.int(1)), .value(.int(2))]))
    }
}

// MARK: - StateExpr: member access properties

@Suite(.serialized) struct StateExprMemberAccessTests {
    @Test func parseKnownProperties() {
        let s: StateExpr = .variable("s")
        #expect(SpecParser.decodeStateExpr(parseExpression("s.cardinality")) == StateExpr.cardinality(s))
        #expect(SpecParser.decodeStateExpr(parseExpression("s.flattened")) == StateExpr.unionAll(s))
        #expect(SpecParser.decodeStateExpr(parseExpression("s.subsets")) == StateExpr.powerSet(s))
        #expect(SpecParser.decodeStateExpr(parseExpression("s.domain")) == StateExpr.domain(s))
        #expect(SpecParser.decodeStateExpr(parseExpression("s.count")) == StateExpr.tupleLength(s))
    }

    @Test func parseUnknownPropertyAsRecordAccess() {
        #expect(SpecParser.decodeStateExpr(parseExpression("msg.type")) == StateExpr.recordAccess(.variable("msg"), "type"))
        #expect(SpecParser.decodeStateExpr(parseExpression("ballot.val")) == StateExpr.recordAccess(.variable("ballot"), "val"))
    }
}

// MARK: - StateExpr: method calls (binary)

@Suite(.serialized) struct StateExprBinaryMethodTests {
    @Test func parseBinaryMethods() {
        let x: StateExpr = .variable("x")
        let s: StateExpr = .variable("s")
        #expect(SpecParser.decodeStateExpr(parseExpression("x.isIn(s)")) == StateExpr.in(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.union(s)")) == StateExpr.union(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.intersection(s)")) == StateExpr.intersection(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.subtracting(s)")) == StateExpr.setDifference(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.isSubset(of: s)")) == StateExpr.subset(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.applying(s)")) == StateExpr.functionApply(x, s))
        let filterResult = SpecParser.decodeStateExpr(parseExpression("x.filtering(s)"))
        #expect(filterResult?.description.contains("\\in") == true)
        let mapResult = SpecParser.decodeStateExpr(parseExpression("x.mapping(s)"))
        #expect(mapResult?.description.contains(":") == true)
        #expect(SpecParser.decodeStateExpr(parseExpression("x.appending(s)")) == StateExpr.tupleAppend(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.concatenating(s)")) == StateExpr.tupleConcatenate(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.integerDivided(by: 2)")) == StateExpr.integerDivide(x, .value(.int(2))))
    }
}

// MARK: - StateExpr: method calls (multi-arg)

@Suite(.serialized) struct StateExprMultiArgMethodTests {
    @Test func parseUpdated() {
        let f: StateExpr = .variable("f")
        #expect(SpecParser.decodeStateExpr(parseExpression("f.updated(at: 0, to: 1)")) == StateExpr.except(f, .value(.int(0)), .value(.int(1))))
    }

    @Test func parseAt() {
        #expect(
            SpecParser.decodeStateExpr(parseExpression("t.at(3)"))
                == StateExpr.tupleDynamicAccess(.variable("t"), .int(3))
        )
    }
}

// MARK: - StateExpr: static calls

@Suite(.serialized) struct StateExprStaticCallTests {
    @Test func parseStaticSet() {
        #expect(
            SpecParser.decodeStateExpr(parseExpression("StateExpr.set([1, 2, 3])"))
                == StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        )
    }

    @Test func parseStaticTuple() {
        #expect(SpecParser.decodeStateExpr(parseExpression("StateExpr.tuple([1, x])")) == StateExpr.tupleLiteral([.value(.int(1)), .variable("x")]))
    }

    @Test func parseStaticRecord() {
        #expect(
            SpecParser.decodeStateExpr(parseExpression("StateExpr.record(name: x, age: 42)"))
                == StateExpr.recordLiteral(["name": .variable("x"), "age": .value(.int(42))])
        )
    }

    @Test func parseStaticIf() {
        let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.if(x == 0, then: 1, else: 2)"))
        #expect(result == StateExpr.ifThenElse(
            StateExpr.equal(.variable("x"), .value(.int(0))),
            .value(.int(1)),
            .value(.int(2))
        ))
    }

    @Test func parseStaticEnabled() {
        #expect(SpecParser.decodeStateExpr(parseExpression("StateExpr.enabled(\"Next\")")) == StateExpr.enabledAction("Next"))
    }

    @Test func parseStaticFunction() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.function(domain: StateExpr.set([1, 2]), x + 1)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("|->") && d.contains("x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticForAll() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.for(allIn: StateExpr.set([1, 2]), x > 0)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("\\A x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticExists() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.exists(in: StateExpr.set([1, 2]), x > 0)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("\\E x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticChoose() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.choose(from: StateExpr.set([1, 2]), matching: x > 0)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("CHOOSE x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticAny() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.any(from: StateExpr.set([1, 2]))")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("CHOOSE x") && d.contains("TRUE"))
    }

    @Test func parseStaticFirstMatchWithFallback() {
        let result = SpecParser.decodeStateExpr(
            parseExpression("StateExpr.firstMatch((when: x == 0, then: 10), (when: x == 1, then: 20), fallback: 99)")
        )
        #expect(result == StateExpr.caseExpr(
            [
                StateExpr.equal(.variable("x"), .value(.int(0))), .value(.int(10)),
                StateExpr.equal(.variable("x"), .value(.int(1))), .value(.int(20))
            ],
            .value(.int(99))
        ))
    }

    @Test func parseStaticFirstMatchNoFallback() {
        let result = SpecParser.decodeStateExpr(
            parseExpression("StateExpr.firstMatch((when: x < 0, then: -1))")
        )
        #expect(result == StateExpr.caseExpr(
            [StateExpr.lessThan(.variable("x"), .value(.int(0))), StateExpr.negate(.value(.int(1)))],
            nil
        ))
    }
}

// MARK: - ActionExpr: basic assignments

@Suite(.serialized) struct ActionExprBasicTests {
    @Test func parseBecomes() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(5)")) == ActionExpr.assign("x", .value(.int(5))))
        #expect(
            SpecParser.decodeActionExpr(parseExpression("x.becomes(x + 1)"))
                == ActionExpr.assign("x", StateExpr.add(.variable("x"), .value(.int(1))))
        )
    }

    @Test func parseStays() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.stays")) == ActionExpr.unchanged("x"))
    }

    @Test func parseGuardedBecomes() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(1).when(x == 0)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign("x", .value(.int(1)))
        ))
    }

    @Test func parseDoubleWhen() {
        let result = SpecParser.decodeActionExpr(parseExpression("x.becomes(1).when(x > 0).when(x < 5)"))
        #expect(result == ActionExpr.and(
            ActionExpr.guard_(StateExpr.and(
                StateExpr.lessThan(.variable("x"), .value(.int(5))),
                StateExpr.greaterThan(.variable("x"), .value(.int(0)))
            )),
            ActionExpr.assign("x", .value(.int(1)))
        ))
    }

    @Test func parseNondeterministicAssign() {
        let result = SpecParser.decodeActionExpr(
            parseExpression("x.becomes(StateExpr.any(from: StateExpr.set([1, 2, 3])))")
        )
        let expectedSet = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        #expect(result == ActionExpr.chooseAction("x", expectedSet))
    }
}

// MARK: - ActionExpr: AND / OR combinations

@Suite(.serialized) struct ActionExprCombinatorTests {
    @Test func parseAndOfTwoActions() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(1) && y.becomes(2)")) == ActionExpr.and(
            ActionExpr.assign("x", .value(.int(1))),
            ActionExpr.assign("y", .value(.int(2)))
        ))
    }

    @Test func parseOrOfTwoActions() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(1) || x.becomes(2)")) == ActionExpr.or(
            ActionExpr.assign("x", .value(.int(1))),
            ActionExpr.assign("x", .value(.int(2)))
        ))
    }

    @Test func parseGuardAndAction() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x > 0 && x.becomes(x - 1)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.greaterThan(.variable("x"), .value(.int(0)))),
            ActionExpr.assign("x", StateExpr.subtract(.variable("x"), .value(.int(1))))
        ))
    }

    @Test func parseActionAndGuard() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(0) && x == 0")) == ActionExpr.and(
            ActionExpr.assign("x", .value(.int(0))),
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0))))
        ))
    }

    @Test func parseStateOrAction() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x == 0 || x.becomes(1)")) == ActionExpr.or(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign("x", .value(.int(1)))
        ))
    }

    @Test func parseHourClockStyleNestedOr() {
        let result = SpecParser.decodeActionExpr(
            parseExpression("(x != 12) && x.becomes(x + 1) || (x == 12) && x.becomes(1)")
        )
        let left = ActionExpr.and(
            ActionExpr.guard_(StateExpr.notEqual(.variable("x"), .value(.int(12)))),
            ActionExpr.assign("x", StateExpr.add(.variable("x"), .value(.int(1))))
        )
        let right = ActionExpr.and(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(12)))),
            ActionExpr.assign("x", .value(.int(1)))
        )
        #expect(result == ActionExpr.or(left, right))
    }
}

// MARK: - ActionExpr: closure parsing

@Suite(.serialized) struct ActionExprClosureTests {
    @Test func parseEmptyClosure() {
        let closure = parseClosure("{}")
        #expect(SpecParser.decodeActionFromClosure(closure) == ActionExpr.guard_(.value(.bool(true))))
    }

    @Test func parseSingleStatementClosure() {
        let closure = parseClosure("{ x.becomes(1) }")
        #expect(SpecParser.decodeActionFromClosure(closure) == ActionExpr.assign("x", .value(.int(1))))
    }

    @Test func parseMultiStatementClosure() {
        let closure = parseClosure("{ x.becomes(1) ; y.stays }")
        #expect(SpecParser.decodeActionFromClosure(closure) == ActionExpr.and(
            ActionExpr.assign("x", .value(.int(1))),
            ActionExpr.unchanged("y")
        ))
    }
}

private func parseClosure(_ source: String) -> ClosureExprSyntax {
    guard case .expr(let expr) = Parser.parse(source: source).statements.first!.item,
          let closure = expr.as(ClosureExprSyntax.self)
    else { fatalError("Not a closure: \(source)") }
    return closure
}

// MARK: - TemporalExpr

@Suite(.serialized) struct TemporalExprTests {
    @Test func parseLeadsTo() {
        #expect(
            SpecParser.decodeTemporal(parseExpression("x.leadsTo(y)").as(FunctionCallExprSyntax.self)!)
                == TemporalExpr.leadsTo(.variable("x"), .variable("y"))
        )
    }

    @Test func parseLeadsToWithExpressions() {
        let result = SpecParser.decodeTemporal(parseExpression("(x > 0).leadsTo(y == 0)").as(FunctionCallExprSyntax.self)!)
        #expect(result == TemporalExpr.leadsTo(
            StateExpr.greaterThan(.variable("x"), .value(.int(0))),
            StateExpr.equal(.variable("y"), .value(.int(0)))
        ))
    }
}

// MARK: - FairnessCondition

@Suite(.serialized) struct FairnessConditionTests {
    @Test func parseWeakFairness() {
        #expect(
            SpecParser.decodeFairness(parseExpression("x.weakFairness(\"Tick\")").as(FunctionCallExprSyntax.self)!)
                == FairnessCondition.weakFairness("Tick")
        )
    }

    @Test func parseStrongFairness() {
        #expect(
            SpecParser.decodeFairness(parseExpression("x.strongFairness(\"Tick\")").as(FunctionCallExprSyntax.self)!)
                == FairnessCondition.strongFairness("Tick")
        )
    }

    @Test func parseUnknownReturnsNil() {
        #expect(SpecParser.decodeFairness(parseExpression("x.unknown()").as(FunctionCallExprSyntax.self)!) == nil)
    }
}

// MARK: - Enum phase parsing

private let cameraModePhases: [String: [String: TLAValue]] = [
    "CameraMode": [
        "idle": .string("idle"),
        "live": .string("live"),
        "recording": .string("recording"),
        "playback": .string("playback")
    ]
]

@Suite(.serialized) struct EnumPhaseParsingTests {
    @Test func parseQualifiedEnumCaseInInvariant() {
        let source = """
        {
            Invariant("idleOnly") {
                mode == CameraMode.idle
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumPhases: cameraModePhases)
        #expect(parsed.invariants.count == 1)
        #expect(parsed.invariants[0].body == .equal(.variable("mode"), .value(.string("idle"))))
    }

    @Test func parseEnumAssignment() {
        let source = """
        {
            Action("test") {
                mode.becomes(CameraMode.live)
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumPhases: cameraModePhases)
        #expect(parsed.actions.count == 1)
        #expect(parsed.actions[0].body == .assign("mode", .value(.string("live"))))
    }

    @Test func parsesVariadicActionParametersInDeclarationOrder() {
        let source = """
        {
            Action("moveElevator", parameters: [
                ActionParameter("person", values: [1, 2]),
                ActionParameter("elevator", values: [10, 20]),
                ActionParameter("direction", values: [100, 200])
            ]) {
                floor.becomes(1)
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)
        #expect(parsed.actions.count == 1)
        #expect(parsed.actions[0].bindings.map(\.name) == ["person", "elevator", "direction"])
        #expect(parsed.actions[0].bindings.map(\.values) == [
            [.int(1), .int(2)], [.int(10), .int(20)], [.int(100), .int(200)]
        ])
        #expect(parsed.actions[0].body == .assign("floor", .value(.int(1))))
    }

    @Test func diagnosesInvalidDomainsAtEveryParameterPosition() {
        let source = """
        {
            Action("moveElevator", parameters: [
                ActionParameter("person", values: personIDs),
                ActionParameter("elevator", values: []),
                ActionParameter("direction", values: [1, 1])
            ]) {
                floor.becomes(1)
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)
        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Parameterized action 'moveElevator' parameter 'person' requires an explicitly written finite values array.",
            "Parameterized action 'moveElevator' parameter 'elevator' requires a non-empty finite values array.",
            "Parameterized action 'moveElevator' parameter 'direction' has duplicate finite-domain values."
        ])
    }

    @Test func normalizesTypedFacadeAndEnumDomainsToBuilderAST() {
        let source = """
        {
            let floor = Var<Int>("floor")
            let cars = Var<Function<CarID, Record<CarSchema>>>("cars")
            let calls = Var<SetExpr<Record<CarSchema>>>("calls")
            Variable(floor, 0)
            Variable(cars)
            Variable(calls)
            Action("move", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                cars.becomes(cars.updating(CarID.carA) { car in
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
        let phases: [String: [String: TLAValue]] = [
            "PersonID": ["alice": .string("alice"), "bob": .string("bob")],
            "CarID": ["carA": .string("carA"), "carB": .string("carB")],
            "Direction": ["up": .string("up"), "down": .string("down")]
        ]
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumPhases: phases,
            enumDomains: [
                "PersonID": [.string("alice"), .string("bob")],
                "CarID": [.string("carA"), .string("carB")],
                "Direction": [.string("up"), .string("down")]
            ]
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
        for (parsedAction, builtAction) in zip(parsed.actions, builderActions) {
            #expect(parsedAction.name == builtAction.0)
            #expect(parsedAction.body == builtAction.1)
            #expect(parsedAction.bindings == builtAction.2)
        }
    }

    @Test func diagnosesUnsupportedTypedUpdateAtItsSource() {
        let source = """
        {
            Action("update", parameters: [
                ActionParameter("person", values: ["alice", "bob"])
            ]) {
                car.becomes(car.updating(CarSchema.field(dynamicKeyPath), to: 2))
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Parameterized action 'update' contains an unsupported typed update; use a directly written finite enum case or schema field token."
        ])
        #expect(parsed.diagnostics.first?.source.contains("dynamicKeyPath") == true)
    }

    @Test func macroAcceptsLocalEnumFiniteDomainsInOrderedBindings() {
        #expect(TypedFacadeEnumDomainMacro.spec.actions.first?.bindings == [
            ActionBinding(name: "person", values: [.string("alice"), .string("bob")]),
            ActionBinding(name: "car", values: [.string("carA"), .string("carB")]),
            ActionBinding(name: "direction", values: [.string("up"), .string("down")])
        ])
    }

    @Test func parseInvalidEnumCaseReturnsNilForInvariant() {
        let source = """
        {
            Invariant("bad") {
                mode == CameraMode.unknown
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumPhases: cameraModePhases)
        #expect(parsed.invariants.isEmpty)
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test func parseEnumInvariant() {
        let source = """
        {
            Invariant("notError") {
                mode != CameraMode.error
            }
        }
        """
        let phases: [String: [String: TLAValue]] = [
            "CameraMode": ["idle": .string("idle"), "error": .string("error")]
        ]
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumPhases: phases)
        #expect(parsed.invariants.count == 1)
        #expect(parsed.invariants[0].body == .notEqual(.variable("mode"), .value(.string("error"))))
    }

    @Test func parseEnumStateVarInit() {
        let source = """
        {
            let mode = StateVar<CameraMode>(CameraMode.idle)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumPhases: cameraModePhases)
        #expect(parsed.variables.count == 1)
        #expect(parsed.variables[0].name == "mode")
        #expect(parsed.variables[0].initial == .string("idle"))
        #expect(parsed.variables[0].swiftTypeName == "CameraMode")
    }
}

private enum TestPersonID: String, FiniteTLAValueDomain {
    case alice, bob
    static let finiteValues = [Self.alice, .bob]
}

@TLAModel
private struct TypedFacadeEnumDomainMacro {
    enum PersonID: String, FiniteTLAValueDomain {
        case alice, bob
        static let finiteValues = [Self.alice, .bob]
    }

    enum CarID: String, FiniteTLAValueDomain {
        case carA, carB
        static let finiteValues = [Self.carA, .carB]
    }

    enum Direction: String, FiniteTLAValueDomain {
        case up, down
        static let finiteValues = [Self.up, .down]
    }

    static var spec: TLASpec {
        TLASpec("TypedFacadeEnumDomainMacro") {
            let floor = Var<Int>("floor")
            Variable(floor, 0)
            Action("move", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                floor.becomes(1)
            }
        }
    }
}

private enum TestCarID: String, FiniteTLAValueDomain {
    case carA, carB
    static let finiteValues = [Self.carA, .carB]
}

private enum TestDirection: String, FiniteTLAValueDomain {
    case up, down
    static let finiteValues = [Self.up, .down]
}

private struct TestCarFields {
    let floor: Int
    let doorsOpen: Bool
}

private enum TestCarSchema: TLARecordSchema {
    typealias Fields = TestCarFields
    static let fieldNames: Set<String> = ["floor", "doorsOpen"]
    static let defaultRecord: TLAValue = .record(["floor": .int(0), "doorsOpen": .bool(false)])

    static func fieldName<Value>(for field: KeyPath<TestCarFields, Value>) -> String? {
        let key = field as AnyKeyPath
        if key == \TestCarFields.floor { return "floor" }
        if key == \TestCarFields.doorsOpen { return "doorsOpen" }
        return nil
    }

    static let floor = field(\TestCarFields.floor)
    static let doorsOpen = field(\TestCarFields.doorsOpen)
}
