extension NativeSwiftEmitter {
    /// Statement boundaries keep nested predicates independently type-checkable.
    /// The second expression remains inside the branch that requires its value.
    static func shortCircuitBoolean(left: String, right: String, conjunction: Bool) -> String {
        let condition = conjunction ? "_leftPredicate" : "!_leftPredicate"
        let earlyResult = conjunction ? "false" : "true"
        return """
        (try { () throws -> Bool in
            let _leftPredicate: Bool = \(left)
            guard \(condition) else { return \(earlyResult) }
            let _rightPredicate: Bool = \(right)
            return _rightPredicate
        }())
        """
    }
}
