import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SymmetryConformanceScope2: Sendable {
  package enum Member: String, CaseIterable, FiniteTLAValueDomain {
    case m0, m1

    package var tlaValue: TLAValue { .constant(rawValue) }

    package init?(formalValue: TLAValue) {
      guard case .constant(let value) = formalValue else { return nil }
      self.init(rawValue: value)
    }
  }

  package enum Step: String, CaseIterable { case choose = "Choose" }

  package static var spec: TLASpec {
    #spec("ModelCollection2") { scope in
      Constant("m0", Member.m0)
      Constant("m1", Member.m1)
      let memberSymmetry = Symmetry(Set(Member.all))
      memberSymmetry
      let chosen = scope.sharedVar(initial: Function<Member, Int>.mapping { _ in 0 })
      Do(Step.choose, over: Member.all) { member in
        When(chosen[member] == 0)
        Assign(chosen[member], to: 1)
      }
    }
  }
}

@TLAModel
package struct SymmetryConformanceScope3: Sendable {
  package enum Member: String, CaseIterable, FiniteTLAValueDomain {
    case m0, m1, m2

    package var tlaValue: TLAValue { .constant(rawValue) }

    package init?(formalValue: TLAValue) {
      guard case .constant(let value) = formalValue else { return nil }
      self.init(rawValue: value)
    }
  }

  package enum Step: String, CaseIterable { case choose = "Choose" }

  package static var spec: TLASpec {
    #spec("ModelCollection3") { scope in
      Constant("m0", Member.m0)
      Constant("m1", Member.m1)
      Constant("m2", Member.m2)
      let memberSymmetry = Symmetry(Set(Member.all))
      memberSymmetry
      let chosen = scope.sharedVar(initial: Function<Member, Int>.mapping { _ in 0 })
      Do(Step.choose, over: Member.all) { member in
        When(chosen[member] == 0)
        Assign(chosen[member], to: 1)
      }
    }
  }
}

@TLAModel
package struct SymmetryConformanceScope4: Sendable {
  package enum Member: String, CaseIterable, FiniteTLAValueDomain {
    case m0, m1, m2, m3

    package var tlaValue: TLAValue { .constant(rawValue) }

    package init?(formalValue: TLAValue) {
      guard case .constant(let value) = formalValue else { return nil }
      self.init(rawValue: value)
    }
  }

  package enum Step: String, CaseIterable { case choose = "Choose" }

  package static var spec: TLASpec {
    #spec("ModelCollection4") { scope in
      Constant("m0", Member.m0)
      Constant("m1", Member.m1)
      Constant("m2", Member.m2)
      Constant("m3", Member.m3)
      let memberSymmetry = Symmetry(Set(Member.all))
      memberSymmetry
      let chosen = scope.sharedVar(initial: Function<Member, Int>.mapping { _ in 0 })
      Do(Step.choose, over: Member.all) { member in
        When(chosen[member] == 0)
        Assign(chosen[member], to: 1)
      }
    }
  }
}

@TLAModel
package struct SymmetryConformanceScope5: Sendable {
  package enum Member: String, CaseIterable, FiniteTLAValueDomain {
    case m0, m1, m2, m3, m4

    package var tlaValue: TLAValue { .constant(rawValue) }

    package init?(formalValue: TLAValue) {
      guard case .constant(let value) = formalValue else { return nil }
      self.init(rawValue: value)
    }
  }

  package enum Step: String, CaseIterable { case choose = "Choose" }

  package static var spec: TLASpec {
    #spec("ModelCollection5") { scope in
      Constant("m0", Member.m0)
      Constant("m1", Member.m1)
      Constant("m2", Member.m2)
      Constant("m3", Member.m3)
      Constant("m4", Member.m4)
      let memberSymmetry = Symmetry(Set(Member.all))
      memberSymmetry
      let chosen = scope.sharedVar(initial: Function<Member, Int>.mapping { _ in 0 })
      Do(Step.choose, over: Member.all) { member in
        When(chosen[member] == 0)
        Assign(chosen[member], to: 1)
      }
    }
  }
}
