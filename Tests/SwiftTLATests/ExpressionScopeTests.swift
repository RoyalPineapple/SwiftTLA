import Testing
@testable import SwiftTLA

struct ExpressionScopeTests {
    @Test("Binder domains retain outer names while bodies exclude bound names")
    func distinguishesDomainsFromBodies() {
        let domain = StateExpr.variable("selected")
        let body = StateExpr.add(.variable("selected"), .variable("outside"))
        let expressions: [StateExpr] = [
            .forAll(domain, "selected", body), .exists(domain, "selected", body),
            .choose(domain, "selected", body), .setFilter(domain, "selected", body),
            .setMap(body, "selected", domain), .functionLiteral(domain, "selected", body),
            .sequenceSelect(domain, "selected", body), .letValue("selected", domain, body)
        ]
        for expression in expressions {
            #expect(expression.freeVariableNames == ["selected", "outside"])
            #expect(StateExpr.letValue("selected", .int(0), expression).freeVariableNames == ["outside"])
        }
    }

    @Test("Deep operator arguments and action scopes retain all free names")
    func traversesNestedScopes() {
        var expression = StateExpr.variable("outside")
        for index in 0..<256 {
            expression = .operatorApplication(.lambda(.init(parameters: ["local"],
                body: .add(.variable("local"), .variable("captured")))), [.value(expression)])
            expression = .letValue("bound\(index)", .int(index), expression)
        }
        #expect(expression.freeVariableNames == ["outside", "captured"])
        var action = ActionExpr.guard_(expression)
        for _ in 0..<256 { action = .and(action, .unchanged(.named("state"))) }
        #expect(action.scopeNames == ["outside", "captured", "state"])
    }
}
