/// A typed facade for a verification collection whose members are exchangeable.
///
/// Runtime element identity remains outside the verification AST. The modeled
/// collection is a function keyed by opaque constants derived from its scope.
public struct SymmetricCollectionVar<Element: Identifiable & Sendable, Value: TLAValueType>: Sendable {
  public let name: String

  public init(_ name: String) {
    self.name = name
  }

  public subscript(_ member: SymmetricMember<Element>) -> Expr<Value> {
    guard member.owner == name else {
      return Expr(.sourceIssue(.symmetricMember(collection: name, owner: member.owner)))
    }
    return Expr(.functionApply(.variable(name), member.binding))
  }

  public func update(_ member: SymmetricMember<Element>, to value: Value) -> ActionExpr {
    update(member, to: Expr<Value>(.value(value.tlaValue)))
  }

  public func update(_ member: SymmetricMember<Element>, to value: Expr<Value>) -> ActionExpr {
    guard member.owner == name else {
      return .assign(.named(name), .sourceIssue(.symmetricMember(collection: name, owner: member.owner)))
    }
    return .assign(.named(name), .except(.variable(name), member.binding, value.raw))
  }

  public func allSatisfy(_ predicate: (Expr<Value>) -> StateExpr) -> StateExpr {
    let member = "member"
    let value = Expr<Value>(.functionApply(.variable(name), .variable(member)))
    return .forAll(memberDomain, member, predicate(value))
  }

  public func contains(where predicate: (Expr<Value>) -> StateExpr) -> StateExpr {
    let member = "member"
    let value = Expr<Value>(.functionApply(.variable(name), .variable(member)))
    return .exists(memberDomain, member, predicate(value))
  }

  public var memberDomain: StateExpr {
    .domain(.variable(name))
  }
}

public struct SymmetricMember<Element: Identifiable & Sendable>: Sendable {
  fileprivate let owner: String
  fileprivate let binding: StateExpr

  fileprivate init(owner: String, binding: StateExpr) {
    self.owner = owner
    self.binding = binding
  }
}

public struct SymmetricCollectionDecl: SpecComponent, Sendable {
  package let metadata: SymmetricCollectionMetadata
  let generatedElementType: String?
  let generatedValueType: String?

  public var name: String { metadata.name }
  public var verificationScope: Int { metadata.verificationScope }
  public var initial: TLAValue { metadata.initial }

  init(
    name: String,
    verificationScope: Int,
    initial: TLAValue,
    generatedElementType: String?,
    generatedValueType: String?
  ) {
    self.metadata = SymmetricCollectionMetadata(
      name: name,
      verificationScope: verificationScope,
      initial: initial
    )
    self.generatedElementType = generatedElementType
    self.generatedValueType = generatedValueType
  }

  var variable: NamedVar {
    NamedVar(
      name: name,
      initialization: .value(.function(Dictionary(uniqueKeysWithValues: metadata.members.map { ($0, initial) }))),
      collectionType: .dictionary(verificationScope),
      origin: .source
    )
  }
}

package struct SymmetricCollectionMetadata: Equatable, Sendable {
  package let name: String
  package let verificationScope: Int
  package let initial: TLAValue
  package let members: [TLAValue]
  package let domainSymbol: String
  package let symmetrySymbol: String

  init(name: String, verificationScope: Int, initial: TLAValue) {
    let symbolStem = name.prefix(1).uppercased() + name.dropFirst()
    let memberSymbols = verificationScope > 0
      ? (0..<verificationScope).map { "\(symbolStem)Member\($0)" }
      : []
    let members = memberSymbols.map(TLAValue.constant)
    self.name = name
    self.verificationScope = verificationScope
    self.initial = initial
    self.members = members
    self.domainSymbol = "\(symbolStem)Keys"
    self.symmetrySymbol = "Symm\(symbolStem)"
  }

  package var generatedSymbols: [String] {
    members.compactMap { value in
      guard case .constant(let symbol) = value else { return nil }
      return symbol
    } + [domainSymbol, symmetrySymbol]
  }
}

struct SymmetryPlan: Sendable {
  private let compilationIdentity: CompilationIdentity
  private let groups: [[[TLAValue: TLAValue]]]

  init(
    compilation: CompiledSpecification,
    reduction: SymmetryReduction
  ) throws {
    compilationIdentity = compilation.identity
    guard case .enabled(let limit) = reduction else {
      groups = []
      return
    }

    let domains = compilation.semantics.symmetricCollections.map(\.members)
      + compilation.semantics.symmetrySets.map { $0.values.sorted() }
    guard domains.isEmpty == false else {
      throw FiniteExplorationConfigurationError.symmetryReductionWithoutDeclarations
    }

    var permutationCount = 1
    var groups: [[[TLAValue: TLAValue]]] = []
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
          candidate.transformingFormalValues { applyMapping($0, mapping) }
        }
      }
    }
    return candidates.min() ?? state
  }

  private static func permutations(
    of values: [TLAValue],
    maximumCount: Int,
    precedingCount: Int,
    limit: Int
  ) throws -> [[TLAValue]] {
    var permutations: [[TLAValue]] = [[]]
    for value in values {
      var next: [[TLAValue]] = []
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

enum SymmetricCollectionValidationError: Error, CustomStringConvertible {
  case invalidScope(collection: String, scope: Int)
  case missingCollectionName
  case invalidCollectionName(String)
  case duplicateCollection(collection: String)
  case symbolCollision(collection: String, symbol: String)
  case invalidOwnership(collection: String)
  case invalidDomain(collection: String)

  public var description: String {
    switch self {
    case .invalidScope(let collection, let scope):
      return "Symmetric collection '\(collection)' has verification scope \(scope); use a positive scope."
    case .missingCollectionName:
      return "A symmetric collection is missing a name; provide a unique collection name."
    case .invalidCollectionName(let name):
      return "Symmetric collection '\(name)' is not a formal identifier; use letters, digits, and underscores, beginning with a letter or underscore."
    case .duplicateCollection(let collection):
      return "Symmetric collection '\(collection)' is declared more than once; declare it once with one scope."
    case .symbolCollision(let collection, let symbol):
      return "Symmetric collection '\(collection)' generated symbol '\(symbol)' collides with an existing symbol; rename the collection."
    case .invalidOwnership(let collection):
      return "Symmetric collection '\(collection)' must own exactly one modeled variable; remove duplicate declarations."
    case .invalidDomain(let collection):
      return "Symmetric collection '\(collection)' must initialize every scoped member to the declared uniform value; "
        + "use SymmetricCollection(_:verificationScope:initial:)."
    }
  }
}

extension TLASpec {
  func symmetricCollectionValidationError() -> SymmetricCollectionValidationError? {
    let collections = symmetricCollections
    guard !collections.isEmpty else { return nil }

    var collectionNames = Set<String>()
    var generatedSymbols = Set<String>()
    var reservedSymbols = renderedDeclarationNames()
    reservedSymbols.formUnion(symmetrySets.map { "Symm\($0.variableName)" })

    for declaration in collections {
      let metadata = declaration.metadata
      guard !metadata.name.isEmpty else { return .missingCollectionName }
      guard TLAStateProjection.Token(validating: metadata.name) != nil else {
        return .invalidCollectionName(metadata.name)
      }
      guard metadata.verificationScope > 0 else {
        return .invalidScope(collection: metadata.name, scope: metadata.verificationScope)
      }
      guard collectionNames.insert(metadata.name).inserted else {
        return .duplicateCollection(collection: metadata.name)
      }
      guard metadata.members.count == metadata.verificationScope,
            Set(metadata.members).count == metadata.verificationScope,
            metadata.members.allSatisfy({ if case .constant = $0 { return true }; return false })
      else { return .invalidDomain(collection: metadata.name) }

      let ownedVariables = variables.filter { $0.name == metadata.name }
      guard ownedVariables.count == 1 else {
        return .invalidOwnership(collection: metadata.name)
      }
      guard case .value(.function(let initialValues)) = ownedVariables[0].initialization,
            Set(initialValues.keys) == Set(metadata.members),
            Set(initialValues.values) == Set([metadata.initial])
      else { return .invalidDomain(collection: metadata.name) }

      for symbol in metadata.generatedSymbols {
        guard !reservedSymbols.contains(symbol), generatedSymbols.insert(symbol).inserted else {
          return .symbolCollision(collection: metadata.name, symbol: symbol)
        }
      }
    }
    return nil
  }
}

@discardableResult
public func SymmetricCollection<Element: Identifiable & Sendable, Value: TLAValueType>(
  _ collection: SymmetricCollectionVar<Element, Value>,
  verificationScope: Int,
  initial: Value
) -> SymmetricCollectionDecl {
  SymmetricCollectionDecl(
    name: collection.name,
    verificationScope: verificationScope,
    initial: initial.tlaValue,
    generatedElementType: swiftSurfaceTypeName(for: Element.self),
    generatedValueType: swiftSurfaceTypeName(for: Value.self)
  )
}

@discardableResult
public func CollectionAction<Element: Identifiable & Sendable, Value: TLAValueType>(
  _ name: String,
  on collection: SymmetricCollectionVar<Element, Value>,
  @ActionBuilder _ body: (SymmetricMember<Element>) -> ActionExpr
) -> ActionDecl {
  let member = "member"
  let token = SymmetricMember<Element>(owner: collection.name, binding: .variable(member))
  return ActionDecl(
    name,
    .existsAction(member, collection.memberDomain, body(token))
  )
}
