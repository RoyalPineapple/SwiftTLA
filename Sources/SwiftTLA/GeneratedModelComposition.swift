import Foundation

public struct GeneratedModelParameterBinding<Configuration: GeneratedModelFields>: Sendable {
    package let fieldName: String
    package let source: StateExpr
}

public func Bind<Configuration: GeneratedModelFields, Value: TLAValueType>(
    _ target: KeyPath<Configuration, Value>, to source: some TypedExpression<Value>, _fieldName: String = ""
) -> GeneratedModelParameterBinding<Configuration> {
    let identity = Configuration.fieldIdentities[target]
    return .init(fieldName: identity?.swiftName ?? _fieldName, source: source.stateExpr)
}

@resultBuilder
public enum GeneratedModelParameterBuilder<Configuration: GeneratedModelFields> {
    public static func buildExpression(_ binding: GeneratedModelParameterBinding<Configuration>)
        -> GeneratedModelParameterBinding<Configuration> { binding }

    public static func buildBlock(_ bindings: GeneratedModelParameterBinding<Configuration>...)
        -> [GeneratedModelParameterBinding<Configuration>] { bindings }
}

package protocol GeneratedModelInstanceSource: SpecComponent {
    var name: String { get }
    var targetModelType: String { get }
    var fieldBindings: [GeneratedModelFieldBinding] { get }
}

package struct GeneratedModelFieldBinding: Hashable, Sendable {
    package let fieldName: String
    package let source: StateExpr

    package init(fieldName: String, source: StateExpr) {
        self.fieldName = fieldName
        self.source = source
    }
}

package struct ParsedGeneratedModelInstance: GeneratedModelInstanceSource {
    package let name: String
    package let targetModelType: String
    package let fieldBindings: [GeneratedModelFieldBinding]

    package init(name: String, targetModelType: String, fieldBindings: [GeneratedModelFieldBinding]) {
        self.name = name
        self.targetModelType = targetModelType
        self.fieldBindings = fieldBindings
    }
}

public struct GeneratedModelInstance<Model: ConfiguredGeneratedModel>: GeneratedModelInstanceSource {
    public let name: String
    package let bindings: [GeneratedModelParameterBinding<Model.Configuration>]
    package let targetModelType: String
    package var fieldBindings: [GeneratedModelFieldBinding] {
        bindings.map { .init(fieldName: $0.fieldName, source: $0.source) }
    }

    package init(name: String, targetModelType: String,
        bindings: [GeneratedModelParameterBinding<Model.Configuration>]) {
        self.name = name
        self.targetModelType = targetModelType
        self.bindings = bindings
    }
}

public func Instance<Model: ConfiguredGeneratedModel>(
    _name: String = "", of model: Model.Type, _typeName: String = "",
    @GeneratedModelParameterBuilder<Model.Configuration> _ bindings: () -> [GeneratedModelParameterBinding<Model.Configuration>]
) -> GeneratedModelInstance<Model> {
    .init(name: _name,
        targetModelType: _typeName.isEmpty ? String(describing: model) : _typeName,
        bindings: bindings())
}

public struct GeneratedModelStateMapping<State: GeneratedModelFields>: Sendable {
    package let fieldName: String
    package let source: StateExpr
}

public func Map<State: GeneratedModelFields, Value: TLAValueType>(
    _ target: KeyPath<State, Value>, from source: some TypedExpression<Value>, _fieldName: String = ""
) -> GeneratedModelStateMapping<State> {
    let identity = State.fieldIdentities[target]
    return .init(fieldName: identity?.swiftName ?? _fieldName, source: source.stateExpr)
}

@resultBuilder
public enum GeneratedModelStateMappingBuilder<State: GeneratedModelFields> {
    public static func buildExpression(_ mapping: GeneratedModelStateMapping<State>)
        -> GeneratedModelStateMapping<State> { mapping }

    public static func buildBlock(_ mappings: GeneratedModelStateMapping<State>...)
        -> [GeneratedModelStateMapping<State>] { mappings }
}

package protocol GeneratedModelRefinementSource: SpecComponent, ModelProperty {
    var name: String { get }
    var instanceName: String { get }
    var fieldMappings: [GeneratedModelFieldBinding] { get }
}

package struct ParsedGeneratedModelRefinement: GeneratedModelRefinementSource {
    package let name: String
    package let reference: PropertyReference
    package let instanceName: String
    package let fieldMappings: [GeneratedModelFieldBinding]

    package init(name: String, reference: PropertyReference, instanceName: String,
        fieldMappings: [GeneratedModelFieldBinding]) {
        self.name = name
        self.reference = reference
        self.instanceName = instanceName
        self.fieldMappings = fieldMappings
    }
}

public struct GeneratedModelRefinement<Model: ConfiguredGeneratedModel>: GeneratedModelRefinementSource {
    public let name: String
    public let reference: PropertyReference
    package let instance: GeneratedModelInstance<Model>
    package let mappings: [GeneratedModelStateMapping<Model.State>]
    package var instanceName: String { instance.name }
    package var fieldMappings: [GeneratedModelFieldBinding] {
        mappings.map { .init(fieldName: $0.fieldName, source: $0.source) }
    }

    package init(name: String, label: String?, instance: GeneratedModelInstance<Model>,
        mappings: [GeneratedModelStateMapping<Model.State>]) {
        self.name = name
        reference = .init(name: name, displayLabel: label)
        self.instance = instance
        self.mappings = mappings
    }
}

public func Refinement<Model: ConfiguredGeneratedModel>(
    _name: String = "", instance: GeneratedModelInstance<Model>, label: String? = nil,
    @GeneratedModelStateMappingBuilder<Model.State> _ mappings: () -> [GeneratedModelStateMapping<Model.State>]
) -> GeneratedModelRefinement<Model> {
    .init(name: _name, label: label, instance: instance, mappings: mappings())
}
