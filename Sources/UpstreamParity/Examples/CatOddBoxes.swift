extension Example {
    public static let catOddBoxes = Entry(
        id: "Moving_Cat_Puzzle/CatOddBoxes",
        upstreamSpec: "Moving_Cat_Puzzle",
        upstreamModule: "specifications/Moving_Cat_Puzzle/Cat.tla",
        upstreamCfg: "specifications/Moving_Cat_Puzzle/CatOddBoxes.cfg",
        expectedDistinct: 30,
        spec: CatOddBoxesModel.spec,
        notes: "Number_Of_Boxes=5. Typed direction phase. TLC upstream = 30.",
    )

}
