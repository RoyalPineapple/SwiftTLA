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
                    .shared(.init(root: "output", initialization: .value(.int(0)))),
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
        #expect(parsed == built)
    }

    @Test("different algorithms have different source tokens")
    func differentAlgorithmsHaveDifferentSourceTokens() {
        let expected = AlgorithmFidelityToken(model: AlgorithmModel(
            name: "FidelityDifference",
            components: [.step(.init(label: .init(name: "start"), statements: [.skip]))]
        ))
        let actual = AlgorithmFidelityToken(model: AlgorithmModel(
            name: "FidelityDifference",
            components: [.step(.init(label: .init(name: "start"), statements: [.stop]))]
        ))

        #expect(expected != actual)
    }

    @Test("call and return restore the caller environment after one atomic procedure step")
    func callReturnRestoresFrame() throws {
        let model = AlgorithmModel(
            name: "ProcedureFrame",
            components: [
                .shared(.init(root: "output", initialization: .value(.int(0)))),
                .step(.init(label: .init(name: "start"), statements: [
                    .call(target: "work", arguments: [.int(7)])
                ])),
                .step(.init(label: .init(name: "finished"), statements: [.stop])),
                .procedure(.init(
                    name: "work",
                    parameters: [.init(root: "workValue", initial: .int(0), swiftTypeName: "Int")],
                    components: [
                        .local(.init(root: "workOffset", initialization: .value(.int(1)), swiftTypeName: "Int")),
                        .step(.init(label: .init(name: "enter"), statements: [
                            .set(target: .root("output"), value: .add(.variable("workValue"), .variable("workOffset"))),
                            .return
                        ]))
                    ]
                ))
            ]
        )

        #expect(AlgorithmValidator.validate(model).isEmpty)
        let spec = try AlgorithmLowerer.lower(model)
        let (compilation, initial) = try initialState(of: spec)
        let afterCall = try apply("start", in: compilation, to: initial)
        #expect(try value(named: "pc", in: afterCall, compilation: compilation) == .string("enter"))
        #expect(try value(named: "workValue", in: afterCall, compilation: compilation) == .int(7))
        #expect(try value(named: "workOffset", in: afterCall, compilation: compilation) == .int(1))
        #expect(try value(named: "stack", in: afterCall, compilation: compilation) != .tuple([]))
        let rendered = compilation.renderedTLAModuleBundle().tla
        #expect(rendered.contains("pc' = \"enter\""))
        #expect(rendered.contains("pc' = \"procedure.work.enter\"") == false)

        let afterReturn = try apply("procedure.work.enter", in: compilation, to: afterCall)
        #expect(try value(named: "output", in: afterReturn, compilation: compilation) == .int(8))
        #expect(try value(named: "workValue", in: afterReturn, compilation: compilation) == .int(0))
        #expect(try value(named: "workOffset", in: afterReturn, compilation: compilation) == .int(1))
        #expect(try value(named: "stack", in: afterReturn, compilation: compilation) == .tuple([]))
        #expect(try value(named: "pc", in: afterReturn, compilation: compilation) == .string("finished"))
    }

    @Test("cross-procedure tail call keeps the original continuation and restores every frame slot")
    func crossProcedureTailCallUsesUnifiedFrame() throws {
        let model = AlgorithmModel(
            name: "TailProcedureFrame",
            components: [
                .shared(.init(root: "output", initialization: .value(.int(0)))),
                .step(.init(label: .init(name: "start"), statements: [
                    .call(target: "outer", arguments: [.int(4)])
                ])),
                .step(.init(label: .init(name: "finished"), statements: [.stop])),
                .procedure(.init(
                    name: "outer",
                    parameters: [.init(root: "outerValue", initial: .int(0), swiftTypeName: "Int")],
                    components: [.step(.init(label: .init(name: "enter"), statements: [
                        .call(target: "inner", arguments: [.variable("outerValue")]),
                        .return
                    ]))]
                )),
                .procedure(.init(
                    name: "inner",
                    parameters: [.init(root: "innerValue", initial: .int(0), swiftTypeName: "Int")],
                    components: [.step(.init(label: .init(name: "enter"), statements: [
                        .set(target: .root("output"), value: .variable("innerValue")),
                        .return
                    ]))]
                ))
            ]
        )

        #expect(AlgorithmValidator.validate(model).isEmpty)
        let spec = try AlgorithmLowerer.lower(model)
        let (compilation, initial) = try initialState(of: spec)
        let inOuter = try apply("start", in: compilation, to: initial)
        let inInner = try apply("procedure.outer.enter", in: compilation, to: inOuter)
        #expect(try value(named: "pc", in: inInner, compilation: compilation) == .string("enter"))
        let outerStack = try value(named: "stack", in: inOuter, compilation: compilation)
        let innerStack = try value(named: "stack", in: inInner, compilation: compilation)
        #expect(innerStack == outerStack)
        #expect(try value(named: "innerValue", in: inInner, compilation: compilation) == .int(4))

        let afterReturn = try apply("procedure.inner.enter", in: compilation, to: inInner)
        #expect(try value(named: "output", in: afterReturn, compilation: compilation) == .int(4))
        #expect(try value(named: "outerValue", in: afterReturn, compilation: compilation) == .int(0))
        #expect(try value(named: "innerValue", in: afterReturn, compilation: compilation) == .int(0))
        #expect(try value(named: "stack", in: afterReturn, compilation: compilation) == .tuple([]))
        #expect(try value(named: "pc", in: afterReturn, compilation: compilation) == .string("finished"))
    }

    @Test("Each processes keep recursive procedure frames and parameter slots independent")
    func eachProcessesIsolateProcedureFrames() throws {
        let workers: [TLAValue] = [.int(1), .int(2)]
        let model = AlgorithmModel(
            name: "ProcessProcedureFrame",
            components: [
                .shared(.init(root: "seen", initialization: .value(.function([
                    .int(1): .int(0),
                    .int(2): .int(0)
                ])), swiftTypeName: "Function<Worker, Int>")),
                .process(.init(
                    typeName: "Worker",
                    domain: workers,
                    fairness: .none,
                    components: [
                        .step(.init(label: .init(name: "start"), statements: [
                            .call(target: "outer", arguments: [.currentProcess])
                        ])),
                        .step(.init(label: .init(name: "finished"), statements: [.stop]))
                    ]
                )),
                .procedure(.init(
                    name: "outer",
                    parameters: [.init(root: "outerValue", initial: .int(0), swiftTypeName: "Int")],
                    components: [.step(.init(label: .init(name: "enter"), statements: [
                        .call(target: "inner", arguments: [.variable("outerValue")])
                    ])), .step(.init(label: .init(name: "return"), statements: [.return]))]
                )),
                .procedure(.init(
                    name: "inner",
                    parameters: [.init(root: "innerValue", initial: .int(0), swiftTypeName: "Int")],
                    components: [.step(.init(label: .init(name: "enter"), statements: [
                        .set(target: .function(root: "seen", key: .variable("innerValue")), value: .variable("innerValue")),
                        .return
                    ]))]
                ))
            ]
        )

        #expect(AlgorithmValidator.validate(model).isEmpty)
        let spec = try AlgorithmLowerer.lower(model)
        let procedureAction = try #require(spec.actions.first { $0.name == "procedure.outer.enter" })
        #expect(procedureAction.bindings.map(\.generatedSwiftType) == ["Worker"])
        let (compilation, initial) = try initialState(of: spec)
        let oneInOuter = try apply("start", process: .int(1), in: compilation, to: initial)
        let bothInOuter = try apply("start", process: .int(2), in: compilation, to: oneInOuter)
        #expect(try functionValue("outerValue", key: .int(1), in: bothInOuter, compilation: compilation) == .int(1))
        #expect(try functionValue("outerValue", key: .int(2), in: bothInOuter, compilation: compilation) == .int(2))

        let oneInInner = try apply("procedure.outer.enter", process: .int(1), in: compilation, to: bothInOuter)
        #expect(try functionValue("innerValue", key: .int(1), in: oneInInner, compilation: compilation) == .int(1))
        #expect(try functionValue("innerValue", key: .int(2), in: oneInInner, compilation: compilation) == .int(0))
        let stackBeforeNestedCall = try functionValue("stack", key: .int(1), in: bothInOuter, compilation: compilation)
        let stackDuringNestedCall = try functionValue("stack", key: .int(1), in: oneInInner, compilation: compilation)
        #expect(stackDuringNestedCall != stackBeforeNestedCall)

        let oneReturned = try apply("procedure.inner.enter", process: .int(1), in: compilation, to: oneInInner)
        #expect(try functionValue("seen", key: .int(1), in: oneReturned, compilation: compilation) == .int(1))
        #expect(try functionValue("seen", key: .int(2), in: oneReturned, compilation: compilation) == .int(0))
        #expect(try functionValue("innerValue", key: .int(1), in: oneReturned, compilation: compilation) == .int(0))
        #expect(try functionValue("outerValue", key: .int(1), in: oneReturned, compilation: compilation) == .int(1))
        #expect(try functionValue("outerValue", key: .int(2), in: oneReturned, compilation: compilation) == .int(2))
        #expect(try functionValue("pc", key: .int(1), in: oneReturned, compilation: compilation) == .string("return"))

        let oneFinished = try apply("procedure.outer.return", process: .int(1), in: compilation, to: oneReturned)
        #expect(try functionValue("pc", key: .int(1), in: oneFinished, compilation: compilation) == .string("finished"))
        #expect(try functionValue("pc", key: .int(2), in: oneFinished, compilation: compilation) == .string("enter"))
    }

    private func initialState(of spec: TLASpec) throws -> (CompiledSpecification, CompiledState) {
        let compilation = try spec.compile()
        let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        return (compilation, state)
    }

    private func apply(_ label: String, in compilation: CompiledSpecification, to state: CompiledState) throws -> CompiledState {
        try #require(try successors(label, in: compilation, from: state).first)
    }

    private func apply(
        _ label: String,
        process: TLAValue,
        in compilation: CompiledSpecification,
        to state: CompiledState
    ) throws -> CompiledState {
        try #require(try successors(label, arguments: [process], in: compilation, from: state).first)
    }

    private func successors(
        _ label: String,
        arguments: [TLAValue]? = nil,
        in compilation: CompiledSpecification,
        from state: CompiledState
    ) throws -> [CompiledState] {
        let action = try #require(compilation.layout.actionID(named: label))
        return try CompiledRuntime(compilation: compilation)
            .successors(for: action, from: state)
            .filter { successor in
                guard let arguments else { return true }
                return try successor.arguments.map { try $0.rendered(using: compilation.layout) } == arguments
            }
            .map(\.state)
    }

    private func value(named name: String, in state: CompiledState, compilation: CompiledSpecification) throws -> TLAValue {
        let variable = try #require(compilation.layout.variableID(named: name))
        return try state.value(for: variable).rendered(using: compilation.layout)
    }

    private func functionValue(
        _ root: String,
        key: TLAValue,
        in state: CompiledState,
        compilation: CompiledSpecification
    ) throws -> TLAValue {
        let formalValue = try value(named: root, in: state, compilation: compilation)
        guard case .function(let values) = formalValue else {
            throw ProcedureLoweringTestError.expectedFunction
        }
        return try #require(values[key])
    }
}

private enum ProcedureLoweringTestError: Error {
    case expectedFunction
}
