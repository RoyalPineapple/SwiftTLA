import Testing
import SwiftSyntax
import SwiftParser
import SwiftTLA
@testable import SwiftTLAPlugin

/// Tests the model macro's state generation helpers and Var name injection.

// MARK: - Type mapping

struct TypeMappingTests {
    @Test func intType()    { #expect(ModelMacro.swiftType(for: .int(0)) == "Int") }
    @Test func boolType()   { #expect(ModelMacro.swiftType(for: .bool(false)) == "Bool") }
    @Test func stringType() { #expect(ModelMacro.swiftType(for: .string("")) == "String") }
    @Test func setType()    { #expect(ModelMacro.swiftType(for: .set([])) == "Set<Int>") }
    @Test func tupleType()  { #expect(ModelMacro.swiftType(for: .tuple([])) == "[TLAValue]") }
    @Test func recordType() { #expect(ModelMacro.swiftType(for: .record([:])) == "[String: TLAValue]") }
    @Test func functionType() { #expect(ModelMacro.swiftType(for: .function([:])) == "[TLAValue: TLAValue]") }
}

struct ExtractorTests {
    @Test func intExtractor()    { #expect(ModelMacro.tlaValueExtractor(for: .int(0)) == "intValue") }
    @Test func boolExtractor()   { #expect(ModelMacro.tlaValueExtractor(for: .bool(false)) == "boolValue") }
    @Test func stringExtractor() { #expect(ModelMacro.tlaValueExtractor(for: .string("")) == "stringValue") }
    @Test func setExtractor()    { #expect(ModelMacro.tlaValueExtractor(for: .set([])) == "intSetValue") }
}

struct ConstructorTests {
    @Test func intConstructor() {
        #expect(ModelMacro.tlaValueConstructor(for: .int(0), value: "x") == ".int(x)")
    }
    @Test func boolConstructor() {
        #expect(ModelMacro.tlaValueConstructor(for: .bool(false), value: "x") == ".bool(x)")
    }
    @Test func setConstructor() {
        #expect(ModelMacro.tlaValueConstructor(for: .set([]), value: "x") == ".set(Set(x.map { .int($0) }))")
    }
}

// MARK: - Variables enum generation

struct VariablesEnumGenerationTests {
    @Test func singleVariable() {
        let vars = [(name: "count", initial: TLAValue.int(0), initialSet: nil as StateExpr?)]
        let result = ModelMacro.generateVariablesEnum(variables: vars)
        #expect(result.contains("case count"))
        #expect(result.contains("enum Variables: String, CaseIterable"))
    }

    @Test func multipleVariables() {
        let vars = [
            (name: "phase", initial: TLAValue.int(0), initialSet: nil as StateExpr?),
            (name: "queued", initial: TLAValue.set([]), initialSet: nil as StateExpr?),
            (name: "inFlight", initial: TLAValue.set([]), initialSet: nil as StateExpr?)
        ]
        let result = ModelMacro.generateVariablesEnum(variables: vars)
        #expect(result.contains("case phase"))
        #expect(result.contains("case queued"))
        #expect(result.contains("case inFlight"))
    }
}

// MARK: - Actions enum generation

struct ActionsEnumGenerationTests {
    @Test func singleAction() {
        let actions = [(name: "Enqueue", body: ActionExpr.unchanged("x"))]
        let result = ModelMacro.generateActionsEnum(actions: actions)
        #expect(result.contains("case Enqueue"))
        #expect(result.contains("enum Actions: String, CaseIterable"))
    }

    @Test func multipleActions() {
        let actions = [
            (name: "Enqueue", body: ActionExpr.unchanged("x")),
            (name: "Dequeue", body: ActionExpr.unchanged("x")),
            (name: "Drain", body: ActionExpr.unchanged("x"))
        ]
        let result = ModelMacro.generateActionsEnum(actions: actions)
        #expect(result.contains("case Enqueue"))
        #expect(result.contains("case Dequeue"))
        #expect(result.contains("case Drain"))
    }
}

// MARK: - State struct generation

struct StateStructGenerationTests {
    @Test func generatesStructWithFields() {
        let vars = [
            (name: "phase", initial: TLAValue.int(0), initialSet: nil as StateExpr?),
            (name: "done", initial: TLAValue.bool(false), initialSet: nil as StateExpr?)
        ]
        let result = ModelMacro.generateStateStruct(variables: vars)
        #expect(result.contains("public struct State"))
        #expect(result.contains("var phase: Int"))
        #expect(result.contains("var done: Bool"))
    }

    @Test func generatesInitFromDict() {
        let vars = [
            (name: "phase", initial: TLAValue.int(0), initialSet: nil as StateExpr?),
            (name: "queued", initial: TLAValue.set([]), initialSet: nil as StateExpr?)
        ]
        let result = ModelMacro.generateStateStruct(variables: vars)
        #expect(result.contains("public init(from dict: [String: TLAValue])"))
        #expect(result.contains("self.phase = dict[Variables.phase.rawValue]!.intValue"))
        #expect(result.contains("self.queued = dict[Variables.queued.rawValue]!.intSetValue"))
    }

    @Test func generatesAsDictionary() {
        let vars = [
            (name: "phase", initial: TLAValue.int(0), initialSet: nil as StateExpr?),
            (name: "done", initial: TLAValue.bool(false), initialSet: nil as StateExpr?)
        ]
        let result = ModelMacro.generateStateStruct(variables: vars)
        #expect(result.contains("var asDictionary: [String: TLAValue]"))
        #expect(result.contains("d[Variables.phase.rawValue] = .int(phase)"))
        #expect(result.contains("d[Variables.done.rawValue] = .bool(done)"))
    }
}

// MARK: - Var name injection

struct VarNameInjectionTests {
    @Test func injectsNameForTypedVar() {
        let source = """
        {
            let phase = Var<Int>()
        }
        """
        let closure = Parser.parse(source: source).statements.first!
            .item.as(ExprSyntax.self)!.as(ClosureExprSyntax.self)!
        let result = ModelMacro.rewriteVarNames(in: closure)
        let rewritten = result.statements.description
        #expect(rewritten.contains(#""phase""#))
    }

    @Test func injectsNameWithValueLabel() {
        let source = """
        {
            let count = Var<Int>(value: 5)
        }
        """
        let closure = Parser.parse(source: source).statements.first!
            .item.as(ExprSyntax.self)!.as(ClosureExprSyntax.self)!
        let result = ModelMacro.rewriteVarNames(in: closure)
        let rewritten = result.statements.description
        #expect(rewritten.contains(#""count""#))
        #expect(rewritten.contains("value: 5"))
    }

    @Test func skipsAlreadyNamedVar() {
        let source = """
        {
            let phase = Var<Int>("explicit")
        }
        """
        let closure = Parser.parse(source: source).statements.first!
            .item.as(ExprSyntax.self)!.as(ClosureExprSyntax.self)!
        let result = ModelMacro.rewriteVarNames(in: closure)
        let rewritten = result.statements.description
        #expect(rewritten.contains(#""explicit""#))
        #expect(!rewritten.contains(#""phase""#))
    }

    @Test func handlesSetType() {
        let source = """
        {
            let queued = Var<TLASetType>()
        }
        """
        let closure = Parser.parse(source: source).statements.first!
            .item.as(ExprSyntax.self)!.as(ClosureExprSyntax.self)!
        let result = ModelMacro.rewriteVarNames(in: closure)
        let rewritten = result.statements.description
        #expect(rewritten.contains(#""queued""#))
    }
}
