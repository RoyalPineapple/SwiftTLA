/// A typed collection of modeled values indexed by application member identities.
///
/// Runtime element identity remains outside the verification AST. The modeled
/// collection is a function keyed by opaque constants derived from its scope.
public struct CollectionVar<Element: Identifiable & Sendable, Value: TLAValueType>: Sendable {
  public let name: String

  public init(_ name: String) {
    self.name = name
  }

  public subscript(_ member: CollectionMember<Element>) -> Expr<Value> {
    guard member.owner == name else {
      return Expr(.sourceIssue(.collectionMember(collection: name, owner: member.owner)))
    }
    return Expr(.functionApply(.variable(name), member.binding))
  }

  public func update(_ member: CollectionMember<Element>, to value: Value) -> ActionExpr {
    update(member, to: Expr<Value>(.value(value.tlaValue)))
  }

  public func update(_ member: CollectionMember<Element>, to value: Expr<Value>) -> ActionExpr {
    guard member.owner == name else {
      return .assign(.named(name), .sourceIssue(.collectionMember(collection: name, owner: member.owner)))
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

public struct CollectionMember<Element: Identifiable & Sendable>: Sendable {
  fileprivate let owner: String
  fileprivate let binding: StateExpr

  fileprivate init(owner: String, binding: StateExpr) {
    self.owner = owner
    self.binding = binding
  }
}

public struct ModelCollectionDecl: SpecComponent, Sendable {
  package let metadata: ModelCollectionMetadata
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
    self.metadata = ModelCollectionMetadata(
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

package struct ModelCollectionMetadata: Equatable, Sendable {
  package let name: String
  package let verificationScope: Int
  package let initial: TLAValue
  package let members: [TLAValue]
  package let domainSymbol: String

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
  }

  package var generatedSymbols: [String] {
    members.compactMap { value in
      guard case .constant(let symbol) = value else { return nil }
      return symbol
    } + [domainSymbol]
  }
}

enum ModelCollectionValidationError: Error, CustomStringConvertible {
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
      return "Model collection '\(collection)' has verification scope \(scope); use a positive scope."
    case .missingCollectionName:
      return "A model collection is missing a name; provide a unique collection name."
    case .invalidCollectionName(let name):
      return "Model collection '\(name)' is not a formal identifier; use letters, digits, and underscores, beginning with a letter or underscore."
    case .duplicateCollection(let collection):
      return "Model collection '\(collection)' is declared more than once; declare it once with one scope."
    case .symbolCollision(let collection, let symbol):
      return "Model collection '\(collection)' generated symbol '\(symbol)' collides with an existing symbol; rename the collection."
    case .invalidOwnership(let collection):
      return "Model collection '\(collection)' must own exactly one modeled variable; remove duplicate declarations."
    case .invalidDomain(let collection):
      return "Model collection '\(collection)' must initialize every scoped member to the declared uniform value; "
        + "use ModelCollection(_:verificationScope:initial:)."
    }
  }
}

extension TLASpec {
  func collectionValidationError() -> ModelCollectionValidationError? {
    let collections = self.collections
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
public func ModelCollection<Element: Identifiable & Sendable, Value: TLAValueType>(
  _ collection: CollectionVar<Element, Value>,
  verificationScope: Int,
  initial: Value
) -> ModelCollectionDecl {
  ModelCollectionDecl(
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
  on collection: CollectionVar<Element, Value>,
  @ActionBuilder _ body: (CollectionMember<Element>) -> ActionExpr
) -> ActionDecl {
  let member = "member"
  let token = CollectionMember<Element>(owner: collection.name, binding: .variable(member))
  return ActionDecl(
    name,
    .existsAction(member, collection.memberDomain, body(token))
  )
}
