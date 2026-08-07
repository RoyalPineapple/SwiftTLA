import Testing
import SwiftSyntax
import SwiftParser
import SwiftTLA

/// Proves SpecParser produces the same AST as the runtime builder
/// for every expression form in the DSL.  Each test parses a source string
/// and compares the result to the equivalent value built through Swift's
/// type system (operator overloads and method calls).

// MARK: - Helpers

private func parseExpression(_ source: String) -> ExprSyntax {
    Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
}

// MARK: - StateExpr: literals

struct StateExprLiteralTests {
    @Test func parseInts() {
        #expect(SpecParser.parseStateExpr(parseExpression("0")) == .value(.int(0)))
        #expect(SpecParser.parseStateExpr(parseExpression("42")) == .value(.int(42)))
    }

    @Test func parseBools() {
        #expect(SpecParser.parseStateExpr(parseExpression("true")) == .value(.bool(true)))
        #expect(SpecParser.parseStateExpr(parseExpression("false")) == .value(.bool(false)))
    }

    @Test func parseStrings() {
        #expect(SpecParser.parseStateExpr(parseExpression("\"hello\"")) == .value(.string("hello")))
        #expect(SpecParser.parseStateExpr(parseExpression("\"left\"")) == .value(.string("left")))
        #expect(SpecParser.parseStateExpr(parseExpression("\"\"")) == .value(.string("")))
    }
}

// MARK: - StateExpr: variables

struct StateExprVariableTests {
    @Test func parseVariableReferences() {
        #expect(SpecParser.parseStateExpr(parseExpression("x")) == .variable("x"))
        #expect(SpecParser.parseStateExpr(parseExpression("count")) == .variable("count"))
        #expect(SpecParser.parseStateExpr(parseExpression("direction")) == .variable("direction"))
    }
}

// MARK: - StateExpr: arithmetic operators

struct StateExprArithmeticTests {
    @Test func parseArithmetic() {
        #expect(SpecParser.parseStateExpr(parseExpression("x + 5")) == StateExpr.add(.variable("x"), .value(.int(5))))
        #expect(SpecParser.parseStateExpr(parseExpression("x - 3")) == StateExpr.subtract(.variable("x"), .value(.int(3))))
        #expect(SpecParser.parseStateExpr(parseExpression("x * 2")) == StateExpr.multiply(.variable("x"), .value(.int(2))))
        #expect(SpecParser.parseStateExpr(parseExpression("x / 4")) == StateExpr.divide(.variable("x"), .value(.int(4))))
        #expect(SpecParser.parseStateExpr(parseExpression("x % 7")) == StateExpr.modulo(.variable("x"), .value(.int(7))))
    }
}

// MARK: - StateExpr: comparison operators

struct StateExprComparisonTests {
    @Test func parseComparisons() {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.parseStateExpr(parseExpression("x == y")) == StateExpr.equal(x, y))
        #expect(SpecParser.parseStateExpr(parseExpression("x != y")) == StateExpr.notEqual(x, y))
        #expect(SpecParser.parseStateExpr(parseExpression("x < y")) == StateExpr.lessThan(x, y))
        #expect(SpecParser.parseStateExpr(parseExpression("x <= y")) == StateExpr.lessOrEqual(x, y))
        #expect(SpecParser.parseStateExpr(parseExpression("x > y")) == StateExpr.greaterThan(x, y))
        #expect(SpecParser.parseStateExpr(parseExpression("x >= y")) == StateExpr.greaterOrEqual(x, y))
    }
}

// MARK: - StateExpr: logical and prefix operators

struct StateExprLogicalPrefixTests {
    @Test func parseLogical() {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.parseStateExpr(parseExpression("x && y")) == StateExpr.and(x, y))
        #expect(SpecParser.parseStateExpr(parseExpression("x || y")) == StateExpr.or(x, y))
    }

    @Test func parsePrefix() {
        let x: StateExpr = .variable("x")
        #expect(SpecParser.parseStateExpr(parseExpression("!x")) == StateExpr.not(x))
        #expect(SpecParser.parseStateExpr(parseExpression("-x")) == StateExpr.negate(x))
    }

    @Test func parseParenthesized() {
        #expect(SpecParser.parseStateExpr(parseExpression("(x)")) == .variable("x"))
    }
}

// MARK: - StateExpr: range operator

struct StateExprRangeTests {
    @Test func parseRangeOperator() {
        #expect(SpecParser.parseStateExpr(parseExpression("1...3")) == StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))]))
        #expect(SpecParser.parseStateExpr(parseExpression("0...2")) == StateExpr.setLiteral([.value(.int(0)), .value(.int(1)), .value(.int(2))]))
    }
}

// MARK: - StateExpr: member access properties

struct StateExprMemberAccessTests {
    @Test func parseKnownProperties() {
        let s: StateExpr = .variable("s")
        #expect(SpecParser.parseStateExpr(parseExpression("s.cardinality")) == StateExpr.cardinality(s))
        #expect(SpecParser.parseStateExpr(parseExpression("s.flattened")) == StateExpr.unionAll(s))
        #expect(SpecParser.parseStateExpr(parseExpression("s.subsets")) == StateExpr.powerSet(s))
        #expect(SpecParser.parseStateExpr(parseExpression("s.domain")) == StateExpr.domain(s))
        #expect(SpecParser.parseStateExpr(parseExpression("s.count")) == StateExpr.tupleLength(s))
    }

    @Test func parseUnknownPropertyAsRecordAccess() {
        #expect(SpecParser.parseStateExpr(parseExpression("msg.type")) == StateExpr.recordAccess(.variable("msg"), "type"))
        #expect(SpecParser.parseStateExpr(parseExpression("ballot.val")) == StateExpr.recordAccess(.variable("ballot"), "val"))
    }
}

// MARK: - StateExpr: method calls (binary)

struct StateExprBinaryMethodTests {
    @Test func parseBinaryMethods() {
        let x: StateExpr = .variable("x")
        let s: StateExpr = .variable("s")
        #expect(SpecParser.parseStateExpr(parseExpression("x.isIn(s)")) == StateExpr.in(x, s))
        #expect(SpecParser.parseStateExpr(parseExpression("x.union(s)")) == StateExpr.union(x, s))
        #expect(SpecParser.parseStateExpr(parseExpression("x.intersection(s)")) == StateExpr.intersection(x, s))
        #expect(SpecParser.parseStateExpr(parseExpression("x.subtracting(s)")) == StateExpr.setDifference(x, s))
        #expect(SpecParser.parseStateExpr(parseExpression("x.isSubset(of: s)")) == StateExpr.subset(x, s))
        #expect(SpecParser.parseStateExpr(parseExpression("x.applying(s)")) == StateExpr.functionApply(x, s))
        let filterResult = SpecParser.parseStateExpr(parseExpression("x.filtering(s)"))
        #expect(filterResult?.description.contains("\\in") == true)
        let mapResult = SpecParser.parseStateExpr(parseExpression("x.mapping(s)"))
        #expect(mapResult?.description.contains(":") == true)
        #expect(SpecParser.parseStateExpr(parseExpression("x.appending(s)")) == StateExpr.tupleAppend(x, s))
        #expect(SpecParser.parseStateExpr(parseExpression("x.concatenating(s)")) == StateExpr.tupleConcatenate(x, s))
        #expect(SpecParser.parseStateExpr(parseExpression("x.integerDivided(by: 2)")) == StateExpr.integerDivide(x, .value(.int(2))))
    }
}

// MARK: - StateExpr: method calls (multi-arg)

struct StateExprMultiArgMethodTests {
    @Test func parseUpdated() {
        let f: StateExpr = .variable("f")
        #expect(SpecParser.parseStateExpr(parseExpression("f.updated(at: 0, to: 1)")) == StateExpr.except(f, .value(.int(0)), .value(.int(1))))
    }

    @Test func parseAt() {
        #expect(SpecParser.parseStateExpr(parseExpression("t.at(3)")) == StateExpr.tupleAccess(.variable("t"), 3))
    }
}

// MARK: - StateExpr: static calls

struct StateExprStaticCallTests {
    @Test func parseStaticSet() {
        #expect(SpecParser.parseStateExpr(parseExpression("StateExpr.set([1, 2, 3])")) == StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))]))
    }

    @Test func parseStaticTuple() {
        #expect(SpecParser.parseStateExpr(parseExpression("StateExpr.tuple([1, x])")) == StateExpr.tupleLiteral([.value(.int(1)), .variable("x")]))
    }

    @Test func parseStaticRecord() {
        #expect(SpecParser.parseStateExpr(parseExpression("StateExpr.record(name: x, age: 42)")) == StateExpr.recordLiteral(["name": .variable("x"), "age": .value(.int(42))]))
    }

    @Test func parseStaticIf() {
        let result = SpecParser.parseStateExpr(parseExpression("StateExpr.if(x == 0, then: 1, else: 2)"))
        #expect(result == StateExpr.ifThenElse(
            StateExpr.equal(.variable("x"), .value(.int(0))),
            .value(.int(1)),
            .value(.int(2))
        ))
    }

    @Test func parseStaticEnabled() {
        #expect(SpecParser.parseStateExpr(parseExpression("StateExpr.enabled(\"Next\")")) == StateExpr.enabledAction("Next"))
    }

    @Test func parseStaticFunction() {
        guard let result = SpecParser.parseStateExpr(parseExpression("StateExpr.function(domain: StateExpr.set([1, 2]), x + 1)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("|->") && d.contains("x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticForAll() {
        guard let result = SpecParser.parseStateExpr(parseExpression("StateExpr.for(allIn: StateExpr.set([1, 2]), x > 0)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("\\A x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticExists() {
        guard let result = SpecParser.parseStateExpr(parseExpression("StateExpr.exists(in: StateExpr.set([1, 2]), x > 0)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("\\E x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticChoose() {
        guard let result = SpecParser.parseStateExpr(parseExpression("StateExpr.choose(from: StateExpr.set([1, 2]), matching: x > 0)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("CHOOSE x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticAny() {
        guard let result = SpecParser.parseStateExpr(parseExpression("StateExpr.any(from: StateExpr.set([1, 2]))")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("CHOOSE x") && d.contains("TRUE"))
    }

    @Test func parseStaticFirstMatchWithFallback() {
        let result = SpecParser.parseStateExpr(
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
        let result = SpecParser.parseStateExpr(
            parseExpression("StateExpr.firstMatch((when: x < 0, then: -1))")
        )
        #expect(result == StateExpr.caseExpr(
            [StateExpr.lessThan(.variable("x"), .value(.int(0))), StateExpr.negate(.value(.int(1)))],
            nil
        ))
    }
}

// MARK: - ActionExpr: basic assignments

struct ActionExprBasicTests {
    @Test func parseBecomes() {
        #expect(SpecParser.parseSingleAction(parseExpression("x.becomes(5)")) == ActionExpr.assign("x", .value(.int(5))))
        #expect(SpecParser.parseSingleAction(parseExpression("x.becomes(x + 1)")) == ActionExpr.assign("x", StateExpr.add(.variable("x"), .value(.int(1)))))
    }

    @Test func parseStays() {
        #expect(SpecParser.parseSingleAction(parseExpression("x.stays")) == ActionExpr.unchanged("x"))
    }

    @Test func parseGuardedBecomes() {
        #expect(SpecParser.parseSingleAction(parseExpression("x.becomes(1).when(x == 0)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign("x", .value(.int(1)))
        ))
    }

    @Test func parseDoubleWhen() {
        let result = SpecParser.parseSingleAction(parseExpression("x.becomes(1).when(x > 0).when(x < 5)"))
        #expect(result == ActionExpr.and(
            ActionExpr.guard_(StateExpr.and(
                StateExpr.lessThan(.variable("x"), .value(.int(5))),
                StateExpr.greaterThan(.variable("x"), .value(.int(0)))
            )),
            ActionExpr.assign("x", .value(.int(1)))
        ))
    }

    @Test func parseNondeterministicAssign() {
        let result = SpecParser.parseSingleAction(
            parseExpression("x.becomes(StateExpr.any(from: StateExpr.set([1, 2, 3])))")
        )
        let expectedSet = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        #expect(result == ActionExpr.chooseAction("x", expectedSet))
    }
}

// MARK: - ActionExpr: AND / OR combinations

struct ActionExprCombinatorTests {
    @Test func parseAndOfTwoActions() {
        #expect(SpecParser.parseSingleAction(parseExpression("x.becomes(1) && y.becomes(2)")) == ActionExpr.and(
            ActionExpr.assign("x", .value(.int(1))),
            ActionExpr.assign("y", .value(.int(2)))
        ))
    }

    @Test func parseOrOfTwoActions() {
        #expect(SpecParser.parseSingleAction(parseExpression("x.becomes(1) || x.becomes(2)")) == ActionExpr.or(
            ActionExpr.assign("x", .value(.int(1))),
            ActionExpr.assign("x", .value(.int(2)))
        ))
    }

    @Test func parseGuardAndAction() {
        #expect(SpecParser.parseSingleAction(parseExpression("x > 0 && x.becomes(x - 1)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.greaterThan(.variable("x"), .value(.int(0)))),
            ActionExpr.assign("x", StateExpr.subtract(.variable("x"), .value(.int(1))))
        ))
    }

    @Test func parseActionAndGuard() {
        #expect(SpecParser.parseSingleAction(parseExpression("x.becomes(0) && x == 0")) == ActionExpr.and(
            ActionExpr.assign("x", .value(.int(0))),
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0))))
        ))
    }

    @Test func parseStateOrAction() {
        #expect(SpecParser.parseSingleAction(parseExpression("x == 0 || x.becomes(1)")) == ActionExpr.or(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign("x", .value(.int(1)))
        ))
    }

    @Test func parseHourClockStyleNestedOr() {
        let result = SpecParser.parseSingleAction(
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

struct ActionExprClosureTests {
    @Test func parseEmptyClosure() {
        let closure = parseClosure("{}")
        #expect(SpecParser.parseActionFrom(closure) == ActionExpr.guard_(.value(.bool(true))))
    }

    @Test func parseSingleStatementClosure() {
        let closure = parseClosure("{ x.becomes(1) }")
        #expect(SpecParser.parseActionFrom(closure) == ActionExpr.assign("x", .value(.int(1))))
    }

    @Test func parseMultiStatementClosure() {
        let closure = parseClosure("{ x.becomes(1) ; y.stays }")
        #expect(SpecParser.parseActionFrom(closure) == ActionExpr.and(
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

struct TemporalExprTests {
    @Test func parseLeadsTo() {
        #expect(SpecParser.parseTemporal(parseExpression("x.leadsTo(y)")) == TemporalExpr.leadsTo(.variable("x"), .variable("y")))
    }

    @Test func parseLeadsToWithExpressions() {
        let result = SpecParser.parseTemporal(parseExpression("(x > 0).leadsTo(y == 0)"))
        #expect(result == TemporalExpr.leadsTo(
            StateExpr.greaterThan(.variable("x"), .value(.int(0))),
            StateExpr.equal(.variable("y"), .value(.int(0)))
        ))
    }
}

// MARK: - FairnessCondition

struct FairnessConditionTests {
    @Test func parseWeakFairness() {
        #expect(SpecParser.parseFairnessExpr(parseExpression("x.weakFairness(\"Tick\")")) == FairnessCondition.weakFairness("Tick"))
    }

    @Test func parseStrongFairness() {
        #expect(SpecParser.parseFairnessExpr(parseExpression("x.strongFairness(\"Tick\")")) == FairnessCondition.strongFairness("Tick"))
    }

    @Test func parseUnknownReturnsNil() {
        #expect(SpecParser.parseFairnessExpr(parseExpression("x.unknown()")) == nil)
    }
}
