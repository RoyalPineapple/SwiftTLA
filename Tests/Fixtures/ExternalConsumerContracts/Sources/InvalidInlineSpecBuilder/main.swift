import SwiftTLA
import SwiftTLAMacros

let algorithm = #spec("InlineAlgorithm") {
    Algorithm(label: "Inline") {}
}

let validation = #spec("InlineValidation") {
    Validation(label: "Inline") {}.checkingDeadlock(false)
}

let qualified = #spec("QualifiedInlineAlgorithm") {
    SwiftTLA . Algorithm(label: "Inline") {}
}

_ = (algorithm, validation, qualified)
