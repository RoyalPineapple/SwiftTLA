import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Generated atomic update proof input")
struct GeneratedAtomicUpdateProofTests {
    @Test("The proof input contains the generated Swift state and copy paths")
    func emittedSwiftTransitionMatchesProofInput() throws {
        let model = try compiledProofModel()
        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let names = ["State", "Snapshot", "__swifttlaFormalProjectionTokens",
            "formalProjection", "formalCall"]
        let actual = try names.map { name in
            let selected = try #require(member(named: name, in: members))
            return "@@ \(name)\n" + selected.description
                .replacingOccurrences(of: #"(?m)^[ \t]+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .newlines)
        }.joined(separator: "\n")
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopySwiftWitness.txt")
            .standardizedFileURL
        let checked = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(actual == checked.trimmingCharacters(in: .newlines))

        let initials = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        let values = try #require(try checkedInitialValues(initials.description))
        #expect(values.first == 0 && values.second == 1)
        let wrongGuard = initials.description.replacingOccurrences(
            of: "_selectedInitial!.second", with: "_selectedInitial!.first")
        #expect(wrongGuard != initials.description)
        #expect(try checkedInitialValues(wrongGuard).map { _ in true } == nil)

        let templateFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopySwiftTemplate.txt")
            .standardizedFileURL
        let template = Parser.parse(source: try String(contentsOf: templateFile, encoding: .utf8))
        let templateMembers = template.statements.compactMap { $0.item.as(DeclSyntax.self) }
        let bindings = try checkedTransitionBindings(members, templateMembers)
        #expect(bindings["__PROOF_FIRST_FIELD__"] == "first")
        #expect(bindings["__PROOF_SECOND_FIELD__"] == "second")
        #expect(bindings["__PROOF_READ__"] == "second")
        #expect(bindings["__PROOF_ACTION__"] == "copy")
        let initialConstruction = try [
            #require(member(named: "_initialStates", in: members)),
            #require(member(named: "_completedInitialStates", in: members)),
            #require(member(named: "initialOutcomes", parameterCount: 0, in: members)),
            #require(member(named: "initialMachines", parameterCount: 0, in: members)),
            #require(member(named: "makeMachine", parameterCount: 0, in: members)),
            #require(member(named: "makeMachine", parameterCount: 1, in: members)),
        ]
        let emittedConstructor = try #require(member(named: "makeMachine", parameterCount: 0, in: members))
        let wrongUniqueness = emittedConstructor.description.replacingOccurrences(
            of: "guard candidates.isEmpty else", with: "guard !candidates.isEmpty else")
        #expect(wrongUniqueness != emittedConstructor.description)
        let wrongConstructor = try #require(Parser.parse(source: wrongUniqueness)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(wrongConstructor.as(FunctionDeclSyntax.self)?.name.text == "makeMachine")
        var wrongConstruction = initialConstruction
        wrongConstruction[4] = wrongConstructor
        do {
            try verifyGeneratedInitialConstruction(wrongConstruction, configured: false)
            Issue.record("A generated constructor with reversed uniqueness was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.initialConstruction")
        }
        let emittedUpdate = try #require(member(named: "_visitUpdates0", in: members))
        let expectedUpdate = try #require(member(named: "_visitUpdates0", in: templateMembers))
        let wrongRead = Parser.parse(source: emittedUpdate.description.replacingOccurrences(
            of: "state.state.second", with: "state.state.first"))
        let wrongReadMember = try #require(wrongRead.statements.first?.item.as(DeclSyntax.self))
        #expect(templateBindings(wrongReadMember, expectedUpdate)?["__PROOF_READ__"] == "first")
        let emittedUpdates = try #require(member(named: "_Updates", in: members))
        let firstSlot = try #require(bindings["__PROOF_FIRST_SLOT__"])
        let secondSlot = try #require(bindings["__PROOF_SECOND_SLOT__"])
        let wrongWriteSource = emittedUpdate.description.replacingOccurrences(
            of: "_Updates(\(firstSlot): ___atomic_0_0)",
            with: "_Updates(\(secondSlot): ___atomic_0_0)")
        #expect(wrongWriteSource != emittedUpdate.description)
        let wrongWrite = try #require(Parser.parse(source: wrongWriteSource)
            .statements.first?.item.as(DeclSyntax.self))
        let compiledAction = try #require(model.program.behavior.actions.first)
        let expectedWrites: [(id: Int, slot: String, value: String)] = [
            (id: 5, slot: firstSlot, value: "___atomic_0_0"),
            (id: 3, slot: secondSlot, value: "___atomic_1_1")
        ]
        try verifyGeneratedActionWriteOutput(emittedUpdate, action: compiledAction.body,
            program: model.program, stateFields: emitter.stateMemberNames,
            parts: expectedWrites)
        do {
            try verifyGeneratedActionWriteOutput(wrongReadMember, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A captured state value read a different compiled field")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.0")
        }
        let wrongInheritedReadSource = emittedUpdate.description.replacingOccurrences(
            of: "let ___atomic_1_1 = ___atomic_0_0",
            with: "let ___atomic_1_1 = state.state.first")
        #expect(wrongInheritedReadSource != emittedUpdate.description)
        let wrongInheritedRead = try #require(Parser.parse(source: wrongInheritedReadSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongInheritedRead, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames, parts: expectedWrites)
            Issue.record("A captured binding reread pre-step state")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.1")
        }
        let wrongBindingSource = emittedUpdate.description.replacingOccurrences(
            of: "try _actionPart1(___atomic_0_0, updates, emit)",
            with: "try _actionPart1(state.state.first, updates, emit)")
        #expect(wrongBindingSource != emittedUpdate.description)
        let wrongBinding = try #require(Parser.parse(source: wrongBindingSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongBinding, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A generated action replaced a captured value before its child")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.0")
        }
        let wrongInheritedSource = emittedUpdate.description.replacingOccurrences(
            of: "try _actionPart2(___atomic_0_0, ___atomic_1_1, updates, emit)",
            with: "try _actionPart2(state.state.first, ___atomic_1_1, updates, emit)")
        #expect(wrongInheritedSource != emittedUpdate.description)
        let wrongInherited = try #require(Parser.parse(source: wrongInheritedSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongInherited, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A generated action replaced an earlier captured value before its child")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.1")
        }
        let wrongChildSource = emittedUpdate.description.replacingOccurrences(
            of: "try _actionPart3(", with: "try _actionPart5(")
        #expect(wrongChildSource != emittedUpdate.description)
        let wrongChild = try #require(Parser.parse(source: wrongChildSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongChild, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A generated action called the wrong child part")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.part.2")
        }
        let missingEntrySource = emittedUpdate.description.replacingOccurrences(
            of: "try _actionPart0(_Updates(), emit)", with: "try emit(_Updates())")
        #expect(missingEntrySource != emittedUpdate.description)
        let missingEntry = try #require(Parser.parse(source: missingEntrySource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(missingEntry, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A generated action never entered its root part")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.entry")
        }
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(wrongWrite, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(emittedUpdate, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames, parts: [])
        }
        let wrongMergeSource = emittedUpdates.description.replacingOccurrences(
            of: "&result.\(secondSlot)", with: "&result.\(firstSlot)")
        #expect(wrongMergeSource != emittedUpdates.description)
        let wrongMerge = Parser.parse(source: wrongMergeSource)
        let wrongMergeMember = try #require(wrongMerge.statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedUpdateMergeOutput(wrongMergeMember, slots: [firstSlot, secondSlot])
        }
        let firstField = try #require(bindings["__PROOF_FIRST_FIELD__"])
        let secondField = try #require(bindings["__PROOF_SECOND_FIELD__"])
        let projectionTokens = try #require(member(named: "__swifttlaFormalProjectionTokens", in: members))
        let projection = try #require(member(named: "formalProjection", in: members))
        let wrongProjectionSource = projection.description.replacingOccurrences(
            of: "snapshot.state.\(secondField)", with: "snapshot.state.\(firstField)")
        #expect(wrongProjectionSource != projection.description)
        let wrongProjection = try #require(Parser.parse(source: wrongProjectionSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedFormalProjectionOutput([projectionTokens, wrongProjection], fields: [
                (formalName: firstField, route: "snapshot.state.\(firstField)",
                    value: "TLAValue.int(snapshot.state.\(firstField))"),
                (formalName: secondField, route: "snapshot.state.\(secondField)",
                    value: "TLAValue.int(snapshot.state.\(firstField))"),
            ])
            Issue.record("A projection routed through the wrong state field was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.actual == "the projected value for \(secondField) reads a different snapshot field")
        }
        let emittedState = try #require(member(named: "State", in: members))
        let wrongStateSource = emittedState.description.replacingOccurrences(
            of: "self.\(secondField) = _value1", with: "self.\(secondField) = _value0")
        #expect(wrongStateSource != emittedState.description)
        let wrongState = Parser.parse(source: wrongStateSource)
        let wrongStateMember = try #require(wrongState.statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedStateConstructorOutput(wrongStateMember, fields: [
                (name: firstField, type: "Int", ordinal: 0, formalName: firstField),
                (name: secondField, type: "Int", ordinal: 1, formalName: secondField),
            ])
        }
        let wrongIdentitySource = emittedState.description.replacingOccurrences(
            of: "formalName: \"\(secondField)\"", with: "formalName: \"\(firstField)\"")
        #expect(wrongIdentitySource != emittedState.description)
        let wrongIdentity = try #require(Parser.parse(source: wrongIdentitySource)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedStateConstructorOutput(wrongIdentity, fields: [
                (name: firstField, type: "Int", ordinal: 0, formalName: firstField),
                (name: secondField, type: "Int", ordinal: 1, formalName: secondField),
            ])
        }
        let wrongApplySource = emittedUpdates.description.replacingOccurrences(
            of: "\(secondSlot) ?? state.state.\(secondField)",
            with: "\(secondSlot) ?? state.state.\(firstField)")
        #expect(wrongApplySource != emittedUpdates.description)
        let wrongApply = Parser.parse(source: wrongApplySource)
        let wrongApplyMember = try #require(wrongApply.statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedUpdateApplyOutput(wrongApplyMember, publicFields: [
                (label: firstField, field: firstField, slot: firstSlot),
                (label: secondField, field: secondField, slot: secondSlot),
            ], hiddenSlots: [])
        }
        let emittedDispatch = try #require(members.first { declaration in
            guard let function = declaration.as(FunctionDeclSyntax.self) else { return false }
            return function.name.text == "_visitSuccessors"
                && function.signature.parameterClause.parameters.contains {
                    $0.firstName.text == "onEvaluationFailure"
                }
        })
        let expectedDispatch = try #require(templateMembers.first { declaration in
            guard let function = declaration.as(FunctionDeclSyntax.self) else { return false }
            return function.name.text == "_visitSuccessors"
                && function.signature.parameterClause.parameters.contains {
                    $0.firstName.text == "onEvaluationFailure"
                }
        })
        #expect(templateBindings(emittedDispatch, expectedDispatch) != nil)
        let wrongFound = Parser.parse(source: emittedDispatch.description.replacingOccurrences(
            of: "found = true", with: "found = false"))
        let wrongFoundMember = try #require(wrongFound.statements.first?.item.as(DeclSyntax.self))
        #expect(templateBindings(wrongFoundMember, expectedDispatch) == nil)
    }

    @Test("A generated write is absent, compatible, or conflicting without changing a rejected value")
    func updateMergeRule() {
        var current: Int? = nil
        #expect(_NativeMachineOperations.mergeUpdate(&current, nil))
        #expect(current == nil)
        #expect(_NativeMachineOperations.mergeUpdate(&current, 3))
        #expect(current == 3)
        #expect(_NativeMachineOperations.mergeUpdate(&current, 3))
        #expect(current == 3)
        #expect(_NativeMachineOperations.mergeUpdate(&current, nil))
        #expect(current == 3)
        #expect(!_NativeMachineOperations.mergeUpdate(&current, 4))
        #expect(current == 3)
    }

    @Test("A captured Boolean reads its compiled state field")
    func capturedBooleanReadsCompiledField() throws {
        let compiled = try GeneratedBooleanCaptureProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedBooleanCaptureProofModel", program: program))
        let members = try emitter.machineMembers()
        let visitor = try #require(member(named: "_visitUpdates0", in: members))
        let writes = try emitter.actionFunctions(action.body).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)
        var wrongSource = visitor.description
        let capturedRead = try #require(wrongSource.range(of: "state.state.mirror"))
        wrongSource.replaceSubrange(capturedRead, with: "state.state.flag")
        let wrong = try #require(Parser.parse(source: wrongSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrong, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A captured Boolean read the wrong state field")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("A captured Boolean equality uses its compiled operands and operator")
    func capturedBooleanEqualityKeepsCompiledComparison() throws {
        let compiled = try GeneratedBooleanEqualityProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        guard case .define(_, let comparison, _) = action.body,
              case .equal = comparison.operation, comparison.children.count == 2,
              case .stateVariable(let lhs) = comparison.children[0].operation,
              case .stateVariable(let rhs) = comparison.children[1].operation else {
            Issue.record("The Boolean source comparison was not lowered to two state reads")
            return
        }
        let variables = program.layout.variables
        #expect(lhs == variables.first(where: { $0.declaration.name == "mirror" })?.id)
        #expect(rhs == variables.first(where: { $0.declaration.name == "flag" })?.id)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedBooleanEqualityProofModel", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action.body).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)
        var changedSource = visitor.description
        let equality = try #require(changedSource.range(of: " == "))
        changedSource.replaceSubrange(equality, with: " != ")
        let changed = try #require(Parser.parse(source: changedSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(changed, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A captured Boolean equality accepted a changed operator")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }

        let rendered = try GeneratedBooleanEqualityProofModel.render().tlaBundle.root.tla
        let declaration = try #require(rendered.split(separator: "\n").first {
            $0.hasPrefix("compare == ")
        })
        #expect(String(declaration) == "compare == (LET __atomic_0 == (mirror = flag) IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\\ flag' = __atomic_1) /\\ UNCHANGED mirror)))")
        #expect(rendered.contains("Init ==\n  /\\ flag = FALSE\n  /\\ mirror = FALSE"))

        let machine = try GeneratedBooleanEqualityProofModel.makeMachine()
        #expect(machine.state.flag == false && machine.state.mirror == false)
        #expect(try machine.formalCall(for: .compare).name == "compare")
        let successor = try #require(machine.successors(for: .compare).first)
        #expect(successor.state.flag && successor.state.mirror == false)
    }

    @Test("A fallible captured equality keeps its checked operand and operator")
    func capturedEqualityKeepsCheckedAddition() throws {
        let compiled = try GeneratedCheckedEqualityProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedCheckedEqualityProofModel", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action.body).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)
        var changedSource = visitor.description
        let equality = try #require(changedSource.range(of: " == "))
        changedSource.replaceSubrange(equality, with: " != ")
        let changed = try #require(Parser.parse(source: changedSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(changed, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A captured equality with checked addition accepted a changed operator")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }

        let rendered = try GeneratedCheckedEqualityProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedCheckedEqualityProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)))

        let machines = try GeneratedCheckedEqualityProofModel.initialMachines()
        #expect(machines.count == 2)
        let passing = try #require(machines.first { $0.state.left == 2 })
        let successor = try #require(passing.successors(for: .compare).first)
        #expect(successor.state.left == 2 && successor.state.right == 3)
        #expect(successor.state.matched)
        var overflowing = try #require(machines.first { $0.state.left == Int.max })
        let before = overflowing.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try overflowing.send(.compare)
        }
        #expect(overflowing.snapshot == before)
    }

    @Test("Ordered copy emission is independent of field names")
    func generatedCopyRuleUsesResolvedFieldNames() throws {
        let model = try compiledProofModel(named: "RenamedAtomicCopyProofModel")
        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let templateFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopySwiftTemplate.txt")
            .standardizedFileURL
        let template = Parser.parse(source: try String(contentsOf: templateFile, encoding: .utf8))
        let bindings = try checkedTransitionBindings(
            members, template.statements.compactMap { $0.item.as(DeclSyntax.self) })
        #expect(bindings["__PROOF_FIRST_FIELD__"] == "left")
        #expect(bindings["__PROOF_SECOND_FIELD__"] == "right")
        #expect(bindings["__PROOF_READ__"] == "right")
        #expect(bindings["__PROOF_ACTION__"] == "copy")
    }

    @Test("Do lowering captures the ordered copy as complete compiled updates")
    func compiledCopyKeepsOrderedReadsAndTargets() throws {
        for (modelName, firstName, secondName) in [
            ("GeneratedAtomicCopyProofModel", "first", "second"),
            ("RenamedAtomicCopyProofModel", "left", "right"),
        ] {
            let program = try compiledProofModel(named: modelName).program
            let variables = program.layout.variables
            let first = try #require(variables.first { $0.declaration.name == firstName })
            let second = try #require(variables.first { $0.declaration.name == secondName })
            let action = try #require(program.behavior.actions.first)
            guard variables.count == 2, program.behavior.actions.count == 1, action.bindings.isEmpty,
                  case .define(let firstCapture, let firstRead, let firstTail) = action.body,
                  case .stateVariable(let source) = firstRead.operation,
                  case .define(let secondCapture, let secondRead, let writes) = firstTail,
                  case .boundValue(let copiedFirst) = secondRead.operation,
                  case .and(let firstPart, let secondWrite) = writes,
                  case .and(let guardPart, let firstWrite) = firstPart,
                  case .guard_(let guardValue) = guardPart,
                  case .value(.boolean(true)) = guardValue.operation,
                  case .assign(let firstTarget, let firstValue) = firstWrite,
                  case .boundValue(let firstValueBinding) = firstValue.operation,
                  case .assign(let secondTarget, let secondValue) = secondWrite,
                  case .boundValue(let secondValueBinding) = secondValue.operation else {
                Issue.record("The compiled action no longer has the proved ordered-copy structure")
                return
            }
            #expect(source == second.id)
            #expect(copiedFirst == firstCapture)
            #expect(firstTarget == first.id && firstValueBinding == firstCapture)
            #expect(secondTarget == second.id && secondValueBinding == secondCapture)
            let onlyLeafExpressions = [firstRead, secondRead, guardValue, firstValue, secondValue]
                .allSatisfy { $0.children.isEmpty }
            #expect(onlyLeafExpressions)
        }
    }

    @Test("The checked TLA module is the model's actual generated output")
    func renderedModuleMatchesProofInput() throws {
        let rendered = try GeneratedAtomicCopyProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopyProofModel.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(rendered == checkedModule)

        let stateNames = try compiledProofModel().program.layout.variables.map(\.declaration.name)
        let missingVariable = rendered.replacingOccurrences(
            of: "VARIABLES first, second\n", with: "VARIABLES first\n")
        #expect(missingVariable != rendered)
        do {
            try verifyRenderedVariableDeclaration(missingVariable, names: stateNames)
            Issue.record("A missing emitted state variable was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.variables")
            #expect(diagnostic.actual == "VARIABLES first")
        }

        let copyDefinition = "copy == (LET __atomic_0 == second IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\\ first' = __atomic_0) /\\ second' = __atomic_1)))"
        try verifyRenderedActionDeclarations(rendered, declarations: [("copy", copyDefinition)])
        let changedAction = rendered.replacingOccurrences(
            of: "second' = __atomic_1", with: "second' = first")
        #expect(changedAction != rendered)
        do {
            try verifyRenderedActionDeclarations(changedAction, declarations: [("copy", copyDefinition)])
            Issue.record("A changed emitted action was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.actions.copy")
        }

        let machine = try GeneratedAtomicCopyProofModel.makeMachine()
        #expect(try machine.formalCall(for: .copy).name == "copy")
        let successors = try machine.successors(for: .copy)
        #expect(successors.count == 1)
        let successor = try #require(successors.first)
        #expect(machine.state.first == 0 && machine.state.second == 1)
        #expect(successor.state.first == 1 && successor.state.second == 1)
        let dispatched = try machine.successors()
        #expect(dispatched.count == 1)
        #expect(dispatched.first?.action == .copy)
        #expect(dispatched.first?.machine.state.first == 1)
        #expect(dispatched.first?.machine.state.second == 1)
    }

    private func checkedInitialValues(_ source: String) throws -> (first: Int, second: Int)? {
        let pattern = #"""
        \A private \s+ static \s+ func \s+ _initialStates
        \( _selectedInitial: \s* State\? \s* = \s* nil \)
        \s* throws \s* -> \s* InitialEvaluationOutcomes \s* < \s* Snapshot \s* > \s* \{
        \s* var \s+ result: \s* \[Snapshot\] \s* = \s* \[\]
        \s* var \s+ firstFailure: \s* NativeMachineEvaluationError\?
        \s* try \s+ _NativeMachineOperations\.visitInitialBranch \s* \( \s* \{
        \s* let \s+ _value_first_0: \s* Int \s* = \s* (-?[0-9]+)
        \s* if \s+ _selectedInitial \s* == \s* nil \s* \|\| \s* _selectedInitial!\.first \s* == \s* _value_first_0 \s* \{
        \s* let \s+ _value_second_1: \s* Int \s* = \s* (-?[0-9]+)
        \s* if \s+ _selectedInitial \s* == \s* nil \s* \|\| \s* _selectedInitial!\.second \s* == \s* _value_second_1 \s* \{
        \s* result\.append \( Snapshot \( state: \s* State \( first: \s* _value_first_0, \s* second: \s* _value_second_1 \) \) \)
        \s* \} \s* \}
        \s* \}, \s* onEvaluationFailure: \s* \{ \s* failure \s+ in
        \s* if \s+ firstFailure \s* == \s* nil \s* \{ \s* firstFailure \s* = \s* failure \s* \}
        \s* \} \s* \)
        \s* return \s+ InitialEvaluationOutcomes \s* \( \s* states: \s* result, \s* firstFailure: \s* firstFailure \s* \)
        \s* \} \s* \z
        """#
        let regex = try NSRegularExpression(pattern: pattern, options: .allowCommentsAndWhitespace)
        let text = source as NSString
        guard let match = regex.firstMatch(in: source, range: NSRange(location: 0, length: text.length)),
              match.range == NSRange(location: 0, length: text.length),
              let first = Int(text.substring(with: match.range(at: 1))),
              let second = Int(text.substring(with: match.range(at: 2))) else { return nil }
        return (first, second)
    }

    private func compiledProofModel(named name: String = "GeneratedAtomicCopyProofModel") throws -> MacroCompilation {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("GeneratedAtomicUpdateProofFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == name })
        return try TLASpecVerifier.parseAndVerify(declaration)
    }

    private func checkedTransitionBindings(
        _ actualMembers: [DeclSyntax], _ templateMembers: [DeclSyntax]
    ) throws -> [String: String] {
        var all: [String: String] = [:]
        let declarations: [(String, Int?)] = [
            ("_Updates", nil), ("_visitUpdates0", 3), ("_visitSuccessors0", 3),
            ("visitSuccessors", 2), ("_visitSuccessors", 3), ("_visitSuccessors", 2),
        ]
        for (name, parameterCount) in declarations {
            let emitted = try #require(member(named: name, parameterCount: parameterCount, in: actualMembers))
            let expected = try #require(member(named: name, parameterCount: parameterCount, in: templateMembers))
            let bindings = try #require(templateBindings(emitted, expected))
            for (key, value) in bindings {
                if let previous = all[key] { _ = try #require(previous == value) }
                all[key] = value
            }
        }
        return all
    }

    private func member(named name: String, parameterCount: Int? = nil, in declarations: [DeclSyntax]) -> DeclSyntax? {
        declarations.first { item in
            if let function = item.as(FunctionDeclSyntax.self) {
                return function.name.text == name && (parameterCount == nil
                    || function.signature.parameterClause.parameters.count == parameterCount)
            }
            return parameterCount == nil && (item.as(StructDeclSyntax.self)?.name.text == name
                || item.as(VariableDeclSyntax.self)?.bindings.first?
                    .pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name)
        }
    }

    private func templateBindings(_ actual: DeclSyntax, _ template: DeclSyntax) -> [String: String]? {
        let actualTokens = Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
        let expectedTokens = Array(template.tokens(viewMode: .sourceAccurate)).map(\.text)
        guard actualTokens.count == expectedTokens.count else { return nil }
        var bindings: [String: String] = [:]
        for (actual, expected) in zip(actualTokens, expectedTokens) {
            if expected.hasPrefix("__PROOF_") {
                if let previous = bindings[expected], previous != actual { return nil }
                bindings[expected] = actual
            } else if actual != expected {
                return nil
            }
        }
        return bindings
    }
}
