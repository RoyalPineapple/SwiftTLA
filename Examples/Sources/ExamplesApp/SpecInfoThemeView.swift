import SwiftUI
import SwiftTLA

/// Shared theme: show state count + .tlaModule (no generated StateMachine).
struct SpecInfoThemeView: View {
    let title: String
    let blurb: String
    let spec: TLASpec

    var body: some View {
        let count = (try? ModelChecker(spec: spec, maxStates: 20_000).exploreGraph().states.count) ?? 0
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title.bold())
            Text(blurb).foregroundStyle(.secondary)
            Text("\(count) reachable states")
                .font(.title3.monospacedDigit())
            ScrollView {
                Text(spec.tlaModule)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .padding(8)
            .background(.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
