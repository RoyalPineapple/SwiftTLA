import SwiftTLA

enum CarID: String, FiniteTLAValueDomain {
  case car

  static let finiteValues = [CarID.car]
}

enum PersonID: String, FiniteTLAValueDomain {
  case person

  static let finiteValues = [PersonID.person]
}

struct CarFields {
  let floor: Int
}

enum CarSchema: TLARecordSchema {
  typealias Fields = CarFields
  static let fieldNames: Set<String> = ["floor"]

  static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
    field as AnyKeyPath == \CarFields.floor ? "floor" : nil
  }
}

let cars = Var<Function<CarID, Record<CarSchema>>>("cars")
let forged = TLAField<CarSchema, String>(name: "floor")
let wrongDomain = cars[.person]
let rawVar = Var<TLAValue>("raw")
let rawExpr = Expr<TLAValue>(.variable("raw"))
let explicitValue = StateExpr.value(.int(1))

let varRawAssignment = rawVar.becomes(explicitValue)
let exprRawAssignment = rawExpr.becomes(explicitValue)
let varDynamicMember = rawVar.floor
let exprDynamicMember = rawExpr.floor

let varUpdated = rawVar.updated(at: 1, to: 2)
let exprUpdated = rawExpr.updated(at: 1, to: 2)
let varApplying = rawVar.applying(1)
let exprApplying = rawExpr.applying(1)
let varUnion = rawVar.union(StateExpr.set([1]))
let exprUnion = rawExpr.union(StateExpr.set([1]))
let varIntersection = rawVar.intersection(StateExpr.set([1]))
let exprIntersection = rawExpr.intersection(StateExpr.set([1]))
let varSubtracting = rawVar.subtracting(StateExpr.set([1]))
let exprSubtracting = rawExpr.subtracting(StateExpr.set([1]))
let varSubset = rawVar.isSubset(of: StateExpr.set([1]))
let exprSubset = rawExpr.isSubset(of: StateExpr.set([1]))
let varMembership = rawVar.isIn(StateExpr.set([1]))
let exprMembership = rawExpr.isIn(StateExpr.set([1]))

let varCardinality = rawVar.cardinality
let exprCardinality = rawExpr.cardinality
let varIsEmpty = rawVar.isEmpty
let exprIsEmpty = rawExpr.isEmpty
let varFlattened = rawVar.flattened
let exprFlattened = rawExpr.flattened
let varSubsets = rawVar.subsets
let exprSubsets = rawExpr.subsets
let varDomain = rawVar.domain
let exprDomain = rawExpr.domain
let varCount = rawVar.count
let exprCount = rawExpr.count
let varHead = rawVar.head
let exprHead = rawExpr.head
let varTail = rawVar.tail
let exprTail = rawExpr.tail

let varFiltering = rawVar.filtering(.value(.bool(true)))
let exprFiltering = rawExpr.filtering(.value(.bool(true)))
let varMapping = rawVar.mapping(.value(.int(1)))
let exprMapping = rawExpr.mapping(.value(.int(1)))
let varAppending = rawVar.appending(.value(.int(1)))
let exprAppending = rawExpr.appending(.value(.int(1)))
let varConcatenating = rawVar.concatenating(.tupleLiteral([]))
let exprConcatenating = rawExpr.concatenating(.tupleLiteral([]))
let varAt = rawVar.at(1)
let exprAt = rawExpr.at(1)
let varIntegerDivision = rawVar.integerDivided(by: 1)
let exprIntegerDivision = rawExpr.integerDivided(by: 1)

print(
  forged,
  wrongDomain,
  varRawAssignment,
  exprRawAssignment,
  varDynamicMember,
  exprDynamicMember,
  varUpdated,
  exprUpdated,
  varApplying,
  exprApplying,
  varUnion,
  exprUnion,
  varIntersection,
  exprIntersection,
  varSubtracting,
  exprSubtracting,
  varSubset,
  exprSubset,
  varMembership,
  exprMembership,
  varCardinality,
  exprCardinality,
  varIsEmpty,
  exprIsEmpty,
  varFlattened,
  exprFlattened,
  varSubsets,
  exprSubsets,
  varDomain,
  exprDomain,
  varCount,
  exprCount,
  varHead,
  exprHead,
  varTail,
  exprTail,
  varFiltering,
  exprFiltering,
  varMapping,
  exprMapping,
  varAppending,
  exprAppending,
  varConcatenating,
  exprConcatenating,
  varAt,
  exprAt,
  varIntegerDivision,
  exprIntegerDivision
)
