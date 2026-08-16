/// Generates package-only direct structure for `StateExpr`.
///
/// Child paths are stable payload positions (`"0"`, `"1[0]"`, and so on),
/// not semantic names or scope metadata.
@attached(member, names: arbitrary)
internal macro StateExprStructural() = #externalMacro(
    module: "SwiftTLAStructurePlugin",
    type: "StateExprStructuralMacro"
)
