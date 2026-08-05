import SwiftUI
public struct DieHardThemeView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 20) {
            Text("💧").font(.system(size: 64))
            Text("Die Hard").font(.largeTitle.bold())
            Text("Measure 4 gallons using a 5-gal and 3-gal jug. 16 states, 6 actions.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(40)
    }
}
