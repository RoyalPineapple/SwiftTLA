import Foundation

public struct SymmetryReference: Hashable, Sendable {
  private let identity = UUID()
}

public enum SymmetryDomain: Hashable, Sendable {
  case finite(Set<TLAValue>)
  case parameter(ParameterReference)

  package func renderedSet(parameterNames: [ParameterReference: String]) -> String? {
    switch self {
    case .finite(let values): return "{\(values.sorted().map(\.description).joined(separator: ", "))}"
    case .parameter(let reference): return parameterNames[reference]
    }
  }
}

public struct SymmetrySetDecl: SpecComponent, Sendable {
  public let variableName: String
  package let reference: SymmetryReference
  let domain: SymmetryDomain

  package init(_ variableName: String, _ values: Set<TLAValue>) {
    self.init(variableName, domain: .finite(values))
  }

  package init(_ variableName: String, domain: SymmetryDomain) {
    self.variableName = variableName
    reference = .init()
    self.domain = domain
  }

  package func resolved() -> SymmetrySet {
    return SymmetrySet(variableName: variableName, domain: domain, reference: reference)
  }
}

public func Symmetry(_ variableName: String, _ values: Set<some TLAValueConvertible>) -> SymmetrySetDecl {
  SymmetrySetDecl(variableName, Set(values.map(\.tlaValue)))
}

public func Symmetry(_name: String = "", _ values: Set<some TLAValueConvertible>) -> SymmetrySetDecl {
  SymmetrySetDecl(_name, Set(values.map(\.tlaValue)))
}

public func Symmetry<Member: TLAValueType>(_name: String = "", _ members: ModelParameter<Set<Member>>) -> SymmetrySetDecl {
  SymmetrySetDecl(_name, domain: .parameter(members.reference))
}

extension TLASpec {
  func renderedDeclarationNames() -> Set<String> {
    Set(
      variables.map(\.name)
        + constants.map(\.name)
        + formalParameters.map(\.name)
        + actions.map(\.name)
        + invariants.map(\.name)
        + reachabilityProperties.map(\.name)
        + temporalProperties.map(\.name)
        + recursiveFuncs.map(\.name)
        + formalOperatorDefinitions.map(\.name)
        + moduleInstances.map(\.name)
        + refinements.map(\.name)
    )
  }

  func validateSymmetryDeclarations() throws {
    var renderedSymbols = renderedDeclarationNames()

    var names = Set<String>()
    var domainOwner: [TLAValue: String] = [:]

    for (index, symmetry) in symmetrySets.enumerated() {
      let path = "symmetrySets[\(index)]"
      guard symmetry.variableName.isEmpty == false,
            case .some = TLAStateProjection.Token(validating: symmetry.variableName) else {
        throw symmetryDiagnostic(
          path: "\(path).name",
          expected: "a non-empty formal identifier",
          actual: symmetry.variableName.isEmpty ? "an empty name" : "'\(symmetry.variableName)'"
        )
      }
      guard names.insert(symmetry.variableName).inserted else {
        throw symmetryDiagnostic(
          path: "\(path).name",
          expected: "one direct symmetry declaration named '\(symmetry.variableName)'",
          actual: "a duplicate declaration"
        )
      }
      let possibleValues: Set<TLAValue>
      switch symmetry.domain {
      case .finite(let values):
        possibleValues = values
      case .parameter(let reference):
        guard let parameter = parameters.first(where: { $0.reference == reference }) else {
          throw symmetryDiagnostic(path: "\(path).values",
            expected: "a model-owned set parameter", actual: "a foreign parameter")
        }
        guard let values = possibleSymmetryValues(in: parameter.domain) else {
          throw symmetryDiagnostic(path: "\(path).values",
            expected: "a finite domain of nonempty atomic member sets",
            actual: "an unsupported parameter domain")
        }
        possibleValues = values
      }
      guard !possibleValues.isEmpty else {
        throw symmetryDiagnostic(
          path: "\(path).values",
          expected: "at least one symmetric value",
          actual: "an empty domain"
        )
      }

      for value in possibleValues.sorted() {
        switch value {
        case .int, .bool, .string, .constant:
          break
        case .set, .tuple, .record, .function:
          throw symmetryDiagnostic(
            path: "\(path).values",
            expected: "atomic integers, booleans, strings, or model constants",
            actual: "a composite symmetry member: \(value)"
          )
        }
      }

      let renderedSymbol = "Symm\(symmetry.variableName)"
      guard renderedSymbols.insert(renderedSymbol).inserted else {
        throw symmetryDiagnostic(
          path: "\(path).renderedName",
          expected: "an unclaimed rendered symbol",
          actual: "'\(renderedSymbol)' is already declared"
        )
      }

      if let overlap = possibleValues.sorted().first(where: domainOwner.keys.contains),
         let owner = domainOwner[overlap] {
        throw symmetryDiagnostic(
          path: "\(path).values",
          expected: "a domain disjoint from every other symmetry declaration",
          actual: "\(overlap) is already owned by \(owner)"
        )
      }
      for value in possibleValues {
        domainOwner[value] = "direct symmetry '\(symmetry.variableName)'"
      }
    }
  }

  private func possibleSymmetryValues(in domain: StateExpr) -> Set<TLAValue>? {
    let alternatives: [StateExpr]
    switch domain {
    case .setLiteral(let values): alternatives = values
    case .value(.set(let values)): alternatives = values.map(StateExpr.value)
    case .setDifference(.powerSet(let members), .setLiteral(let excluded))
      where excluded.count == 1 && literalSymmetrySet(excluded[0])?.isEmpty == true:
      return literalSymmetrySet(members)
    default: return nil
    }
    let candidates = alternatives.map(literalSymmetrySet)
    guard candidates.allSatisfy({ $0 != nil }) else { return nil }
    let values = candidates.compactMap { $0 }
    guard values.allSatisfy({ !$0.isEmpty }) else { return [] }
    return Set(values.flatMap { $0 })
  }

  private func literalSymmetrySet(_ expression: StateExpr) -> Set<TLAValue>? {
    switch expression {
    case .value(.set(let values)): return values
    case .setLiteral(let values):
      let members = values.compactMap { value -> TLAValue? in
        if case .value(let literal) = value { return literal }
        return nil
      }
      return members.count == values.count ? Set(members) : nil
    default: return nil
    }
  }

  private func symmetryDiagnostic(
    path: String,
    expected: String,
    actual: String
  ) -> CompilationDiagnostic {
    CompilationDiagnostic(
      code: .invalidSymmetryDeclaration,
      stage: .validation,
      path: path,
      expected: expected,
      actual: actual,
      nextSafeAction: "Correct the direct symmetry declaration, then compile again."
    )
  }
}
