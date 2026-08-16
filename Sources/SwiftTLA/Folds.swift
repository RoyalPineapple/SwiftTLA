/// A source-faithful port of the TLA+ Community Modules `Folds` module.
///
/// Import `Folds.module` when a specification needs its general set-folding
/// operator. Most Swift models use `FunctionsModule.module` and its typed `Fold`
/// facade instead.
public enum Folds {
    /// The `Folds.tla` source module.
    public static let module = TLASpec("Folds") {
        FormalDefinition(
            "MapThenFoldSet",
            parameters: [
                .operator("op", arity: 2),
                .value("base"),
                .operator("f", arity: 1),
                .operator("choose", arity: 1),
                .value("S")
            ],
            body: .letIn(
                [LocalOperator(
                    "iter",
                    parameters: ["s"],
                    body: .ifThenElse(
                        .equal(.variable("s"), .setLiteral([])),
                        .variable("base"),
                        .letValue(
                            "x",
                            .operatorApplication(
                                .reference("choose", arity: 1),
                                [.value(.variable("s"))]
                            ),
                            .operatorApplication(
                                .reference("op", arity: 2),
                                [
                                    .value(.operatorApplication(
                                        .reference("f", arity: 1),
                                        [.value(.variable("x"))]
                                    )),
                                    .value(.recursiveCall(
                                        "iter",
                                        [.setDifference(
                                            .variable("s"),
                                            .setLiteral([.variable("x")])
                                        )]
                                    ))
                                ]
                            )
                        )
                    )
                )],
                .recursiveCall("iter", [.variable("S")])
            )
        )
    }
}
