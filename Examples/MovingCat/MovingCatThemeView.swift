import SwiftUI
public struct MovingCatThemeView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 20) {
            Text("🐱").font(.system(size: 64))
            Text("Moving Cat").font(.largeTitle.bold())
            Text("Find the cat hiding in N boxes. Cat moves each night, you check each morning. 70 states.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(40)
    }
}
