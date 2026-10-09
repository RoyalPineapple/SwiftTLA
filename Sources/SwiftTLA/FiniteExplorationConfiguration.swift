package enum FiniteExplorationConfigurationError: Error, Sendable, Equatable {
    case nonPositiveStateLimit(Int)
    case nonPositivePermutationLimit(Int)
    case symmetryReductionRequiresSafetyOnly
    case symmetryReductionNotSupportedByFormalExplorer
}

/// Whether a rendered TLA+ bundle enables its declared symmetry reduction.
public enum SymmetryReduction: Sendable, Equatable {
    case disabled
    case enabled(maximumPermutationCount: Int)
}

package struct FiniteExplorationConfiguration: Sendable, Equatable, Codable {
    package let maximumStateLimit: Int
    package let symmetryReduction: SymmetryReduction

    package init(
        maximumStateLimit: Int,
        symmetryReduction: SymmetryReduction
    ) throws {
        guard maximumStateLimit > 0 else {
            throw FiniteExplorationConfigurationError.nonPositiveStateLimit(maximumStateLimit)
        }
        if case .enabled(let maximumPermutationCount) = symmetryReduction,
           maximumPermutationCount <= 0 {
            throw FiniteExplorationConfigurationError.nonPositivePermutationLimit(
                maximumPermutationCount
            )
        }
        self.maximumStateLimit = maximumStateLimit
        self.symmetryReduction = symmetryReduction
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case maximumStateLimit
        case symmetryReduction
        case maximumPermutationCount
    }

    private enum SymmetryReductionName: String, Codable {
        case disabled
        case enabled
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(validatingKeys: CodingKeys.self)
        let mode = try container.decode(SymmetryReductionName.self, forKey: .symmetryReduction)
        let symmetryReduction: SymmetryReduction
        switch mode {
        case .disabled:
            guard container.contains(.maximumPermutationCount) == false else {
                throw DecodingError.dataCorruptedError(
                    forKey: .maximumPermutationCount,
                    in: container,
                    debugDescription: "Disabled symmetry reduction cannot declare a permutation limit."
                )
            }
            symmetryReduction = .disabled
        case .enabled:
            symmetryReduction = .enabled(
                maximumPermutationCount: try container.decode(
                    Int.self,
                    forKey: .maximumPermutationCount
                )
            )
        }
        try self.init(
            maximumStateLimit: container.decode(Int.self, forKey: .maximumStateLimit),
            symmetryReduction: symmetryReduction
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maximumStateLimit, forKey: .maximumStateLimit)
        switch symmetryReduction {
        case .disabled:
            try container.encode(SymmetryReductionName.disabled, forKey: .symmetryReduction)
        case .enabled(let maximumPermutationCount):
            try container.encode(SymmetryReductionName.enabled, forKey: .symmetryReduction)
            try container.encode(maximumPermutationCount, forKey: .maximumPermutationCount)
        }
    }
}
