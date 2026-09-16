public struct TemporalHandle: ModelProperty {
    package enum Kind: String, Sendable {
        case always = "Always"
        case eventually = "Eventually"
        case alwaysEventually = "AlwaysEventually"
        case eventuallyAlways = "EventuallyAlways"
    }

    public let reference: PropertyReference
    package let kind: Kind

    package init(name: String, kind: Kind, label: String? = nil) {
        reference = .init(name: name, displayLabel: label)
        self.kind = kind
    }

    public func callAsFunction(_ predicate: some TypedExpression<Bool>) -> TemporalDecl {
        declaration(predicate.stateExpr)
    }

    package func declaration(_ predicate: StateExpr) -> TemporalDecl {
        let expression: TemporalCondition<StateExpr>
        switch kind {
        case .always: expression = .always(predicate)
        case .eventually: expression = .eventually(predicate)
        case .alwaysEventually: expression = .alwaysEventually(predicate)
        case .eventuallyAlways: expression = .eventuallyAlways(predicate)
        }
        return .init(reference: reference, expr: expression)
    }
}

public struct LeadsToHandle: ModelProperty {
    public let reference: PropertyReference

    package init(name: String, label: String? = nil) { reference = .init(name: name, displayLabel: label) }

    public func callAsFunction(_ premise: some TypedExpression<Bool>, _ consequence: some TypedExpression<Bool>) -> TemporalDecl {
        declaration(premise.stateExpr, consequence.stateExpr)
    }

    package func declaration(_ premise: StateExpr, _ consequence: StateExpr) -> TemporalDecl {
        .init(reference: reference, expr: .leadsTo(premise, consequence))
    }
}

public func Always(label: String? = nil, _name: String = "") -> TemporalHandle { .init(name: _name, kind: .always, label: label) }
public func Eventually(label: String? = nil, _name: String = "") -> TemporalHandle { .init(name: _name, kind: .eventually, label: label) }
public func AlwaysEventually(label: String? = nil, _name: String = "") -> TemporalHandle { .init(name: _name, kind: .alwaysEventually, label: label) }
public func EventuallyAlways(label: String? = nil, _name: String = "") -> TemporalHandle { .init(name: _name, kind: .eventuallyAlways, label: label) }
public func LeadsTo(label: String? = nil, _name: String = "") -> LeadsToHandle { .init(name: _name, label: label) }
