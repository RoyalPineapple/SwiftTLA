import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

// Shared inputs for parser and DSL-builder comparison tests.

func parseSpecTestExpression(_ source: String) throws -> ExprSyntax {
    try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
}

func parseSpecTestClosure(_ source: String) throws -> ClosureExprSyntax {
    try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
}

func parserTestEnum(
    _ typeName: String,
    cases: TLARecord = .init([]),
    finiteValues: [TLAValue]? = nil
) -> SourceEnum {
    .init(typeName: typeName, cases: cases.fields.map { (name: $0.name, value: $0.value) }, finiteValues: finiteValues)
}

enum ParserNode: String, FiniteTLAValueDomain {
    case left
    case right

    static var defaultValue: Self { .left }
    static let finiteValues: [ParserNode] = [.left, .right]

    var tlaValue: TLAValue { .string(rawValue) }
}

let cameraModeDefinition = parserTestEnum(
    "CameraMode",
    cases: [
        "idle": .string("idle"),
        "live": .string("live"),
        "recording": .string("recording"),
        "playback": .string("playback")
    ]
)

@TLAModel
struct DefinePhaseGeneratedModel {
    enum Step: String, CaseIterable { case stay }

    enum Mode: String, FiniteTLAValueDomain {
        case define

        static var defaultValue: Self { .define }
        static let finiteValues = [Self.define]
    }

    static var spec: TLASpec {
        #spec("DefinePhaseGeneratedModel") {
            let phase = Algorithm(label: "Phase", scoped: { scope in
                let mode: SharedVariable<Mode> = scope.sharedVar(_name: "mode", initial: .define)
                Do(Step.stay) { Assign(mode, to: mode) }
            })
            phase
            FormalDefinition("Visible", parameters: [], body: true, plusCalPhase: .define)
        }
    }
}

@TLAModel
struct FormalDefinitionFidelityMacro {
    static var spec: TLASpec {
        #spec("FormalDefinitionFidelityMacro") {
            let value = Var<Int>("value")
            Variable(value, 0)
            FormalDefinition("Refines", parameters: [], body: true)
            SwiftTLA.Action("stay") { value.stays }
        }
    }
}

@TLAModel
struct TypedFacadeEnumDomainMacro {
    enum PersonID: String, FiniteTLAValueDomain {
        case alice, bob
        static var defaultValue: Self { .alice }
        static let finiteValues = [Self.alice, .bob]
    }

    enum CarID: String, FiniteTLAValueDomain {
        case carA, carB
        static var defaultValue: Self { .carA }
        static let finiteValues = [Self.carA, .carB]
    }

    enum Direction: String, FiniteTLAValueDomain {
        case up, down
        static var defaultValue: Self { .up }
        static let finiteValues = [Self.up, .down]
    }

    static var spec: TLASpec {
        #spec("TypedFacadeEnumDomainMacro") {
            let floor = Var<Int>("floor")
            Variable(floor, 0)
            SwiftTLA.Action("move", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                floor.becomes(1)
            }
        }
    }
}
