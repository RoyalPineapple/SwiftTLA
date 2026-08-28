func valueContains(_ val: TLAValue, _ target: TLAValue) -> Bool {
  if val == target { return true }
  switch val {
  case .set(let s):
    return s.contains(where: { valueContains($0, target) })
  case .function(let f):
    for (k, v) in f {
      if valueContains(k, target) || valueContains(v, target) { return true }
    }
    return false
  case .tuple(let t):
    return t.contains(where: { valueContains($0, target) })
  case .record(let r):
    return r.fields.contains(where: { valueContains($0.value, target) })
  default:
    return false
  }
}
func applyMapping(_ val: TLAValue, _ mapping: [TLAValue: TLAValue]) -> TLAValue {
  if let canonical = mapping[val] { return canonical }
  switch val {
  case .set(let s):
    return .set(Set(s.map { applyMapping($0, mapping) }))
  case .function(let f):
    var newFunc: [TLAValue: TLAValue] = [:]
    for (k, v) in f {
      let newKey = applyMapping(k, mapping)
      let newVal = applyMapping(v, mapping)
      newFunc[newKey] = newVal
    }
    return .function(newFunc)
  case .tuple(let elements):
    return .tuple(elements.map { applyMapping($0, mapping) })
  case .record(let fields):
    return .record(TLARecord(fields.fields.map {
      .init($0.name, applyMapping($0.value, mapping))
    }))
  default:
    return val
  }
}
public struct SymmetrySetDecl: SpecComponent {
  public let variableName: String
  public let values: Set<TLAValue>
  init(_ variableName: String, _ values: Set<TLAValue>) {
    self.variableName = variableName
    self.values = values
  }
}
public func Symmetry(_ variableName: String, _ values: Set<some TLAValueConvertible>)
  -> SymmetrySetDecl {
  SymmetrySetDecl(variableName, Set(values.map(\.tlaValue)))
}

extension TLASpec {
  func renderedDeclarationNames() -> Set<String> {
    Set(
      variables.map(\.name)
        + constants.map(\.name)
        + formalParameters.map(\.name)
        + actions.map(\.name)
        + invariants.map(\.name)
        + temporalProperties.map(\.name)
        + recursiveFuncs.map(\.name)
        + formalOperatorDefinitions.map(\.name)
        + moduleInstances.map(\.name)
        + refinements.map(\.name)
    )
  }

  func validateSymmetryDeclarations() throws {
    var renderedSymbols = renderedDeclarationNames()
    renderedSymbols.formUnion(symmetricCollections.flatMap(\.metadata.generatedSymbols))

    var names = Set<String>()
    var domainOwner = Dictionary(uniqueKeysWithValues: symmetricCollections.flatMap { collection in
      collection.metadata.members.map { ($0, "symmetric collection '\(collection.name)'") }
    })

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
      guard symmetry.values.isEmpty == false else {
        throw symmetryDiagnostic(
          path: "\(path).values",
          expected: "at least one symmetric value",
          actual: "an empty domain"
        )
      }

      let renderedSymbol = "Symm\(symmetry.variableName)"
      guard renderedSymbols.insert(renderedSymbol).inserted else {
        throw symmetryDiagnostic(
          path: "\(path).renderedName",
          expected: "an unclaimed rendered symbol",
          actual: "'\(renderedSymbol)' is already declared"
        )
      }

      if let overlap = TLAValue.sorted(symmetry.values).first(where: domainOwner.keys.contains),
         let owner = domainOwner[overlap] {
        throw symmetryDiagnostic(
          path: "\(path).values",
          expected: "a domain disjoint from every other symmetry declaration",
          actual: "\(overlap) is already owned by \(owner)"
        )
      }
      for value in symmetry.values {
        domainOwner[value] = "direct symmetry '\(symmetry.variableName)'"
      }
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
