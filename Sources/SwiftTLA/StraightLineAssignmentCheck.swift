enum StraightLineAssignmentCheck {
    private enum Term: Equatable {
        case prior(String)
        case literal(TLAValue)
    }

    private enum Visit {
        case action(ActionExpr)
        case unbind(String)
    }

    static func verify(_ step: AtomicStep, lowered: ActionExpr, stateRoots: Set<String>) throws {
        guard step.bindings.isEmpty else { return }

        var source: [String: Term] = [:]
        for statement in step.model.statements {
            guard case .set(let target, let expression) = statement,
                  case .root(let root) = target, stateRoots.contains(root) else { return }
            switch expression {
            case .variable(let name) where stateRoots.contains(name):
                source[root] = source[name] ?? .prior(name)
            case .value(let literal):
                source[root] = .literal(literal)
            default:
                return
            }
        }

        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "actions.\(step.model.label.name).orderedAssignments",
                expected: "the complete symbolic result of the source assignments",
                actual: "the lowered action has a different result or unsupported operation",
                nextSafeAction: "Report this assignment lowering failure."
            )
        }

        func value(_ expression: StateExpr, bindings: [String: Term]) throws -> Term {
            switch expression {
            case .variable(let name):
                if let bound = bindings[name] { return bound }
                guard stateRoots.contains(name) else { throw mismatch() }
                return .prior(name)
            case .value(let literal):
                return .literal(literal)
            default:
                throw mismatch()
            }
        }

        var writes: [String: Term] = [:]
        var bindings: [String: Term] = [:]
        var pending: [Visit] = [.action(lowered)]
        while let next = pending.popLast() {
            guard case .action(let action) = next else {
                if case .unbind(let name) = next { bindings.removeValue(forKey: name) }
                continue
            }
            switch action {
            case .define(let name, let expression, let body):
                guard !stateRoots.contains(name), bindings[name] == nil else { throw mismatch() }
                bindings[name] = try value(expression, bindings: bindings)
                pending.append(.unbind(name))
                pending.append(.action(body))
            case .and(let left, let right):
                pending.append(.action(right))
                pending.append(.action(left))
            case .guard_(.value(.bool(true))):
                break
            case .assign(.named(let root), let expression):
                guard stateRoots.contains(root) else { throw mismatch() }
                let assigned = try value(expression, bindings: bindings)
                guard writes[root] == nil || writes[root] == assigned else { throw mismatch() }
                writes[root] = assigned
            case .unchanged(.named(let root)):
                guard stateRoots.contains(root),
                      writes[root] == nil || writes[root] == .prior(root) else { throw mismatch() }
                writes[root] = .prior(root)
            default:
                throw mismatch()
            }
        }

        guard stateRoots.allSatisfy({ (writes[$0] ?? .prior($0)) == (source[$0] ?? .prior($0)) }) else {
            throw mismatch()
        }
    }
}
