import SwiftUI
public struct MajorityThemeView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 20) {
            Text("🗳️").font(.system(size: 64))
            Text("Majority Vote").font(.largeTitle.bold())
            Text("Boyer-Moore single-pass algorithm. 5 states in bounded model.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(40)
    }
}
