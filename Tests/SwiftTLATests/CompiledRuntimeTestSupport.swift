@testable import SwiftTLA
import Testing

func firstCompiledState(in compilation: CompiledSpecification) throws -> CompiledState {
    try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
}

func renderedInitialStates(in compilation: CompiledSpecification) throws -> [TLAStateProjection] {
    try CompiledRuntime(compilation: compilation).initialStates().map {
        try $0.projection(using: compilation.layout)
    }
}

func compiledSuccessors(
    named name: String,
    arguments: [TLAValue],
    in compilation: CompiledSpecification,
    from state: CompiledState
) throws -> [CompiledState] {
    let action = try #require(compilation.layout.actionID(named: name))
    return try CompiledRuntime(compilation: compilation)
        .successors(for: action, from: state)
        .filter { successor in
            try successor.arguments.map { try $0.rendered(using: compilation.layout) } == arguments
        }
        .map(\.state)
}

func renderedValue(
    named name: String,
    in state: CompiledState,
    compilation: CompiledSpecification
) throws -> TLAValue {
    let variable = try #require(compilation.layout.variableID(named: name))
    return try state.value(for: variable).rendered(using: compilation.layout)
}
