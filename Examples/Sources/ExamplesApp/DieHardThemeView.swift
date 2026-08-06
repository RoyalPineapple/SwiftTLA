import ExamplesLibrary
import SwiftUI
public struct DieHardThemeView: View {
    public init() {}
    public var body: some View {
        SpecInfoThemeView(
            title: "Die Hard",
            blurb: "Upstream DieHard — TypeOK reachability (16 states).",
            spec: DieHard.spec
        )
    }
}
