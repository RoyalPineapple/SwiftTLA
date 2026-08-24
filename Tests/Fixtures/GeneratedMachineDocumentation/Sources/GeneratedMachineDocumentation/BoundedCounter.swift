// Example ID: generated-machine-bounded-model

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BoundedCounter {
    enum Process: String, CaseIterable {
        case only

        }
    }
}
