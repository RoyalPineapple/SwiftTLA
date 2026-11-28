public struct TemporalPropertyHandle: ModelProperty {
    public let reference: PropertyReference

    package init(name: String, label: String? = nil) {
        reference = .init(name: name, displayLabel: label)
    }

    public func callAsFunction(_ condition: TemporalCondition<Expr<Bool>>) -> TemporalDecl {
        declaration(condition.map(\.stateExpr))
    }

    /// Requires the complete temporal condition separately for every member of the domain.
    public func callAsFunction<Domain: FormalSetValue>(
        forEach domain: some TypedExpression<Domain>,
        file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
        _ condition: (Expr<Domain.Element>) -> TemporalCondition<Expr<Bool>>
    ) -> QuantifiedTemporalDeclaration {
        let binder = generatedBinderName(file: file, line: line, column: column)
        return .init(property: .init(name: reference.name,
            expr: condition(Expr(.variable(binder))).map(\.stateExpr),
            bindings: [.init(name: binder, domain: domain.stateExpr,
                generatedSwiftType: swiftSurfaceTypeName(for: Domain.Element.self))], reference: reference))
    }

    package func declaration(_ condition: TemporalCondition<StateExpr>) -> TemporalDecl {
        .init(reference: reference, expr: condition)
    }
}

public struct QuantifiedTemporalDeclaration: SpecComponent, Sendable {
    package let property: NamedTemporal
}

public func Temporal(label: String? = nil, _name: String = "") -> TemporalPropertyHandle {
    .init(name: _name, label: label)
}

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
