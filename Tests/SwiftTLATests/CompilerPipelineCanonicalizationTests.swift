import Testing
@testable import SwiftTLA
import SwiftTLAMacros

private struct CompilerPipelineMember: Identifiable, Sendable {
    let id: Int
}

@TLAModel
private struct CompilerPipelineGeneratedModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineGeneratedModel") {
            let counter = Var<Int>("counter")
            Variable(counter, 0)
            Action("increment") { counter.becomes(counter + 1) }
        }
    }
}

@TLAModel
private struct CompilerPipelineExplicitFormalNameModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineExplicitFormalName") {
            let counter = Var<Int>("counter", 0)
            Variable(counter)
            Action("increment") { counter.becomes(counter + 1) }
        }
    }
}

@TLAModel
private struct CompilerPipelineAlgorithmModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineAlgorithmModel") {
            Algorithm("CompilerPipelineAlgorithmModel") {
                let count = SharedVar(initial: 0)
                Do("increment") {
                    Assign(count, to: count + 1)
                }
            }
        }
    }
}

@TLAModel
private struct CompilerPipelineInitializationModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineInitializationModel") {
            let computed = Var<Int>("computed")
            let choice = Var<Int>("choice")
            Variable(computed: computed) { computed + 1 }
            Variable(from: choice.name, StateExpr.set([1, 2]))
            Action("stay") { computed.stays && choice.stays }
        }
    }
}

@TLAModel
private struct CompilerPipelineCollectionModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineCollectionModel") {
            let devices = SymmetricCollectionVar<CompilerPipelineMember, Int>("devices")
            SymmetricCollection(devices, verificationScope: 2, initial: 0)
            CollectionAction("advance", on: devices) { member in
                devices[member] == 0 && devices.update(member, to: 1)
            }
        }
    }
}

@Suite("Compiler pipeline canonicalization")
struct CompilerPipelineCanonicalizationTests {
    @Test("macro compilation uses the explicit formal module name")
    func macroUsesExplicitFormalModuleName() throws {
        let compilation = try CompilerPipelineExplicitFormalNameModel.compiledSpecification()

        #expect(compilation.spec.name == "CompilerPipelineExplicitFormalName")
        #expect(compilation.identity == try CompilerPipelineExplicitFormalNameModel.spec.compile().identity)
    }

    @Test("direct specifications retain one identity through runtime and checker")
    func directSpecificationUsesOneCompiledPayload() throws {
        let counter = Var<Int>("counter", 0)
        let spec = TLASpec("CanonicalCounter") {
            Variable(counter, 0)
            Action("increment") {
                counter.becomes(counter + 1)
            }
        }

        let compilation = try spec.compile()
        let runtime = SpecRuntime(compilation: compilation)
        let checker = ModelChecker(compilation: compilation, maxStates: 3)

        #expect(runtime.compilation?.identity == compilation.identity)
        #expect(checker.compilation?.identity == compilation.identity)
        #expect(try runtime.successors(.init(name: "increment"), from: ["counter": .int(0)]) == [["counter": .int(1)]])
        #expect(try checker.exploreGraph().states.count == 3)
    }

    @Test("#spec Algorithm lowering reaches macro-generated consumers through one identity")
    func algorithmSpecificationUsesMacroCompiledPayload() throws {
        let compilation = try CompilerPipelineAlgorithmModel.compiledSpecification()

        #expect(CompilerPipelineAlgorithmModel.runtime.compilation?.identity == compilation.identity)
        #expect(try CompilerPipelineAlgorithmModel.verifySpec() > 0)
        #expect(try CompilerPipelineAlgorithmModel.transitionMatrix().isEmpty == false)
        #expect(compilation.spec.tlaModule == CompilerPipelineAlgorithmModel.spec.tlaModule)
    }

    @Test("duplicate declarations fail with an actionable typed diagnostic")
    func duplicateVariableBlocksCompilation() {
        let spec = TLASpec(
            name: "Invalid",
            variables: [NamedVar(name: "value", initial: .int(0)), NamedVar(name: "value", initial: .int(1))],
            actions: [],
            invariants: []
        )

        #expect(throws: CompilationDiagnostic.self) {
            try spec.compile()
        }
    }

    @Test("macro-generated consumers and rendering retain the compiled identity")
    func macroGeneratedConsumersUseCompiledPayload() throws {
        let compilation = try CompilerPipelineGeneratedModel.compiledSpecification()

        #expect(CompilerPipelineGeneratedModel.runtime.compilation?.identity == compilation.identity)
        #expect(try CompilerPipelineGeneratedModel.verifySpec() > 0)
        #expect(try CompilerPipelineGeneratedModel.transitionMatrix().isEmpty == false)
        #expect(compilation.spec.tlaModule == CompilerPipelineGeneratedModel.spec.tlaModule)
    }

    @Test("#spec lowering preserves every canonical variable initialization field")
    func specMacroRetainsInitializationForms() throws {
        let compilation = try CompilerPipelineInitializationModel.compiledSpecification()
        let computed = try #require(compilation.spec.variables.first { $0.name == "computed" })
        let choice = try #require(compilation.spec.variables.first { $0.name == "choice" })

        #expect(computed.initExpr == .add(.variable("computed"), .int(1)))
        #expect(computed.lazySet == nil)
        #expect(choice.initExpr == nil)
        #expect(choice.lazySet == .setLiteral([.value(.int(1)), .value(.int(2))]))
        #expect(CompilerPipelineInitializationModel.runtime.compilation?.identity == compilation.identity)
    }

    @Test("#spec lowering preserves symmetric collection metadata")
    func specMacroRetainsSymmetricCollectionMetadata() throws {
        let compilation = try CompilerPipelineCollectionModel.compiledSpecification()
        let devices = try #require(compilation.spec.variables.first { $0.name == "devices" })
        let declaration = try #require(compilation.spec.symmetricCollections.first { $0.name == "devices" })

        #expect(devices.collectionType == .dictionary(2))
        #expect(declaration.variable == devices)
        #expect(declaration.verificationScope == 2)
        #expect(CompilerPipelineCollectionModel.runtime.compilation?.identity == compilation.identity)
    }

    @Test("semantic compilation fields change the identity")
    func semanticFieldsContributeToIdentity() throws {
        let base = TLASpec(
            name: "Fingerprint",
            variables: [NamedVar(name: "value", initial: .int(0))],
            actions: [NamedAction(name: "step", body: .assign("value", .int(1)))],
            invariants: []
        )
        let variants = [
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], checkDeadlock: true),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], theorems: ["Safety == TRUE"]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], recursiveDefs: ["CountDown(_)"]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], recursiveFuncs: [.init(name: "CountDown", params: ["n"], body: .variable("n"))]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], symmetryGroups: [.init(["value"])]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], symmetricCollections: [.init(name: "members", verificationScope: 1, initial: .int(0))]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], extendsModules: "Naturals")
        ]

        let identity = try base.compile().identity
        for variant in variants {
            #expect(try variant.compile().identity != identity)
        }
    }

    @Test("identity includes action domains, all initialisation forms, and imported semantics")
    func structuralFieldsContributeToIdentity() throws {
        let base = TLASpec(
            name: "StructuralFingerprint",
            variables: [NamedVar(name: "value", initial: .int(0))],
            actions: [NamedAction(name: "step", body: .assign("value", .int(1)), bindings: [
                .init(name: "choice", values: [.int(0), .int(1)])
            ])],
            invariants: []
        )
        let importedA = TLASpec(
            name: "Imported",
            variables: [NamedVar(name: "inner", initial: .int(0))],
            actions: [NamedAction(name: "stay", body: .unchanged("inner"))],
            invariants: []
        )
        let importedB = TLASpec(
            name: "Imported",
            variables: [NamedVar(name: "inner", initial: .int(1))],
            actions: [NamedAction(name: "stay", body: .unchanged("inner"))],
            invariants: []
        )
        let variants = [
            TLASpec(name: "StructuralFingerprint", variables: base.variables, actions: [
                .init(name: "step", body: .assign("value", .int(1)), bindings: [.init(name: "choice", values: [.int(0), .int(2)])])
            ], invariants: []),
            TLASpec(name: "StructuralFingerprint", variables: [
                .init(name: "value", initial: .int(0), initExpr: .value(.int(1)))
            ], actions: base.actions, invariants: []),
            TLASpec(name: "StructuralFingerprint", variables: [
                .init(name: "value", initial: .int(0), collectionType: .dictionary(2))
            ], actions: base.actions, invariants: []),
            TLASpec(name: "StructuralFingerprint", variables: base.variables, actions: base.actions, invariants: [], imports: [importedA]),
            TLASpec(name: "StructuralFingerprint", variables: base.variables, actions: base.actions, invariants: [], imports: [importedB])
        ]

        let identity = try base.compile().identity
        for variant in variants {
            #expect(try variant.compile().identity != identity)
        }
        #expect(try variants[3].compile().identity != variants[4].compile().identity)
    }

    @Test("nested set values with separator-bearing strings have distinct identities")
    func separatorBearingSetValuesDoNotCollide() throws {
        let splitValues = TLASpec(
            name: "SeparatorCollision",
            variables: [
                NamedVar(name: "value", initial: .set([.string("a"), .string("b")]))
            ],
            actions: [],
            invariants: []
        )
        let embeddedSeparator = TLASpec(
            name: "SeparatorCollision",
            variables: [
                NamedVar(name: "value", initial: .set([.string("a\u{1E}string|b")]))
            ],
            actions: [],
            invariants: []
        )

        #expect(try splitValues.compile().identity != embeddedSeparator.compile().identity)
    }
}
