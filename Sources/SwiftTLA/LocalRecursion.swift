/// A typed handle for one locally recursive TLA+ operator.
///
/// `LetRec` is deliberately unary. Model inputs with more than one value as a
/// `Pair` or typed `Record`, preserving one local TLA+ operator parameter.
public struct LocalRecursion<Input: TLAValueType, Output: TLAValueType>: Sendable {
    fileprivate let name: String

    public func callAsFunction(_ input: some StateExprConvertible) -> Expr<Output> {
        Expr(.recursiveCall(name, [input.stateExpr]))
    }
}

/// Builds TLA+ `LET name(input) == definition IN body` without exposing the
/// raw local-operator AST to an application model.
public func LetRec<
    Input: TLAValueType,
    Output: TLAValueType,
    Definition: StateExprConvertible,
    Result: StateExprConvertible
>(
    _ name: String,
    taking _: Input.Type,
    _ definition: (LocalRecursion<Input, Output>, WithValue<Input>) -> Definition,
    in body: (LocalRecursion<Input, Output>) -> Result
) -> Expr<Output> {
    precondition(!name.isEmpty, "A local recursive operator needs a name.")
    let inputName = FreshVarName.fresh()
    let recursion = LocalRecursion<Input, Output>(name: name)
    return Expr(.letIn(
        [LocalOperator(
            name,
            parameters: [inputName],
            body: definition(recursion, WithValue(expression: .variable(inputName))).stateExpr
        )],
        body(recursion).stateExpr
    ))
}
