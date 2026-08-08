import SwiftTLA

extension Example {
    public static let catEvenBoxes = Entry(
        id: "Moving_Cat_Puzzle/CatEvenBoxes",
        upstreamSpec: "Moving_Cat_Puzzle",
        upstreamModule: "specifications/Moving_Cat_Puzzle/Cat.tla",
        upstreamCfg: "specifications/Moving_Cat_Puzzle/CatEvenBoxes.cfg",        spec: catSpec(boxes: 6),
        notes: "Number_Of_Boxes=6. TLC upstream = 48.",
    )

}
