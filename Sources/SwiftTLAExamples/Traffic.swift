import SwiftTLA
public enum TrafficSpec {
    public static let light = Var<Int>("light")
    public static let spec = TLASpec("Traffic") {
        Variable(light, 0)
        Act("Next") { light.next == (light + 1) % 3 }
        Invariant("Valid") { light >= 0 && light <= 2 }
    }
}
