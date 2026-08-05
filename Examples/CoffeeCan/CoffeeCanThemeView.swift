import SwiftUI
public struct CoffeeCanThemeView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 20) {
            Text("☕").font(.system(size: 64))
            Text("Coffee Can").font(.largeTitle.bold())
            Text("Remove beans: same color → add black, different → keep white. 36 states.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(40)
    }
}
