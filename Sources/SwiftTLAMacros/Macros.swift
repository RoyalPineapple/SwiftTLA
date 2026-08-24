import SwiftTLA

/// Macro-generated surfaces may name Foundation types (for example
/// `Foundation.UUID` request identifiers on the generated `Live` facade).
/// Every `@TLAModel` file imports this module to resolve its macros, so
/// re-exporting Foundation guarantees expansions resolve without the model
/// file importing Foundation itself. Attached macros cannot add imports.
@_exported import Foundation

/// Generates a typed model machine from the declaration's `TLASpec`.
///
/// The generated surface includes `State`, `Action`, `Transition`, direct
/// execution, and typed live-machine members when the model contains a nested
/// live adapter.
@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: TLAModelType, names: arbitrary)
public macro TLAModel() = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(member, names: named(defaultValue), named(finiteValues))
@attached(extension, conformances: FiniteTLAValueDomain, names: arbitrary)
public macro _TLAFiniteEnum() = #externalMacro(module: "SwiftTLAPlugin", type: "FiniteEnumMacro")

/// Requires a nested actor and generates an adapter for its enclosing `@TLAModel`.
///
/// A nested adapter exposes the enclosing model's typed state and transition
/// result through type aliases.
@attached(member, names: arbitrary)
@attached(extension, conformances: TLAModelType, names: arbitrary)
public macro TLAActor() = #externalMacro(module: "SwiftTLAPlugin", type: "TLAActorMacro")

/// Declares a formal specification body for `@TLAModel`.
///
/// `#spec` is the compile-time boundary for the PlusCal-shaped authoring DSL.
/// The macro validates its literal name and body shape, then produces the
/// canonical `TLASpec` expression consumed by `@TLAModel`.
@freestanding(expression)
public macro spec(_ name: StaticString, @SpecBuilder _ body: () -> [SpecComponent]) -> TLASpec = #externalMacro(module: "SwiftTLAPlugin", type: "SpecExpressionMacro")

@freestanding(expression)
public macro spec(_ name: StaticString, @SpecBuilder scoped body: (SpecificationScope) -> [SpecComponent]) -> TLASpec = #externalMacro(module: "SwiftTLAPlugin", type: "SpecExpressionMacro")
