import ExamplesLibrary
import SwiftUI
public struct CoffeeCanThemeView: View {
    public init() {}
    public var body: some View {
        SpecInfoThemeView(
            title: "Coffee Can",
            blurb: "Upstream shape, MaxBeanCount=5 (20 states).",
            spec: CoffeeCan.spec
        )
    }
}
