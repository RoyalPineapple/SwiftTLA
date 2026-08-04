import SwiftUI
import SwiftTLA
import SwiftTLAGenerator
import SwiftTLAExamples
import SwiftTLAMacros

@main struct DemoApp: App { var body: some Scene { WindowGroup { ContentView() } } }

struct ContentView: View {
    @State private var selected: ExampleDescription?
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) { ForEach(Examples.all) { ex in Label(ex.name, systemImage: icon(ex.name)).tag(ex) } }
                .navigationTitle("Examples").listStyle(.sidebar).frame(minWidth: 200)
        } detail: { if let ex = selected { ExampleDetailView(example: ex) } }
    }
    func icon(_ n: String) -> String { ["HourClock":"clock","DieHard":"drop","CoffeeCan":"cup.and.saucer","MovingCat":"cat","Majority":"checkmark.circle"][n] ?? "square.grid.3x3" }
}

struct ExampleDetailView: View {
    let example: ExampleDescription; @State private var showTLA = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.name).font(.largeTitle).bold()
                    Text(example.about).foregroundStyle(.secondary)
                    if let u = URL(string: example.source) { Link("Source ↗", destination: u).font(.caption) }
                }.padding()
                Divider()
                interactive.frame(maxWidth: .infinity).padding()
                Divider()
                SourcePanels(spec: example.spec)
            }
        }
    }
    @ViewBuilder var interactive: some View { switch example.name { case "HourClock": HourClockScreen(); case "DieHard": DieHardScreen(); case "CoffeeCan": CoffeeCanScreen(); case "MovingCat": CatScreen(); case "Majority": MajorityScreen(); case "BoundedCounter": CounterScreen(); case "Toggle": ToggleScreen(); case "ThreeState": ThreeScreen(); default: GraphScreen(ex: example) } }
}

// MARK: - Source panels

struct SourcePanels: View {
    let spec: TLASpec
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            CodePanel(title: "@TLASpec", text: spec.annotatedDescription)
            Spacer().frame(width: 25)
            CodePanel(title: "TLA+", text: spec.tlaDescription)
        }
    }
}

struct CodePanel: View {
    let title: String; let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 8)
            ScrollView(.vertical) {
                Text(text).font(.system(size: 10, design: .monospaced)).padding(8).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary).cornerRadius(4)
            .overlay(alignment: .topTrailing) {
                Button(action: { copy(text) }) { Image(systemName: "doc.on.doc").font(.caption2).padding(6) }
                    .buttonStyle(.plain).background(.regularMaterial).cornerRadius(4).padding(4)
            }
        }.frame(maxWidth: .infinity)
    }
}

func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }

// MARK: - Screens

struct HourClockScreen: View { @State private var c=HourClock(hr:1)
    var body: some View { VStack(spacing:16) { Text("\(c.hr):00").font(.system(size:72,weight:.bold,design:.monospaced)); Button("Tick"){c.apply(.tick)}.buttonStyle(.borderedProminent); Button("Reset"){c=HourClock(hr:1)}.buttonStyle(.bordered); Text("12 states verified").font(.caption).foregroundStyle(.secondary) } }
}

struct DieHardScreen: View { @State private var p=DieHard(jug3:0,jug5:0)
    var body: some View { VStack(spacing:16) { HStack(spacing:40) { jug("3 gal",p.jug3,3); jug("5 gal",p.jug5,5) }; Text(p.jug5==4 ? "🎉 4 gallons!" : "\(p.jug5) gal").font(.title); ForEach(p.availableActions,id:\.self){a in Button(a.rawValue){p.apply(a)}.buttonStyle(.bordered)}; Button("Reset"){p=DieHard(jug3:0,jug5:0)}.buttonStyle(.bordered); Text("16 states verified").font(.caption).foregroundStyle(.secondary) } }
    func jug(_ t:String,_ l:Int,_ c:Int) -> some View { VStack{ZStack(alignment:.bottom){Rectangle().stroke().frame(width:60,height:120);Rectangle().fill(.blue.opacity(0.6)).frame(width:58,height:CGFloat(l)/CGFloat(c)*118)};Text(t).font(.caption)} }
}

struct CoffeeCanScreen: View { @State private var c=CoffeeCan(black:5,white:5)
    var body: some View { VStack(spacing:16) { HStack(spacing:40) { bean("Black",c.black); bean("White",c.white) }; Text("Parity: \(c.white%2) — \(c.parityPreserved ? "✓" : "✗")").foregroundColor(c.parityPreserved ? .green : .red); ForEach(c.availableActions,id:\.self){a in Button(a.rawValue){c.apply(a)}.buttonStyle(.bordered)}; Button("Reset"){c=CoffeeCan(black:5,white:5)}.buttonStyle(.bordered) } }
    func bean(_ l:String,_ n:Int) -> some View { VStack{Text("\(n)").font(.system(size:48,weight:.bold,design:.monospaced));Text(l).font(.caption)} }
}

struct CatScreen: View { @State private var g:StateGraph?;@State private var id:StateGraph.StateID?;@State private var h:[String]=[]
    var body: some View { VStack(spacing:12) { if let g,let id,let s=g.states[id] { let cat=v(s["cat"]),obs=v(s["observed"]),dir=v(s["direction"]); HStack(spacing:4){ForEach(1...6,id:\.self){i in VStack{ZStack{RoundedRectangle(cornerRadius:4).fill(i<=obs ? .green.opacity(0.3):.gray.opacity(0.1)).frame(width:40,height:40);if i==cat{Text("🐱").font(.title2)}};Text("\(i)").font(.caption2)}}}; Text(dir==1 ? "→ right" : "← left").foregroundStyle(.secondary); ForEach(g.transitions[id] ?? [],id:\.action){t in Button(t.action){self.id=t.target;h.append(t.action)}.buttonStyle(.bordered)}; if !h.isEmpty{Text(h.joined(separator:" → ")).font(.caption).foregroundStyle(.secondary)} }; Button("Reset"){load()}.buttonStyle(.bordered); Text("24 states verified").font(.caption).foregroundStyle(.secondary) }.padding().onAppear{load()} }
    func load(){if let g=try? ModelChecker(spec:MovingCatSpec.spec,maxStates:100).exploreGraph(){self.g=g;id=g.states.keys.min(by:{$0.id<$1.id});h=[]}}
    func v(_ x:TLAValue?)->Int{if case .int(let n)=(x ?? .int(0)){return n};return 0}
}

struct MajorityScreen: View { @State private var g:StateGraph?;@State private var id:StateGraph.StateID?;@State private var h:[String]=[]
    var body: some View { VStack(spacing:12) { if let g,let id,let s=g.states[id] { let c=v(s["candidate"]),cnt=v(s["count"]),idx=v(s["index"]); Text("Candidate \(c) leads with \(cnt)").font(.title2); ProgressView(value:Double(idx),total:4).padding(.horizontal); Text(idx==4 ? "✓ Winner: \(c)" : "Scanning \(idx)/4").foregroundStyle(idx==4 ? .green:.secondary); ForEach(g.transitions[id] ?? [],id:\.action){t in Button(t.action){self.id=t.target;h.append(t.action)}.buttonStyle(.bordered)} }; Button("Reset"){load()}.buttonStyle(.bordered) }.padding().onAppear{load()} }
    func load(){if let g=try? ModelChecker(spec:MajorSpec.spec,maxStates:200).exploreGraph(){self.g=g;id=g.states.keys.min(by:{$0.id<$1.id});h=[]}}
    func v(_ x:TLAValue?)->Int{if case .int(let n)=(x ?? .int(0)){return n};return 0}
}

struct CounterScreen: View { @State private var g:StateGraph?;@State private var id:StateGraph.StateID?;@State private var h:[String]=[]
    var body: some View { VStack(spacing:12) { if let g,let id,let s=g.states[id] { let x=v(s["x"]); HStack(spacing:0){ForEach(-3...3,id:\.self){n in VStack{Rectangle().fill(n==x ? .blue:.gray.opacity(0.2)).frame(width:30,height:n==x ? 30:20);Text("\(n)").font(.caption2)}}}; Text("x = \(x)").font(.title3); ForEach(g.transitions[id] ?? [],id:\.action){t in Button(t.action){self.id=t.target;h.append(t.action)}.buttonStyle(.bordered)} }; Button("Reset"){load()}.buttonStyle(.bordered); Text("7 states verified").font(.caption).foregroundStyle(.secondary) }.padding().onAppear{load()} }
    func load(){if let g=try? ModelChecker(spec:BoundedCounterSpec.spec,maxStates:20).exploreGraph(){self.g=g;id=g.states.keys.min(by:{$0.id<$1.id});h=[]}}
    func v(_ x:TLAValue?)->Int{if case .int(let n)=(x ?? .int(0)){return n};return 0}
}

struct ToggleScreen: View { @State private var g:StateGraph?;@State private var id:StateGraph.StateID?;@State private var h:[String]=[]
    var body: some View { VStack(spacing:12) { if let g,let id,let s=g.states[id] { let x=v(s["x"]); Circle().fill(x==1 ? .green:.gray).frame(width:80,height:80).overlay(Text(x==1 ?"ON":"OFF").foregroundColor(.white).bold()); ForEach(g.transitions[id] ?? [],id:\.action){t in Button(t.action){self.id=t.target;h.append(t.action)}.buttonStyle(.bordered)} }; Button("Reset"){load()}.buttonStyle(.bordered); Text("2 states verified").font(.caption).foregroundStyle(.secondary) }.padding().onAppear{load()} }
    func load(){if let g=try? ModelChecker(spec:ToggleSpec.spec,maxStates:10).exploreGraph(){self.g=g;id=g.states.keys.min(by:{$0.id<$1.id});h=[]}}
    func v(_ x:TLAValue?)->Int{if case .int(let n)=(x ?? .int(0)){return n};return 0}
}

struct ThreeScreen: View { @State private var g:StateGraph?;@State private var id:StateGraph.StateID?;@State private var h:[String]=[]
    var body: some View { VStack(spacing:12) { if let g,let id,let s=g.states[id] { let st=v(s["state"]); HStack(spacing:40){ForEach(0..<3,id:\.self){i in VStack{Circle().fill(i==st ? .orange:.gray.opacity(0.2)).frame(width:50,height:50).overlay(Text("\(i)").bold());if i==st{Text("current").font(.caption2)}}}}; ForEach(g.transitions[id] ?? [],id:\.action){t in Button(t.action){self.id=t.target;h.append(t.action)}.buttonStyle(.bordered)} }; Button("Reset"){load()}.buttonStyle(.bordered); Text("3 states verified").font(.caption).foregroundStyle(.secondary) }.padding().onAppear{load()} }
    func load(){if let g=try? ModelChecker(spec:ThreeStateSpec.spec,maxStates:10).exploreGraph(){self.g=g;id=g.states.keys.min(by:{$0.id<$1.id});h=[]}}
    func v(_ x:TLAValue?)->Int{if case .int(let n)=(x ?? .int(0)){return n};return 0}
}

struct GraphScreen: View { let ex:ExampleDescription; @State private var g:StateGraph?;@State private var id:StateGraph.StateID?;@State private var h:[String]=[]
    var body: some View { VStack(spacing:12) { if let g,let id,let s=g.states[id] { VStack(spacing:4){ForEach(s.sorted(by:{$0.key<$1.key}),id:\.key){k,v in HStack{Text(k).bold();Text("=\(v)")}}}.padding().background(.quaternary).cornerRadius(8); ForEach(g.transitions[id] ?? [],id:\.action){t in Button(t.action){self.id=t.target;h.append(t.action)}.buttonStyle(.bordered)}; if !h.isEmpty{Text(h.joined(separator:" → ")).font(.caption)} }; Button("Reset"){load()}.buttonStyle(.bordered); Text("\(g?.states.count ?? 0) states verified").font(.caption).foregroundStyle(.secondary) }.padding().onAppear{load()} }
    func load(){if let g=try? ModelChecker(spec:ex.spec,maxStates:10000).exploreGraph(){self.g=g;id=g.states.keys.min(by:{$0.id<$1.id});h=[]}}
}
