import SwiftUI
public struct AllocatorThemeView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 20) {
            Text("📦").font(.system(size: 64))
            Text("Allocator").font(.largeTitle.bold())
            Text("Allocate and free resources. Invariant: available + allocated = 3. 4 states.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(40)
    }
}
