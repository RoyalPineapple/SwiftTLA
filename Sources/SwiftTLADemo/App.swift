import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAExamples

for example in allExamples {
    print(example.name)
    print(example.spec.annotatedForm)
    print("---")
}
