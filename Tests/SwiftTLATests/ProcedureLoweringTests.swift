@testable import SwiftTLA
import Testing

@Suite("Procedure Lowering")
struct ProcedureLoweringTests {
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
}
