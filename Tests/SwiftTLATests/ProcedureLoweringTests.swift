@testable import SwiftTLA
import Testing

@Suite("Procedure Lowering")
struct ProcedureLoweringTests {
    @Test("pre-lowering Algorithm fidelity alpha-normalizes local statement binders")
    func algorithmFidelityAlphaNormalizesScopedBinders() {
        func model(letName: String, withName: String, chooseName: String) -> AlgorithmModel {
            AlgorithmModel(
                name: "ScopedFidelity",
                components: [
                    .shared(.init(root: "output", initial: .int(0))),
                    .step(.init(label: .init(name: "start"), statements: [
                        .letBinding(variable: letName, value: .int(1), [
                            .with(variable: withName, source: .setLiteral([.value(.int(1))]), [
                                .choose(variable: chooseName, domain: [.int(1)], [
                                    .set(target: .root("output"), value: .add(.variable(letName), .add(.variable(withName), .variable(chooseName))))
                                ])
                            ])
                        ])
                    ]))
                ]
            )
        }

        let parsed = AlgorithmFidelityToken(model: model(letName: "first", withName: "second", chooseName: "third"))
        let built = AlgorithmFidelityToken(model: model(letName: "x", withName: "y", chooseName: "z"))
        #expect(_tlaAlgorithmFidelityEvidence([parsed], [built]) == nil)
    }

    @Test("pre-lowering Algorithm fidelity reports a semantic path")
    func algorithmFidelityReportsSemanticDifference() {
        let expected = AlgorithmFidelityToken(model: AlgorithmModel(
            name: "FidelityDifference",
            components: [.step(.init(label: .init(name: "start"), statements: [.skip]))]
        ))
        let actual = AlgorithmFidelityToken(model: AlgorithmModel(
            name: "FidelityDifference",
            components: [.step(.init(label: .init(name: "start"), statements: [.stop]))]
        ))

        let evidence = _tlaAlgorithmFidelityEvidence([expected], [actual])
        #expect(evidence?.whatFailed == "Algorithm IR differs before lowering")
        #expect(evidence?.location == .semanticPath("algorithms[0].components[0].statements[0]"))
        #expect(evidence?.expected == "skip")
        #expect(evidence?.actual == "stop")
    }

    @Test("call and return restore the caller environment after one atomic procedure step")
    func callReturnRestoresFrame() throws {
        let model = AlgorithmModel(
            name: "ProcedureFrame",
            components: [
                .shared(.init(root: "output", initial: .int(0))),
                .step(.init(label: .init(name: "start"), statements: [
                    .call(target: "work", arguments: [.int(7)])
                ])),
                .step(.init(label: .init(name: "finished"), statements: [.stop])),
                .procedure(.init(
                    name: "work",
                    parameters: [.init(root: "workValue", initial: .int(0), swiftTypeName: "Int")],
                    locals: [.init(root: "workOffset", initial: .int(1), swiftTypeName: "Int")],
                    steps: [.init(label: .init(name: "enter"), statements: [
                        .set(target: .root("output"), value: .add(.variable("workValue"), .variable("workOffset"))),
                        .return
                    ])]
                ))
            ]
        )

        #expect(AlgorithmValidator.validate(model).isEmpty)
        let spec = AlgorithmLowerer.lower(model)
        let initial = try #require(computeInitialStates(spec).first)
        let afterCall = try apply("start", in: spec, to: initial)
        #expect(afterCall["pc"] == .string("procedure.work.enter"))
        #expect(afterCall["workValue"] == .int(7))
        #expect(afterCall["workOffset"] == .int(1))
        #expect(afterCall["__pcal_stack"] != .tuple([]))

        let afterReturn = try apply("procedure.work.enter", in: spec, to: afterCall)
        #expect(afterReturn["output"] == .int(8))
        #expect(afterReturn["workValue"] == .int(0))
        #expect(afterReturn["workOffset"] == .int(1))
        #expect(afterReturn["__pcal_stack"] == .tuple([]))
        #expect(afterReturn["pc"] == .string("finished"))
    }

    @Test("cross-procedure tail call keeps the original continuation and restores every frame slot")
    func crossProcedureTailCallUsesUnifiedFrame() throws {
        let model = AlgorithmModel(
            name: "TailProcedureFrame",
            components: [
                .shared(.init(root: "output", initial: .int(0))),
                .step(.init(label: .init(name: "start"), statements: [
                    .call(target: "outer", arguments: [.int(4)])
                ])),
                .step(.init(label: .init(name: "finished"), statements: [.stop])),
                .procedure(.init(
                    name: "outer",
                    parameters: [.init(root: "outerValue", initial: .int(0), swiftTypeName: "Int")],
                    locals: [],
                    steps: [.init(label: .init(name: "enter"), statements: [
                        .call(target: "inner", arguments: [.variable("outerValue")]),
                        .return
                    ])]
                )),
                .procedure(.init(
                    name: "inner",
                    parameters: [.init(root: "innerValue", initial: .int(0), swiftTypeName: "Int")],
                    locals: [],
                    steps: [.init(label: .init(name: "enter"), statements: [
                        .set(target: .root("output"), value: .variable("innerValue")),
                        .return
                    ])]
                ))
            ]
        )

        #expect(AlgorithmValidator.validate(model).isEmpty)
        let spec = AlgorithmLowerer.lower(model)
        let initial = try #require(computeInitialStates(spec).first)
        let inOuter = try apply("start", in: spec, to: initial)
        let inInner = try apply("procedure.outer.enter", in: spec, to: inOuter)
        #expect(inInner["pc"] == .string("procedure.inner.enter"))
        #expect(inInner["__pcal_stack"] == inOuter["__pcal_stack"])
        #expect(inInner["innerValue"] == .int(4))

        let afterReturn = try apply("procedure.inner.enter", in: spec, to: inInner)
        #expect(afterReturn["output"] == .int(4))
        #expect(afterReturn["outerValue"] == .int(0))
        #expect(afterReturn["innerValue"] == .int(0))
        #expect(afterReturn["__pcal_stack"] == .tuple([]))
        #expect(afterReturn["pc"] == .string("finished"))
    }

    @Test("Each processes keep recursive procedure frames and parameter slots independent")
    func eachProcessesIsolateProcedureFrames() throws {
        let workers: [TLAValue] = [.int(1), .int(2)]
        let model = AlgorithmModel(
            name: "ProcessProcedureFrame",
            components: [
                .shared(.init(root: "seen", initial: .value(.function([
                    .int(1): .int(0),
                    .int(2): .int(0)
                ])))),
                .process(.init(
                    typeName: "Worker",
                    domain: workers,
                    fairness: .none,
                    components: [
                        .step(.init(label: .init(name: "start"), statements: [
                            .call(target: "outer", arguments: [.variable("__pcal_self")])
                        ])),
                        .step(.init(label: .init(name: "finished"), statements: [.stop]))
                    ]
                )),
                .procedure(.init(
                    name: "outer",
                    parameters: [.init(root: "outerValue", initial: .int(0), swiftTypeName: "Int")],
                    locals: [],
                    steps: [.init(label: .init(name: "enter"), statements: [
                        .call(target: "inner", arguments: [.variable("outerValue")])
                    ]), .init(label: .init(name: "return"), statements: [
                        .return
                    ])]
                )),
                .procedure(.init(
                    name: "inner",
                    parameters: [.init(root: "innerValue", initial: .int(0), swiftTypeName: "Int")],
                    locals: [],
                    steps: [.init(label: .init(name: "enter"), statements: [
                        .set(target: .function(root: "seen", key: .variable("innerValue")), value: .variable("innerValue")),
                        .return
                    ])]
                ))
            ]
        )

        #expect(AlgorithmValidator.validate(model).isEmpty)
        let spec = AlgorithmLowerer.lower(model)
        let initial = try #require(computeInitialStates(spec).first)
        let oneInOuter = try apply("start", process: .int(1), in: spec, to: initial)
        let bothInOuter = try apply("start", process: .int(2), in: spec, to: oneInOuter)
        #expect(try functionValue("outerValue", key: .int(1), in: bothInOuter) == .int(1))
        #expect(try functionValue("outerValue", key: .int(2), in: bothInOuter) == .int(2))

        let oneInInner = try apply("procedure.outer.enter", process: .int(1), in: spec, to: bothInOuter)
        #expect(try functionValue("innerValue", key: .int(1), in: oneInInner) == .int(1))
        #expect(try functionValue("innerValue", key: .int(2), in: oneInInner) == .int(0))
        let stackBeforeNestedCall = try functionValue("__pcal_stack", key: .int(1), in: bothInOuter)
        let stackDuringNestedCall = try functionValue("__pcal_stack", key: .int(1), in: oneInInner)
        #expect(stackDuringNestedCall != stackBeforeNestedCall)

        let oneReturned = try apply("procedure.inner.enter", process: .int(1), in: spec, to: oneInInner)
        #expect(try functionValue("seen", key: .int(1), in: oneReturned) == .int(1))
        #expect(try functionValue("seen", key: .int(2), in: oneReturned) == .int(0))
        #expect(try functionValue("innerValue", key: .int(1), in: oneReturned) == .int(0))
        #expect(try functionValue("outerValue", key: .int(1), in: oneReturned) == .int(1))
        #expect(try functionValue("outerValue", key: .int(2), in: oneReturned) == .int(2))
        #expect(try functionValue("pc", key: .int(1), in: oneReturned) == .string("procedure.outer.return"))

        let oneFinished = try apply("procedure.outer.return", process: .int(1), in: spec, to: oneReturned)
        #expect(try functionValue("pc", key: .int(1), in: oneFinished) == .string("finished"))
        #expect(try functionValue("pc", key: .int(2), in: oneFinished) == .string("procedure.outer.enter"))
    }

    private func apply(_ label: String, in spec: TLASpec, to state: [String: TLAValue]) throws -> [String: TLAValue] {
        let action = try #require(spec.actions.first(where: { $0.name == label }))
        let next = try ActionEnumerator.enumerate(
            action.body,
            from: state,
            varNames: spec.variables.map(\.name)
        )
        #expect(next.count == 1)
        return try #require(next.first)
    }

    private func apply(
        _ label: String,
        process: TLAValue,
        in spec: TLASpec,
        to state: [String: TLAValue]
    ) throws -> [String: TLAValue] {
        let action = try #require(spec.actions.first(where: { $0.name == label }))
        let variant = try #require(actionInvocations(action).first { $0.invocation.arguments == [process] })
        let next = try ActionEnumerator.enumerate(variant.body, from: state, varNames: spec.variables.map(\.name))
        #expect(next.count == 1)
        return try #require(next.first)
    }

    private func functionValue(_ root: String, key: TLAValue, in state: [String: TLAValue]) throws -> TLAValue {
        let value = try #require(state[root])
        return try #require(value.functionValue[key])
    }
}
