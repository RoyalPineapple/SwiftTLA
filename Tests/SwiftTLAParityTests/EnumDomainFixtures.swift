import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct IntEnumToggleModel {
  enum Mode: Int, CaseIterable, FiniteTLAValueDomain, StateExprConvertible {
    case idle = 0
    case active = 1

    static var defaultValue: Self { .idle }
    static let finiteValues = allCases
  }

  enum Step: String, CaseIterable { case toggle }

  static var spec: TLASpec {
    #spec("IntEnumToggle") { scope in
      let mode = scope.sharedVar(_name: "mode", initial: Mode.idle)
      let algorithm = Algorithm(label: "Toggle") {
        Do(Step.toggle) {
          Assign(mode, to: If(mode == Mode.idle, then: Mode.active, else: Mode.idle))
          Goto(Step.toggle)
        }
      }
      algorithm
      Invariant("TypeOK") { mode == Mode.idle || mode == Mode.active }
    }
  }
}

@TLAModel
struct StringEnumToggleModel {
  enum Status: String, CaseIterable, FiniteTLAValueDomain, StateExprConvertible {
    case on, off

    static var defaultValue: Self { .on }
    static let finiteValues = allCases
  }

  enum Step: String, CaseIterable { case toggle }

  static var spec: TLASpec {
    #spec("StringEnumToggle") { scope in
      let status = scope.sharedVar(_name: "status", initial: Status.on)
      let algorithm = Algorithm(label: "Toggle") {
        Do(Step.toggle) {
          Assign(status, to: If(status == Status.on, then: Status.off, else: Status.on))
          Goto(Step.toggle)
        }
      }
      algorithm
      Invariant("TypeOK") { status == Status.on || status == Status.off }
    }
  }
}
