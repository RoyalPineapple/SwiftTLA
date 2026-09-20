import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct DictionaryKeyIdentityModel {
    enum Key: Int, CaseIterable { case first = 1, second = 2 }
    enum Label: String, CaseIterable { case first, second }
    private enum Step: String, CaseIterable { case update }
    typealias Links = [Key: Key]

    static var spec: TLASpec {
        #spec("DictionaryKeyIdentity") { scope in
            let values: SharedVariable<[Key: Int]> = scope.sharedVar(initial: [.first: 1, .second: 2])
            let links: SharedVariable<Links> = scope.sharedVar(initial: [.first: .second, .second: .first])
            let labels: SharedVariable<[Label: Key]> = scope.sharedVar(initial: [.first: .first, .second: .second])
            Algorithm("DictionaryKeyIdentity") {
                Do(Step.update) {
                    Assign(values[Key.first], to: values[links[Key.first]])
                    Assign(labels[Label.first], to: links[Key.first])
                    Stop()
                }
            }
        }
    }
}
