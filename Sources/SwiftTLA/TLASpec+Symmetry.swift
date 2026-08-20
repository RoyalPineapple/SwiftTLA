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
