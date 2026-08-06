import ExamplesLibrary
import SwiftUI
public struct HourClockThemeView: View {
    public init() {}
    public var body: some View {
        SpecInfoThemeView(
            title: "Hour Clock",
            blurb: "Upstream SpecifyingSystems/HourClock — hr ∈ 1..12.",
            spec: HourClock.spec
        )
    }
}
