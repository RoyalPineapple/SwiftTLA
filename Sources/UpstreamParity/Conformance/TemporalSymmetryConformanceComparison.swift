import Foundation

package struct TemporalComparison: Equatable, Encodable, Sendable {
  package static let schema = "TemporalComparison"

  package let schema: String
  package let caseID: String
  package let configuration: TemporalCaseConfiguration
  package let status: TemporalComparisonStatus
  package let swiftResult: TemporalPropertyResult
  package let tlcResult: TemporalPropertyResult

  package init(
    caseID: String,
    configuration: TemporalCaseConfiguration,
    swiftRun: CompletedGraphRun,
    tlcRun: CompletedGraphRun,
    swiftResult: TemporalPropertyResult,
    tlcResult: TemporalPropertyResult
  ) throws {
    guard swiftRun.isPassEligible, tlcRun.isPassEligible else {
      throw EvidenceFormatError.invalidField(record: caseID, field: "incomplete comparison graph")
    }
    self.schema = Self.schema
    self.caseID = caseID
    self.configuration = configuration
    self.swiftResult = swiftResult
    self.tlcResult = tlcResult
    guard !caseID.isEmpty else {
      throw EvidenceFormatError.inconsistentReference(record: caseID, field: "temporal comparison")
    }
    switch (swiftResult, tlcResult) {
    case (.unavailable, _), (_, .unavailable):
      status = .unavailable
    case (.satisfied, .violated), (.violated, .satisfied):
      status = .propertyOutcomeDifference
    case (.satisfied, .satisfied), (.violated, .violated):
      status = compareFiniteGraphs(expected: tlcRun, actual: swiftRun).isConformant
        ? .exact
        : .graphDifference
    }
  }
}

package struct SymmetryOrbit: Equatable, Encodable, Sendable {
  package let members: [String]
  package let semanticRepresentative: String
  package let swiftExecutableRepresentative: String
  package let tlcExecutableRepresentative: String

  package init(
    members: [String],
    semanticRepresentative: String,
    swiftExecutableRepresentative: String,
    tlcExecutableRepresentative: String
  ) throws {
    let orderedMembers = members.sorted()
    guard orderedMembers.isEmpty == false,
          Set(orderedMembers).count == orderedMembers.count,
          orderedMembers.allSatisfy({ $0.isEmpty == false }),
          semanticRepresentative == orderedMembers.first,
          orderedMembers.contains(swiftExecutableRepresentative),
          orderedMembers.contains(tlcExecutableRepresentative) else {
      throw EvidenceFormatError.invalidField(record: "orbit", field: "members or representative")
    }
    self.members = orderedMembers
    self.semanticRepresentative = semanticRepresentative
    self.swiftExecutableRepresentative = swiftExecutableRepresentative
    self.tlcExecutableRepresentative = tlcExecutableRepresentative
  }
}

package struct SymmetryQuotientTransition: Hashable, Encodable, Sendable, Comparable {
  package let sourceRepresentative: String
  package let action: String
  package let targetRepresentative: String

  package init(sourceRepresentative: String, action: String, targetRepresentative: String) throws {
    guard sourceRepresentative.isEmpty == false,
          action.isEmpty == false,
          targetRepresentative.isEmpty == false else {
      throw EvidenceFormatError.invalidField(record: "quotient transition", field: "transition")
    }
    self.sourceRepresentative = sourceRepresentative
    self.action = action
    self.targetRepresentative = targetRepresentative
  }

  package static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.sourceRepresentative != rhs.sourceRepresentative {
      return lhs.sourceRepresentative < rhs.sourceRepresentative
    }
    if lhs.action != rhs.action { return lhs.action < rhs.action }
    return lhs.targetRepresentative < rhs.targetRepresentative
  }
}

package struct SymmetryOrbitComparison: Equatable, Encodable, Sendable {
  package static let schema = "SymmetryOrbitComparison"

  package let schema: String
  package let caseID: String
  package let orbits: [SymmetryOrbit]
  package let quotientTransitions: [SymmetryQuotientTransition]

  package init(
    caseID: String,
    orbits: [SymmetryOrbit],
    quotientTransitions: [SymmetryQuotientTransition]
  ) throws {
    let members = orbits.flatMap(\.members)
    let representatives = Set(orbits.map(\.semanticRepresentative))
    let orderedTransitions = quotientTransitions.sorted()
    guard caseID.isEmpty == false,
          orbits.isEmpty == false,
          Set(members).count == members.count,
          Set(orderedTransitions).count == orderedTransitions.count,
          orderedTransitions.allSatisfy({
            representatives.contains($0.sourceRepresentative)
              && representatives.contains($0.targetRepresentative)
          }) else {
      throw EvidenceFormatError.invalidField(record: caseID, field: "orbit comparison")
    }
    schema = Self.schema
    self.caseID = caseID
    self.orbits = orbits.sorted { $0.semanticRepresentative < $1.semanticRepresentative }
    self.quotientTransitions = orderedTransitions
  }
}
