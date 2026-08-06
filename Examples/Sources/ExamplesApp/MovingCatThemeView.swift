import ExamplesLibrary
import SwiftUI
public struct MovingCatThemeView: View {
    public init() {}
    public var body: some View {
        SpecInfoThemeView(
            title: "Moving Cat",
            blurb: "Upstream CatEvenBoxes (6 boxes, 48 states).",
            spec: MovingCat.spec
        )
    }
}
