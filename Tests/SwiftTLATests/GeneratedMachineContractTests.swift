import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct GeneratedContractSurfaceModel {
    static var spec: TLASpec {
        #spec("GeneratedContractSurfaceModel") {
            let count = Var<Int>("count")
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1).when(count < 1) }
        }
    }
}

@Suite("Generated machine contracts")
struct GeneratedMachineContractTests {
    private func compilation() throws -> CompiledSpecification {
        let count = Var<Int>("count")
        let spec = TLASpec("GeneratedMachineContract") {
            Variable(count, 0)
            Action("advance", parameters: [ActionParameter<Int>("step", values: [1, 2])]) {
                count.becomes(count + 1).when(count < 1)
            }
        }
        return try spec.compile()
    }

    private func plan(_ compilation: CompiledSpecification) throws -> MachineSurfacePlan {
        try .init(
            compilation: compilation,
            swiftFacts: .init(
                variableTypes: ["count": "Int"],
                actionBindingTypes: ["advance": ["step": "Int"]]
            )
        )
    }

    private func projection(_ count: Int) throws -> TLAStateProjection {
        let token = try #require(TLAStateProjection.Token(validating: "count"))
        return try .init(validating: [.init(token: token, value: .int(count))])
    }

    private func behavior(
        _ compilation: CompiledSpecification,
        plan: MachineSurfacePlan
    ) -> GeneratedMachineBehavior {
        let runtime = SpecRuntime(compilation: compilation)
        return .init(
            initialStates: { try runtime.initialStateProjections() },
            actions: plan.actionInputs.map { input in
                .init(successors: { projection in
                    try runtime.successors(
                        actionAt: input.ordinal,
                        arguments: input.arguments,
                        from: projection
                    )
                })
            }
        )
    }

    @Test("metadata domains are rejected when they drift from the machine plan")
    func rejectsMetadataDomainDrift() throws {
        let compilation = try compilation()
        let plan = try plan(compilation)
        let action = try #require(plan.actions.first)
        let driftedAction = MachineSurfacePlan.Action(
            formalName: action.formalName,
            swiftIdentifier: action.swiftIdentifier,
            bindings: [
                .init(formalName: "step", swiftType: "Int", domain: [.int(1)], isPublic: true)
            ]
        )
        let metadata = GeneratedMachineMetadata(
            compilationIdentity: plan.compilationIdentity,
            schemaIdentifier: plan.schemaIdentifier,
            variables: plan.variables,
            actions: [driftedAction]
        )

        let report = GeneratedMachineContractVerifier.verify(
            compilation: compilation,
            plan: plan,
            metadata: metadata,
            expectedSchemaIdentifier: plan.schemaIdentifier,
            verificationStateLimit: 4,
            decodeState: { _ in },
            behavior: behavior(compilation, plan: plan)
        )

        #expect(report.status == .difference)
        #expect(report.diagnostic?.code == .metadataDomainMismatch)
    }

    @Test("machine-plan action inputs retain declared action order")
    func actionInputsRetainDeclaredOrder() throws {
        let plan = try plan(compilation())
        #expect(plan.actionInputs == [
            .init(ordinal: 0, arguments: [.int(1)]),
            .init(ordinal: 0, arguments: [.int(2)])
        ])
    }

    @Test("projection decoding failures are a difference, not unavailable evaluation")
    func distinguishesProjectionDecodeMismatch() throws {
        let compilation = try compilation()
        let plan = try plan(compilation)

        let report = GeneratedMachineContractVerifier.verify(
            compilation: compilation,
            plan: plan,
            metadata: plan.metadata,
            expectedSchemaIdentifier: plan.schemaIdentifier,
            verificationStateLimit: 4,
            decodeState: { _ in
                throw TLAStateProjectionDiagnostic.typeMismatch(
                    path: "count",
                    expected: "String",
                    actual: .int(0)
                )
            },
            behavior: behavior(compilation, plan: plan)
        )

        #expect(report.status == .difference)
        #expect(report.diagnostic?.code == .projectionDecodeMismatch)
    }

    @Test("a behavior witness that omits a formal transition is a mismatch")
    func detectsDeliberateBehaviorMismatch() throws {
        let compilation = try compilation()
        let plan = try plan(compilation)
        let initial = try projection(0)
        let behavior = GeneratedMachineBehavior(
            initialStates: { [initial] },
            actions: [.init(successors: { _ in [] }), .init(successors: { _ in [] })]
        )

        let report = GeneratedMachineContractVerifier.verify(
            compilation: compilation,
            plan: plan,
            metadata: plan.metadata,
            expectedSchemaIdentifier: plan.schemaIdentifier,
            verificationStateLimit: 4,
            decodeState: { _ in },
            behavior: behavior
        )

        #expect(report.status == .difference)
        #expect(report.diagnostic?.code == .behaviorMismatch)
    }

    @Test("a behavior witness with an extra labeled successor is a mismatch")
    func rejectsExtraSuccessorOccurrence() throws {
        let compilation = try compilation()
        let plan = try plan(compilation)
        let reference = behavior(compilation, plan: plan)
        let behavior = GeneratedMachineBehavior(
            initialStates: reference.initialStates,
            actions: reference.actions.map { action in
                .init(successors: { state in
                    let targets = try action.successors(state)
                    return targets + targets
                })
            }
        )

        let report = GeneratedMachineContractVerifier.verify(
            compilation: compilation,
            plan: plan,
            metadata: plan.metadata,
            expectedSchemaIdentifier: plan.schemaIdentifier,
            verificationStateLimit: 4,
            decodeState: { _ in },
            behavior: behavior
        )

        #expect(report.status == .difference)
        #expect(report.diagnostic?.code == .behaviorMismatch)
    }

    @Test("a behavior witness with duplicate initial state is a mismatch")
    func rejectsDuplicateInitialStateOccurrence() throws {
        let compilation = try compilation()
        let plan = try plan(compilation)
        let reference = behavior(compilation, plan: plan)
        let behavior = GeneratedMachineBehavior(
            initialStates: {
                let initial = try reference.initialStates()
                return initial + initial
            },
            actions: reference.actions
        )

        let report = GeneratedMachineContractVerifier.verify(
            compilation: compilation,
            plan: plan,
            metadata: plan.metadata,
            expectedSchemaIdentifier: plan.schemaIdentifier,
            verificationStateLimit: 4,
            decodeState: { _ in },
            behavior: behavior
        )

        #expect(report.status == .difference)
        #expect(report.diagnostic?.code == .behaviorMismatch)
    }

    @Test("an expansion-time schema fingerprint rejects runtime plan drift")
    func rejectsSchemaFingerprintDrift() throws {
        let compilation = try compilation()
        let plan = try plan(compilation)

        let report = GeneratedMachineContractVerifier.verify(
            compilation: compilation,
            plan: plan,
            metadata: plan.metadata,
            expectedSchemaIdentifier: "different-schema",
            verificationStateLimit: 4,
            decodeState: { _ in },
            behavior: behavior(compilation, plan: plan)
        )

        #expect(report.status == .difference)
        #expect(report.diagnostic?.code == .schemaMismatch)
    }

    @Test("the macro exposes metadata and verifies its generated projection surface")
    func macroGeneratedSurfaceUsesTheMachinePlan() throws {
        let compilation = try GeneratedContractSurfaceModel.compiledSpecification()
        let plan = try MachineSurfacePlan(compilation: compilation)
        let report = GeneratedContractSurfaceModel.verifyGeneratedMachineContract()

        #expect(GeneratedContractSurfaceModel.generatedMachineMetadata == plan.metadata)
        #expect(plan.variables.map(\.formalName) == compilation.layout.variables.map(\.declaration.name))
        #expect(plan.actions.map(\.formalName) == compilation.layout.actions.map(\.declaration.name))
        #expect(report.status == .exact)
        #expect(report.initialStateCount == 1)
        #expect(report.transitionCount == 1)
        #expect(GeneratedContractSurfaceModel.machineSchema.model.name == "GeneratedContractSurfaceModel")
        #expect(GeneratedContractSurfaceModel.machineSchema.state.map(\.id) == ["count"])
        #expect(GeneratedContractSurfaceModel.machineSchema.actions.map(\.id) == ["advance"])
    }
}
