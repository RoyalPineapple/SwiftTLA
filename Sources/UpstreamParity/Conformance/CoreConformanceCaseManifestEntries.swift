import Foundation

package struct CoreConformanceCaseManifestIdentityMapping: Decodable, Sendable {
        package let variables: [String: String]
        package let actions: [String: String]

        private enum CodingKeys: String, CodingKey, CaseIterable { case variables, actions }

        package init(from decoder: Decoder) throws {
            let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            variables = try container.decode([String: String].self, forKey: .variables)
            actions = try container.decode([String: String].self, forKey: .actions)
        }
    }

package struct CoreConformanceCaseManifestInvocationMapping: Decodable, Sendable {
        package let wrapper: String
        package let action: String
        package let arguments: [String]
        package let indices: [Int]

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case wrapper, action, arguments, indices
        }

        package init(wrapper: String, action: String, arguments: [String], indices: [Int]) throws {
            _ = try CoreConformanceInvocationMapping(
                wrapper: wrapper, action: action, arguments: arguments, indices: indices)
            self.wrapper = wrapper
            self.action = action
            self.arguments = arguments
            self.indices = indices
        }

        package init(from decoder: Decoder) throws {
            let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            try self.init(
                wrapper: container.decode(String.self, forKey: .wrapper),
                action: container.decode(String.self, forKey: .action),
                arguments: container.decode([String].self, forKey: .arguments),
                indices: container.decode([Int].self, forKey: .indices))
        }

        package func runtimeValue() throws -> CoreConformanceInvocationMapping {
            try CoreConformanceInvocationMapping(
                wrapper: wrapper, action: action, arguments: arguments, indices: indices)
        }
    }

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
