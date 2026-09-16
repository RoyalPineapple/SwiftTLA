import Foundation
import UpstreamParity

func graphStream(case finiteGraphCase: FiniteGraphCase, runID: UUID) throws -> Data {
  let state: [String: Any] = [
    "fingerprint": "1", "level": 1,
    "bindings": [["ordinal": 0, "name": "x", "tla": "1"]]
  ]
  let common: [String: Any] = [
    "schema": "swifttla.tlc.graph-events", "version": 2, "runId": runID.uuidString.lowercased(), "caseId": finiteGraphCase.id
  ]
  let records = [
    common.merging(["type": "header", "callback": "writer.header", "seq": 0]) { $1 },
    common.merging(["type": "initial", "callback": "writeState.initial", "seq": 1, "state": state]) { $1 }
  ]
  let body = try records.reduce(into: Data()) { payload, record in
    payload.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
    payload.append(10)
  }
  let footer = common.merging([
    "type": "footer", "callback": "writer.footer", "seq": 2, "status": "closed",
    "counts": ["header": 1, "initial": 1], "lastBodySeq": 1, "bodySha256": SHA256.hex(body)
  ]) { $1 }
  let footerData = try JSONSerialization.data(withJSONObject: footer, options: [.sortedKeys])
  return body + footerData + Data([10])
}

func numberedInitialStateTrace() throws -> Data {
  let state: [Any] = [1, ["x": 1]]
  return try JSONSerialization.data(withJSONObject: [
    "vars": ["x"],
    "counterexample": ["state": [state], "action": []]
  ], options: [.sortedKeys])
}
