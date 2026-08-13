import SwiftTLA
import SwiftTLAMacros

@TLAActor
actor OrphanAdapter {}

@TLAModel
struct OuterModel {
  static var spec: TLASpec {
    TLASpec("OuterModel") {
      let count = Var<Int>("count")
      Variable(count, 0)
    }
  }

  @TLAModel
  struct InnerModel {
    static var spec: TLASpec {
      TLASpec("InnerModel") {
        let count = Var<Int>("count")
        Variable(count, 0)
      }
    }

    @TLAObservable
    final class AmbiguousAdapter {}
  }
}

@TLAModel
final class UnsupportedModel {
  static var spec: TLASpec {
    TLASpec("UnsupportedModel") {
      let count = Var<Int>("count")
      Variable(count, 0)
    }
  }

  @TLAActor
  actor UnsupportedAdapter {}
}
