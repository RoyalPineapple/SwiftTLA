import Foundation

package struct CoreConformanceCaseManifestValueNormalization: Decodable, Sendable {
        package let binding: String
        package let functionKeys: [String: String]

        private enum CodingKeys: String, CodingKey, CaseIterable { case binding, functionKeys }

        package init(binding: String, functionKeys: [String: String]) throws {
            _ = try CoreConformanceValueNormalization(
                binding: binding, functionKeys: functionKeys)
            self.binding = binding
            self.functionKeys = functionKeys
        }

        package init(from decoder: Decoder) throws {
            let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            try self.init(
                binding: container.decode(String.self, forKey: .binding),
                functionKeys: container.decode([String: String].self, forKey: .functionKeys))
        }

        package func runtimeValue() throws -> CoreConformanceValueNormalization {
            try CoreConformanceValueNormalization(
                binding: binding, functionKeys: functionKeys)
        }
    }

package struct CoreConformanceCaseManifestUpstream: Decodable, Sendable {
        package let repository: String
        package let commit: String

        private enum CodingKeys: String, CodingKey, CaseIterable { case repository, commit }

        package init(from decoder: Decoder) throws {
            let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            repository = try container.decode(String.self, forKey: .repository)
            commit = try container.decode(String.self, forKey: .commit)
        }
    }

package struct CoreConformanceCaseManifestFixtures: Decodable, Sendable {
        package let module: String
        package let configuration: String

        private enum CodingKeys: String, CodingKey, CaseIterable { case module, configuration }

        package init(from decoder: Decoder) throws {
            let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            module = try container.decode(String.self, forKey: .module)
            configuration = try container.decode(String.self, forKey: .configuration)
        }
    }
