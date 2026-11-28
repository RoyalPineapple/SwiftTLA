import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct QuantifiedDictionaryReadModel {
    typealias Row = Dictionary<Int, Int>
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("QuantifiedDictionaryReadModel") { scope in
            let keys = IntRange(0, through: 1)
            let missing = IntRange(2, through: 2)
            let values = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: keys) { k in k.expr })
            let grid = scope.sharedVar(initial: Dictionary<Int, Row>.mapping(over: keys) { row in
                Dictionary<Int, Int>.mapping(over: keys) { column in row * 10 + column }
            })
            let zero = scope.sharedVar(initial: 0)
            Do(Step.stay) { Skip() }
            Invariant("guarded") {
                IntRange(0, through: 2).allSatisfy { k in
                    k == 2 || (values[k] >= 0 && values[k] == k)
                }
            }
            Invariant("cells") {
                keys.allSatisfy { row in keys.allSatisfy { column in
                    grid[row][column] == row * 10 + column && grid[column][row] == column * 10 + row
                        && grid[row][column] >= 0 && grid[column][row] >= 0
                } }
            }
            Invariant("arithmeticFirst") {
                missing.allSatisfy { k in
                    1 / zero == 1 && (values[k] >= 0 && values[k] == k)
                }
            }
            Invariant("lookupFirst") {
                missing.allSatisfy { k in
                    (values[k] >= 0 && values[k] == k) && 1 / zero == 1
                }
            }
        }
    }
}
