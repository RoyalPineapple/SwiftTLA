public struct SymmetrySetDecl: SpecComponent, Sendable {
  enum Domain: Sendable {
    case values(Set<TLAValue>)
    case collection
  }

  public let variableName: String
  let domain: Domain

  package init(_ variableName: String, _ values: Set<TLAValue>) {
    self.variableName = variableName
    domain = .values(values)
  }

  package init(collectionName: String) {
    variableName = collectionName
    domain = .collection
  }

  package func resolved(in collections: [ModelCollectionDecl]) -> SymmetrySet {
    let values: Set<TLAValue>
    switch domain {
    case .values(let members): values = members
    case .collection:
      values = Set(collections.first { $0.name == variableName }?.metadata.members ?? [])
    }
    return SymmetrySet(variableName: variableName, values: values)
  }
}

/// Declares that consistently renaming these members preserves the model and its checked properties.
public func Symmetry<Element, Value>(_ collection: CollectionVar<Element, Value>) -> SymmetrySetDecl {
  SymmetrySetDecl(collectionName: collection.name)
}

public func Symmetry(_ variableName: String, _ values: Set<some TLAValueConvertible>) -> SymmetrySetDecl {
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
    renderedSymbols.formUnion(collections.flatMap(\.metadata.generatedSymbols))

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
      guard symmetry.values.isEmpty == false else {
        throw symmetryDiagnostic(
          path: "\(path).values",
          expected: "at least one symmetric value",
          actual: "an empty domain"
        )
      }

      for value in symmetry.values.sorted() {
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

      if let overlap = symmetry.values.sorted().first(where: domainOwner.keys.contains),
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

struct SymmetryPlan: Sendable {
  private let compilationIdentity: CompilationIdentity
  private let groups: [[[CompiledValue: CompiledValue]]]

  init(
    compilation: CompiledSpecification,
    reduction: SymmetryReduction
  ) throws {
    compilationIdentity = compilation.identity
    guard case .enabled(let limit) = reduction else {
      groups = []
      return
    }

    let domains = compilation.semantics.symmetrySets.map { $0.values.sorted() }
    guard domains.isEmpty == false else {
      throw FiniteExplorationConfigurationError.symmetryReductionWithoutDeclarations
    }

    var permutationCount = 1
    var groups: [[[CompiledValue: CompiledValue]]] = []
    for members in domains {
      let permutations = try Self.permutations(
        of: members,
        maximumCount: limit / permutationCount,
        precedingCount: permutationCount,
        limit: limit
      )
      permutationCount *= permutations.count
      groups.append(permutations.map { permutation in
        Dictionary(uniqueKeysWithValues: zip(members, permutation))
      })
    }
    self.groups = groups
  }

  func canonicalState(_ state: CompiledState) throws -> CompiledState {
    try state.requireIdentity(compilationIdentity)
    let candidates = groups.reduce([state]) { candidates, group in
      candidates.flatMap { candidate in
        group.map { mapping in
          candidate.applying(mapping)
        }
      }
    }
    return candidates.min() ?? state
  }

  private static func permutations(
    of values: [CompiledValue],
    maximumCount: Int,
    precedingCount: Int,
    limit: Int
  ) throws -> [[CompiledValue]] {
    var permutations: [[CompiledValue]] = [[]]
    for value in values {
      var next: [[CompiledValue]] = []
      for permutation in permutations {
        for index in 0...permutation.count {
          guard next.count < maximumCount else {
            let (required, overflow) = precedingCount.multipliedReportingOverflow(
              by: next.count + 1
            )
            throw FiniteExplorationConfigurationError.permutationLimitExceeded(
              required: overflow ? .max : required,
              limit: limit
            )
          }
          var candidate = permutation
          candidate.insert(value, at: index)
          next.append(candidate)
        }
      }
      permutations = next
    }
    return permutations
  }
}
