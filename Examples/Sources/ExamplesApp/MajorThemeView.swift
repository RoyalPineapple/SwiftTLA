import ExamplesLibrary
import SwiftUI
public struct MajorityThemeView: View {
    public init() {}
    public var body: some View {
        SpecInfoThemeView(
            title: "Majority",
            blurb: "Boyer-Moore sketch (full MCMajority is in parity roadmap).",
            spec: Majority.spec
        )
    }
}
