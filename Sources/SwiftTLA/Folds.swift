/// A source-faithful port of the TLA+ Community Modules `Folds` module.
///
/// Import `Folds.module` when a specification needs its general set-folding
/// operator. Most Swift models use `FunctionsModule.module` and its typed `Fold`
/// facade instead.
public enum Folds {
    /// The `Folds.tla` source module.
    public static let module = TLASpec("Folds") {
        Definition(
            """
            MapThenFoldSet(op(_,_), base, f(_), choose(_), S) ==
              LET iter[s \\in SUBSET S] ==
                    IF s = {} THEN base
                    ELSE LET x == choose(s)
                         IN op(f(x), iter[s \\ {x}])
              IN iter[S]
            """
        )
    }
}
