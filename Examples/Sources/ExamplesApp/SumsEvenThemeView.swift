import SwiftUI
public struct SumsEvenThemeView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "function").font(.system(size: 64))
            Text("∀ x ∈ ℕ : Even(x + x)").font(.largeTitle.monospaced())
            Text("A TLA+ theorem — not a state machine.").foregroundStyle(.secondary)
        }.padding(40)
    }
}
