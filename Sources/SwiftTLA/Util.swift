/// A source-faithful port of the KeyValueStore example's `Util` module.
///
/// `Util` is an upstream dependency, not a new SwiftTLA invention. It keeps
/// its own module file so TLC resolves the same `Util -> Functions -> Folds`
/// relationship as the original example.
public enum KeyValueStoreUtil {
    /// The `Util.tla` source module.
    public static let module = TLASpec("Util") {
        Extends("Naturals, TLC")
        Import(FunctionsModule.module)

        FormalDefinition(
            "intersects",
            parameters: [.value("a"), .value("b")],
            body: .notEqual(.intersection(.variable("a"), .variable("b")), .setLiteral([]))
        )
        FormalDefinition(
            "max",
            parameters: [.value("s")],
            body: .choose(.variable("s"), "i", .not(.exists(.variable("s"), "j", .greaterThan(.variable("j"), .variable("i")))))
        )
        FormalDefinition(
            "min",
            parameters: [.value("s")],
            body: .choose(.variable("s"), "i", .not(.exists(.variable("s"), "j", .lessThan(.variable("j"), .variable("i")))))
        )
        FormalDefinition(
            "ReduceSet",
            parameters: [.operator("op", arity: 2), .value("set"), .value("base")],
            body: .letIn(
                [LocalOperator(
                    "iter",
                    parameters: ["s"],
                    body: .ifThenElse(
                        .equal(.variable("s"), .setLiteral([])),
                        .variable("base"),
                        .letValue(
                            "x",
                            .choose(.variable("s"), "x", .bool(true)),
                            .operatorApplication(.reference("op", arity: 2), [
                                .value(.variable("x")),
                                .value(.recursiveCall("iter", [.setDifference(.variable("s"), .setLiteral([.variable("x")]))]))
                            ])
                        )
                    )
                )],
                .recursiveCall("iter", [.variable("set")])
            )
        )
        FormalDefinition(
            "ReduceSeq",
            parameters: [.operator("op", arity: 2), .value("seq"), .value("acc")],
            body: .operatorApplication(.reference("FoldFunction", arity: 3), [
                .operator(.reference("op", arity: 2)), .value(.variable("acc")), .value(.variable("seq"))
            ])
        )
        FormalDefinition(
            "Index",
            parameters: [.value("seq"), .value("e")],
            body: .choose(
                .integerRange(.int(1), .tupleLength(.variable("seq"))),
                "i",
                .equal(.tupleDynamicAccess(.variable("seq"), .variable("i")), .variable("e"))
            )
        )
        FormalDefinition(
            "SeqToSet",
            parameters: [.value("s")],
            body: .setMap(
                .functionApply(.variable("s"), .variable("i")),
                "i",
                .domain(.variable("s"))
            )
        )
        FormalDefinition(
            "Last",
            parameters: [.value("seq")],
            body: .tupleDynamicAccess(.variable("seq"), .tupleLength(.variable("seq")))
        )
        FormalDefinition(
            "IsEmpty",
            parameters: [.value("seq")],
            body: .equal(.tupleLength(.variable("seq")), .int(0))
        )
        FormalDefinition(
            "INTERSECTION",
            parameters: [.value("setOfSets")],
            body: .operatorApplication(.reference("ReduceSet", arity: 3), [
                .operator(.lambda(.init(parameters: ["left", "right"], body: .intersection(.variable("left"), .variable("right"))))),
                .value(.variable("setOfSets")),
                .value(.unionAll(.variable("setOfSets")))
            ])
        )
        FormalDefinition(
            "PermSeqs",
            parameters: [.value("S")],
            body: .letIn(
                [LocalOperator(
                    "perms",
                    parameters: ["ss"],
                    body: .ifThenElse(
                        .equal(.variable("ss"), .setLiteral([])),
                        .setLiteral([.tupleLiteral([])]),
                        .letValue(
                            "ps",
                            .functionLiteral(
                                .variable("ss"),
                                "x",
                                .setMap(
                                    .tupleAppend(.variable("sq"), .variable("x")),
                                    "sq",
                                    .recursiveCall("perms", [
                                        .setDifference(.variable("ss"), .setLiteral([.variable("x")]))
                                    ])
                                )
                            ),
                            .unionAll(.setMap(
                                .functionApply(.variable("ps"), .variable("x")),
                                "x",
                                .variable("ss")
                            ))
                        )
                    )
                )],
                .recursiveCall("perms", [.variable("S")])
            )
        )

        // `SelectSeq` and TLC's `Print` have no executable formal AST node.
        // Keep their upstream source exact until K2 gives those operations a
        // structured evaluator contract; see the focused failure tests.
        Definition("Remove(seq, elem) == SelectSeq(seq, LAMBDA e : e /= elem)")
        Definition("test(lhs, rhs) == lhs /= rhs => Print(<<lhs, \" IS NOT \", rhs>>, FALSE)")
    }
}
