// TLC evaluates and prints formal values while checking the module’s assumptions.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/AsynchronousInterface/PrintValues.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct PrintValuesModel: Sendable {
    package struct Pets: Hashable, Sendable {
        package let cat: Int
        package let dog: String
    }

    package struct Player: Hashable, Sendable {
        package let game: String
        package let player: String
        package let homers: Int
    }

    package static var spec: TLASpec {
        #spec("PrintValues") { scope in
            Extends(.naturals, .tlc)
            let pets = Pets.expression(cat: 1, dog: "d")
            let original = Player.expression(game: "baseball", player: "Marris", homers: 61)
            let updated = Player.expression(game: original.game, player: "McGuire", homers: original.homers + 9)
            Assume(Print(Pair<String, Int>.literal("Three more cats: ", pets.cat + 3), returning: true)
                && Print(Pair.literal("Here's a record: ", updated), returning: true))
            Validation("Upstream") {}.checkingDeadlock(false)
        }
    }
}
