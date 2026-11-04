import Foundation
import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct MathematicalIntegerDomainTests {
    @Test("Integer domains retain mathematical Int without machine-bound substitutions")
    func configurationExecutionAndExport() throws {
        for values: Set<Int> in [[], [-7, 42], [Int.min, Int.max]] {
            let configuration = try MathematicalIntegerDomainModel.Configuration(Values: values)
            let input = values.sorted()
            var machine = try MathematicalIntegerDomainModel.makeMachine(
                .init(value: Int.min, copy: Int.min + 1, sequence: input), configuration: configuration)
            #expect(try machine.send(.increment).after.value == Int.min + 1)
            #expect(machine.state.copy == Int.min + 1)
            #expect(machine.state.sequence == input)
            for value in [Int.min, 0, Int.max - 1] {
                let state = MathematicalIntegerDomainModel.State(value: value, copy: value + 1, sequence: input)
                #expect(try MathematicalIntegerDomainModel.makeMachine(state,
                    configuration: configuration).state == state)
            }
            #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
                try MathematicalIntegerDomainModel.makeMachine(
                    .init(value: Int.max, copy: Int.max, sequence: input), configuration: configuration)
            }
            #expect(throws: NativeMachineEvaluationError.nonEnumerableIntegerDomain) {
                try MathematicalIntegerDomainModel.initialMachines(configuration: configuration)
            }
            let bundle = try MathematicalIntegerDomainModel.render(configuration: configuration).tlaBundle
            #expect(bundle.tla.contains("ASSUME Values \\in SUBSET (Int)"))
            #expect(bundle.tla.contains("value \\in Int"))
            #expect(bundle.tla.contains("Seq(Values)"))
            #expect(bundle.tla.contains("Integers"))
            let lines = bundle.tla.components(separatedBy: "\n")
            let start = try #require(lines.firstIndex(of: "Init =="))
            let end = lines[(start + 1)...].firstIndex(of: "") ?? lines.count
            let predicates = lines[(start + 1)..<end].map { String($0.dropFirst(5)) }
            try verifyRenderedInitialConjunction(bundle.tla, predicates: predicates,
                expectedIntPredicates: ["value": "value \\in Int"],
                expectedIntStateNames: ["value", "copy"], expectedPredicateCount: 6)
            if values.isEmpty {
                let changed = predicates.map { $0 == "value \\in Int" ? "value \\in {}" : $0 }
                try #require(changed != predicates)
                let actual = lines[start..<end].joined(separator: "\n")
                let replacement = (["Init =="] + changed.map { "  /\\ \($0)" }).joined(separator: "\n")
                let module = bundle.tla.replacingOccurrences(of: actual, with: replacement)
                try #require(module != bundle.tla)
                do {
                    try verifyRenderedInitialConjunction(module, predicates: changed,
                        expectedIntPredicates: ["value": "value \\in Int"],
                        expectedIntStateNames: ["value", "copy"], expectedPredicateCount: 6)
                    Issue.record("The emitted mathematical Int domain was replaced by an empty domain")
                } catch let diagnostic as CompilationDiagnostic {
                    #expect(diagnostic.path == "tla.Init")
                }
            }
            for name in ["value", "copy"] {
                let small = "(\(name) >= \(TLAValue.int(Int(Int32.min)).description) /\\ \(name) <= \(TLAValue.int(Int(Int32.max)).description))"
                let allowed = "\(name) \\in \(TLAValue.int(Int.min).description)..\(TLAValue.int(Int.max).description)"
                let predicate = "(IF \(small) THEN TRUE ELSE \(allowed))"
                #expect(predicates.filter { $0 == predicate }.count == 1,
                    "Declared Int state constraint missing: \(name)")
                for mutation in ["omit", "duplicate", "widen"] {
                    let changed: [String]
                    switch mutation {
                    case "omit": changed = predicates.filter { $0 != predicate }
                    case "duplicate": changed = predicates + [predicate]
                    default:
                        changed = predicates.map { $0 == predicate
                            ? predicate.replacingOccurrences(of: "ELSE \(allowed)", with: "ELSE TRUE") : $0 }
                    }
                    let actual = lines[start..<end].joined(separator: "\n")
                    let replacement = (["Init =="] + changed.map { "  /\\ \($0)" }).joined(separator: "\n")
                    let module = bundle.tla.replacingOccurrences(of: actual, with: replacement)
                    try #require(module != bundle.tla)
                    do {
                        try verifyRenderedInitialConjunction(module, predicates: changed,
                            expectedIntStateNames: ["value", "copy"], expectedPredicateCount: 6)
                        Issue.record("Declared Int state \(mutation) corruption accepted: \(name)")
                    } catch let diagnostic as CompilationDiagnostic {
                        #expect(diagnostic.path == "tla.Init")
                    }
                }
            }
            #expect(lines.contains { $0.hasPrefix("__SwiftTLAInitialOverflowFailure") },
                "A mathematical domain prefix dropped the dependent initializer failure")
            if values.isEmpty {
                let compilation = try MathematicalIntegerDomainModel.spec.compile()
                let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
                let copy = try #require(program.layout.variables.first { $0.declaration.name == "copy" })
                let value = try #require(program.layout.variables.first { $0.declaration.name == "value" })
                let index = try #require(program.behavior.initializations.firstIndex { $0.variable == copy.id })
                guard case .value(let expression) = program.behavior.initializations[index].initialization else {
                    Issue.record("The dependent copy lost its value initializer")
                    return
                }
                let prefix = program.behavior.initializations[..<index]
                let declarations = lines.filter { $0.hasPrefix("__SwiftTLAInitialOverflowFailure\(copy.id.ordinal)(") }
                let declaration = try #require(declarations.count == 1 ? declarations[0] : nil)
                let separator = try #require(declaration.range(of: " == "))
                let header = String(declaration[..<separator.lowerBound])
                let relation = String(declaration[separator.upperBound...])
                let open = try #require(header.firstIndex(of: "("))
                let close = try #require(header.lastIndex(of: ")"))
                let operandsName = String(header[header.index(after: open)..<close])
                let pattern = try NSRegularExpression(
                    pattern: #"(?:LET|\\E) (__SwiftTLAInitialValue[0-9]+_*) (?:==|\\in)"#)
                let boundNames = pattern.matches(in: relation,
                    range: NSRange(relation.startIndex..<relation.endIndex, in: relation)).compactMap {
                    Range($0.range(at: 1), in: relation).map { String(relation[$0]) }
                }
                try #require(boundNames.count == prefix.count && Set(boundNames).count == boundNames.count)
                let names = Dictionary(uniqueKeysWithValues: zip(prefix.map(\.variable), boundNames))
                let renderer = CompiledTLARenderer(moduleName: program.moduleName,
                    reservedNames: [], layout: program.layout,
                    bindings: .init(binders: program.binderNames), operators: .init(),
                    actions: program.behavior.actions, functions: program.functions,
                    enums: program.enums, parameterDomains: program.behavior.parameterDomains)
                let failures = try renderer.expressionEvaluationFailures(expression, stateNames: names)
                let failure = try #require(failures.count == 1 ? failures[0] : nil)
                let operation = try #require(lines.first {
                    $0.hasPrefix("__SwiftTLAInitialOverflowOperation\(copy.id.ordinal) == ")
                })
                let aggregateName = "__SwiftTLAAnyInitialEvaluationFailure"
                let aggregate = try #require(lines.first { $0.hasPrefix("\(aggregateName) == ") })
                let selected = String(aggregate.dropFirst("\(aggregateName) == ".count))
                try #require(selected.hasPrefix("(") && selected.hasSuffix(")"))
                let selection = String(selected.dropFirst().dropLast())
                try StraightLineRenderedActionCheck.verifyInitialFailureAggregate(bundle.tla,
                    predicates: [selection], name: aggregateName)
                try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
                    after: prefix, names: names,
                    emitted: [(failure, relation, operandsName, selection, operation, nil)],
                    siteOrdinal: copy.id.ordinal, layout: program.layout)
                let bound = try #require(names[value.id])
                let typed = StraightLineRenderedActionCheck.initialIntStatePredicate(named: bound)
                try #require(relation.components(separatedBy: typed).count == 2
                    && selection.components(separatedBy: typed).count == 2)
                for (label, replacement) in [
                    ("widenedPrefix", "TRUE"),
                    ("narrowedPrefix", typed.replacingOccurrences(of: TLAValue.int(Int.max).description,
                        with: TLAValue.int(Int.max - 1).description)),
                ] {
                    let changedRelation = relation.replacingOccurrences(of: typed, with: replacement)
                    let changedSelection = selection.replacingOccurrences(of: typed, with: replacement)
                    try #require(changedRelation != relation && changedSelection != selection)
                    let changedModule = bundle.tla.replacingOccurrences(of: declaration,
                        with: "\(header) == \(changedRelation)").replacingOccurrences(of: aggregate,
                            with: "\(aggregateName) == (\(changedSelection))")
                    try #require(changedModule != bundle.tla)
                    try StraightLineRenderedActionCheck.verifyInitialFailureAggregate(changedModule,
                        predicates: [changedSelection], name: aggregateName)
                    do {
                        try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
                            after: prefix, names: names,
                            emitted: [(failure, changedRelation, operandsName, changedSelection, operation, nil)],
                            siteOrdinal: copy.id.ordinal, layout: program.layout)
                        Issue.record("Declared Int initial failure \(label) corruption accepted")
                    } catch let diagnostic as CompilationDiagnostic {
                        #expect(diagnostic.path == "tla.initialEvaluationFailures")
                    }
                }
            }
        }
        let unavailableConfiguration = try MathematicalIntegerDomainModel.Configuration(Values: [])
        do {
            let result = try MathematicalIntegerDomainModel.initialOutcomes(configuration: unavailableConfiguration)
            Issue.record("Native non-enumerable Int returned model outcomes: states=\(result.states.count), failure=\(String(describing: result.firstFailure)), initializer=\(String(describing: result.firstFailureInitializerOrdinal))")
        } catch let failure as NativeMachineEvaluationError {
            #expect(failure == .nonEnumerableIntegerDomain)
        }
        do {
            let result = try CompiledRuntime(compilation: MathematicalIntegerDomainModel.spec.compile()).initialOutcomes()
            Issue.record("Compiled non-enumerable Int returned model outcomes: states=\(result.states.count), failure=\(String(describing: result.firstFailure)), initializer=\(String(describing: result.firstFailureInitializerOrdinal))")
        } catch let failure as EvalError {
            #expect(failure == .nonEnumerableIntegerDomain)
        }

    }

    @Test("Integer membership and subsets do not enumerate Int")
    func membershipAndEnumeration() throws {
        for value in [Int.min, -1, 0, 1, Int.max] {
            #expect(try evaluateClosed(Int.all.contains(value).stateExpr) == .bool(true))
        }
        let values = Set<Int>([Int.min, 0, Int.max])
        #expect(try evaluateClosed(Subsets(of: Int.all).contains(values).stateExpr) == .bool(true))
        #expect(try evaluateClosed(values.isSubset(of: Int.all).stateExpr) == .bool(true))
        #expect(try evaluateClosed(Sequences(of: Int.all).contains(values.sorted()).stateExpr) == .bool(true))
        #expect(throws: EvalError.nonEnumerableIntegerDomain) { try evaluateClosed(Int.all.stateExpr) }
    }
}
