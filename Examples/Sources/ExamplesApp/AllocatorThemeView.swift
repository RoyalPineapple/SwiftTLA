import ExamplesLibrary
import SwiftUI
public struct AllocatorThemeView: View {
    public init() {}
    public var body: some View {
        SpecInfoThemeView(
            title: "Allocator",
            blurb: "SimpleAllocator (Merz) — 3 clients, 2 resources, 400 states.",
            spec: Allocator.spec
        )
    }
}
