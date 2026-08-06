import SwiftUI
import SwiftTLAUI

enum ExampleID: Int, CaseIterable {
    case hourClock = 0, dieHard, coffeeCan, movingCat, majority, sumsEven, allocator
}

@main
struct ExamplesApp: App {
    @State private var selected: ExampleID = .hourClock
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(ExampleID.allCases, id: \.self) { id in
                    Button(examples[id]!.name) { selected = id }
                        .buttonStyle(.plain)
                        .foregroundStyle(selected == id ? .primary : .secondary)
                        .fontWeight(selected == id ? .bold : .regular)
                }.navigationTitle("Examples")
            } detail: {
                ExamplePage(id: selected)
            }
        }
    }
}

struct ExamplePage: View {
    let id: ExampleID

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                themeView.frame(minWidth: 300).padding(24)
                if let code = codeForExample {
                    Divider()
                    CodeView(swift: code.swift, tla: code.tla).frame(height: 250)
                }
            }
        }
    }

    private var codeForExample: (swift: String, tla: String)? {
        switch id {
        case .hourClock: (HourClock.spec.swiftSource, HourClock.tla)
        case .dieHard:   (DieHard.spec.swiftSource, DieHard.tla)
        case .coffeeCan: (CoffeeCan.spec.swiftSource, CoffeeCan.tla)
        case .movingCat: (MovingCat.spec.swiftSource, MovingCat.tla)
        case .majority:  (Majority.spec.swiftSource, Majority.tla)
        case .sumsEven:  (SumsEven.spec.swiftSource, SumsEven.tla)
        case .allocator: (Allocator.spec.swiftSource, Allocator.tla)
        }
    }

    @ViewBuilder
    private var themeView: some View {
        switch id {
        case .hourClock: HourClockThemeView()
        case .dieHard:   DieHardThemeView()
        case .coffeeCan: CoffeeCanThemeView()
        case .movingCat: MovingCatThemeView()
        case .majority:  MajorityThemeView()
        case .sumsEven:  SumsEvenThemeView()
        case .allocator: AllocatorThemeView()
        }
    }
}

extension HourClock { static var tla: String { spec.tlaModule } }
extension DieHard   { static var tla: String { spec.tlaModule } }
extension CoffeeCan { static var tla: String { spec.tlaModule } }
extension MovingCat { static var tla: String { spec.tlaModule } }
extension Majority  { static var tla: String { spec.tlaModule } }
extension SumsEven  { static var tla: String { spec.tlaModule } }
extension Allocator { static var tla: String { spec.tlaModule } }

struct CodeView: View {
    let swift: String; let tla: String
    @State private var cs = false; @State private var ct = false
    var body: some View {
        HStack(spacing: 0) {
            col("Swift DSL", swift, $cs); Divider(); col("TLA+", tla, $ct)
        }
    }
    func col(_ t: String, _ c: String, _ copied: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(t).font(.caption).foregroundStyle(.secondary).padding(.leading, 8).padding(.top, 4)
                Spacer()
                Button(copied.wrappedValue ? "OK" : "Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c, forType: .string); copied.wrappedValue = true }
                    .font(.caption).buttonStyle(.plain).padding(.trailing, 8).padding(.top, 4)
            }
            ScrollView {
                Text(c).font(.system(size: 10, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }.background(.black.opacity(0.03))
        }
    }
}

private let examples: [ExampleID: ExampleDescription] = {
    let allByName = Dictionary(grouping: Examples.all, by: { $0.name })
    var result: [ExampleID: ExampleDescription] = [:]
    let mapping: [ExampleID: String] = [
        .hourClock: "HourClock", .dieHard: "DieHard", .coffeeCan: "CoffeeCan",
        .movingCat: "MovingCat", .majority: "Majority", .sumsEven: "SumsEven",
        .allocator: "Allocator"
    ]
    for (id, name) in mapping {
        result[id] = allByName[name]?.first
    }
    return result
}()
