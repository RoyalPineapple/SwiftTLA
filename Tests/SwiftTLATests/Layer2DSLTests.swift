import Testing
import SwiftTLA

@Suite(.serialized) struct Layer2GuardTests {
    @Test func guardInActionContext() {
        let x = Var<Int>("x")
        let action = Action("test") {
            Guard(x == 0)
            x.becomes(1)
        }
        #expect(action.body == .and(
            .guard_(.equal(.variable("x"), .int(0))),
            .assign("x", .int(1))
        ))
    }

    @Test func guardMultipleConditions() {
        let x = Var<Int>("x")
        let action = Action("test") {
            Guard(x > 0)
            Guard(x < 10)
            x.becomes(x + 1)
        }
        #expect(action.body == .and(
            .and(
                .guard_(.greaterThan(.variable("x"), .int(0))),
                .guard_(.lessThan(.variable("x"), .int(10)))
            ),
            .assign("x", .add(.variable("x"), .int(1)))
        ))
    }
}

@Suite(.serialized) struct Layer2WhenOtherwiseTests {
    @Test func whenOnly() {
        let x = Var<Int>("x")
        let action = Action("test") {
            When(x < 5) { x.becomes(x + 1) }
        }
        #expect(action.body == .and(.guard_(.lessThan(.variable("x"), .int(5))), .assign("x", .add(.variable("x"), .int(1)))))
    }

    @Test func whenOtherwiseChained() {
        let x = Var<Int>("x")
        let result = When(x < 5) { x.becomes(x + 1) }.Otherwise { x.becomes(0) }
        #expect(result == .or(
            .and(.guard_(.lessThan(.variable("x"), .int(5))), .assign("x", .add(.variable("x"), .int(1)))),
            .assign("x", .int(0))
        ))
    }

    @Test func whenOtherwiseInAction() {
        let x = Var<Int>("x")
        let action = Action("test") {
            When(x < 5) { x.becomes(x + 1) }.Otherwise { x.becomes(0) }
        }
        #expect(action.body == .or(
            .and(.guard_(.lessThan(.variable("x"), .int(5))), .assign("x", .add(.variable("x"), .int(1)))),
            .assign("x", .int(0))
        ))
    }

    @Test func hourClockLayer2ExpectedLowering() {
        let hr = Var<Int>("hr", 0)
        let layer2WithGuard = When(hr < 12) { hr.becomes(hr + 1) }.Otherwise { hr.becomes(1) }
        // Layer 2 Otherwise doesn't include the hr==12 guard; the two branches
        // produce identical state spaces when bounded by invariants.
        let expected = ActionExpr.or(
            .and(.guard_(.lessThan(.variable("hr"), .int(12))), .assign("hr", .add(.variable("hr"), .int(1)))),
            .assign("hr", .int(1))
        )
        #expect(layer2WithGuard == expected)
    }
}

@Suite(.serialized) struct Layer2StayTests {
    @Test func staySingleVariable() {
        let x = Var<Int>("x")
        #expect(Stay(x) == .unchanged("x"))
    }

    @Test func stayTwoVariables() {
        let x = Var<Int>("x")
        let y = Var<Bool>("y")
        #expect(Stay(x, y) == .and(.unchanged("x"), .unchanged("y")))
    }

    @Test func stayThreeVariables() {
        let x = Var<Int>("x")
        let y = Var<Bool>("y")
        let z = Var<String>("z")
        #expect(Stay(x, y, z) == .and(.and(.unchanged("x"), .unchanged("y")), .unchanged("z")))
    }

    @Test func stayInAction() {
        let x = Var<Int>("x")
        let y = Var<Bool>("y")
        let action = Action("test") {
            x.becomes(1)
            Stay(y)
        }
        #expect(action.body == .and(.assign("x", .int(1)), .unchanged("y")))
    }
}

@Suite(.serialized) struct Layer2ChooseTests {
    @Test func chooseFromSet() {
        let x = Var<Int>("x")
        let set = StateExpr.setLiteral([.int(1), .int(2), .int(3)])
        let result = Choose(x, from: set)
        #expect(result == .chooseAction("x", .setLiteral([.int(1), .int(2), .int(3)])))
    }

    @Test func chooseFromVariable() {
        let x = Var<Int>("x")
        let q = Var<TLASet>("q")
        let result = Choose(x, from: q)
        #expect(result == .chooseAction("x", .variable("q")))
    }
}

@Suite(.serialized) struct Layer2SwitchTests {
    @Test func switchTwoCasesNoDefault() {
        let phase = Var<Int>("phase")
        let result = Switch(phase, cases: [
            Case(0) { phase.becomes(1) },
            Case(1) { phase.becomes(2) }
        ])
        #expect(result == .or(
            .and(.guard_(.equal(.variable("phase"), .int(0))), .assign("phase", .int(1))),
            .or(
                .and(.guard_(.equal(.variable("phase"), .int(1))), .assign("phase", .int(2))),
                .guard_(.bool(false))
            )
        ))
    }

    @Test func switchWithDefault() {
        let phase = Var<Int>("phase")
        let result = Switch(phase, cases: [
            Case(0) { phase.becomes(1) },
            Case(1) { phase.becomes(2) }
        ], default: Default { phase.becomes(0) })
        #expect(result == .or(
            .and(.guard_(.equal(.variable("phase"), .int(0))), .assign("phase", .int(1))),
            .or(
                .and(.guard_(.equal(.variable("phase"), .int(1))), .assign("phase", .int(2))),
                .assign("phase", .int(0))
            )
        ))
    }

    @Test func switchInAction() {
        let phase = Var<Int>("phase")
        let action = Action("step") {
            Switch(phase, cases: [
                Case(0) { phase.becomes(1) },
                Case(1) { phase.becomes(2) }
            ], default: Default { phase.becomes(0) })
        }
        #expect(action.body == .or(
            .and(.guard_(.equal(.variable("phase"), .int(0))), .assign("phase", .int(1))),
            .or(
                .and(.guard_(.equal(.variable("phase"), .int(1))), .assign("phase", .int(2))),
                .assign("phase", .int(0))
            )
        ))
    }

    @Test func switchStringCases() {
        let state = Var<String>("state")
        let result = Switch(state, cases: [
            Case("idle") { state.becomes("running") },
            Case("running") { state.becomes("stopped") }
        ], default: Default { state.becomes("idle") })
        let expected = ActionExpr.or(
            ActionExpr.and(ActionExpr.guard_(.equal(.variable("state"), .value(.string("idle")))), ActionExpr.assign("state", .value(.string("running")))),
            ActionExpr.or(
                ActionExpr.and(ActionExpr.guard_(.equal(.variable("state"), .value(.string("running")))), ActionExpr.assign("state", .value(.string("stopped")))),
                ActionExpr.assign("state", .value(.string("idle")))
            )
        )
        #expect(result == expected)
    }

    @Test func caseProducesTuple() {
        let phase = Var<Int>("phase")
        let c = Case(0) { phase.becomes(1) }
        #expect(c.0 == 0)
        #expect(c.1 == .assign("phase", .int(1)))
    }

    @Test func defaultReturnsBody() {
        let phase = Var<Int>("phase")
        let d = Default { phase.becomes(0) }
        #expect(d == .assign("phase", .int(0)))
    }
}

@Suite(.serialized) struct Layer2ForEachTests {
    @Test func forEachSymmetricCollection() {
        struct Process: Identifiable {
            let id: String
        }
        let processes = SymmetricCollectionVar<Process, Int>("processes")
        let pc = Var<TLAFunctionType>("pc")

        let result = ForEach(processes) { p in
            pc.becomes(pc)
        }
        guard case .existsAction(let name, let domain, _) = result else {
            Issue.record("Expected existsAction, got \(result)")
            return
        }
        #expect(name.hasPrefix("x"))
        #expect(domain == .domain(.variable("processes")))
    }

    @Test func forEachWithGuardAndAssign() {
        struct Device: Identifiable {
            let id: String
        }
        let devices = SymmetricCollectionVar<Device, String>("devices")
        let pc = Var<TLAFunctionType>("pc")

        QuantVar.resetCounter()
        let readyExpr: StateExpr = .value(.string("ready"))
        let result = ForEach(devices) { p in
            Guard(pc == readyExpr)
            pc.becomes(pc)
        }
        guard case .existsAction = result else {
            Issue.record("Expected existsAction")
            return
        }
    }
}

@Suite(.serialized) struct Layer2AllSatisfyTests {
    @Test func allSatisfySymmetricCollection() {
        struct Device: Identifiable {
            let id: String
        }
        let devices = SymmetricCollectionVar<Device, Bool>("devices")

        QuantVar.resetCounter()
        let result = AllSatisfy(devices) { $0 == true }
        guard case .forAll(.domain(.variable("devices")), _, let body) = result else {
            Issue.record("Expected forAll over domain")
            return
        }
        #expect(body == .equal(.functionApply(.variable("devices"), .variable("x1")), .value(.bool(true))))
    }
}

@Suite(.serialized) struct Layer2TLAExportTests {
    @Test func guardLoweringToTLA() {
        let x = Var<Int>("x")
        let spec = TLASpec("GuardTest") {
            Variable(x)
            Action("tick") {
                Guard(x == 0)
                x.becomes(1)
            }
            Invariant("valid") { x >= 0 }
        }
        let tla = spec.tlaModule
        #expect(tla.contains("/\\"))
        #expect(tla.contains("x = 0"))
        #expect(tla.contains("x' = 1"))
    }

    @Test func whenOtherwiseTLA() {
        let hr = Var<Int>("hr", 0)
        let specL2 = TLASpec("HourClockL2") {
            Variable(hr)
            Action("tick") {
                When(hr < 12) { hr.becomes(hr + 1) }.Otherwise { hr.becomes(1) }
            }
            Invariant("valid") { hr >= 1 && hr <= 12 }
        }
        let tla = specL2.tlaModule
        #expect(tla.contains("tick =="))
        #expect(tla.contains("hr < 12"))
        #expect(tla.contains("hr' = (hr + 1)"))
        #expect(tla.contains("hr' = 1"))
    }
}
