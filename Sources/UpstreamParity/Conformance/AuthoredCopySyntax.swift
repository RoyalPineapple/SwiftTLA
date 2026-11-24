import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

// Read the same scoped Algorithm for copy binding and sequential-control evidence.
enum AuthoredCopySyntax {
    struct Selection {
        fileprivate let members: MemberBlockItemListSyntax
        let algorithm: String
        fileprivate let scope: String
        fileprivate let capturedRoots: [String: String]
        fileprivate let body: CodeBlockItemListSyntax
        fileprivate let sourceStart: Int
        fileprivate let declaration: TokenSyntax
        fileprivate let registration: TokenSyntax
        fileprivate let hasExplicitCapture: Bool
    }

    private struct Label: Hashable {
        let enumName: String
        let caseName: String
    }

    private static func specification(source: String, modelName: String, requiringModuleName: Bool = false) throws
        -> (MemberBlockItemListSyntax, ClosureExprSyntax) {
        let file = Parser.parse(source: source)
        let models = file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .filter { name($0.name) == modelName }
        guard !file.hasError, models.count == 1, let model = models.first else { throw unsupported }
        let members = model.memberBlock.members
        guard let spec = try ModelSpecificationSyntax.find(in: members, defaultName: modelName),
              !requiringModuleName || spec.name.utf8.elementsEqual(modelName.utf8) else {
            throw unsupported
        }
        return (members, spec.closure)
    }

    static func select(source: String, modelName: String) throws -> Selection {
        try select(source: source, modelName: modelName, includingCapturedRoots: false)
    }

    private static func select(source: String, modelName: String, includingCapturedRoots: Bool) throws -> Selection {
        let (members, specBody) = try specification(source: source, modelName: modelName)
        var bindings: [String: (declaration: TokenSyntax, call: FunctionCallExprSyntax)] = [:]
        var selected: (name: String, declaration: TokenSyntax, registration: TokenSyntax, call: FunctionCallExprSyntax)?
        for item in specBody.statements {
            if let (declaration, value) = letBindingTokens(item), let call = value.as(FunctionCallExprSyntax.self),
               reference(call.calledExpression) == "Algorithm" {
                guard bindings.updateValue((declaration, call), forKey: name(declaration)) == nil else { throw unsupported }
            } else if let registration = referenceToken(item.item.as(ExprSyntax.self)),
                      let (declaration, call) = bindings[name(registration)] {
                guard selected == nil else { throw unsupported }
                selected = (name(registration), declaration, registration, call)
            }
        }
        guard let selected, let body = ModelSpecificationSyntax.algorithmBody(selected.call) else { throw unsupported }
        let parameters = ModelSpecificationSyntax.parameterNames(in: body)
        let specParameters = ModelSpecificationSyntax.parameterNames(in: specBody)
        let scope: String
        var capturedRoots: [String: String] = [:]
        if parameters.count == 1, let parameter = parameters.first {
            scope = parameter
        } else if includingCapturedRoots, body.signature == nil,
                  specParameters.count == 1, let specScope = specParameters.first {
            scope = specScope
            for item in specBody.statements where item.position.utf8Offset < selected.declaration.position.utf8Offset {
                if let (binding, explicit) = try rootDeclaration(item, in: specScope) {
                    guard capturedRoots.updateValue(explicit ?? binding, forKey: binding) == nil else { throw unsupported }
                }
            }
        } else {
            throw unsupported
        }
        return Selection(members: members, algorithm: selected.name, scope: scope, capturedRoots: capturedRoots,
            body: body.statements,
            sourceStart: specBody.positionAfterSkippingLeadingTrivia.utf8Offset,
            declaration: selected.declaration, registration: selected.registration,
            hasExplicitCapture: specBody.signature?.capture != nil || body.signature?.capture != nil)
    }

    static func proofInputs(_ selection: Selection, comparingParsedRows: Bool = false,
                            lexicalSource: DirectCopyLexicalSource? = nil, authoredBytes: [UInt8] = [],
                            expectedFields: Set<String>? = nil) throws -> String {
        guard comparingParsedRows == (lexicalSource != nil),
              comparingParsedRows == (expectedFields != nil) else { throw unsupported }
        let events = lexicalSource?.events
        func matchesSpan(_ span: DirectCopyLexicalSource.Span, _ syntax: some SyntaxProtocol) -> Bool {
            let start = syntax.positionAfterSkippingLeadingTrivia.utf8Offset
            let end = syntax.endPositionBeforeTrailingTrivia.utf8Offset
            return start >= selection.sourceStart && end >= start && end <= authoredBytes.count
                && span.offset == start - selection.sourceStart && span.length == end - start
                && authoredBytes[start..<end].elementsEqual(syntax.trimmedDescription.utf8)
        }
        func matches(_ observed: DirectCopyLexicalSource.Token, _ token: TokenSyntax) -> Bool {
            observed.name.utf8.elementsEqual(name(token).utf8) && matchesSpan(observed.span, token)
        }
        if let lexicalSource {
            guard !selection.hasExplicitCapture, events?.count == selection.body.count,
                  matches(lexicalSource.algorithm, selection.declaration),
                  matches(lexicalSource.registration, selection.registration),
                  lexicalSource.algorithm.name.utf8.elementsEqual(lexicalSource.registration.name.utf8)
            else { throw unsupported }
        }
        let fields = comparingParsedRows ? "ParsedCopyFields" : "WitnessCopyFields"
        let rows = comparingParsedRows ? "ParsedCopyActionRows" : "WitnessCopyActionRows"
        let lexicalTheorem = comparingParsedRows ? "AuthoredCopySyntaxBindsParsedRows" : "AuthoredCopySyntaxBindsWitnessRows"
        var declarations: [String] = []
        var localBindings: Set<[UInt8]> = []
        var steps: [String] = []
        var enumNames: Set<String> = []
        var operations: [String] = []
        var rootsByBinding: [[UInt8]: String] = [:]
        var sharedRoots: Set<[UInt8]> = []
        var lexicalDeclarations: [String] = []
        func appendLexicalRoot(_ binding: String, root: String) {
            rootsByBinding[Array(binding.utf8)] = root
            lexicalDeclarations.append("[binding |-> \(TLAValue.string(binding)), explicit |-> \(optionalLiteral(root))]")
        }
        for (index, item) in selection.body.enumerated() {
            let event = events?[index]
            if let (binding, explicit) = try rootDeclaration(item, in: selection.scope) {
                guard localBindings.insert(Array(binding.utf8)).inserted else { throw unsupported }
                if let event {
                    guard case .shared(let observed, let override) = event,
                          let (token, value) = letBindingTokens(item), matches(observed, token),
                          let call = value.as(FunctionCallExprSyntax.self) else { throw unsupported }
                    let explicitSyntax = call.arguments.first(where: { $0.label?.text == "_name" })?.expression
                    if let override {
                        guard let explicitSyntax, let explicit, override.value.utf8.elementsEqual(explicit.utf8),
                              matchesSpan(override.span, explicitSyntax) else { throw unsupported }
                    } else if explicitSyntax != nil { throw unsupported }
                    operations.append("[kind |-> \"shared\", binding |-> \(TLAValue.string(binding)), "
                                      + "explicit |-> \(optionalLiteral(explicit)), readBinding |-> \"\"]")
                    let root = explicit ?? binding
                    guard sharedRoots.insert(Array(root.utf8)).inserted else { throw unsupported }
                    appendLexicalRoot(binding, root: root)
                }
                declarations.append("[binding |-> \(TLAValue.string(binding)), explicit |-> \(optionalLiteral(explicit))]")
                continue
            }
            if case .alias(let observed, let read)? = event {
                guard let (token, value) = letBindingTokens(item), let rhs = referenceToken(value),
                      matches(observed, token), matches(read, rhs),
                      let root = rootsByBinding[Array(name(rhs).utf8)],
                      localBindings.insert(Array(name(token).utf8)).inserted else { throw unsupported }
                operations.append("[kind |-> \"alias\", binding |-> \(TLAValue.string(name(token))), "
                                  + "explicit |-> \(optionalLiteral(nil)), readBinding |-> \(TLAValue.string(name(rhs)))]")
                appendLexicalRoot(name(token), root: root)
                continue
            }
            guard let call = item.item.as(FunctionCallExprSyntax.self), reference(call.calledExpression) == "Do",
                  call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
                  let label = labelReference(argument.expression),
                  call.additionalTrailingClosures.isEmpty,
                  let body = call.trailingClosure, !body.statements.isEmpty else { throw unsupported }
            let observedCopies: [DirectCopyLexicalSource.Copy]?
            if let event {
                guard body.signature?.capture == nil,
                      case .step(let observed, let copies) = event, copies.count == body.statements.count,
                      let access = argument.expression.as(MemberAccessExprSyntax.self),
                      let owner = referenceToken(access.base),
                      matches(observed.enumName, owner), matches(observed.caseName, access.declName.baseName)
                else { throw unsupported }
                observedCopies = copies
            } else {
                observedCopies = nil
            }
            let copies = try body.statements.enumerated().map { (position, statement) -> String in
                guard let assign = statement.item.as(FunctionCallExprSyntax.self), reference(assign.calledExpression) == "Assign",
                      assign.trailingClosure == nil, assign.additionalTrailingClosures.isEmpty,
                      assign.arguments.count == 2, let target = assign.arguments.first, target.label == nil,
                      let read = assign.arguments.last, read.label?.text == "to",
                      let targetName = reference(target.expression), let readName = reference(read.expression),
                      localBindings.contains(Array(targetName.utf8)),
                      localBindings.contains(Array(readName.utf8)) else { throw unsupported }
                if let observed = observedCopies?[position] {
                    guard let targetToken = referenceToken(target.expression), let readToken = referenceToken(read.expression),
                          matches(observed.target, targetToken), matches(observed.read, readToken) else { throw unsupported }
                }
                return "[targetBinding |-> \(TLAValue.string(targetName)), readBinding |-> \(TLAValue.string(readName))]"
            }
            enumNames.insert(label.enumName)
            let visibility = comparingParsedRows ? ", visible |-> \(operations.count)" : ""
            steps.append("[enumName |-> \(TLAValue.string(label.enumName)), caseName |-> \(TLAValue.string(label.caseName)), copies |-> \(tuple(copies))\(visibility)]")
        }
        guard !declarations.isEmpty, !steps.isEmpty else { throw unsupported }
        if let expectedFields, sharedRoots != Set(expectedFields.map { Array($0.utf8) }) { throw unsupported }
        let enumCases = try enumBindings(in: selection.members, named: enumNames).map { label, explicit in
            "[enumName |-> \(TLAValue.string(label.enumName)), caseName |-> \(TLAValue.string(label.caseName)), explicit |-> \(optionalLiteral(explicit))]"
        }
        let orderedDeclarations = comparingParsedRows ? "\nAuthoredCopyDeclarationOrder == \(tuple(declarations))" : ""
        let lexicalInput = comparingParsedRows ? """
            LOCAL DirectParser == INSTANCE DirectCopyLexicalRule
            LOCAL CopyHistories == INSTANCE IndexedHistoryRules
            AuthoredCopyLexicalOperations == \(tuple(operations))
            LOCAL AuthoredCopyLexicalDeclarations == \(tuple(lexicalDeclarations))
            \(Self.copyLexicalProof)

            """ : ""
        let sourceDeclarations = comparingParsedRows
            ? "{AuthoredCopyLexicalDeclarations[index] : index \\in DOMAIN AuthoredCopyLexicalDeclarations}"
            : set(declarations)
        let sourceDeclarationDefinition = comparingParsedRows ? ", AuthoredCopyLexicalDeclarations" : ""
        let syntaxProof = #"""
        \#(lexicalInput)AuthoredCopyDeclarations == \#(sourceDeclarations)
        AuthoredCopyEnumCases == \#(set(enumCases))
        AuthoredCopySteps == \#(tuple(steps))\#(orderedDeclarations)

        LOCAL NameOrSpelling(explicit, spelling) == IF explicit.present THEN explicit.value ELSE spelling
        LOCAL VariableNames(rows) == {NameOrSpelling(row.explicit, row.binding) : row \in rows}
        LOCAL BindingNames(binding) == VariableNames({row \in AuthoredCopyDeclarations : row.binding = binding})
        LOCAL LabelNames(step) ==
            {NameOrSpelling(row.explicit, row.caseName) : row \in
                {entry \in AuthoredCopyEnumCases : entry.enumName = step.enumName /\ entry.caseName = step.caseName}}
        LOCAL Single(values) == CHOOSE value \in values : TRUE

        AuthoredCopyFields == VariableNames(AuthoredCopyDeclarations)
        AuthoredCopyOrigins ==
            [binding \in {row.binding : row \in AuthoredCopyDeclarations} |-> Single(BindingNames(binding))]
        LOCAL CopyTargets(copies) == {copies[index].target : index \in DOMAIN copies}
        LOCAL ResolveCopy(copy) ==
            [target |-> Single(BindingNames(copy.targetBinding)), read |-> Single(BindingNames(copy.readBinding))]
        LOCAL ResolveCopies(step) == [index \in DOMAIN step.copies |-> ResolveCopy(step.copies[index])]
        LOCAL ResolveStep(step) ==
            [label |-> Single(LabelNames(step)), copies |-> ResolveCopies(step),
             frame |-> AuthoredCopyFields \ CopyTargets(ResolveCopies(step))]
        AuthoredCopyActionRows == [index \in DOMAIN AuthoredCopySteps |-> ResolveStep(AuthoredCopySteps[index])]

        THEOREM AuthoredCopySyntaxSuppliesTypedSchedulerInput ==
            /\ AuthoredCopyOrigins \in [DOMAIN AuthoredCopyOrigins -> AuthoredCopyFields]
            /\ \A row \in DOMAIN AuthoredCopySteps :
                LET raw == AuthoredCopySteps[row].copies
                    copies == AuthoredCopyActionRows[row].copies
                IN /\ Len(raw) \in Nat \ {0}
                   /\ DOMAIN raw = 1..Len(raw)
                   /\ copies = [position \in DOMAIN raw |-> copies[position]]
                   /\ \A position \in DOMAIN raw :
                          /\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                          /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins
                          /\ copies[position] =
                              [target |-> AuthoredCopyOrigins[raw[position].targetBinding],
                               read |-> AuthoredCopyOrigins[raw[position].readBinding]]
        PROOF
        <1>declarations. \A left, right \in AuthoredCopyDeclarations :
            left.binding = right.binding => left = right
            BY ONLY SMT DEF AuthoredCopyDeclarations\#(sourceDeclarationDefinition)
        <1>. DEFINE schedulerDeclarations == \#(set(comparingParsedRows ? lexicalDeclarations : declarations))
        <1>declarationSet. AuthoredCopyDeclarations = schedulerDeclarations
            BY ONLY SMT DEF AuthoredCopyDeclarations, schedulerDeclarations\#(sourceDeclarationDefinition)
        <1>originDomain. DOMAIN AuthoredCopyOrigins = {row.binding : row \in schedulerDeclarations}
            BY ONLY <1>declarationSet, SMT DEF AuthoredCopyOrigins
        <1>roots. \A binding \in DOMAIN AuthoredCopyOrigins :
            \E root \in AuthoredCopyFields : BindingNames(binding) = {root}
            <2>. TAKE binding \in DOMAIN AuthoredCopyOrigins
            <2>origin. PICK declaration \in AuthoredCopyDeclarations : declaration.binding = binding
                BY ONLY (binding \in DOMAIN AuthoredCopyOrigins), <1>originDomain, <1>declarationSet, SMT
            <2>. DEFINE root == NameOrSpelling(declaration.explicit, declaration.binding)
            <2>field. root \in AuthoredCopyFields
                BY ONLY <2>origin, SMT DEF root, AuthoredCopyFields, VariableNames
            <2>singleton. BindingNames(binding) = {root}
                <3>unique. \A other \in AuthoredCopyDeclarations : other.binding = binding => other = declaration
                    BY ONLY <2>origin, <1>declarations, SMT
                <3>member. \A value : value \in BindingNames(binding) <=> value \in {root}
                    BY ONLY <2>origin, <3>unique, SMT DEF BindingNames, VariableNames, root
                <3>. QED BY ONLY <3>member, SetExtensionality, Zenon
            <2>. QED BY ONLY <2>field, <2>singleton, Zenon
        <1>bindings. \A binding \in DOMAIN AuthoredCopyOrigins :
            AuthoredCopyOrigins[binding] \in AuthoredCopyFields
            BY ONLY <1>roots, SMT DEF AuthoredCopyOrigins, Single
        <1>typed. AuthoredCopyOrigins \in [DOMAIN AuthoredCopyOrigins -> AuthoredCopyFields]
            BY ONLY <1>bindings, SMT DEF AuthoredCopyOrigins
        <1>raw. \A row \in DOMAIN AuthoredCopySteps :
            LET raw == AuthoredCopySteps[row].copies
            IN /\ Len(raw) \in Nat \ {0}
               /\ DOMAIN raw = 1..Len(raw)
               /\ \A position \in DOMAIN raw :
                      /\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                      /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins
            <2>size. \A row \in DOMAIN AuthoredCopySteps :
                LET raw == AuthoredCopySteps[row].copies
                IN Len(raw) \in Nat \ {0} /\ DOMAIN raw = 1..Len(raw)
                BY ONLY SMT DEF AuthoredCopySteps
            <2>references. \A row \in DOMAIN AuthoredCopySteps :
                \A position \in DOMAIN AuthoredCopySteps[row].copies :
                    /\ AuthoredCopySteps[row].copies[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                    /\ AuthoredCopySteps[row].copies[position].readBinding \in DOMAIN AuthoredCopyOrigins
                BY ONLY <1>originDomain, SMT DEF AuthoredCopySteps, schedulerDeclarations
            <2>. QED BY ONLY <2>size, <2>references, SMT
        <1>rows. \A row \in DOMAIN AuthoredCopySteps :
            LET raw == AuthoredCopySteps[row].copies
                copies == AuthoredCopyActionRows[row].copies
            IN /\ copies = [position \in DOMAIN raw |-> copies[position]]
               /\ \A position \in DOMAIN raw :
                    (/\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                     /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins)
                    => copies[position] =
                          [target |-> AuthoredCopyOrigins[raw[position].targetBinding],
                           read |-> AuthoredCopyOrigins[raw[position].readBinding]]
            <2>. TAKE row \in DOMAIN AuthoredCopySteps
            <2>. DEFINE raw == AuthoredCopySteps[row].copies
                        copies == AuthoredCopyActionRows[row].copies
            <2>row. AuthoredCopyActionRows[row] = ResolveStep(AuthoredCopySteps[row])
                BY ONLY (row \in DOMAIN AuthoredCopySteps), SMT DEF AuthoredCopyActionRows
            <2>function. copies = [position \in DOMAIN raw |-> ResolveCopy(raw[position])]
                BY ONLY <2>row, SMT DEF copies, raw, ResolveStep, ResolveCopies
            <2>shape. copies = [position \in DOMAIN raw |-> copies[position]]
                BY ONLY <2>function, SMT
            <2>operands. \A position \in DOMAIN raw :
                ( /\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                  /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins)
                => copies[position] =
                    [target |-> AuthoredCopyOrigins[raw[position].targetBinding],
                     read |-> AuthoredCopyOrigins[raw[position].readBinding]]
                <3>. TAKE position \in DOMAIN raw
                <3>. DEFINE item == raw[position]
                <3>pair. copies[position] = ResolveCopy(item)
                    BY ONLY <2>function, (position \in DOMAIN raw), SMT DEF item
                <3>. QED BY ONLY <3>pair, SMT DEF item, ResolveCopy, AuthoredCopyOrigins
            <2>. QED BY ONLY <2>shape, <2>operands, SMT DEF raw, copies
        <1>. QED BY ONLY <1>typed, <1>raw, <1>rows, SMT

        LOCAL CopyNamesBind(raw, copy) ==
            /\ BindingNames(raw.targetBinding) = {copy.target}
            /\ BindingNames(raw.readBinding) = {copy.read}
            /\ copy = [target |-> copy.target, read |-> copy.read]

        LOCAL RowBindings(raw, witness) ==
            /\ LabelNames(raw) = {witness.label}
            /\ DOMAIN raw.copies = DOMAIN witness.copies
            /\ \A index \in DOMAIN witness.copies : CopyNamesBind(raw.copies[index], witness.copies[index])
            /\ AuthoredCopyFields \ CopyTargets(witness.copies) = witness.frame

        LOCAL CopyFunction(copies) == [index \in DOMAIN copies |-> copies[index]]
        LOCAL FunctionShapedStep(witness) ==
            [label |-> witness.label, copies |-> CopyFunction(witness.copies), frame |-> witness.frame]

        THEOREM LexicalBindingsDetermineTheOrderedCopyStep ==
            ASSUME NEW raw, NEW witness, RowBindings(raw, witness)
            PROVE ResolveStep(raw) = FunctionShapedStep(witness)
        PROOF
        <1>. DEFINE copies == witness.copies
        <1>label. Single(LabelNames(raw)) = witness.label BY SMT DEF RowBindings, Single
        <1>domains. DOMAIN ResolveCopies(raw) = DOMAIN copies BY SMT DEF RowBindings, ResolveCopies, copies
        <1>bindings. \A index \in DOMAIN copies : ResolveCopies(raw)[index] = copies[index]
            <2>. SUFFICES ASSUME NEW index \in DOMAIN copies
                         PROVE ResolveCopies(raw)[index] = copies[index]
                OBVIOUS
            <2>copy. CopyNamesBind(raw.copies[index], copies[index]) BY SMT DEF RowBindings, copies
            <2>names. /\ Single(BindingNames(raw.copies[index].targetBinding)) = copies[index].target
                      /\ Single(BindingNames(raw.copies[index].readBinding)) = copies[index].read
                BY ONLY <2>copy, SMT DEF CopyNamesBind, Single
            <2>. QED BY <2>copy, <2>names, SMT DEF RowBindings, CopyNamesBind, ResolveCopies, ResolveCopy, copies
        <1>rows. ResolveCopies(raw) = CopyFunction(copies)
            BY ONLY <1>domains, <1>bindings, SMT DEF ResolveCopies, CopyFunction
        <1>targets. CopyTargets(CopyFunction(copies)) = CopyTargets(copies)
            BY ONLY SMT DEF CopyFunction, CopyTargets
        <1>. QED BY <1>label, <1>rows, <1>targets, SMT DEF ResolveStep, FunctionShapedStep, RowBindings, copies

        THEOREM \#(lexicalTheorem) ==
            /\ AuthoredCopyFields = \#(fields)
            /\ AuthoredCopyActionRows = \#(rows)
            /\ \A left, right \in DOMAIN AuthoredCopyActionRows :
                 left # right => AuthoredCopyActionRows[left].label # AuthoredCopyActionRows[right].label
        PROOF
        <1>fields. AuthoredCopyFields = \#(fields)
            BY ONLY SMT DEF AuthoredCopyFields, AuthoredCopyDeclarations\#(sourceDeclarationDefinition), VariableNames, NameOrSpelling, \#(fields)
        <1>domain. DOMAIN AuthoredCopyActionRows = DOMAIN \#(rows)
            BY ONLY SMT DEF AuthoredCopyActionRows, AuthoredCopySteps, \#(rows)
        <1>points. \A row \in DOMAIN \#(rows) :
            AuthoredCopyActionRows[row] = \#(rows)[row]
            PROOF
            <2>. SUFFICES ASSUME NEW row \in DOMAIN \#(rows)
                         PROVE AuthoredCopyActionRows[row] = \#(rows)[row]
                OBVIOUS
            <2>. DEFINE raw == AuthoredCopySteps[row]
                        witness == \#(rows)[row]
            <2>label. LabelNames(raw) = {witness.label}
                BY ONLY (row \in DOMAIN \#(rows)), SMT
                    DEF raw, witness, AuthoredCopySteps, \#(rows),
                        LabelNames, NameOrSpelling, AuthoredCopyEnumCases
            <2>count. DOMAIN raw.copies = DOMAIN witness.copies
                BY ONLY (row \in DOMAIN \#(rows)), SMT
                    DEF raw, witness, AuthoredCopySteps, \#(rows)
            <2>all. \A index \in DOMAIN witness.copies : CopyNamesBind(raw.copies[index], witness.copies[index])
                PROOF
                <3>. SUFFICES ASSUME NEW index \in DOMAIN witness.copies
                             PROVE CopyNamesBind(raw.copies[index], witness.copies[index])
                    OBVIOUS
                <3>target. BindingNames(raw.copies[index].targetBinding) = {witness.copies[index].target}
                    BY ONLY (row \in DOMAIN \#(rows)), (index \in DOMAIN witness.copies), SMT
                        DEF raw, witness, AuthoredCopySteps, \#(rows), BindingNames,
                            VariableNames, NameOrSpelling, AuthoredCopyDeclarations\#(sourceDeclarationDefinition)
                <3>read. BindingNames(raw.copies[index].readBinding) = {witness.copies[index].read}
                    BY ONLY (row \in DOMAIN \#(rows)), (index \in DOMAIN witness.copies), SMT
                        DEF raw, witness, AuthoredCopySteps, \#(rows), BindingNames,
                            VariableNames, NameOrSpelling, AuthoredCopyDeclarations\#(sourceDeclarationDefinition)
                <3>shape. witness.copies[index] =
                    [target |-> witness.copies[index].target, read |-> witness.copies[index].read]
                    BY ONLY (row \in DOMAIN \#(rows)), (index \in DOMAIN witness.copies), SMT
                        DEF witness, \#(rows)
                <3>. QED BY ONLY <3>target, <3>read, <3>shape DEF CopyNamesBind
            <2>frame. AuthoredCopyFields \ CopyTargets(witness.copies) = witness.frame
                BY ONLY (row \in DOMAIN \#(rows)), <1>fields, SMT
                    DEF witness, \#(rows), \#(fields), CopyTargets
            <2>bindings. RowBindings(raw, witness)
                BY ONLY <2>label, <2>count, <2>all, <2>frame DEF RowBindings
            <2>resolved. ResolveStep(raw) = FunctionShapedStep(witness)
                BY ONLY <2>bindings, LexicalBindingsDetermineTheOrderedCopyStep, SMT
            <2>shape. FunctionShapedStep(witness) = witness
                BY ONLY (row \in DOMAIN \#(rows)), SMT
                    DEF FunctionShapedStep, CopyFunction, witness, \#(rows)
            <2>. QED BY ONLY (row \in DOMAIN \#(rows)), <1>domain, <2>resolved, <2>shape, SMT
                DEF AuthoredCopyActionRows, AuthoredCopySteps, raw, witness, \#(rows)
        <1>functions. AuthoredCopyActionRows = CopyFunction(\#(rows))
            BY ONLY <1>domain, <1>points, SMT DEF AuthoredCopyActionRows, CopyFunction
        <1>rows. AuthoredCopyActionRows = \#(rows)
            BY ONLY <1>functions, SMT DEF CopyFunction, \#(rows)
        <1>labels. \A left, right \in DOMAIN \#(rows) :
                     left # right => \#(rows)[left].label # \#(rows)[right].label
            BY ONLY SMT DEF \#(rows)
        <1>. QED BY ONLY <1>fields, <1>rows, <1>labels, SMT
        """#
        return comparingParsedRows
            ? [syntaxProof, copyParserProof, copyBuilderProof, copyFrontendProof].joined(separator: "\n\n")
            : syntaxProof
    }

    private static let copyLexicalProof = #"""
        LOCAL CandidateCopyLexicalRoots ==
            [index \in DOMAIN AuthoredCopyLexicalDeclarations |-> AuthoredCopyLexicalDeclarations[index].explicit.value]
        LOCAL MaterializedCopyLexicalDeclarations ==
            DirectParser!CopyLexicalDeclarations(AuthoredCopyLexicalOperations)

        THEOREM AuthoredCopyLexicalOperationsAreWellBound ==
            DirectParser!CopyLexicalOperationsAreWellBound(AuthoredCopyLexicalOperations)
            BY ONLY SMT DEF DirectParser!CopyLexicalOperationsAreWellBound, DirectParser!ParserSequence,
                AuthoredCopyLexicalOperations

        THEOREM AuthoredCopyBindingsAreTheMaterializedLexicalDeclarations ==
            MaterializedCopyLexicalDeclarations = AuthoredCopyLexicalDeclarations
        PROOF
        <1>. DEFINE chosen == DirectParser!CopyLexicalRoots(AuthoredCopyLexicalOperations)
                    fields == DirectParser!CopySharedRoots(AuthoredCopyLexicalOperations)
                    count == Len(AuthoredCopyLexicalOperations)
        <1>shape. /\ count \in Nat
                   /\ DOMAIN AuthoredCopyLexicalOperations = 1..count
                   /\ DOMAIN AuthoredCopyLexicalDeclarations = 1..count
            BY ONLY SMT DEF count, AuthoredCopyLexicalOperations, AuthoredCopyLexicalDeclarations
        <1>types. /\ CandidateCopyLexicalRoots \in [1..count -> fields]
                   /\ chosen \in [1..count -> fields]
            <2>observed. CandidateCopyLexicalRoots \in [1..count -> fields]
                BY ONLY <1>shape, SMT
                    DEF CandidateCopyLexicalRoots, AuthoredCopyLexicalDeclarations, fields,
                        AuthoredCopyLexicalOperations, DirectParser!CopySharedRoots,
                        DirectParser!ParserRoot, DirectParser!ParserName
            <2>rule. chosen \in [1..count -> fields]
                BY ONLY AuthoredCopyLexicalOperationsAreWellBound,
                    DirectParser!EveryWellBoundLexicalListProducesARootHistory, SMT
                    DEF DirectParser!CopyLexicalRootHistory, chosen, fields, count
            <2>. QED BY ONLY <2>observed, <2>rule
        <1>steps. \A index \in 1..count :
            (\A prior \in 1..(index - 1) : CandidateCopyLexicalRoots[prior] = chosen[prior])
            => CandidateCopyLexicalRoots[index] = chosen[index]
            <2>. TAKE index \in 1..count
            <2>. DEFINE op == AuthoredCopyLexicalOperations[index]
            <2>where. index \in DOMAIN AuthoredCopyLexicalOperations
                BY ONLY (index \in 1..count), <1>shape
            <2>meaning. /\ (op.kind = "shared" => chosen[index] = DirectParser!ParserRoot(op))
                        /\ (op.kind = "alias" =>
                                chosen[index] = chosen[DirectParser!CopyAliasSource(AuthoredCopyLexicalOperations, index)])
                BY ONLY <2>where, AuthoredCopyLexicalOperationsAreWellBound,
                    DirectParser!TheAliasHistoryUsesTheActualEarlierRoot, SMT DEF chosen, op
            <2>. SUFFICES ASSUME \A prior \in 1..(index - 1) : CandidateCopyLexicalRoots[prior] = chosen[prior]
                         PROVE CandidateCopyLexicalRoots[index] = chosen[index]
                OBVIOUS
            <2>shared. CASE op.kind = "shared"
                <3>root. CandidateCopyLexicalRoots[index] = DirectParser!ParserRoot(op)
                    BY ONLY <2>where, <2>shared, SMT DEF op, CandidateCopyLexicalRoots, AuthoredCopyLexicalDeclarations,
                        AuthoredCopyLexicalOperations, DirectParser!ParserRoot, DirectParser!ParserName
                <3>. QED BY ONLY <2>shared, <2>meaning, <3>root
            <2>alias. CASE op.kind = "alias"
                <3>. DEFINE prior == DirectParser!CopyAliasSource(AuthoredCopyLexicalOperations, index)
                <3>earlier. /\ prior \in 1..(index - 1)
                             /\ AuthoredCopyLexicalOperations[prior].binding = op.readBinding
                    BY ONLY <2>where, <2>alias, AuthoredCopyLexicalOperationsAreWellBound,
                        DirectParser!CopyAliasNamesExactlyOneVisibleSource, SMT DEF prior, op
                <3>root. CandidateCopyLexicalRoots[index] = CandidateCopyLexicalRoots[prior]
                    BY ONLY <2>where, <2>alias, <3>earlier, <1>shape, SMT
                        DEF op, CandidateCopyLexicalRoots, AuthoredCopyLexicalDeclarations,
                            AuthoredCopyLexicalOperations, count
                <3>. QED BY ONLY <2>alias, <2>meaning, <3>earlier, <3>root,
                    (\A earlier \in 1..(index - 1) : CandidateCopyLexicalRoots[earlier] = chosen[earlier]), SMT DEF prior
            <2>. QED BY ONLY <2>where, AuthoredCopyLexicalOperationsAreWellBound,
                <2>shared, <2>alias, SMT DEF DirectParser!CopyLexicalOperationsAreWellBound, op
        <1>roots. CandidateCopyLexicalRoots = chosen
            BY ONLY <1>shape, <1>types, <1>steps, CopyHistories!FiniteIndexedHistoriesAgree, SMT
        <1>declarations. \A index \in 1..count :
            AuthoredCopyLexicalDeclarations[index] =
                [binding |-> AuthoredCopyLexicalOperations[index].binding,
                 explicit |-> [present |-> TRUE, value |-> CandidateCopyLexicalRoots[index]]]
            BY ONLY <1>shape, SMT
                DEF CandidateCopyLexicalRoots, AuthoredCopyLexicalDeclarations, AuthoredCopyLexicalOperations
        <1>. QED BY ONLY <1>shape, <1>roots, <1>declarations, SMT
            DEF MaterializedCopyLexicalDeclarations, DirectParser!CopyLexicalDeclarations, chosen,
                AuthoredCopyLexicalDeclarations
        """#

    private static let copyParserProof = #"""
        LOCAL ConstructedCopyRows ==
            DirectParser!ParserCopyRows(<<>>, MaterializedCopyLexicalDeclarations, AuthoredCopyEnumCases, AuthoredCopySteps)
        LOCAL ConstructedCopyFields == DirectParser!ParserCopyFields(MaterializedCopyLexicalDeclarations)

        THEOREM ActualParserRowsHaveAuthoredLexicalConstruction ==
            /\ DirectParser!WellBoundDirectCopySyntax(MaterializedCopyLexicalDeclarations, AuthoredCopyEnumCases, AuthoredCopySteps)
            /\ ParsedCopyFields = ConstructedCopyFields
            /\ ParsedCopyActionRows = ConstructedCopyRows
            /\ DOMAIN ParsedCopyActionRows = DOMAIN AuthoredCopySteps
        PROOF
        <1>rawScope. DirectParser!WellBoundDirectCopySyntax(
                AuthoredCopyLexicalOperations, AuthoredCopyEnumCases, AuthoredCopySteps)
            BY ONLY SMT DEF DirectParser!WellBoundDirectCopySyntax, DirectParser!ParserSequence,
                DirectParser!DeclaredCopyBindings, DirectParser!RegisteredParserCases,
                AuthoredCopyLexicalOperations, AuthoredCopyEnumCases, AuthoredCopySteps
        <1>empty. DirectParser!ParserSequence(<<>>)
            BY ONLY SMT DEF DirectParser!ParserSequence
        <1>construction.
            /\ DirectParser!WellBoundDirectCopySyntax(MaterializedCopyLexicalDeclarations,
                                                      AuthoredCopyEnumCases, AuthoredCopySteps)
            /\ DirectParser!ParserCopyFields(MaterializedCopyLexicalDeclarations) =
                   DirectParser!CopySharedRoots(AuthoredCopyLexicalOperations)
            /\ DirectParser!ParserRowsAppendInOrder(AuthoredCopySteps, ConstructedCopyRows)
            /\ \A index \in DOMAIN AuthoredCopySteps :
                   LET step == AuthoredCopySteps[index]
                       scope == DirectParser!ParserScopeAt(<<>>, MaterializedCopyLexicalDeclarations, step.visible)
                   IN DirectParser!ParserRowUsesAuthoredSyntax(MaterializedCopyLexicalDeclarations, scope,
                       AuthoredCopyEnumCases, step, ConstructedCopyRows[index])
            BY ONLY <1>rawScope, <1>empty, AuthoredCopyLexicalOperationsAreWellBound,
                DirectParser!WellBoundAliasedCopySyntaxProducesOrderedRows, SMT
                DEF ConstructedCopyRows, MaterializedCopyLexicalDeclarations
        <1>inputs. DirectParser!WellBoundDirectCopySyntax(MaterializedCopyLexicalDeclarations,
                                                        AuthoredCopyEnumCases, AuthoredCopySteps)
            BY ONLY <1>construction
        <1>fields. ParsedCopyFields = ConstructedCopyFields
            BY ONLY <1>construction, SMT DEF ConstructedCopyFields, DirectParser!CopySharedRoots,
                DirectParser!ParserRoot, DirectParser!ParserName, AuthoredCopyLexicalOperations, ParsedCopyFields
        <1>domain. /\ DOMAIN ConstructedCopyRows = DOMAIN AuthoredCopySteps
                   /\ DOMAIN ParsedCopyActionRows = DOMAIN AuthoredCopySteps
            BY ONLY <1>construction, SMT DEF DirectParser!ParserRowsAppendInOrder,
                AuthoredCopySteps, ParsedCopyActionRows
        <1>point. ASSUME NEW index \in DOMAIN AuthoredCopySteps
                   PROVE ConstructedCopyRows[index] = ParsedCopyActionRows[index]
            PROOF
            <2>. DEFINE step == AuthoredCopySteps[index]
                        actual == ParsedCopyActionRows[index]
                        computed == ConstructedCopyRows[index]
                        scope == DirectParser!ParserScopeAt(<<>>, MaterializedCopyLexicalDeclarations, step.visible)
            <2>semantics. DirectParser!ParserRowUsesAuthoredSyntax(
                    MaterializedCopyLexicalDeclarations, scope, AuthoredCopyEnumCases, step, computed)
                BY ONLY (index \in DOMAIN AuthoredCopySteps), <1>construction, SMT DEF step, computed, scope
            <2>label. computed.label = actual.label
                <3>enum. \A entry \in DirectParser!RegisteredParserCases(AuthoredCopyEnumCases, step) :
                              DirectParser!RegisteredCaseRaw(entry) = actual.label
                    BY ONLY (index \in DOMAIN AuthoredCopySteps), <1>domain, SMT
                        DEF DirectParser!RegisteredParserCases, DirectParser!RegisteredCaseRaw,
                            DirectParser!ParserName, AuthoredCopyEnumCases, AuthoredCopySteps,
                            ParsedCopyActionRows, step, actual
                <3>. QED BY ONLY <2>semantics, <3>enum, SMT DEF DirectParser!ParserRowUsesAuthoredSyntax
            <2>length. /\ DOMAIN computed.copies = DOMAIN step.copies
                       /\ DOMAIN actual.copies = DOMAIN step.copies
                BY ONLY (index \in DOMAIN AuthoredCopySteps), <1>domain, <2>semantics, SMT
                    DEF DirectParser!ParserRowUsesAuthoredSyntax, DirectParser!ParserRowsAppendInOrder,
                        AuthoredCopySteps, ParsedCopyActionRows, step, actual
            <2>pair. ASSUME NEW position \in DOMAIN step.copies
                      PROVE computed.copies[position] = actual.copies[position]
                PROOF
                <3>. DEFINE source == step.copies[position]
                            observed == actual.copies[position]
                <3>visible. \E target, read \in 1..step.visible :
                    /\ MaterializedCopyLexicalDeclarations[target].binding = source.targetBinding
                    /\ MaterializedCopyLexicalDeclarations[read].binding = source.readBinding
                    /\ DirectParser!ParserRoot(MaterializedCopyLexicalDeclarations[target]) = observed.target
                    /\ DirectParser!ParserRoot(MaterializedCopyLexicalDeclarations[read]) = observed.read
                    BY ONLY (index \in DOMAIN AuthoredCopySteps), (position \in DOMAIN step.copies),
                        <1>domain, <2>length, AuthoredCopyBindingsAreTheMaterializedLexicalDeclarations, SMT
                        DEF AuthoredCopyLexicalDeclarations, AuthoredCopySteps,
                            ParsedCopyActionRows, DirectParser!ParserRoot, DirectParser!ParserName,
                            step, actual, source, observed
                <3>record. observed = [target |-> observed.target, read |-> observed.read]
                    BY ONLY (index \in DOMAIN AuthoredCopySteps), (position \in DOMAIN step.copies),
                        <1>domain, <2>length, SMT DEF ParsedCopyActionRows, actual, observed
                <3>. QED BY ONLY (position \in DOMAIN step.copies), <2>semantics, <3>visible, <3>record, SMT
                    DEF DirectParser!ParserRowUsesAuthoredSyntax, DirectParser!ParserCopyUsesBothBindings, source, observed
            <2>shapes. /\ computed.copies = [position \in DOMAIN step.copies |-> computed.copies[position]]
                       /\ actual.copies = [position \in DOMAIN step.copies |-> actual.copies[position]]
                BY ONLY (index \in DOMAIN AuthoredCopySteps), <1>domain, <1>inputs, <2>semantics, <2>length, SMT
                    DEF DirectParser!ParserRowUsesAuthoredSyntax, DirectParser!ParserRowsAppendInOrder,
                        DirectParser!WellBoundDirectCopySyntax, DirectParser!ParserSequence, DirectParser!ParserPrefix,
                        ParsedCopyActionRows, step, actual
            <2>copies. computed.copies = actual.copies
                BY ONLY <2>pair, <2>shapes, SMT
            <2>frame. computed.frame = actual.frame
                <3>constructed. computed.frame = ConstructedCopyFields \ DirectParser!ParserTargets(computed.copies)
                    BY ONLY <2>semantics DEF DirectParser!ParserRowUsesAuthoredSyntax, ConstructedCopyFields
                <3>captured. actual.frame = ParsedCopyFields \ DirectParser!ParserTargets(actual.copies)
                    BY ONLY (index \in DOMAIN AuthoredCopySteps), <1>domain, SetExtensionality, SMT
                        DEF ParsedCopyFields, ParsedCopyActionRows, DirectParser!ParserTargets, actual
                <3>. QED BY ONLY <3>constructed, <3>captured, <1>fields, <2>copies, SMT
            <2>. QED BY ONLY (index \in DOMAIN AuthoredCopySteps), <1>domain, <1>inputs, <2>label, <2>copies, <2>frame, SMT
                DEF ConstructedCopyRows, DirectParser!ParserCopyRows, DirectParser!ParserCopyRow,
                    DirectParser!WellBoundDirectCopySyntax, DirectParser!ParserSequence,
                    ParsedCopyActionRows, actual, computed
        <1>shapes. /\ ConstructedCopyRows = [index \in DOMAIN AuthoredCopySteps |-> ConstructedCopyRows[index]]
                   /\ ParsedCopyActionRows = [index \in DOMAIN AuthoredCopySteps |-> ParsedCopyActionRows[index]]
            BY ONLY <1>domain, <1>construction, <1>inputs, SMT DEF
                DirectParser!WellBoundDirectCopySyntax, DirectParser!ParserRowsAppendInOrder,
                DirectParser!ParserPrefix, DirectParser!ParserSequence, ParsedCopyActionRows
        <1>rows. ParsedCopyActionRows = ConstructedCopyRows
            BY ONLY <1>point, <1>shapes, SMT
        <1>. QED BY ONLY <1>inputs, <1>fields, <1>rows, <1>domain
        """#

    private static let copyBuilderProof = #"""
        LOCAL CopyBuilder == INSTANCE OrderedScalarCopyRule
        LOCAL CopyBuilderSequences == INSTANCE SequenceTheorems
        LOCAL CopyBuilderDeclarations ==
            [index \in DOMAIN AuthoredCopyDeclarationOrder |->
                DirectParser!ParserRoot(AuthoredCopyDeclarationOrder[index])]
        LOCAL CopyBuilderSteps ==
            [index \in DOMAIN AuthoredCopySteps |->
                [label |-> ParsedCopyActionRows[index].label, copies |-> AuthoredCopySteps[index].copies]]

        THEOREM AuthoredCopyBuilderConstructsTheCompilerInventory ==
            CopyBuilder!DirectCopyBuilderInventoryExecution(WitnessCopyFields, CopyBuilderDeclarations,
                AuthoredCopyOrigins, CopyBuilderSteps)
        PROOF
        <1>parser. /\ DirectParser!ParserSequence(AuthoredCopyDeclarationOrder)
                   /\ DirectParser!ParserSequence(AuthoredCopySteps)
            BY ONLY ActualParserRowsHaveAuthoredLexicalConstruction, SMT
                DEF DirectParser!WellBoundDirectCopySyntax, DirectParser!ParserSequence, AuthoredCopyDeclarationOrder
        <1>present. /\ 1 \in DOMAIN AuthoredCopyDeclarationOrder /\ 1 \in DOMAIN AuthoredCopySteps
            BY ONLY SMT DEF AuthoredCopyDeclarationOrder, AuthoredCopySteps
        <1>sourceShape.
            /\ Len(AuthoredCopyDeclarationOrder) \in Nat \ {0}
            /\ DOMAIN AuthoredCopyDeclarationOrder = 1..Len(AuthoredCopyDeclarationOrder)
            /\ Len(AuthoredCopySteps) \in Nat \ {0} /\ DOMAIN AuthoredCopySteps = 1..Len(AuthoredCopySteps)
            BY ONLY <1>parser, <1>present, SMT DEF DirectParser!ParserSequence
        <1>roots. {CopyBuilderDeclarations[index] : index \in DOMAIN CopyBuilderDeclarations} = WitnessCopyFields
            BY ONLY ParsedDirectCopyRowsMatchTheActualBuilder, SMT
                DEF CopyBuilderDeclarations, AuthoredCopyDeclarationOrder, ParsedCopyFields,
                    DirectParser!ParserRoot, DirectParser!ParserName
        <1>declarations.
            /\ Len(CopyBuilderDeclarations) \in Nat \ {0}
            /\ CopyBuilderDeclarations \in [1..Len(CopyBuilderDeclarations) -> WitnessCopyFields]
            /\ \A key \in WitnessCopyFields : \E index \in 1..Len(CopyBuilderDeclarations) :
                   CopyBuilderDeclarations[index] = key
            <2>function. CopyBuilderDeclarations \in [1..Len(AuthoredCopyDeclarationOrder) -> WitnessCopyFields]
                BY ONLY <1>sourceShape, <1>roots, SMT DEF CopyBuilderDeclarations
            <2>sequence. CopyBuilderDeclarations \in Seq(WitnessCopyFields)
                BY ONLY <1>sourceShape, <2>function, CopyBuilderSequences!SeqDef, SMT
            <2>length. Len(CopyBuilderDeclarations) = Len(AuthoredCopyDeclarationOrder)
                BY ONLY <1>sourceShape, <2>sequence, CopyBuilderSequences!LenProperties, SMT DEF CopyBuilderDeclarations
            <2>. QED BY ONLY <1>sourceShape, <1>roots, <2>function, <2>length, SMT DEF CopyBuilderDeclarations
        <1>distinct. \A left, right \in 1..Len(CopyBuilderDeclarations) :
                         CopyBuilderDeclarations[left] = CopyBuilderDeclarations[right] => left = right
            BY ONLY <1>declarations, SMT DEF CopyBuilderDeclarations, AuthoredCopyDeclarationOrder,
                DirectParser!ParserRoot, DirectParser!ParserName
        <1>steps.
            /\ Len(CopyBuilderSteps) \in Nat \ {0}
            /\ DOMAIN CopyBuilderSteps = 1..Len(CopyBuilderSteps)
            /\ DOMAIN CopyBuilderSteps = DOMAIN AuthoredCopySteps
            <2>. DEFINE values == {CopyBuilderSteps[index] : index \in DOMAIN CopyBuilderSteps}
            <2>function. CopyBuilderSteps \in [1..Len(AuthoredCopySteps) -> values]
                BY ONLY <1>sourceShape, SMT DEF CopyBuilderSteps, values
            <2>sequence. CopyBuilderSteps \in Seq(values)
                BY ONLY <1>sourceShape, <2>function, CopyBuilderSequences!SeqDef, SMT
            <2>. QED BY ONLY <1>sourceShape, <2>sequence, CopyBuilderSequences!LenProperties, SMT DEF CopyBuilderSteps
        <1>typed. \A index \in DOMAIN CopyBuilderSteps :
            /\ CopyBuilderSteps[index].label \in STRING
            /\ CopyBuilder!DirectCopyTypedSyntax(WitnessCopyFields, AuthoredCopyOrigins, CopyBuilderSteps[index].copies)
            <2>. TAKE index \in DOMAIN CopyBuilderSteps
            <2>index. /\ index \in DOMAIN AuthoredCopySteps /\ index \in DOMAIN ParsedCopyActionRows
                BY ONLY (index \in DOMAIN CopyBuilderSteps), <1>steps, ActualParserRowsHaveAuthoredLexicalConstruction
            <2>label. CopyBuilderSteps[index].label \in STRING
                BY ONLY <2>index, SMT DEF CopyBuilderSteps, ParsedCopyActionRows
            <2>copies. CopyBuilder!DirectCopyTypedSyntax(WitnessCopyFields, AuthoredCopyOrigins, CopyBuilderSteps[index].copies)
                BY ONLY <2>index, AuthoredCopySyntaxSuppliesTypedSchedulerInput, AuthoredCopySyntaxBindsParsedRows,
                    ParsedDirectCopyRowsMatchTheActualBuilder, SMT DEF CopyBuilderSteps, CopyBuilder!DirectCopyTypedSyntax
            <2>. QED BY ONLY <2>label, <2>copies
        <1>input. CopyBuilder!DirectCopyBuilderInventoryInput(WitnessCopyFields, CopyBuilderDeclarations,
                       AuthoredCopyOrigins, CopyBuilderSteps)
            BY ONLY <1>declarations, <1>distinct, <1>steps, <1>typed, SMT DEF CopyBuilder!DirectCopyBuilderInventoryInput
        <1>. QED BY ONLY <1>input, CopyBuilder!DirectCopyBuilderConstructsEveryWellBoundInventory
        """#

    private static let copyFrontendProof = #"""
        THEOREM AuthoredCopyFrontendProducesTheCompilerRows ==
            /\ AuthoredCopyFields = WitnessCopyFields
            /\ AuthoredCopyActionRows = WitnessCopyActionRows
            /\ AuthoredCopyOrigins \in [DOMAIN AuthoredCopyOrigins -> WitnessCopyFields]
            /\ DOMAIN AuthoredCopySteps = DOMAIN WitnessCopyActionRows
            /\ \A row \in DOMAIN WitnessCopyActionRows :
                LET raw == AuthoredCopySteps[row].copies
                    copies == WitnessCopyActionRows[row].copies
                IN /\ Len(raw) \in Nat \ {0}
                   /\ DOMAIN raw = 1..Len(raw)
                   /\ \A position \in DOMAIN raw :
                           /\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                           /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins
                   /\ copies = [position \in DOMAIN raw |->
                           [target |-> AuthoredCopyOrigins[raw[position].targetBinding],
                            read |-> AuthoredCopyOrigins[raw[position].readBinding]]]
        PROOF
        <1>ordered. /\ AuthoredCopyFields = WitnessCopyFields
                    /\ AuthoredCopyActionRows = WitnessCopyActionRows
            BY ONLY AuthoredCopySyntaxBindsParsedRows, ParsedDirectCopyRowsMatchTheActualBuilder, SMT
        <1>origins. AuthoredCopyOrigins \in [DOMAIN AuthoredCopyOrigins -> WitnessCopyFields]
            BY ONLY <1>ordered, AuthoredCopySyntaxSuppliesTypedSchedulerInput, SMT
        <1>domain. DOMAIN AuthoredCopySteps = DOMAIN WitnessCopyActionRows
            BY ONLY ActualParserRowsHaveAuthoredLexicalConstruction, ParsedDirectCopyRowsMatchTheActualBuilder, SMT
        <1>rows. \A row \in DOMAIN WitnessCopyActionRows :
            LET raw == AuthoredCopySteps[row].copies
                copies == WitnessCopyActionRows[row].copies
            IN /\ Len(raw) \in Nat \ {0}
               /\ DOMAIN raw = 1..Len(raw)
               /\ \A position \in DOMAIN raw :
                       /\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                       /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins
               /\ copies = [position \in DOMAIN raw |->
                       [target |-> AuthoredCopyOrigins[raw[position].targetBinding],
                        read |-> AuthoredCopyOrigins[raw[position].readBinding]]]
            <2>. TAKE row \in DOMAIN WitnessCopyActionRows
            <2>. DEFINE raw == AuthoredCopySteps[row].copies
                        copies == WitnessCopyActionRows[row].copies
            <2>authored. row \in DOMAIN AuthoredCopySteps
                BY ONLY (row \in DOMAIN WitnessCopyActionRows), <1>domain
            <2>built. Len(raw) \in Nat \ {0}
                BY ONLY <2>authored, AuthoredCopyBuilderConstructsTheCompilerInventory, SMT
                    DEF CopyBuilder!DirectCopyBuilderInventoryExecution, CopyBuilder!DirectCopyBuilderBodyExecution,
                        CopyBuilderSteps, raw
            <2>projection. /\ DOMAIN raw = 1..Len(raw)
                           /\ \A position \in DOMAIN raw :
                                /\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                                /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins
                           /\ copies = [position \in DOMAIN raw |-> copies[position]]
                           /\ \A position \in DOMAIN raw :
                                copies[position] =
                                    [target |-> AuthoredCopyOrigins[raw[position].targetBinding],
                                     read |-> AuthoredCopyOrigins[raw[position].readBinding]]
                BY ONLY <2>authored, <1>ordered, AuthoredCopySyntaxSuppliesTypedSchedulerInput, SMT
                    DEF raw, copies
            <2>. QED BY ONLY <2>built, <2>projection, SMT DEF raw, copies
        <1>. QED BY ONLY <1>ordered, <1>origins, <1>domain, <1>rows
        """#

    struct UnsupportedControlSyntax: Error {
        let reason: String
    }

    static func controlMachine(_ selection: Selection) throws -> SequentialControlEvidence.Machine {
        try controlFrontend(selection).machine
    }

    static func controlFrontend(_ selection: Selection) throws
        -> (machine: SequentialControlEvidence.Machine, declared: SequentialControlEvidence.DeclaredSyntax,
            literalInitials: [(name: String, value: TLAValue)]?) {
        let body = try authoredSteps(selection)
        guard let machine = SequentialControlEvidence.authoredMachine(steps: body.steps, algorithmName: selection.algorithm)
        else { throw unsupported }
        return (machine, .init(algorithm: selection.algorithm, steps: body.steps), body.literalInitials)
    }

    static func capturedSequentialSteps(source: String, modelName: String) throws
        -> (algorithm: String, fields: Set<String>, steps: [AlgorithmStepModel]) {
        let selection = try select(source: source, modelName: modelName, includingCapturedRoots: true)
        let authored = try authoredSteps(selection)
        return (selection.algorithm, authored.fields, authored.steps)
    }

    private static func authoredSteps(_ selection: Selection) throws
        -> (fields: Set<String>, steps: [AlgorithmStepModel], literalInitials: [(name: String, value: TLAValue)]?) {
        var roots = selection.capturedRoots
        var steps: [AlgorithmStepModel] = []
        var literalInitials: [(name: String, value: TLAValue)]? = roots.isEmpty ? [] : nil
        var labels: [Label: String] = [:]
        var enumNames: Set<String> = []

        func resolve(_ expression: ExprSyntax?) throws -> String {
            guard let key = labelReference(expression) else {
                throw UnsupportedControlSyntax(reason: "The proof requires a model-local String enum case reference for each label.")
            }
            if enumNames.insert(key.enumName).inserted {
                for (item, raw) in try enumBindings(in: selection.members, named: [key.enumName]) {
                    labels[item] = raw ?? item.caseName
                }
            }
            guard let label = labels[key] else {
                throw UnsupportedControlSyntax(reason: "The control label \(key.enumName).\(key.caseName) has no declared case.")
            }
            return label
        }

        for item in selection.body {
            if steps.isEmpty, let declaration = try scopedRootDeclaration(item, in: selection.scope) {
                let root = declaration.explicit ?? declaration.binding
                guard roots.updateValue(root, forKey: declaration.binding) == nil else { throw unsupported }
                if let value = scalarLiteralInitializer(declaration.initializer) {
                    literalInitials?.append((root, value))
                } else {
                    literalInitials = nil
                }
                continue
            }
            guard let call = item.item.as(FunctionCallExprSyntax.self),
                  let kind = reference(call.calledExpression), ["Do", "While"].contains(kind),
                  let label = call.arguments.first, label.label == nil,
                  let body = call.trailingClosure, call.additionalTrailingClosures.isEmpty else {
                throw UnsupportedControlSyntax(reason: "Expected a shared declaration followed by sequential Do or While blocks.")
            }
            if kind == "Do", call.arguments.map({ $0.label?.text }) == [nil, "in"],
               let metatype = call.arguments.last?.expression.as(MemberAccessExprSyntax.self),
               reference(metatype.base) == "State", name(metatype.declName.baseName) == "self",
               metatype.declName.argumentNames == nil {
                let writes = try stateFieldWrites(body, fields: Set(roots.values))
                steps.append(.init(label: .init(name: try resolve(label.expression)), statements: writes))
                continue
            }
            guard body.signature == nil else { throw unsupported }
            let extra = call.arguments.dropFirst()
            let loop: StateExpr?
            var statements = try controlStatements(body.statements, roots: roots, resolve: resolve)
            if kind == "While", extra.count == 1, let predicate = extra.first, predicate.label == nil {
                loop = try controlExpression(predicate.expression, roots: roots)
            } else if kind == "Do", extra.count <= 1, extra.allSatisfy({ $0.label?.text == "when" }) {
                loop = nil
                if let predicate = extra.first {
                    statements.insert(.when(try controlExpression(predicate.expression, roots: roots)), at: 0)
                }
            } else {
                throw UnsupportedControlSyntax(reason: "Expected a While condition or one optional Do when: condition.")
            }
            steps.append(.init(label: .init(name: try resolve(label.expression)), statements: statements, loopCondition: loop))
        }
        let fields = Set(roots.values)
        guard fields.count == roots.count, !steps.isEmpty, Set(steps.map(\.label)).count == steps.count else {
            throw UnsupportedControlSyntax(reason: "Expected distinct roots and a nonempty sequence of distinct control labels.")
        }
        return (fields, steps, literalInitials)
    }

    private static func boundArithmeticView(
        _ authored: StateExpr, source: [StraightLineAssignmentCheck.OrderedIntNode]
    ) throws -> (view: String, parents: String) {
        var pending: [(origin: Int, syntax: StateExpr, parent: Int)] = [(1, authored, 0)]
        var kinds = Array(repeating: "", count: source.count)
        var literals = Array(repeating: TLAValue.int(0), count: source.count)
        var reads = literals
        var left = literals
        var right = literals
        var parents = literals
        var bound = 0

        while let (origin, syntax, parent) = pending.popLast() {
            guard origin > 0, origin <= source.count, kinds[origin - 1].isEmpty else { throw unsupported }
            let slot = origin - 1
            switch (syntax, source[slot]) {
            case (.value(.int(let authoredValue)), .literal(let returnedValue)) where authoredValue == returnedValue:
                kinds[slot] = "literal"
                literals[slot] = .int(authoredValue)
            case (.variable(let authoredName), .read(let returnedName))
                where authoredName.utf8.elementsEqual(returnedName.utf8):
                kinds[slot] = "read"
                reads[slot] = .string(authoredName)
            case (.add(let first, let second), .add(let leftOrigin, let rightOrigin)):
                guard leftOrigin > origin, rightOrigin > origin, leftOrigin != rightOrigin else { throw unsupported }
                kinds[slot] = "add"
                left[slot] = .int(leftOrigin)
                right[slot] = .int(rightOrigin)
                pending.append((rightOrigin, second, origin))
                pending.append((leftOrigin, first, origin))
            default:
                throw unsupported
            }
            parents[slot] = .int(parent)
            bound += 1
        }
        // The returned indices address the proof rows. The tags and leaf values come from authored syntax.
        guard bound == source.count else { throw unsupported }
        let view = "[root |-> 1, kinds |-> \(TLAValue.tuple(kinds.map(TLAValue.string))), "
            + "literals |-> \(TLAValue.tuple(literals)), reads |-> \(TLAValue.tuple(reads)), "
            + "left |-> \(TLAValue.tuple(left)), right |-> \(TLAValue.tuple(right))]"
        return (view, TLAValue.tuple(parents).description)
    }

    struct ArithmeticProofInput {
        let algorithm: String
        let labels: [String]
        let ordinal: Int
        let name: String
        let module: String

        var label: String { labels[ordinal] }
        var continuation: String? { labels.dropFirst(ordinal + 1).first }
    }

    static func arithmeticRoute(algorithm: String, label: String, ordinal: Int, continuation: String?) -> TLAValue {
        .record(TLARecord([
            .init("algorithm", .string(algorithm)), .init("label", .string(label)), .init("ordinal", .int(ordinal)),
            .init("continuation", .tuple(continuation.map { [.string($0)] } ?? [])),
        ]))
    }

    static func arithmeticProofInput(
        _ selection: Selection, spec: TLASpec, renderedModule: String, sourceAction: String?
    ) throws -> ArithmeticProofInput {
        let authored = try authoredSteps(selection)
        guard let fallback = authored.fields.sorted().first,
              spec.sourceAlgorithms.count == 1, let built = spec.sourceAlgorithms.first?.model,
              built.name.utf8.elementsEqual(selection.algorithm.utf8) else { throw unsupported }
        let actual = built.components.compactMap { component -> AlgorithmStepModel? in
            guard case .step(let step) = component else { return nil }
            return step
        }
        let labels = authored.steps.map(\.label.name)
        guard actual.count == labels.count,
              zip(actual, authored.steps).allSatisfy({
                  $0.0.label.name.utf8.elementsEqual($0.1.label.name.utf8)
                      && $0.0.loopCondition == nil && $0.1.loopCondition == nil
              }) else { throw unsupported }
        let matching = labels.indices.filter { index in
            if let sourceAction { return labels[index].utf8.elementsEqual(sourceAction.utf8) }
            return labels.count == 1
        }
        guard matching.count == 1, let ordinal = matching.first else { throw unsupported }
        let step = authored.steps[ordinal]
        let action = actual[ordinal]
        let fields = built.components.compactMap { component -> String? in
            guard case .shared(let declaration) = component else { return nil }
            return declaration.root
        }
        guard fields.count == authored.fields.count, Set(fields) == authored.fields,
              action.statements.count == step.statements.count else { throw unsupported }
        let rows = try zip(step.statements, action.statements).map { source, returned in
            guard case .set(.root(let target), let sourceValue) = source, authored.fields.contains(target),
                  case .set(.root(let actualTarget), let expression) = returned,
                  actualTarget.utf8.elementsEqual(target.utf8), expression == sourceValue,
                  let certificate = StraightLineAssignmentCheck.orderedIntCertificate(expression, reads: authored.fields)
            else { throw unsupported }
            let authoredBinding = try boundArithmeticView(sourceValue, source: certificate.source)
            let syntax = try InitialFailureEvidence.sourceSyntaxView(certificate)
            let retained = "[view |-> \(syntax.view), origins |-> \(syntax.origins), inverse |-> \(syntax.indices)]"
            return (target: TLAValue.string(target).description, retained: retained,
                    authoredView: authoredBinding.view, authoredParents: authoredBinding.parents, nodes: syntax.emitted)
        }
        let countColumns = tuple(rows.map { String($0.nodes.count) })
        let kindColumns = tuple(rows.map { tuple($0.nodes.map { TLAValue.string($0.kind).description }) })
        let literalColumns = tuple(rows.map { tuple($0.nodes.map { $0.kind == "literal" ? $0.payload : "0" }) })
        let formalFallback = TLAValue.string(fallback).description
        let readColumns = tuple(rows.map { tuple($0.nodes.map { $0.kind == "read" ? $0.payload : formalFallback }) })
        let leftColumns = tuple(rows.map { tuple($0.nodes.map { String($0.left) }) })
        let rightColumns = tuple(rows.map { tuple($0.nodes.map { String($0.right) }) })
        guard case .set(.root(let firstTarget), _)? = step.statements.first else { throw unsupported }
        let suffix = labels.count == 1 ? "" : "\(renderedModule)Action\(ordinal + 1)"
        let moduleName = "SwiftTLAArithmeticAssignmentSource" + suffix
        let entries = TLAValue.tuple(labels.map { .tuple([.string($0)]) })
        let routeDeclaration = suffix.isEmpty ? "" : #"""

        MasterRouteRules == INSTANCE ActionOutcomeInterface
            WITH UpdateValues <- {}, FailureValues <- {}, NoFailure <- <<>>
        MasterAuthoredEntries == \#(entries)
        MasterSelectedSlot == \#(ordinal + 1)
        MasterSelectedRoute ==
            [algorithm |-> \#(TLAValue.string(selection.algorithm)),
             label |-> MasterAuthoredEntries[MasterSelectedSlot][1],
             ordinal |-> MasterSelectedSlot - 1,
             continuation |-> MasterRouteRules!FollowingSequentialEntry(MasterAuthoredEntries, MasterSelectedSlot, <<>>)]
        """#
        let module = #"""
        ---- MODULE \#(moduleName) ----
        EXTENDS TLAPS, Integers, Sequences
        MasterFields == \#(TLAValue.set(Set(authored.fields.map(TLAValue.string))))
        MasterTarget == \#(TLAValue.string(firstTarget))\#(routeDeclaration)
        MasterTargets == \#(tuple(rows.map(\.target)))
        MasterNodeCounts == \#(countColumns)
        MasterNodeKinds == \#(kindColumns)
        MasterNodeLiterals == \#(literalColumns)
        MasterNodeReadKeys == \#(readColumns)
        MasterNodeLeft == \#(leftColumns)
        MasterNodeRight == \#(rightColumns)
        LOCAL MasterAuthoredViews == \#(tuple(rows.map(\.authoredView)))
        LOCAL MasterAuthoredParents == \#(tuple(rows.map(\.authoredParents)))
        LOCAL MasterRetainedRows == \#(tuple(rows.map(\.retained)))
        MasterNodes(index) == [node \in 1..MasterNodeCounts[index] |->
            [kind |-> MasterNodeKinds[index][node],
             payload |-> IF MasterNodeKinds[index][node] = "read"
                         THEN MasterNodeReadKeys[index][node] ELSE MasterNodeLiterals[index][node],
             left |-> MasterNodeLeft[index][node], right |-> MasterNodeRight[index][node]]]
        MasterRows == [index \in DOMAIN MasterNodeCounts |->
            [target |-> MasterTargets[index], view |-> MasterAuthoredViews[index],
             inverse |-> MasterRetainedRows[index].inverse, fallback |-> \#(formalFallback),
             emitted |-> [count |-> MasterNodeCounts[index], height |-> 1,
                          indices |-> <<MasterNodeCounts[index]>>, origins |-> MasterRetainedRows[index].origins,
                          nodes |-> MasterNodes(index)]]]
        Rule == INSTANCE OrderedAssignmentOutputRules WITH Keys <- MasterFields,
            SwiftIntMin <- \#(TLAValue.int(Int.min)), SwiftIntMax <- \#(TLAValue.int(Int.max)),
            Vars <- {}, Values <- {}, ActionLabels <- {}, FailureValues <- {}, NoFailure <- <<>>
        THEOREM ActualAuthoredRHSBindsTheReturnedSourceOccurrences ==
            /\ DOMAIN MasterAuthoredViews = DOMAIN MasterNodeCounts
            /\ \A row \in DOMAIN MasterNodeCounts :
                   /\ MasterAuthoredViews[row] = MasterRetainedRows[row].view
                   /\ Rule!CompilerOccurrenceTree(MasterAuthoredViews[row], MasterNodeCounts[row])
        PROOF
        <1>domain. DOMAIN MasterAuthoredViews = DOMAIN MasterNodeCounts
            BY ONLY IsaM("simp") DEF MasterAuthoredViews, MasterNodeCounts
        <1>binding. \A row \in DOMAIN MasterNodeCounts :
            MasterAuthoredViews[row] = MasterRetainedRows[row].view
            BY ONLY IsaM("simp") DEF MasterAuthoredViews, MasterRetainedRows, MasterNodeCounts
        <1>tree. \A row \in DOMAIN MasterNodeCounts :
            Rule!CompilerOccurrenceTree(MasterAuthoredViews[row], MasterNodeCounts[row])
            <2>. TAKE row \in DOMAIN MasterNodeCounts
            <2>. DEFINE view == MasterAuthoredViews[row]
                        count == MasterNodeCounts[row]
            <2>shape. /\ count \in Nat \ {0} /\ view.root = 1
                       /\ DOMAIN view.kinds = 1..count
                BY ONLY (row \in DOMAIN MasterNodeCounts), SMT DEF view, count, MasterAuthoredViews, MasterNodeCounts
            <2>children. \A node \in 1..count :
                /\ view.kinds[node] \in {"literal", "read", "add"}
                /\ (view.kinds[node] = "add" =>
                    /\ view.left[node] \in (node + 1)..count
                    /\ view.right[node] \in (node + 1)..count
                    /\ view.left[node] # view.right[node])
                BY ONLY (row \in DOMAIN MasterNodeCounts), SMT DEF view, count, MasterAuthoredViews, MasterNodeCounts
            <2>unique. \A first, second \in 1..count :
                (view.kinds[first] = "add" /\ view.kinds[second] = "add" /\
                 {view.left[first], view.right[first]} \cap {view.left[second], view.right[second]} # {}) => first = second
                BY ONLY (row \in DOMAIN MasterNodeCounts), SMT DEF view, count, MasterAuthoredViews, MasterNodeCounts
            <2>coverage. \A child \in 2..count :
                \E parent \in 1..(child - 1) :
                    view.kinds[parent] = "add" /\ child \in {view.left[parent], view.right[parent]}
                <3>. TAKE child \in 2..count
                <3>. DEFINE parent == MasterAuthoredParents[row][child]
                <3>index. parent \in 1..(child - 1)
                    BY ONLY (row \in DOMAIN MasterNodeCounts), (child \in 2..count), SMT
                        DEF parent, count, MasterAuthoredParents, MasterNodeCounts
                <3>edge. view.kinds[parent] = "add" /\ child \in {view.left[parent], view.right[parent]}
                    BY ONLY (row \in DOMAIN MasterNodeCounts), (child \in 2..count), SMT
                        DEF parent, view, count, MasterAuthoredParents, MasterAuthoredViews, MasterNodeCounts
                <3>. QED BY ONLY <3>index, <3>edge, Zenon
            <2>. QED BY ONLY <2>shape, <2>children, <2>unique, <2>coverage, SMT
                DEF view, count, Rule!CompilerOccurrenceTree
        <1>. QED BY ONLY <1>domain, <1>binding, <1>tree, SMT


        THEOREM MasterAssignmentsAreSupported ==
            /\ Rule!SupportedAssignmentList(MasterRows)
            /\ Len(MasterRows) = \#(rows.count)
        PROOF
        <1>shape. /\ Len(MasterRows) \in Nat
                  /\ DOMAIN MasterRows = 1..Len(MasterRows)
                  /\ Len(MasterRows) = \#(rows.count)
            <2>domain. DOMAIN MasterRows = 1..\#(rows.count)
                BY ONLY SMT DEF MasterRows, MasterNodeCounts
            <2>. DEFINE values == {MasterRows[index] : index \in DOMAIN MasterRows}
            <2>function. MasterRows \in [1..\#(rows.count) -> values]
                BY ONLY <2>domain, SMT DEF values, MasterRows
            <2>sequence. MasterRows \in Seq(values)
                BY ONLY <2>function, Rule!SeqDef, SMT
            <2>. QED BY ONLY <2>domain, <2>sequence, Rule!LenProperties, SMT
        <1>rows. \A i \in DOMAIN MasterRows :
            /\ MasterRows[i].target \in MasterFields
            /\ Rule!AssignmentRhsCertificate(MasterRows[i])
            <2>. SUFFICES ASSUME NEW i \in DOMAIN MasterRows
                         PROVE /\ MasterRows[i].target \in MasterFields
                               /\ Rule!AssignmentRhsCertificate(MasterRows[i])
                OBVIOUS
            <2>. DEFINE row == MasterRows[i]
                        count == MasterNodeCounts[i]
                        view == MasterRetainedRows[i].view
                        origins == MasterRetainedRows[i].origins
                        nodes == MasterNodes(i)
            <2>index. i \in DOMAIN MasterNodeCounts
                BY ONLY (i \in DOMAIN MasterRows), SMT DEF MasterRows
            <2>authored. /\ MasterAuthoredViews[i] = view
                          /\ Rule!CompilerOccurrenceTree(view, count)
                BY ONLY <2>index, ActualAuthoredRHSBindsTheReturnedSourceOccurrences, SMT DEF view, count
            <2>record. row =
                [target |-> MasterTargets[i], view |-> view, inverse |-> MasterRetainedRows[i].inverse,
                 fallback |-> \#(formalFallback), emitted |-> [count |-> count, height |-> 1, indices |-> <<count>>,
                                                  origins |-> origins, nodes |-> nodes]]
                BY ONLY <2>index, <2>authored, SMT DEF row, MasterRows, count, origins, nodes
            <2>sourceDomain. DOMAIN view.kinds = 1..count
                BY ONLY <2>authored DEF Rule!CompilerOccurrenceTree
            <2>projection. /\ row.target = MasterTargets[i] /\ row.fallback = \#(formalFallback)
                           /\ row.view = view
                           /\ row.emitted.count = count /\ row.emitted.height = 1
                           /\ row.emitted.indices = <<count>>
                           /\ row.emitted.origins = origins /\ row.emitted.nodes = nodes
                BY ONLY <2>record, SMT
            <2>types. /\ row.target \in MasterFields /\ row.fallback \in MasterFields
                      /\ Rule!NodeEmissionArrays(row.emitted) /\ row.emitted.count > 0
                <3>names. MasterTargets[i] \in MasterFields /\ \#(formalFallback) \in MasterFields
                    BY ONLY <2>index, SMT DEF MasterNodeCounts, MasterTargets, MasterFields
                <3>count. count \in Nat \ {0}
                    BY ONLY <2>index, SMT DEF count, MasterNodeCounts
                <3>origins. origins = [j \in 1..count |-> origins[j]]
                    BY ONLY <2>index, SMT DEF origins, count, MasterNodeCounts, MasterRetainedRows
                <3>. QED BY ONLY <2>projection, <3>names, <3>count, <3>origins, SMT DEF nodes, MasterNodes, Rule!NodeEmissionArrays
            <2>domains. /\ row.inverse \in [DOMAIN row.view.kinds -> 1..row.emitted.count]
                         /\ row.emitted.origins \in [1..row.emitted.count -> DOMAIN row.view.kinds]
                BY ONLY <2>index, <2>record, <2>sourceDomain, SMT
                    DEF view, count, origins, MasterNodeCounts, MasterRetainedRows
            <2>preorder. \A j \in 1..row.emitted.count : row.inverse[row.emitted.origins[j]] = j
                BY ONLY <2>index, <2>record, SMT DEF count, origins, MasterNodeCounts, MasterRetainedRows
            <2>postorder. \A node \in DOMAIN row.view.kinds : row.emitted.origins[row.inverse[node]] = node
                BY ONLY <2>index, <2>record, <2>sourceDomain, SMT
                    DEF view, count, origins, MasterNodeCounts, MasterRetainedRows
            <2>root. row.emitted.origins[row.emitted.count] = row.view.root
                BY ONLY <2>index, <2>record, SMT DEF view, count, origins, MasterNodeCounts, MasterRetainedRows
            <2>payload. Rule!AllNodePayloadsMatchSource(row.view, row.emitted)
                <3>points. \A j \in 1..count : Rule!NodePayloadMatchesSource(row.view, row.emitted, j)
                    <4>. TAKE j \in 1..count
                    <4>. DEFINE origin == origins[j]
                                kind == MasterNodeKinds[i][j]
                                literal == MasterNodeLiterals[i][j]
                                read == MasterNodeReadKeys[i][j]
                                left == MasterNodeLeft[i][j]
                                right == MasterNodeRight[i][j]
                    <4>kind. kind \in {"literal", "read", "add"} /\ kind = view.kinds[origin]
                        BY ONLY <2>index, (j \in 1..count), SMT DEF kind, view, origin, origins, count,
                            MasterNodeKinds, MasterNodeCounts, MasterRetainedRows
                    <4>literal. /\ (kind = "literal" => literal = view.literals[origin])
                                /\ (kind = "add" => literal = 0)
                        BY ONLY <2>index, (j \in 1..count), SMT DEF kind, literal, view, origin, origins, count,
                            MasterNodeKinds, MasterNodeLiterals, MasterNodeCounts, MasterRetainedRows
                    <4>read. kind = "read" => read = view.reads[origin]
                        BY ONLY <2>index, (j \in 1..count), SMT DEF kind, read, view, origin, origins, count,
                            MasterNodeKinds, MasterNodeReadKeys, MasterNodeCounts, MasterRetainedRows
                    <4>left. IF kind = "add" THEN left \in 1..(j - 1) /\ origins[left] = view.left[origin] ELSE left = 0
                        BY ONLY <2>index, (j \in 1..count), SMT DEF kind, left, view, origin, origins, count,
                            MasterNodeKinds, MasterNodeLeft, MasterNodeCounts, MasterRetainedRows
                    <4>right. IF kind = "add" THEN right \in 1..(j - 1) /\ origins[right] = view.right[origin] ELSE right = 0
                        BY ONLY <2>index, (j \in 1..count), SMT DEF kind, right, view, origin, origins, count,
                            MasterNodeKinds, MasterNodeRight, MasterNodeCounts, MasterRetainedRows
                    <4>. QED BY ONLY <2>projection, (j \in 1..count), <4>kind, <4>literal, <4>read, <4>left, <4>right, SMT
                        DEF Rule!NodePayloadMatchesSource, nodes, MasterNodes, origin, kind, literal, read, left, right
                <3>. QED BY ONLY <2>projection, <3>points, SMT DEF Rule!AllNodePayloadsMatchSource
            <2>bound. /\ Rule!TypedVisitedSourceInputs(row.view, row.emitted)
                      /\ \A j \in 1..row.emitted.count :
                             row.emitted.nodes[j].kind = "read" => row.emitted.nodes[j].payload \in MasterFields
                <3>literals. \A j \in 1..count :
                    view.kinds[origins[j]] = "literal" => Rule!InRange(view.literals[origins[j]])
                    BY ONLY <2>index, SMT DEF count, view, origins, MasterNodeCounts, MasterRetainedRows, Rule!InRange
                <3>reads. \A j \in 1..count :
                    view.kinds[origins[j]] = "read" => view.reads[origins[j]] \in MasterFields
                    BY ONLY <2>index, SMT DEF count, view, origins, MasterNodeCounts, MasterRetainedRows, MasterFields
                <3>emitted. \A j \in 1..count :
                    MasterNodeKinds[i][j] = "read" => MasterNodeReadKeys[i][j] \in MasterFields
                    BY ONLY <2>index, SMT DEF count, MasterNodeCounts, MasterNodeKinds, MasterNodeReadKeys, MasterFields
                <3>. QED BY ONLY <2>projection, <3>literals, <3>reads, <3>emitted, SMT
                    DEF Rule!TypedVisitedSourceInputs, nodes, MasterNodes
            <2>. QED BY ONLY <2>types, <2>domains, <2>preorder, <2>postorder, <2>root, <2>payload, <2>bound, SMT
                DEF row, Rule!AssignmentRhsCertificate, Rule!LiteralReadAddCertificate
        <1>. QED BY ONLY <1>shape, <1>rows, SMT DEF Rule!SupportedAssignmentList
        ====
        """# + "\n"
        return .init(algorithm: selection.algorithm, labels: labels, ordinal: ordinal, name: moduleName, module: module)
    }

    static func conditionalProofInput(source: String, modelName: String) throws -> TLAValue? {
        let (members, specBody) = try specification(source: source, modelName: modelName)
        guard let parameters = specBody.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              parameters.count == 1, let parameter = parameters.first,
              let call = specBody.statements.last?.item.as(FunctionCallExprSyntax.self),
              reference(call.calledExpression) == "Do",
              call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
              let label = labelReference(argument.expression),
              let body = call.trailingClosure, body.signature == nil, call.additionalTrailingClosures.isEmpty,
              let declaredLabel = try enumBindings(in: members, named: [label.enumName]).first(where: { $0.0 == label })
        else { return nil }

        var roots: [String: String] = [:]
        for item in specBody.statements.dropLast() {
            guard let (binding, explicit) = try rootDeclaration(item, in: name(parameter.name)),
                  roots.updateValue(explicit ?? binding, forKey: binding) == nil else { return nil }
        }
        let fields = Set(roots.values.map(TLAValue.string))
        guard fields.count == roots.count else { return nil }
        let statements = try controlStatements(body.statements, roots: roots, resolve: { _ in throw unsupported })
        guard statements.count == 1, case .ifElse(let predicate, let yes, let no)? = statements.first,
              let guardTerm = scalarComparison(predicate), let yesWrite = conditionalWrite(yes),
              let noWrite = conditionalWrite(no) else { return nil }

        return .record(["fields": .set(fields), "label": .string(declaredLabel.1 ?? label.caseName),
                        "predicate": guardTerm, "ifTrue": yesWrite, "ifFalse": noWrite])
    }

    struct BranchwiseAssignments {
        struct Write {
            let target: TLAValue
            let sourceTerm: [TLAValue]
        }

        let fields: Set<TLAValue>
        let label: TLAValue
        let prefix: [Write]
        let arms: [[Write]]
        let suffix: [Write]
    }

    static func branchwiseAssignments(source: String, modelName: String) throws -> BranchwiseAssignments {
        let (members, specBody) = try specification(source: source, modelName: modelName, requiringModuleName: true)
        let parameters = ModelSpecificationSyntax.parameterNames(in: specBody)
        let items = Array(specBody.statements)
        let steps = items.indices.filter { index in
            guard let call = items[index].item.as(FunctionCallExprSyntax.self) else { return false }
            return reference(call.calledExpression) == "Do"
        }
        guard parameters.count == 1, let scope = parameters.first,
              steps.count == 1, let stepIndex = steps.first,
              let call = items[stepIndex].item.as(FunctionCallExprSyntax.self),
              call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
              let label = labelReference(argument.expression),
              let body = call.trailingClosure, body.signature == nil, call.additionalTrailingClosures.isEmpty,
              let declaredLabel = try enumBindings(in: members, named: [label.enumName]).first(where: { $0.0 == label })
        else { throw unsupported }

        var roots: [String: String] = [:]
        for item in items[..<stepIndex] {
            guard let (binding, explicit) = try rootDeclaration(item, in: scope),
                  roots.updateValue(explicit ?? binding, forKey: binding) == nil else { throw unsupported }
        }
        let fields = Set(roots.values.map(TLAValue.string))
        let statements = try controlStatements(body.statements, roots: roots, resolve: { _ in throw unsupported })
        guard fields.count == roots.count, let fork = statements.firstIndex(where: {
            if case .either = $0 { return true }
            return false
        }), case .either(let first, let second) = statements[fork] else { throw unsupported }

        func scalar(_ expression: StateExpr) -> TLAValue? {
            switch expression {
            case .variable, .value(.int): return expression.scalarEvidenceTerm
            default: return nil
            }
        }
        func writes(_ statements: some Sequence<AlgorithmStatementModel>) throws -> [BranchwiseAssignments.Write] {
            try statements.map { statement in
                guard case .set(.root(let target), let value) = statement else { throw unsupported }
                if let operand = scalar(value) { return .init(target: .string(target), sourceTerm: [operand]) }
                let operation: (tag: String, left: StateExpr, right: StateExpr)
                switch value {
                case .divide(let left, let right): operation = ("divide", left, right)
                case .modulo(let left, let right): operation = ("modulo", left, right)
                default: throw unsupported
                }
                guard let left = scalar(operation.left), let right = scalar(operation.right) else { throw unsupported }
                return .init(target: .string(target), sourceTerm: [.tuple([.string(operation.tag)]), left, right])
            }
        }
        return try .init(fields: fields, label: .string(declaredLabel.1 ?? label.caseName),
                         prefix: writes(statements[..<fork]), arms: [writes(first), writes(second)],
                         suffix: writes(statements[(fork + 1)...]))
    }

    private static func scalarComparison(_ expression: StateExpr) -> TLAValue? {
        func isOperand(_ value: StateExpr) -> Bool {
            switch value {
            case .variable, .value(.int), .value(.bool): true
            default: false
            }
        }
        switch expression {
        case .equal(let lhs, let rhs), .lessThan(let lhs, let rhs):
            guard isOperand(lhs), isOperand(rhs) else { return nil }
            return expression.scalarEvidenceTerm
        default: return nil
        }
    }

    private static func conditionalWrite(_ statements: [AlgorithmStatementModel]) -> TLAValue? {
        guard statements.count == 1,
              case .set(.root(let target), let value)? = statements.first,
              case .value(.bool) = value, let term = value.scalarEvidenceTerm else { return nil }
        return .tuple([.string(target), term])
    }

    private static func controlStatements(_ statements: CodeBlockItemListSyntax, roots: [String: String],
                                          resolve: (ExprSyntax?) throws -> String) throws -> [AlgorithmStatementModel] {
        try statements.map { item in
            let error = UnsupportedControlSyntax(reason: "Unsupported control statement: \(item.trimmedDescription)")
            guard let call = item.item.as(FunctionCallExprSyntax.self), let kind = reference(call.calledExpression) else {
                throw error
            }
            if kind == "If" {
                let extra = call.arguments.dropFirst()
                guard let predicate = call.arguments.first, predicate.label == nil,
                      let body = call.trailingClosure, body.signature == nil,
                      extra.count + call.additionalTrailingClosures.count <= 1,
                      extra.allSatisfy({ $0.label?.text == "else" }),
                      call.additionalTrailingClosures.allSatisfy({ $0.label.text == "else" }) else { throw error }
                let noClosure = call.additionalTrailingClosures.first?.closure ?? extra.first?.expression.as(ClosureExprSyntax.self)
                guard (extra.isEmpty || noClosure != nil), noClosure?.signature == nil else { throw error }
                let yes = try controlStatements(body.statements, roots: roots, resolve: resolve)
                let no = try noClosure.map { try controlStatements($0.statements, roots: roots, resolve: resolve) } ?? []
                return .ifElse(try controlExpression(predicate.expression, roots: roots), yes, no)
            }
            if kind == "Either" {
                guard call.arguments.isEmpty, let first = call.trailingClosure, first.signature == nil,
                      call.additionalTrailingClosures.count == 1,
                      let other = call.additionalTrailingClosures.first,
                      other.label.text == "or", other.closure.signature == nil else { throw error }
                return try .either(controlStatements(first.statements, roots: roots, resolve: resolve),
                                   controlStatements(other.closure.statements, roots: roots, resolve: resolve))
            }
            guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else { throw error }
            switch kind {
            case "Stop" where call.arguments.isEmpty: return .stop
            case "Skip" where call.arguments.isEmpty: return .skip
            case "When", "Goto":
                guard call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil else { throw error }
                if kind == "When" { return .when(try controlExpression(argument.expression, roots: roots)) }
                return .goto(.init(name: try resolve(argument.expression)))
            case "Assign":
                guard call.arguments.count == 2, let target = call.arguments.first, target.label == nil,
                      let binding = reference(target.expression), let root = roots[binding],
                      let value = call.arguments.last, value.label?.text == "to" else { throw error }
                return .set(target: .root(root), value: try controlExpression(value.expression, roots: roots))
            default: throw error
            }
        }
    }

    // shortcut: The retained source evidence uses scalar reads, literals, and explicitly grouped built-in operations.
    private static func stateFieldWrites(_ body: ClosureExprSyntax, fields: Set<String>) throws -> [AlgorithmStatementModel] {
        guard let signature = body.signature, signature.capture == nil, signature.attributes.isEmpty,
              signature.effectSpecifiers == nil, signature.returnClause == nil,
              case .simpleInput(let parameters) = signature.parameterClause,
              parameters.count == 1, let parameter = parameters.first, name(parameter.name) != "_" else { throw unsupported }
        func field(_ expression: ExprSyntax) -> String? {
            guard let member = expression.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil,
                  reference(member.base)?.utf8.elementsEqual(name(parameter.name).utf8) == true else { return nil }
            let key = name(member.declName.baseName)
            return fields.first { $0.utf8.elementsEqual(key.utf8) }
        }
        return try body.statements.map { item in
            guard let expression = item.item.as(ExprSyntax.self) else { throw unsupported }
            let parts: [ExprSyntax]
            if let sequence = expression.as(SequenceExprSyntax.self) { parts = Array(sequence.elements) }
            else if let infix = expression.as(InfixOperatorExprSyntax.self) {
                parts = [infix.leftOperand, infix.operator, infix.rightOperand]
            } else { throw unsupported }
            guard parts.count == 3, let target = field(parts[0]) else { throw unsupported }
            let rhs: StateExpr
            if let read = field(parts[2]) {
                rhs = .variable(read)
            } else {
                guard parts[2].is(IntegerLiteralExprSyntax.self)
                    || (parts[2].as(PrefixOperatorExprSyntax.self)?.operator.text == "-"
                        && parts[2].as(PrefixOperatorExprSyntax.self)?.expression.is(IntegerLiteralExprSyntax.self) == true),
                      case .value(.int(let number)) = try controlExpression(parts[2], roots: [:]) else { throw unsupported }
                rhs = .value(.int(number))
            }
            if parts[1].is(AssignmentExprSyntax.self) { return .set(target: .root(target), value: rhs) }
            guard parts[1].as(BinaryOperatorExprSyntax.self)?.operator.text == "+=" else { throw unsupported }
            return .set(target: .root(target), value: .add(.variable(target), rhs))
        }
    }

    private static func controlExpression(_ expression: ExprSyntax, roots: [String: String]) throws -> StateExpr {
        let error = UnsupportedControlSyntax(reason: "Unsupported scalar control expression: \(expression.trimmedDescription)")
        if let binding = reference(expression), let root = roots[binding] { return .variable(root) }
        if let member = expression.as(MemberAccessExprSyntax.self), name(member.declName.baseName) == "expr",
           let binding = reference(member.base), let root = roots[binding] { return .variable(root) }
        if let literal = expression.as(BooleanLiteralExprSyntax.self) { return .value(.bool(literal.literal.text == "true")) }
        let sign = expression.as(PrefixOperatorExprSyntax.self)
        if sign == nil || sign?.operator.text == "-" || sign?.operator.text == "+",
           let literal = (sign?.expression ?? expression).as(IntegerLiteralExprSyntax.self) {
            let spelling = literal.literal.text.filter { $0 != "_" }
            let radix: Int
            switch spelling.prefix(2) {
            case "0b": radix = 2
            case "0o": radix = 8
            case "0x": radix = 16
            default: radix = 10
            }
            let digits = radix == 10 ? spelling[...] : spelling.dropFirst(2)
            guard let value = Int((sign?.operator.text ?? "") + digits, radix: radix) else { throw error }
            return .value(.int(value))
        }
        if let group = expression.as(TupleExprSyntax.self), group.elements.count == 1,
           let part = group.elements.first, part.label == nil {
            return try controlExpression(part.expression, roots: roots)
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "!" {
            return .not(try controlExpression(prefix.expression, roots: roots))
        }
        let elements: [ExprSyntax]
        if let sequence = expression.as(SequenceExprSyntax.self) { elements = Array(sequence.elements) }
        else if let infix = expression.as(InfixOperatorExprSyntax.self) {
            elements = [infix.leftOperand, infix.operator, infix.rightOperand]
        } else { throw error }
        if elements.count > 3, !elements.count.isMultiple(of: 2),
           stride(from: 1, to: elements.count, by: 2).allSatisfy({
               elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "+"
           }) {
            var value = try controlExpression(elements[0], roots: roots)
            for index in stride(from: 2, to: elements.count, by: 2) {
                value = .add(value, try controlExpression(elements[index], roots: roots))
            }
            return value
        }
        guard elements.count == 3, let operation = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text else {
            throw error
        }
        let lhs = try controlExpression(elements[0], roots: roots)
        let rhs = try controlExpression(elements[2], roots: roots)
        switch operation {
        case "==": return .equal(lhs, rhs)
        case "!=": return .notEqual(lhs, rhs)
        case "<": return .lessThan(lhs, rhs)
        case "<=": return .lessOrEqual(lhs, rhs)
        case ">": return .greaterThan(lhs, rhs)
        case ">=": return .greaterOrEqual(lhs, rhs)
        case "&&": return .and(lhs, rhs)
        case "||": return .or(lhs, rhs)
        case "+": return .add(lhs, rhs)
        case "-": return .subtract(lhs, rhs)
        case "/": return .divide(lhs, rhs)
        case "%": return .modulo(lhs, rhs)
        default: throw error
        }
    }

    private static var unsupported: InitialFailureEvidenceError { .unsupportedGeneratedOutput }

    private static func name(_ token: TokenSyntax) -> String { token.identifier?.name ?? token.text }

    private static func referenceToken(_ expression: ExprSyntax?) -> TokenSyntax? {
        expression?.as(DeclReferenceExprSyntax.self)?.baseName
    }

    private static func reference(_ expression: ExprSyntax?) -> String? {
        referenceToken(expression).map(name)
    }

    private static func letBinding(_ item: CodeBlockItemSyntax) -> (String, ExprSyntax)? {
        letBindingTokens(item).map { (name($0.0), $0.1) }
    }

    private static func letBindingTokens(_ item: CodeBlockItemSyntax) -> (TokenSyntax, ExprSyntax)? {
        guard let declaration = item.item.as(VariableDeclSyntax.self), declaration.bindingSpecifier.text == "let",
              declaration.bindings.count == 1, let binding = declaration.bindings.first,
              let token = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let value = binding.initializer?.value, binding.accessorBlock == nil else { return nil }
        return (token, value)
    }

    private static func labelReference(_ expression: ExprSyntax?) -> Label? {
        guard let access = expression?.as(MemberAccessExprSyntax.self), let enumName = reference(access.base) else { return nil }
        return .init(enumName: enumName, caseName: name(access.declName.baseName))
    }

    private static func rootDeclaration(_ item: CodeBlockItemSyntax, in scope: String) throws -> (String, String?)? {
        try scopedRootDeclaration(item, in: scope).map { ($0.binding, $0.explicit) }
    }

    private static func scopedRootDeclaration(_ item: CodeBlockItemSyntax, in scope: String) throws
        -> (binding: String, explicit: String?, initializer: LabeledExprSyntax)? {
        guard let (binding, value) = letBinding(item), let call = value.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              reference(member.base) == scope, name(member.declName.baseName) == "sharedVar",
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              call.arguments.filter({ $0.label?.text == "_name" }).count <= 1,
              call.arguments.allSatisfy({ ["_name", "label", "initial", "initiallyIn"].contains($0.label?.text ?? "") })
        else { return nil }
        let initializers = call.arguments.filter { $0.label?.text == "initial" || $0.label?.text == "initiallyIn" }
        guard initializers.count == 1, let initializer = initializers.first else { return nil }
        return (binding, try literal(call.arguments.first(where: { $0.label?.text == "_name" })?.expression), initializer)
    }

    private static func scalarLiteralInitializer(_ initializer: LabeledExprSyntax) -> TLAValue? {
        guard initializer.label?.text == "initial",
              let expression = try? controlExpression(initializer.expression, roots: [:]) else { return nil }
        switch expression {
        case .value(.int(let value)): return .int(value)
        case .value(.bool(let value)): return .bool(value)
        default: return nil
        }
    }

    private static func enumBindings(in members: MemberBlockItemListSyntax, named enumNames: Set<String>) throws
        -> [(Label, String?)] {
        let enums = members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.filter { enumNames.contains(name($0.name)) }
        guard enums.count == enumNames.count, Set(enums.map { name($0.name) }) == enumNames else { throw unsupported }
        return try enums.flatMap { enumeration in
            guard enumeration.attributes.isEmpty, enumeration.genericParameterClause == nil,
                  let type = enumeration.inheritanceClause?.inheritedTypes.first?.type.as(IdentifierTypeSyntax.self),
                  name(type.name) == "String" else { throw unsupported }
            var caseNames: Set<String> = []
            return try enumeration.memberBlock.members.flatMap { member -> [(Label, String?)] in
                guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else { throw unsupported }
                return try cases.elements.map { element in
                    guard element.parameterClause == nil, caseNames.insert(name(element.name)).inserted else { throw unsupported }
                    let explicit = try literal(element.rawValue?.value)
                    return (Label(enumName: name(enumeration.name), caseName: name(element.name)), explicit)
                }
            }
        }
    }

    private static func literal(_ expression: ExprSyntax?) throws -> String? {
        guard let expression else { return nil }
        guard let value = expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else { throw unsupported }
        return value
    }

    private static func optionalLiteral(_ literal: String?) -> String {
        guard let literal else { return #"[present |-> FALSE, value |-> ""]"# }
        return "[present |-> TRUE, value |-> \(TLAValue.string(literal))]"
    }

    private static func set(_ rows: [String]) -> String { "{\(rows.joined(separator: ", "))}" }

    private static func tuple(_ rows: [String]) -> String { "<<\(rows.joined(separator: ", "))>>" }
}
