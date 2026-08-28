extension Example {
    package static let catOddBoxes = FiniteModelFixture(
        expectedDistinct: 30,
        maximumStateLimit: 50_000,
        spec: CatOddBoxesModel.spec,
    )

}
