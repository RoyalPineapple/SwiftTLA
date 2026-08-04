import SwiftTLA
import SwiftTLAGeneration

let specs: [String: () -> TLASpec] = [
    "HourClock": { HourClock.spec },
    "DieHard":   { DieHard.spec },
    "CoffeeCan": { CoffeeCan.spec },
    "MovingCat": { MovingCat.spec },
    "Majority":  { Majority.spec },
]

for (name, specBuilder) in specs {
    let tla = specBuilder().tlaModule
    let path = "Examples/\(name)/\(name).tla"
    try! tla.write(toFile: path, atomically: true, encoding: .utf8)
    print("Generated \(path)")
}
