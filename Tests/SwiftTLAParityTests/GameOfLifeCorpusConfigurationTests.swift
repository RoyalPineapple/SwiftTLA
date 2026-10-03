import Testing
import SwiftTLA
@testable import UpstreamParity

struct GameOfLifeCorpusConfigurationTests {
    @Test("Game of Life's published configuration reaches independent native validation")
    func nativePipelineSelectsPublishedConfiguration() throws {
        #expect(try modelValidationScenarios().contains {
            $0.id == "game-of-life-0" && $0.scenario.name == "GameOfLife"
        })
    }

    @Test("Game of Life admits every configured grid and keeps upstream checks")
    func completeInitialFunctionSpace() throws {
        let scenario = try #require(GameOfLifeModel.validationScenarios().first)
        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["TypeOK"])
        #expect(rendered.checksDeadlock)
        #expect(rendered.tlaBundle.cfg.contains("N = 4"))
        #expect(try scenario.initialMachines().count == 65_536)
    }

    @Test("Generated Game of Life machine updates every cell synchronously")
    func blinkerTransition() throws {
        typealias Position = GameOfLifeModel.NativeRecord0
        let positions = (1...4).flatMap { column in
            (1...4).map { row in Position(first: column, second: row) }
        }
        let vertical: Set<Position> = [
            .init(first: 2, second: 2), .init(first: 2, second: 3), .init(first: 2, second: 4),
        ]
        let horizontal: Set<Position> = [
            .init(first: 1, second: 3), .init(first: 2, second: 3), .init(first: 3, second: 3),
        ]
        func grid(_ alive: Set<Position>) -> [Position: Bool] {
            Dictionary(uniqueKeysWithValues: positions.map { ($0, alive.contains($0)) })
        }
        let scenario = try #require(GameOfLifeModel.validationScenarios().first)
        var machine = try GameOfLifeModel.makeMachine(
            .init(grid: grid(vertical)), configuration: scenario.configuration)
        #expect(try machine.violatedInvariants().isEmpty)
        #expect(try machine.send(.Next).after.grid == grid(horizontal))
        #expect(try machine.send(.Next).after.grid == grid(vertical))
    }
}
