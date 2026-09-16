import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct NativePropertyIdentityModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("NativePropertyIdentity") { scope in
            let count = scope.sharedVar(_name: "count", initial: 0)
            Algorithm("NativePropertyIdentity") {
                Do(Step.advance) {
                    Assign(count, to: 1)
                    Stop()
                }
            }
            Invariant("Safe") { count == 0 }
            Reachable("AtOne") { count == 1 }
            Always("NeverOne", count == 0)
        }
    }
}

@TLAModel
struct NativePropertylessModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("NativePropertyless") { scope in
            let count = scope.sharedVar(_name: "count", initial: 0)
            Algorithm("NativePropertyless") {
                Do(Step.advance) {
                    Assign(count, to: 1)
                    Stop()
                }
            }
        }
    }
}
