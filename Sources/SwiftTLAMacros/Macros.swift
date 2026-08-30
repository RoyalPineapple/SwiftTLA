import SwiftTLA

/// Generates a typed Swift state machine from a struct's source model.
///
/// The generated surface includes `State`, `Action`, `Transition`, direct
/// execution, and a typed actor that owns the generated machine.
@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro TLAModel() = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(member, names: named(defaultValue), named(finiteValues))
public macro _TLAFiniteEnum() = #externalMacro(module: "SwiftTLAPlugin", type: "FiniteEnumMacro")

@attached(member, names: named(defaultValue))
public macro _TLAValueEnum() = #externalMacro(module: "SwiftTLAPlugin", type: "ValueEnumMacro")

/// Declares a source model for `@TLAModel`.
///
/// `#spec` is the compile-time boundary for the PlusCal-shaped authoring DSL.
/// The macro validates its literal name and body shape, then produces the
/// `TLASpec` source model consumed by `@TLAModel`.
@freestanding(expression)
public macro spec(_ name: StaticString, @SpecBuilder _ body: () -> [SpecComponent]) -> TLASpec = #externalMacro(module: "SwiftTLAPlugin", type: "SpecExpressionMacro")

@freestanding(expression)
public macro spec(_ name: StaticString, @SpecBuilder scoped body: (SpecificationScope) -> [SpecComponent]) -> TLASpec = #externalMacro(module: "SwiftTLAPlugin", type: "SpecExpressionMacro")
