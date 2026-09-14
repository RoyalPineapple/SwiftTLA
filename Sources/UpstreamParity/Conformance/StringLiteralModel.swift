import SwiftTLA
import SwiftTLAMacros

/// Exercises string serialization through the same complete-graph comparison as corpus models.
@TLAModel
package struct StringLiteralModel {
    package static var spec: TLASpec {
        #spec("StringLiterals") { scope in
            let text = scope.sharedVar("text", initial: "plain")
            SwiftTLA.Action("Escape") {
                text.becomes("quote\" slash\\ newline\n return\r tab\t form\u{c} e\u{301}")
                    .when(text == "plain")
            }
            SwiftTLA.Action("Reset") {
                text.becomes("plain").when(text != "plain")
            }
            Invariant("KnownText") {
                text == "plain" || text == "quote\" slash\\ newline\n return\r tab\t form\u{c} e\u{301}"
            }
        }
    }
}
