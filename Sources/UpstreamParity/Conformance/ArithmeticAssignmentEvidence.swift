import Foundation
import SwiftTLA

private struct ArithmeticAssignmentFailureReceipt: Codable {
    struct Binding: Codable {
        let name: String
        let value: TLAValue
    }

    let label: String
    let actionOrdinal: Int
    let site: Int
    let completed: [Int]
    let kind: String
    let operation: String
    let operands: [Int]
    let before: [Binding]

    var tla: TLAValue {
        let original = TLAValue.function(Dictionary(uniqueKeysWithValues: before.map {
            (TLAValue.string($0.name), $0.value)
        }))
        let failure = TLAValue.tuple([.string(kind), .string(operation), .tuple(operands.map(TLAValue.int))])
        return .record(TLARecord([
            .init("label", .string(label)),
            .init("actionOrdinal", .int(actionOrdinal)),
            .init("site", .int(site)),
            .init("completed", .tuple(completed.map(TLAValue.int))),
            .init("payload", failure),
            .init("before", original),
        ]))
    }
}

private struct ArithmeticAssignmentPreparation: Codable {
    let sourceSHA: String
    let sourceCompilationIdentity: String
    let authoredSourceSHA256: String
    let nativeSourceSHA256: String
    let files: [String: String]
}

package enum ArithmeticAssignmentEvidence {
    package static func prepare(sourceSHA: String, authoredSource: Data, nativeSource: Data,
                                to directory: URL) throws {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard TLCReferencePin.isRevision(sourceSHA) else { throw InitialFailureEvidenceError.invalidSourceSHA }
        guard !authoredSource.contains(0), let authored = String(data: authoredSource, encoding: .utf8),
              !nativeSource.contains(0), let native = String(data: nativeSource, encoding: .utf8) else { throw invalid }

        let spec = OrderedOverflowModel.spec
        let compilation = try spec.compile()
        let inputs = try CompiledTypeInputs(compilation: compilation,
            types: CompiledTypeContext(enums: .init(), formalNames: [:])) { spelling in
                guard ["Int", "Swift.Int"].contains(spelling) else { throw invalid }
                return .int
            }
        let program = try CompiledProgram(inputs: inputs)
        let rendered = try OrderedOverflowModel.render()
        let bundle = rendered.tlaBundle
        let direct = try program.renderModule()
        guard case .compiled(let identity, _, _) = bundle.provenance, identity == program.identity,
              bundle.imports.isEmpty, direct.imports.isEmpty,
              rendered.actions == direct.renderedActions,
              let catalog = StraightLineRenderedActionCheck.unboundActionCatalog(in: rendered, layout: program.layout),
              let config = bundle.root.cfg,
              bundle.root.tla.utf8.elementsEqual(direct.renderedModuleSource.utf8),
              config.utf8.elementsEqual(try direct.configuration.render(usesSymmetryReduction: false).utf8)
        else { throw invalid }

        let live = try observe(program)
        let nativeDefinitions = try nativeScalarActionDefinitions(native, program: program, selectedActionOrdinal: live.actionOrdinal)
        let nativeModule = """
        ---- MODULE SwiftTLANativeAssignmentActions ----
        EXTENDS Integers

        \(nativeDefinitions)
        NativeAssignmentFailure == \(live.tla)
        ====

        """
        let sourceModule = "SwiftTLAArithmeticAssignmentSource"
        let selection = try AuthoredCopySyntax.select(
            source: authored, modelName: String(describing: OrderedOverflowModel.self))
        let source = try AuthoredCopySyntax.arithmeticProofInput(selection, spec: spec)
        guard source.label == live.label,
              let outputProof = try OrderedRHSTLAProof.render(rendered, program: program, sourceAction: source.label,
                sourceModule: sourceModule, sourceRows: "MasterRows", supportTheorem: "MasterAssignmentsAreSupported"),
              let configured = OrderedRHSCFGProof.render(for: rendered, catalog: catalog, actionProofModule: outputProof.name)
        else { throw invalid }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let outputs = [
            ("authored-arithmetic-source.swift", authoredSource),
            ("native-arithmetic-source.swift", nativeSource),
            ("\(bundle.root.name).tla", Data(bundle.root.tla.utf8)),
            ("\(bundle.root.name).cfg", Data(config.utf8)),
            ("\(sourceModule).tla", Data(source.module.utf8)),
            ("SwiftTLANativeAssignmentActions.tla", Data(nativeModule.utf8)),
            ("native-assignment-failure.json", try encoder.encode(live)),
            ("\(outputProof.name).tla", outputProof.bytes),
            ("\(configured.name).tla", configured.bytes),
        ]
        let manifest = ArithmeticAssignmentPreparation(sourceSHA: sourceSHA,
            sourceCompilationIdentity: identity.description, authoredSourceSHA256: SHA256.hex(authoredSource),
            nativeSourceSHA256: SHA256.hex(nativeSource),
            files: Dictionary(uniqueKeysWithValues: outputs.map { ($0.0, SHA256.hex($0.1)) }))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in outputs {
            try data.write(to: directory.appendingPathComponent(name), options: .withoutOverwriting)
        }
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("arithmetic-preparation.json"),
                                           options: .withoutOverwriting)
    }

    private static func observe(_ program: CompiledProgram) throws -> ArithmeticAssignmentFailureReceipt {
        let invalid = InitialFailureEvidenceError.unsupportedNativeOutcome
        let machine = try OrderedOverflowModel.makeMachine()
        let before = try machine.formalProjection(of: machine.snapshot)
        var context = CheckingContext(registers: try machine.initialCheckingRegisters())
        context.startRecordingOrderedIntAssignmentFailures()
        var callbacks: [(FormalActionCall, NativeMachineEvaluationError)] = []
        var emittedSuccessor = false
        let found = try machine.visitValidationOutcomes(checking: &context, { _, _ in
            emittedSuccessor = true
            return true
        }, onEvaluationFailure: { action, reason in
            callbacks.append((try machine.formalCall(for: action), reason))
            return true
        })
        guard !found, !emittedSuccessor, callbacks.count == 1, let (call, reason) = callbacks.first,
              let failures = context.orderedIntAssignmentFailures, failures.count == 1, let failure = failures.first,
              failure.reason == reason, case .integerOverflow(.addition, let operands) = reason, operands.count == 2,
              failure.assignmentOrdinal > 0, failure.preceding.count == failure.assignmentOrdinal - 1,
              program.layout.actions.indices.contains(failure.actionOrdinal),
              call.arguments.isEmpty else { throw invalid }
        let action = program.layout.actions[failure.actionOrdinal]
        guard action.id.ordinal == failure.actionOrdinal, !action.isTermination, program.requiresOrderedIntOutput(action.id),
              action.renderedName.utf8.elementsEqual(call.name.utf8),
              before.entries.count == program.layout.variables.count,
              before.entries.allSatisfy({ entry in
                  program.layout.variables.contains(where: {
                      $0.formalName.utf8.elementsEqual(entry.token.description.utf8)
                  })
              }) else { throw invalid }
        return .init(label: action.declaration.name, actionOrdinal: failure.actionOrdinal, site: failure.assignmentOrdinal,
            completed: failure.preceding, kind: "integerOverflow", operation: "addition", operands: operands,
            before: before.entries.map { .init(name: $0.token.description, value: $0.value) })
    }
}
