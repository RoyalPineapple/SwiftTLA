import Foundation
import SwiftTLA

enum SelectedActionFailureEvidence {
    struct Input {
        let actionLines: [String]
        let definitions: String
    }

    static func input(authoredText: String, spec: TLASpec, program: CompiledProgram,
                      rendered: RenderedModule) throws -> Input {
        let authored = try AuthoredCopySyntax.capturedSequentialSteps(
            source: authoredText, modelName: "SelectedChecksModel")
        guard authored.steps.count == 1, let step = authored.steps.first,
              step.loopCondition == nil, step.statements.count == 3,
              case .when(.equal(.variable(let read), .value(.int(let compared)))) = step.statements[0],
              case .set(.root(let target), .value(.int(let written))) = step.statements[1],
              case .goto(let destination) = step.statements[2],
              destination == step.label,
              spec.sourceAlgorithms.count == 1, let built = spec.sourceAlgorithms.first?.model,
              built.name == authored.algorithm
        else { throw invalid("authored and built action operands") }
        let builtSteps = built.components.compactMap { component -> AlgorithmStepModel? in
            guard case .step(let step) = component else { return nil }
            return step
        }
        guard builtSteps.count == 1, let builtStep = builtSteps.first, builtStep.loopCondition == nil,
              builtStep.label == step.label, builtStep.statements == step.statements
        else { throw invalid("authored and built action operands") }

        let layout = program.layout
        let scalars = layout.variables.filter { $0.declaration.origin != .programCounter }
        let controls = layout.variables.filter { $0.declaration.origin == .programCounter }
        guard Set(scalars.map(\.declaration.name)) == authored.fields,
              scalars.allSatisfy({ program.variableTypes[$0.id] == .int }),
              let readField = scalars.first(where: { $0.declaration.name == read }),
              let targetField = scalars.first(where: { $0.declaration.name == target }),
              let control = layout.controlLocations.first(where: {
                  $0.owner == .sequential(algorithm: authored.algorithm) && $0.sourceName == destination.name
              })
        else { throw invalid("action field and label identities") }
        let intFields = Set(scalars.map(\.formalName))
        let controlFields = Set(controls.map(\.formalName))
        let controlValues = Set(layout.controlLocations.map(\.formalName))

        let source = record([
            ("label", .string(step.label.name)), ("field", .string(readField.formalName)),
            ("compare", .int(compared)), ("target", .string(targetField.formalName)),
            ("write", .int(written)), ("goto", .string(control.formalName)),
        ])

        let declarations = rendered.renderedModuleSource.components(separatedBy: "\n")
        let formalCalls = Set(rendered.renderedActions.map(\.renderedName))
        guard rendered.symbolicActions.isEmpty, !formalCalls.isEmpty,
              formalCalls.count == program.behavior.enabledActionIndices.count else {
            throw invalid("complete rendered action inventory")
        }
        var actionLines: [String] = []
        var actionRows: [TLAValue] = []
        for index in program.behavior.enabledActionIndices {
            let action = program.behavior.actions[index]
            let name = program.layout.actions[action.id.ordinal].renderedName
            let prefix = "\(name) == "
            let definitions = declarations.filter { $0.hasPrefix(prefix) }
            guard formalCalls.contains(name), action.bindings.isEmpty, definitions.count == 1,
                  let declaration = definitions.first else { throw invalid("rendered action declaration") }
            try StraightLineRenderedActionCheck.verify(action.body, rendered: String(declaration.dropFirst(prefix.count)),
                layout: layout, binders: rendered.temporalBindingNames, moduleName: rendered.moduleName, required: true)
            actionLines.append(declaration)
            actionRows.append(record([
                ("name", .string(name)), ("demands", .tuple(try demands(action.body, layout: layout,
                    intFields: intFields, controlFields: controlFields))),
            ]))
        }
        return .init(actionLines: actionLines, definitions: """
            AuthoredTotalActionOperands == \(source)
            TotalActionIntegerFields == \(TLAValue.set(Set(intFields.map(TLAValue.string))))
            TotalActionControlFields == \(TLAValue.set(Set(controlFields.map(TLAValue.string))))
            TotalActionControlValues == \(TLAValue.set(Set(controlValues.map(TLAValue.string))))
            TotalActionMinimum == \(TLAValue.int(Int.min))
            TotalActionMaximum == \(TLAValue.int(Int.max))
            RenderedTotalActionOperands == \(TLAValue.tuple(actionRows))
            ActualActionFailureDeclarations == \(TLAValue.tuple(rendered.evaluationFailureDeclarations.map(TLAValue.string)))
            """)
    }

    private static func demands(_ action: CompiledActionExpr, layout: CompiledLayout,
                                intFields: Set<String>, controlFields: Set<String>) throws -> [TLAValue] {
        func field(_ id: VariableID) throws -> String {
            guard let name = layout.variables.first(where: { $0.id == id })?.formalName,
                  intFields.contains(name) || controlFields.contains(name)
            else { throw invalid("action field") }
            return name
        }
        func demand(_ kind: String, _ value: TLAValue) -> TLAValue {
            record([("kind", .string(kind)), ("value", value)])
        }
        func expression(_ term: CompiledExpression, scope: Set<BinderID>) throws -> [TLAValue] {
            switch term.operation {
            case .equal where term.children.count == 2:
                return try term.children.flatMap { try expression($0, scope: scope) }
            case .stateVariable(let id) where term.children.isEmpty:
                let name = try field(id)
                return [demand(intFields.contains(name) ? "integerRead" : "controlRead", .string(name))]
            case .value(.integer(let value)) where term.children.isEmpty:
                return [demand("integerLiteral", .int(value))]
            case .value(.boolean) where term.children.isEmpty:
                return []
            case .controlLocation(let id) where term.children.isEmpty:
                guard let location = layout.controlLocations.first(where: { $0.id == id }) else {
                    throw invalid("action control operand")
                }
                return [demand("controlLiteral", .string(location.formalName))]
            case .boundValue(let id) where term.children.isEmpty && scope.contains(id):
                // The defining value was checked before the scope was extended.
                return []
            default: throw invalid("expression outside the read, literal and equality rules")
            }
        }
        func visit(_ action: CompiledActionExpr, scope: Set<BinderID>) throws -> [TLAValue] {
            switch action {
            case .guard_(let term):
                return try expression(term, scope: scope)
            case .assign(let target, let term):
                _ = try field(target)
                return try expression(term, scope: scope)
            case .unchanged(let target):
                let name = try field(target)
                return [demand(intFields.contains(name) ? "integerRead" : "controlRead", .string(name))]
            case .define(let binder, let term, let body):
                return try expression(term, scope: scope) + visit(body, scope: scope.union([binder]))
            case .and(let first, let later):
                return try visit(first, scope: scope) + visit(later, scope: scope)
            default: throw invalid("action outside scalar guard, capture, assignment and frame rules")
            }
        }
        return try visit(action, scope: [])
    }

    private static func record(_ fields: [(String, TLAValue)]) -> TLAValue {
        .record(TLARecord(fields.map { .init($0.0, $0.1) }))
    }

    private static func invalid(_ field: String) -> EvidenceFormatError {
        .invalidField(record: "SelectedChecks action", field: field)
    }
}
