import SwiftUI
import SwiftTLAUI

public struct HourClockThemeView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 20) {
            Text("🕐").font(.system(size: 64))
            Text("Hour Clock").font(.largeTitle.bold())
            Text("Cycles from 1 to 12. Each tick advances, wrapping from 12 back to 1. 12 states, 1 action.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(40)
    }
}
