import Testing
import SwiftTLA

// MARK: - Test helpers

private struct TestKey: Identifiable, TLAValueConvertible, TLABridgeable, Hashable {
    let id: Int
    var tlaValue: TLAValue { .int(id) }
    init(id: Int) { self.id = id }
    init(tlaValue: TLAValue) { id = tlaValue.intValue }
}
extension TLAValue {
    var intValue: Int { if case .int(let n) = self { return n }; return 0 }
}

// MARK: - SetVar: AST lowering

@Suite(.serialized) struct SetVarASTLoweringTests {
    @Test func insertLowersToUnionAssign() {
        let s = SetVar<Int>("seen")
        let result = s.insert(5)
        #expect(result == .assign("seen", .union(.variable("seen"), .setLiteral([.value(.int(5))]))))
    }

    @Test func removeLowersToSetDifferenceAssign() {
        let s = SetVar<Int>("seen")
        let result = s.remove(3)
        #expect(result == .assign("seen", .setDifference(.variable("seen"), .setLiteral([.value(.int(3))]))))
    }

    @Test func containsLowersToInExpr() {
        let s = SetVar<Int>("seen")
        #expect(s.contains(5) == .in(.value(.int(5)), .variable("seen")))
    }

    @Test func isEmptyLowersToCardinalityZero() {
        let s = SetVar<Int>("seen")
        #expect(s.isEmpty == .equal(.cardinality(.variable("seen")), .value(.int(0))))
    }

    @Test func unionLowersToUnionAssign() {
        let a = SetVar<Int>("a")
        let b = SetVar<Int>("b")
        #expect(a.union(b) == .assign("a", .union(.variable("a"), .variable("b"))))
    }

    @Test func insertThenRemoveInAction() {
        let seen = SetVar<Int>("seen")
        let action = Action("toggle") {
            seen.insert(1)
            seen.remove(2)
        }
        #expect(action.body == .and(
            .assign("seen", .union(.variable("seen"), .setLiteral([.value(.int(1))]))),
            .assign("seen", .setDifference(.variable("seen"), .setLiteral([.value(.int(2))])))
        ))
    }

    @Test func declarationInSpecProducesCorrectVarDecl() {
        let seen = SetVar<Int>("seen")
        let spec = TLASpec("Test") { seen }
        #expect(spec.variables.count == 1)
        #expect(spec.variables[0].name == "seen")
        #expect(spec.variables[0].initial == .set([]))
        #expect(spec.variables[0].collectionType == .set)
    }
}

// MARK: - ArrayVar: AST lowering

@Suite(.serialized) struct ArrayVarASTLoweringTests {
    @Test func appendLowersToTupleAppendAssign() {
        let a = ArrayVar<Int>("vals", count: 3)
        #expect(a.append(42) == .assign("vals", .tupleAppend(.variable("vals"), .value(.int(42)))))
    }

    @Test func sizeExprLowersToTupleLength() {
        let a = ArrayVar<Int>("vals", count: 3)
        #expect(a.sizeExpr == .tupleLength(.variable("vals")))
    }

    @Test func isEmptyExprLowersToTupleLengthZero() {
        let a = ArrayVar<Int>("vals", count: 3)
        #expect(a.isEmptyExpr == .equal(.tupleLength(.variable("vals")), .value(.int(0))))
    }

    @Test func declarationInSpecProducesCorrectVarDecl() {
        let vals = ArrayVar<Int>("vals", count: 3)
        let spec = TLASpec("Test") { vals }
        #expect(spec.variables.count == 1)
        #expect(spec.variables[0].name == "vals")
        #expect(spec.variables[0].initial == .tuple([.int(0), .int(0), .int(0)]))
        #expect(spec.variables[0].collectionType == .array(3))
    }

    @Test func appendInAction() {
        let vals = ArrayVar<String>("vals", count: 0)
        let action = Action("add") { vals.append("hello") }
        #expect(action.body == .assign("vals", .tupleAppend(.variable("vals"), .value(.string("hello")))))
    }
}

// MARK: - DictionaryVar: AST lowering

@Suite(.serialized) struct DictionaryVarASTLoweringTests {
    @Test func containsKeyLowersToInDomain() {
        let d = DictionaryVar<TestKey, Bool>("enabled", scope: 4)
        let key = TestKey(id: 1)
        #expect(d.contains(key: key) == .in(.value(key.tlaValue), .domain(.variable("enabled"))))
    }

    @Test func isEmptyExprLowersToCardinalityDomainZero() {
        let d = DictionaryVar<TestKey, Bool>("enabled", scope: 4)
        #expect(d.isEmptyExpr == .equal(.cardinality(.domain(.variable("enabled"))), .value(.int(0))))
    }

    @Test func declarationInSpecProducesCorrectVarDecl() {
        let d = DictionaryVar<TestKey, Bool>("enabled", scope: 4)
        let spec = TLASpec("Test") { d }
        #expect(spec.variables.count == 1)
        #expect(spec.variables[0].name == "enabled")
        #expect(spec.variables[0].collectionType == .dictionary(4))
        // When scope > 0, SymmetricCollectionDecl generates a function with member keys
        guard case .function(let f) = spec.variables[0].initial else {
            Issue.record("Expected function initial"); return
        }
        #expect(f.count == 4) // 4 member constants
    }
}

// MARK: - Native extraction & update

@Suite(.serialized) struct NativeExtractionTests {
    @Test func setVarExtractIntegers() {
        let seen = SetVar<Int>("seen")
        var state: [String: TLAValue] = [:]
        seen.update(in: &state, to: [1, 2, 3])
        #expect(seen.extract(from: state) == [1, 2, 3])
    }

    @Test func setVarExtractEmpty() {
        let seen = SetVar<Int>("seen")
        let state: [String: TLAValue] = ["seen": .set([])]
        #expect(seen.extract(from: state).isEmpty)
    }

    @Test func setVarExtractMissingReturnsEmpty() {
        let seen = SetVar<Int>("seen")
        #expect(seen.extract(from: [:]).isEmpty)
    }

    @Test func arrayVarExtractIntegers() {
        let vals = ArrayVar<Int>("vals", count: 3)
        var state: [String: TLAValue] = [:]
        vals.update(in: &state, to: [10, 20, 30])
        #expect(vals.extract(from: state) == [10, 20, 30])
    }

    @Test func arrayVarExtractEmpty() {
        let vals = ArrayVar<Int>("vals", count: 0)
        #expect(vals.extract(from: ["vals": .tuple([])]).isEmpty)
    }

    @Test func dictionaryVarExtract() {
        let d = DictionaryVar<TestKey, Bool>("enabled", scope: 4)
        var state: [String: TLAValue] = [:]
        d.update(in: &state, to: [TestKey(id: 1): true, TestKey(id: 2): false])
        let extracted = d.extract(from: state)
        #expect(extracted[TestKey(id: 1)] == true)
        #expect(extracted[TestKey(id: 2)] == false)
    }

    @Test func setVarRoundTripThroughTLAValue() {
        let seen = SetVar<Int>("seen")
        var state: [String: TLAValue] = [:]
        seen.update(in: &state, to: [5, 10, 15])
        guard case .set(let s) = state["seen"] else { Issue.record("Expected set"); return }
        #expect(s.count == 3)
        #expect(s.contains(.int(5)))
        #expect(s.contains(.int(10)))
        #expect(s.contains(.int(15)))
    }
}

// MARK: - TLA+ export

@Suite(.serialized) struct CollectionTLAExportTests {
    @Test func setVarExportsAsSet() {
        let seen = SetVar<Int>("seen")
        let spec = TLASpec("SetTest") {
            seen
            Action("add") { seen.insert(5) }
        }
        let tla = spec.tlaModule
        #expect(tla.contains("seen = {}"))
        #expect(tla.contains("seen' = (seen \\cup {5})"))
    }

    @Test func arrayVarExportsAsTuple() {
        let vals = ArrayVar<Int>("vals", count: 2)
        let spec = TLASpec("ArrTest") {
            vals
            Action("push") { vals.append(99) }
        }
        let tla = spec.tlaModule
        #expect(tla.contains("vals = <<0, 0>>"))
        #expect(tla.contains("vals' = Append(vals, 99)"))
    }

    @Test func dictionaryVarExportsAsFunction() {
        let d = DictionaryVar<TestKey, Bool>("enabled", scope: 2)
        let spec = TLASpec("DictTest") { d }
        let tla = spec.tlaModule
        #expect(tla.contains("enabled = ["))
        #expect(tla.contains("|->"))
        #expect(tla.contains("EnabledKeys"))
        #expect(tla.contains("Permutations"))
    }

    @Test func setWithRemoveExportsSetDiff() {
        let seen = SetVar<Int>("seen")
        let spec = TLASpec("RemoveTest") {
            seen
            Action("drop") { seen.remove(3) }
        }
        let tla = spec.tlaModule
        #expect(tla.contains("seen' = (seen \\ {3})"))
    }
}

// MARK: - Codegen round-trip

@Suite(.serialized) struct CollectionCodegenTests {
    @Test func setVarRoundTrip() {
        let seen = SetVar<Int>("seen")
        let spec = TLASpec("RT") { seen }
        let source = spec.swiftSource
        #expect(source.contains("SetVar<Int>(\"seen\")"))
    }

    @Test func arrayVarRoundTrip() {
        let vals = ArrayVar<Int>("vals", count: 3)
        let spec = TLASpec("RT") { vals }
        let source = spec.swiftSource
        #expect(source.contains("ArrayVar<Int>(\"vals\", count: 3)"))
    }

    @Test func dictionaryVarRoundTrip() {
        let d = DictionaryVar<TestKey, Bool>("enabled", scope: 4)
        let spec = TLASpec("RT") { d }
        let source = spec.swiftSource
        #expect(source.contains("DictionaryVar<SomeID, Int>(\"enabled\", scope: 4)"))
    }

    @Test func scalarVarEmitsDirectly() {
        let x = Var<Int>("x", 0)
        let spec = TLASpec("RT") { x }
        let source = spec.swiftSource
        #expect(source.contains("Var<Int>(\"x\", 0)"))
    }
}

// MARK: - Model-checking proof: Layer 2 types verified by TLA+ BFS

@Suite(.serialized) struct CollectionModelCheckerProofTests {
    @Test func setVarBFSProof() throws {
        let seen = SetVar<Int>("seen")
        let spec = TLASpec("SetProof") {
            seen
            Action("add1") { seen.insert(1) }
            Action("add2") { seen.insert(2) }
            Invariant("subset") { seen.isEmpty || seen.contains(1) || seen.contains(2) }
        }
        let result = try ModelChecker(spec: spec).check()
        guard case .ok(let count) = result.underlyingOutcome else {
            Issue.record("Expected ok, got \(result)"); return
        }
        #expect(count == 4) // {}, {1}, {2}, {1,2}
    }

    @Test func setVarRemoveBFSProof() throws {
        let seen = SetVar<Int>("seen")
        let spec = TLASpec("RemoveProof") {
            seen
            Action("add") { seen.insert(1) }
            Action("toggle") { (seen.contains(1) && seen.remove(1)) }
            Invariant("valid") { seen.isEmpty || seen.contains(1) }
        }
        let result = try ModelChecker(spec: spec).check()
        guard case .ok(let count) = result.underlyingOutcome else {
            Issue.record("Expected ok, got \(result)"); return
        }
        #expect(count == 2) // {}, {1}
    }

    @Test func arrayVarBFSProof() throws {
        let vals = ArrayVar<Int>("vals", count: 0)
        let spec = TLASpec("ArrProof") {
            vals
            Action("push") { (vals.sizeExpr < 2 && vals.append(1)) }
            Invariant("lenAtMost2") { vals.sizeExpr <= 2 }
        }
        let result = try ModelChecker(spec: spec).check()
        guard case .ok(let count) = result.underlyingOutcome else {
            Issue.record("Expected ok, got \(result)"); return
        }
        #expect(count == 3) // <<>>, <<1>>, <<1,1>>
    }

    @Test func dictionaryVarBFSProof() throws {
        let d = DictionaryVar<TestKey, Bool>("enabled", scope: 2)
        let k0 = DictMember<TestKey>(key: TestKey(id: 0).tlaValue)
        let k1 = DictMember<TestKey>(key: TestKey(id: 1).tlaValue)
        let spec = TLASpec("DictProof") {
            d
            Action("a1") { d.update(k0, to: true) }
            Action("a2") { d.update(k1, to: true) }
            Invariant("coherent") { d.allSatisfy { $0 == true || $0 == false } }
        }
        let result = try ModelChecker(spec: spec).check()
        // With scope > 0, dictionary is symmetric → bounded verification
        guard case .ok(let count) = result.underlyingOutcome else {
            Issue.record("Expected ok, got \(result)"); return
        }
        #expect(count == 4)
    }

    @Test func dictionaryCollectionActionBindsItsSelectedMember() throws {
        let d = DictionaryVar<TestKey, Bool>("enabled", scope: 2)
        let spec = TLASpec("BoundDictionaryMember") {
            d
            CollectionAction("enable", on: d) { member in
                d[member] == false && d.update(member, to: true)
            }
        }

        let result = try ModelChecker(spec: spec).check()
        guard case .ok(let count) = result.underlyingOutcome else {
            Issue.record("Expected ok, got \(result)")
            return
        }
        #expect(count == 3)
    }
}
