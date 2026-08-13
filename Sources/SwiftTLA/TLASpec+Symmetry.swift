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
    return r.values.contains(where: { valueContains($0, target) })
  default:
    return false
  }
}
func stateContains(_ state: [String: TLAValue], _ target: TLAValue) -> Bool {
  state.values.contains(where: { valueContains($0, target) })
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
    return .record(fields.mapValues { applyMapping($0, mapping) })
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
public struct SymmetryVariableGroup: Hashable, Sendable {
  public let names: [String]
  init(_ n: [String]) { names = n }
  func canonicalize(_ state: [String: TLAValue]) -> [String: TLAValue] {
    guard names.count > 1 else { return state }
    var vals = names.compactMap { state[$0] }
    guard vals.count == names.count else { return state }
    vals.sort(by: { $0.description < $1.description })
    var result = state
    for (i, name) in names.enumerated() { result[name] = vals[i] }
    return result
  }
}
public struct SymmetryVariableGroupDecl: SpecComponent {
  public let names: [String]
  init(_ n: [String]) { names = n }
}
public func SymmetryGroup(_ names: String...) -> SymmetryVariableGroupDecl {
  SymmetryVariableGroupDecl(names)
}
