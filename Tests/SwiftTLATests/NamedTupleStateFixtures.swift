import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct NamedTupleStateModel {
    @TLATuple
    struct Coordinates: Hashable, Sendable {
        let z: Int
        let y: Int
        let x: Int
        let roll: Int
        let pitch: Int
        let yaw: Int
    }

    @TLATuple struct Empty: Hashable, Sendable {}
    @TLATuple struct Single: Hashable, Sendable { let sample: Int }
    enum Step: String, CaseIterable { case rotate }

    static var spec: TLASpec {
        #spec("NamedTupleState") { scope in
            let point = scope.sharedVar(initial: Coordinates(z: 1, y: 2, x: 3, roll: 4, pitch: 5, yaw: 6))
            let empty = scope.sharedVar(initial: Empty())
            let single = scope.sharedVar(initial: Single(sample: 7))
            Do(Step.rotate) {
                point.set(Coordinates.expression(z: point.yaw, y: point.z, x: point.y,
                    roll: point.x, pitch: point.roll, yaw: single.sample))
                empty.set(Empty())
            }
        }
    }
}
