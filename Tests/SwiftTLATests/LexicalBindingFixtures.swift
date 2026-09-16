import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SavedValuesMachine {
    enum Step: String, CaseIterable { case save }

    static var spec: TLASpec {
        #spec("SavedValues") { scope in
            let value = scope.sharedVar("value", initial: 1)
            let result = scope.sharedVar("result", initial: 0)
            let valid = scope.sharedVar("valid", initial: false)
            Algorithm("Save") {
                Do(Step.save) {
                    let first = value
                    let second = first + 1
                    let third = second + 1
                    Let(third == 3) { matches in
                        Assign(value, to: 9)
                        Assign(result, to: first * 100 + second * 10 + third)
                        Assign(valid, to: matches)
                        Stop()
                    }
                }
            }
        }
    }
}
