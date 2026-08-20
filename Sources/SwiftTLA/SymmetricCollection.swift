/// A typed facade for a verification collection whose members are exchangeable.
///
/// Runtime element identity remains outside the verification AST. The modeled
/// collection is a function keyed by opaque constants derived from its scope.
public struct SymmetricCollectionVar<Element: Identifiable, Value: TLAValueType>: Sendable {
  public let name: String

  public init(_ name: String) {
    self.name = name
  }

  public subscript(_ member: SymmetricMember<Element>) -> Expr<Value> {
    precondition(member.owner == name, "A symmetric member may only select its owning collection")
    return Expr(.functionApply(.variable(name), member.binding))
  }

  public func update(_ member: SymmetricMember<Element>, to value: Value) -> ActionExpr {
    update(member, to: Expr<Value>(.value(value.tlaValue)))
  }

  public func update(_ member: SymmetricMember<Element>, to value: Expr<Value>) -> ActionExpr {
    precondition(member.owner == name, "A symmetric member may only update its owning collection")
    return .assign(name, .except(.variable(name), member.binding, value.raw))
  }

  public func allSatisfy(_ predicate: (Expr<Value>) -> StateExpr) -> StateExpr {
    let member = FreshVarName.fresh()
    let value = Expr<Value>(.functionApply(.variable(name), .variable(member)))
    return .forAll(memberDomain, member, predicate(value))
  }

  public func contains(where predicate: (Expr<Value>) -> StateExpr) -> StateExpr {
    let member = FreshVarName.fresh()
    let value = Expr<Value>(.functionApply(.variable(name), .variable(member)))
    return .exists(memberDomain, member, predicate(value))
  }

  public var memberDomain: StateExpr {
    .domain(.variable(name))
  }
}

/// Opaque action-selection token for a symmetric collection member.
///
/// It intentionally provides no public identity projection or comparison
/// conformance. Only its owning collection may consume it as a selector.
public struct SymmetricMember<Element: Identifiable> {
  fileprivate let owner: String
  fileprivate let binding: StateExpr

  fileprivate init(owner: String, binding: StateExpr) {
    self.owner = owner
    self.binding = binding
  }
}

public struct SymmetricCollectionDecl: SpecComponent, Sendable {
  public let metadata: SymmetricCollectionMetadata

  public var name: String { metadata.name }
  public var verificationScope: Int { metadata.verificationScope }
  public var initial: TLAValue { metadata.initial }

  public init(name: String, verificationScope: Int, initial: TLAValue) {
    self.metadata = SymmetricCollectionMetadata(
      name: name,
      verificationScope: verificationScope,
      initial: initial
    )
  }

  var variable: NamedVar {
    NamedVar(
      name: name,
      initial: .function(Dictionary(uniqueKeysWithValues: metadata.members.map { ($0, initial) })),
      collectionType: .dictionary(verificationScope)
    )
  }
}

public struct SymmetricCollectionMetadata: Equatable, Sendable {
  public let name: String
  public let verificationScope: Int
  public let initial: TLAValue
  public let members: [TLAValue]
  public let domainSymbol: String
  public let symmetrySymbol: String
  public let symbolOwnership: [String: String]

  init(name: String, verificationScope: Int, initial: TLAValue) {
    let symbolStem = symmetricCollectionSymbolStem(name)
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
    self.symbolOwnership = Dictionary(
      uniqueKeysWithValues: memberSymbols.enumerated().map {
        ($0.element, "symmetric collection '\(name)' member \($0.offset + 1)")
      } + [
        (domainSymbol, "symmetric collection '\(name)' member domain"),
        (symmetrySymbol, "symmetric collection '\(name)' symmetry operator")
      ]
    )
  }

  public var generatedSymbols: [String] {
    members.compactMap { value in
      guard case .constant(let symbol) = value else { return nil }
      return symbol
    } + [domainSymbol, symmetrySymbol]
  }
}

func symmetricCollectionSymbolStem(_ name: String) -> String {
  let sanitized = name.unicodeScalars.map { scalar -> Character in
    switch scalar.value {
    case 65...90, 97...122, 48...57, 95:
      return Character(String(scalar))
    default:
      return "_"
    }
  }
  let base = String(sanitized)
  guard let first = base.first else { return "Collection" }
  let identifier = first.isNumber ? "Collection_\(base)" : base
  return identifier.prefix(1).uppercased() + identifier.dropFirst()
}

struct SymmetricCollectionPermutationGroup: Sendable {
  let mappings: [[TLAValue: TLAValue]]

  init(members: [TLAValue]) {
    self.mappings = Self.permutations(of: members).map { permutation in
      Dictionary(uniqueKeysWithValues: zip(members, permutation))
    }
  }

  private static func permutations(of values: [TLAValue]) -> [[TLAValue]] {
    guard let first = values.first else { return [[]] }
    return permutations(of: Array(values.dropFirst())).flatMap { tail in
      (0...tail.count).map { index in
        var permutation = tail
        permutation.insert(first, at: index)
        return permutation
      }
    }
  }
}

func applySymmetricMemberPermutation(
  _ state: [String: TLAValue],
  mapping: [TLAValue: TLAValue]
) -> [String: TLAValue] {
  state.mapValues { applySymmetricMemberPermutation($0, mapping: mapping) }
}

func applySymmetricMemberPermutation(
  _ value: TLAValue,
  mapping: [TLAValue: TLAValue]
) -> TLAValue {
  if let replacement = mapping[value] { return replacement }
  switch value {
  case .set(let values):
    return .set(Set(values.map { applySymmetricMemberPermutation($0, mapping: mapping) }))
  case .tuple(let values):
    return .tuple(values.map { applySymmetricMemberPermutation($0, mapping: mapping) })
  case .record(let fields):
    return .record(fields.mapValues { applySymmetricMemberPermutation($0, mapping: mapping) })
  case .function(let entries):
    return .function(Dictionary(uniqueKeysWithValues: entries.map {
      (
        applySymmetricMemberPermutation($0.key, mapping: mapping),
        applySymmetricMemberPermutation($0.value, mapping: mapping)
      )
    }))
  default:
    return value
  }
}

func symmetricStateEncoding(_ state: [String: TLAValue]) -> String {
  state.keys.sorted().map { "\(String(reflecting: $0))=\(symmetricValueEncoding(state[$0]!))" }
    .joined(separator: "|")
}

private func symmetricValueEncoding(_ value: TLAValue) -> String {
  switch value {
  case .int(let integer): return "int:\(integer)"
  case .bool(let boolean): return "bool:\(boolean)"
  case .string(let string): return "string:\(String(reflecting: string))"
  case .constant(let symbol): return "constant:\(String(reflecting: symbol))"
  case .set(let values):
    return "set:[\(values.map(symmetricValueEncoding).sorted().joined(separator: ","))]"
  case .tuple(let values):
    return "tuple:[\(values.map(symmetricValueEncoding).joined(separator: ","))]"
  case .record(let fields):
    let encodedFields = fields.keys.sorted().map {
      "\(String(reflecting: $0)):\(symmetricValueEncoding(fields[$0]!))"
    }
    return "record:[\(encodedFields.joined(separator: ","))]"
  case .function(let entries):
    let encodedEntries = entries.map {
      "\(symmetricValueEncoding($0.key)):\(symmetricValueEncoding($0.value))"
    }.sorted()
    return "function:[\(encodedEntries.joined(separator: ","))]"
  }
}

public struct SymmetricCollectionScope: Equatable, Sendable {
  public let collectionName: String
  public let verificationScope: Int

  public init(collectionName: String, verificationScope: Int) {
    self.collectionName = collectionName
    self.verificationScope = verificationScope
  }

  public var description: String {
    "\(collectionName): \(verificationScope) exchangeable members"
  }
}

public enum SymmetricCollectionValidationError: Error, CustomStringConvertible {
  case invalidScope(collection: String, scope: Int)
  case missingCollectionName
  case duplicateCollection(collection: String)
  case symbolCollision(collection: String, symbol: String)
  case invalidOwnership(collection: String)
  case invalidDomain(collection: String)
  case permutationBudgetExceeded(collection: String, scope: Int, product: Int, budget: Int)
  case invalidPermutationBudget(Int)

  public var description: String {
    switch self {
    case .invalidScope(let collection, let scope):
      return "Symmetric collection '\(collection)' has verification scope \(scope); use a positive scope."
    case .missingCollectionName:
      return "A symmetric collection is missing a name; provide a unique collection name."
    case .duplicateCollection(let collection):
      return "Symmetric collection '\(collection)' is declared more than once; declare it once with one scope."
    case .symbolCollision(let collection, let symbol):
      return "Symmetric collection '\(collection)' generated symbol '\(symbol)' collides with an existing symbol; rename the collection."
    case .invalidOwnership(let collection):
      return "Symmetric collection '\(collection)' must own exactly one modeled variable; remove duplicate declarations."
    case .invalidDomain(let collection):
      return "Symmetric collection '\(collection)' must initialize every scoped member to the declared uniform value; "
        + "use SymmetricCollection(_:verificationScope:initial:)."
    case .permutationBudgetExceeded(let collection, let scope, let product, let budget):
      return "Symmetric collection '\(collection)' at scope \(scope) requires permutation product \(product), "
        + "exceeding budget \(budget); lower a scope or raise the configured budget."
    case .invalidPermutationBudget(let budget):
      return "Symmetric collection permutation budget \(budget) is invalid; configure a positive budget."
    }
  }
}

public extension TLASpec {
  func symmetricCollectionValidationError(
    permutationProductBudget: Int = 100_000
  ) -> SymmetricCollectionValidationError? {
    let collections = symmetricCollections
    guard !collections.isEmpty else { return nil }
    guard permutationProductBudget > 0 else {
      return .invalidPermutationBudget(permutationProductBudget)
    }

    var collectionNames = Set<String>()
    var generatedSymbols = Set<String>()
    var reservedSymbols = Set(variables.map(\.name))
    reservedSymbols.formUnion(constants.keys)
    reservedSymbols.formUnion(actions.map(\.name))
    reservedSymbols.formUnion(invariants.map(\.name))
    reservedSymbols.formUnion(temporalProperties.map(\.name))
    reservedSymbols.formUnion(recursiveFuncs.map(\.name))
    reservedSymbols.formUnion(symmetrySets.map { "Symm\($0.variableName)" })
    reservedSymbols.formUnion(definitions.compactMap(\.name))
    reservedSymbols.formUnion(recursiveDefs.compactMap(tlaDeclaredSymbol))
    reservedSymbols.formUnion(runtimeFuncBodies.compactMap(tlaDeclaredSymbol))
    reservedSymbols.formUnion(theorems.compactMap(tlaDeclaredSymbol))

    var product = 1
    for declaration in collections {
      let metadata = declaration.metadata
      guard !metadata.name.isEmpty else { return .missingCollectionName }
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
      guard case .function(let initialValues) = ownedVariables[0].initial,
            Set(initialValues.keys) == Set(metadata.members),
            Set(initialValues.values) == Set([metadata.initial])
      else { return .invalidDomain(collection: metadata.name) }

      let verificationSymbols = (1...metadata.verificationScope).map {
        "__symmetric_\(metadata.name)_member_\($0)"
      }
      for symbol in metadata.generatedSymbols + verificationSymbols {
        guard !reservedSymbols.contains(symbol), generatedSymbols.insert(symbol).inserted else {
          return .symbolCollision(collection: metadata.name, symbol: symbol)
        }
      }

      if metadata.verificationScope > 1 {
        for factor in 2...metadata.verificationScope {
          let (nextProduct, overflow) = product.multipliedReportingOverflow(by: factor)
          let requiredProduct = overflow ? Int.max : nextProduct
          guard !overflow, requiredProduct <= permutationProductBudget else {
            return .permutationBudgetExceeded(
              collection: metadata.name,
              scope: metadata.verificationScope,
              product: requiredProduct,
              budget: permutationProductBudget
            )
          }
          product = requiredProduct
        }
      }
    }
    return nil
  }
}

private func tlaDeclaredSymbol(_ text: String) -> String? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard let first = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
  let name = first.split(separator: "(", maxSplits: 1).first
  guard let name, !name.isEmpty else { return nil }
  return String(name)
}

@discardableResult
public func SymmetricCollection<Element: Identifiable, Value: TLAValueType>(
  _ collection: SymmetricCollectionVar<Element, Value>,
  verificationScope: Int,
  initial: Value
) -> SymmetricCollectionDecl {
  SymmetricCollectionDecl(
    name: collection.name, verificationScope: verificationScope, initial: initial.tlaValue)
}

@discardableResult
public func SymmetricCollection<Element: Identifiable, Value: TLAValueType>(
  _ initialState: Var<Value>,
  verificationScope: Int,
  elementType: Element.Type
) -> SymmetricCollectionDecl {
  SymmetricCollectionDecl(
    name: initialState.name, verificationScope: verificationScope, initial: initialState.initial ?? Value.defaultValue.tlaValue)
}

@discardableResult
public func CollectionAction<Element: Identifiable, Value: TLAValueType>(
  _ name: String,
  on collection: SymmetricCollectionVar<Element, Value>,
  @ActionBuilder _ body: (SymmetricMember<Element>) -> ActionExpr
) -> ActionDecl {
  let member = FreshVarName.fresh()
  let token = SymmetricMember<Element>(owner: collection.name, binding: .variable(member))
  return ActionDecl(name, .existsAction(member, collection.memberDomain, body(token)))
}
