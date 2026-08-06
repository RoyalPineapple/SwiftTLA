import SwiftTLA

extension Example {
    public static let catOddBoxes = Entry(
        id: "Moving_Cat_Puzzle/CatOddBoxes",
        upstreamSpec: "Moving_Cat_Puzzle",
        upstreamModule: "specifications/Moving_Cat_Puzzle/Cat.tla",
        upstreamCfg: "specifications/Moving_Cat_Puzzle/CatOddBoxes.cfg",
        expectedDistinct: 30,
        expectedResult: "success",
        spec: catSpec(boxes: 5),
        notes: "Number_Of_Boxes=5. Move_Cat /\\ Observe_Box. TLC upstream = 30.",
        matchesUpstreamTLC: true
    )

}
