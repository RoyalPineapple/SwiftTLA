/// A source-faithful port of the TLA+ Community Modules `Functions` module.
///
/// The module provides function predicates and folds. It is a source
/// dependency: `Import(FunctionsModule.module)` writes both `Functions.tla` and
/// its `Folds.tla` dependency beside the consuming module for TLC.
public enum FunctionsModule {
    /// The `Functions.tla` source module.
    public static let module = TLASpec("Functions") {
        Import(Folds.module)

        FormalDefinition(
            "Restrict",
            parameters: [.value("f"), .value("S")],
            body: .functionLiteral(.variable("S"), "x", .functionApply(.variable("f"), .variable("x")))
        )
        FormalDefinition(
            "RestrictDomain",
            parameters: [.value("f"), .operator("Test", arity: 1)],
            body: .operatorApplication(.reference("Restrict", arity: 2), [
                .value(.variable("f")),
                .value(.setFilter(
                    .domain(.variable("f")),
                    "x",
                    .operatorApplication(.reference("Test", arity: 1), [.value(.variable("x"))])
                ))
            ])
        )
        FormalDefinition(
            "RestrictValues",
            parameters: [.value("f"), .operator("Test", arity: 1)],
            body: .letValue(
                "S",
                .setFilter(
                    .domain(.variable("f")),
                    "x",
                    .operatorApplication(
                        .reference("Test", arity: 1),
                        [.value(.functionApply(.variable("f"), .variable("x")))]
                    )
                ),
                .operatorApplication(.reference("Restrict", arity: 2), [
                    .value(.variable("f")), .value(.variable("S"))
                ])
            )
        )
        FormalDefinition(
            "IsRestriction",
            parameters: [.value("narrow"), .value("wide")],
            body: .and(
                .subset(.domain(.variable("narrow")), .domain(.variable("wide"))),
                .forAll(
                    .intersection(.domain(.variable("narrow")), .domain(.variable("wide"))),
                    "x",
                    .equal(
                        .functionApply(.variable("narrow"), .variable("x")),
                        .functionApply(.variable("wide"), .variable("x"))
                    )
                )
            )
        )
        FormalDefinition(
            "Range",
            parameters: [.value("f")],
            body: .setMap(.functionApply(.variable("f"), .variable("x")), "x", .domain(.variable("f")))
        )
        FormalDefinition(
            "Pointwise",
            parameters: [.value("f"), .value("g"), .operator("T", arity: 2)],
            body: .functionLiteral(
                .domain(.variable("f")),
                "e",
                .operatorApplication(.reference("T", arity: 2), [
                    .value(.functionApply(.variable("f"), .variable("e"))),
                    .value(.functionApply(.variable("g"), .variable("e")))
                ])
            )
        )
        FormalDefinition(
            "Inverse",
            parameters: [.value("f"), .value("S"), .value("T")],
            body: .functionLiteral(
                .variable("T"),
                "t",
                .choose(
                    .variable("S"),
                    "s",
                    .or(
                        .not(.in(.variable("t"), .operatorApplication(.reference("Range", arity: 1), [.value(.variable("f"))]))),
                        .equal(.functionApply(.variable("f"), .variable("s")), .variable("t"))
                    )
                )
            )
        )
        FormalDefinition(
            "AntiFunction",
            parameters: [.value("f")],
            body: .operatorApplication(.reference("Inverse", arity: 3), [
                .value(.variable("f")),
                .value(.domain(.variable("f"))),
                .value(.operatorApplication(.reference("Range", arity: 1), [.value(.variable("f"))]))
            ])
        )
        FormalDefinition(
            "IsInjective",
            parameters: [.value("f")],
            body: .forAll(.domain(.variable("f")), "a",
                .forAll(.domain(.variable("f")), "b",
                    .or(
                        .not(.equal(
                            .functionApply(.variable("f"), .variable("a")),
                            .functionApply(.variable("f"), .variable("b"))
                        )),
                        .equal(.variable("a"), .variable("b"))
                    )
                )
            )
        )
        FormalDefinition(
            "Injection",
            parameters: [.value("S"), .value("T")],
            body: .setFilter(
                .functionSet(.variable("S"), .variable("T")),
                "M",
                .operatorApplication(.reference("IsInjective", arity: 1), [.value(.variable("M"))])
            )
        )
        FormalDefinition(
            "Surjection",
            parameters: [.value("S"), .value("T")],
            body: .setFilter(
                .functionSet(.variable("S"), .variable("T")),
                "M",
                .forAll(.variable("T"), "t",
                    .exists(.variable("S"), "s",
                        .equal(.functionApply(.variable("M"), .variable("s")), .variable("t"))
                    )
                )
            )
        )
        FormalDefinition(
            "Bijection",
            parameters: [.value("S"), .value("T")],
            body: .intersection(
                .operatorApplication(.reference("Injection", arity: 2), [.value(.variable("S")), .value(.variable("T"))]),
                .operatorApplication(.reference("Surjection", arity: 2), [.value(.variable("S")), .value(.variable("T"))])
            )
        )
        FormalDefinition(
            "ExistsInjection",
            parameters: [.value("S"), .value("T")],
            body: .notEqual(.operatorApplication(.reference("Injection", arity: 2), [.value(.variable("S")), .value(.variable("T"))]), .setLiteral([]))
        )
        FormalDefinition(
            "ExistsSurjection",
            parameters: [.value("S"), .value("T")],
            body: .notEqual(.operatorApplication(.reference("Surjection", arity: 2), [.value(.variable("S")), .value(.variable("T"))]), .setLiteral([]))
        )
        FormalDefinition(
            "ExistsBijection",
            parameters: [.value("S"), .value("T")],
            body: .notEqual(.operatorApplication(.reference("Bijection", arity: 2), [.value(.variable("S")), .value(.variable("T"))]), .setLiteral([]))
        )
        FormalDefinition(
            "FoldFunctionOnSet",
            parameters: [.operator("op", arity: 2), .value("base"), .value("fun"), .value("indices")],
            body: .operatorApplication(.reference("MapThenFoldSet", arity: 5), [
                .operator(.reference("op", arity: 2)),
                .value(.variable("base")),
                .operator(.lambda(.init(parameters: ["i"], body: .functionApply(.variable("fun"), .variable("i"))))),
                .operator(.lambda(.init(parameters: ["s"], body: .choose(.variable("s"), "x", .bool(true))))),
                .value(.variable("indices"))
            ])
        )
        FormalDefinition(
            "FoldFunction",
            parameters: [.operator("op", arity: 2), .value("base"), .value("fun")],
            body: .operatorApplication(.reference("FoldFunctionOnSet", arity: 4), [
                .operator(.reference("op", arity: 2)),
                .value(.variable("base")),
                .value(.variable("fun")),
                .value(.domain(.variable("fun")))
            ])
        )
        FormalDefinition(
            "SumFunctionOnSet",
            parameters: [.value("fun"), .value("indices")],
            body: .operatorApplication(.reference("FoldFunctionOnSet", arity: 4), [
                .operator(.lambda(.init(parameters: ["left", "right"], body: .add(.variable("left"), .variable("right"))))),
                .value(.int(0)), .value(.variable("fun")), .value(.variable("indices"))
            ])
        )
        FormalDefinition(
            "SumFunction",
            parameters: [.value("fun")],
            body: .operatorApplication(.reference("SumFunctionOnSet", arity: 2), [
                .value(.variable("fun")), .value(.domain(.variable("fun")))
            ])
        )
    }
}
