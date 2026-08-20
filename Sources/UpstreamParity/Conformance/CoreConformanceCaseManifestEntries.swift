import Foundation

public struct CoreConformanceCaseManifestIdentityMapping: Decodable, Sendable {
        public let variables: [String: String]
        public let actions: [String: String]

        private enum CodingKeys: String, CodingKey, CaseIterable { case variables, actions }

        public init(from decoder: Decoder) throws {
            let container = try CoreGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            variables = try container.decode([String: String].self, forKey: .variables)
            actions = try container.decode([String: String].self, forKey: .actions)
        }
    }

public struct CoreConformanceCaseManifestInvocationMapping: Decodable, Sendable {
        public let wrapper: String
        public let action: String
        public let arguments: [String]
        public let indices: [Int]

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case wrapper, action, arguments, indices
        }

        public init(wrapper: String, action: String, arguments: [String], indices: [Int]) throws {
            _ = try CoreConformanceInvocationMapping(
                wrapper: wrapper, action: action, arguments: arguments, indices: indices)
            self.wrapper = wrapper
            self.action = action
            self.arguments = arguments
            self.indices = indices
        }

        public init(from decoder: Decoder) throws {
            let container = try CoreGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            try self.init(
                wrapper: container.decode(String.self, forKey: .wrapper),
                action: container.decode(String.self, forKey: .action),
                arguments: container.decode([String].self, forKey: .arguments),
                indices: container.decode([Int].self, forKey: .indices))
        }

        public var runtimeValue: CoreConformanceInvocationMapping {
            try! CoreConformanceInvocationMapping(
                wrapper: wrapper, action: action, arguments: arguments, indices: indices)
        }
    }

public struct CoreConformanceCaseManifestValueNormalization: Decodable, Sendable {
        public let binding: String
        public let functionKeys: [String: String]

        private enum CodingKeys: String, CodingKey, CaseIterable { case binding, functionKeys }

        public init(binding: String, functionKeys: [String: String]) throws {
            _ = try CoreConformanceValueNormalization(
                binding: binding, functionKeys: functionKeys)
            self.binding = binding
            self.functionKeys = functionKeys
        }

        public init(from decoder: Decoder) throws {
            let container = try CoreGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            try self.init(
                binding: container.decode(String.self, forKey: .binding),
                functionKeys: container.decode([String: String].self, forKey: .functionKeys))
        }

        public var runtimeValue: CoreConformanceValueNormalization {
            try! CoreConformanceValueNormalization(
                binding: binding, functionKeys: functionKeys)
        }
    }

public struct CoreConformanceCaseManifestUpstream: Decodable, Sendable {
        public let repository: String
        public let commit: String

        private enum CodingKeys: String, CodingKey, CaseIterable { case repository, commit }

        public init(from decoder: Decoder) throws {
            let container = try CoreGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            repository = try container.decode(String.self, forKey: .repository)
            commit = try container.decode(String.self, forKey: .commit)
        }
    }

public struct CoreConformanceCaseManifestFixtures: Decodable, Sendable {
        public let module: String
        public let configuration: String

        private enum CodingKeys: String, CodingKey, CaseIterable { case module, configuration }

        public init(from decoder: Decoder) throws {
            let container = try CoreGovernanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            module = try container.decode(String.self, forKey: .module)
            configuration = try container.decode(String.self, forKey: .configuration)
        }
    }
