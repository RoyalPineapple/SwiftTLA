package enum EvidenceFormatError: Error, Equatable, Sendable {
  case invalidSchema(String)
  case duplicateID(kind: String, id: String)
  case invalidField(record: String, field: String)
  case inconsistentReference(record: String, field: String)
}
