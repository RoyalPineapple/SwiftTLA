import SwiftSyntax
import SwiftParser
import SwiftBasicFormat

extension ParserSession {
    // MARK: - Unified spec builder parser

    /// Source-boundary declaration facts for one specification closure.
    public struct BoundSourceContext: Sendable, Equatable {
        public struct Variable: Sendable, Equatable {
            public let sourceName: String
            public let swiftTypeName: String?

            public init(sourceName: String, swiftTypeName: String?) {
                self.sourceName = sourceName
                self.swiftTypeName = swiftTypeName
            }
        }

        public let variables: [Variable]

        public init(variables: [Variable] = []) {
            self.variables = variables
        }

        public var swiftVariableTypes: [String: String] {
            Dictionary(
                uniqueKeysWithValues: variables.compactMap { variable in
                    variable.swiftTypeName.map { (variable.sourceName, $0) }
                }
            )
        }
    }

    public struct ParsedSpecComponents {
        /// Canonical formal variables and Swift-only type facts for generated
        /// surface code.
        public var variables: [ParsedVariable] = []
        public var actions: [ParsedAction] = []
        public var symmetricCollections: [ParsedSymmetricCollection] = []
        public var collectionActions: [ParsedCollectionAction] = []
        public var diagnostics: [SymmetricCollectionParseDiagnostic] = []
        public var invariants: [(name: String, body: StateExpr)] = []
        public var temporal: [(name: String, expr: TemporalExpr)] = []
        public var fairness: [FairnessCondition] = []
        public var constraint: StateExpr?
        public var imports: [TLASpec] = []
        public var importConfigurations: [FormalModuleConfiguration] = []
        public var moduleInstances: [FormalModuleInstance] = []
        public var refinements: [RefinementDecl] = []
        public var requiredCapabilities: [FormalCapability] = []
        public var extendsModules: [StandardModule] = []
        public var sourceAlgorithms: [Algorithm] = []
        public var formalParameters: [FormalModuleParameter] = []
        public var formalOperatorDefinitions: [FormalOperatorDefinition] = []
        public var symmetrySets: [SymmetrySet] = []
        /// Authored algorithms in the source model.
        public var algorithmFidelityTokens: [AlgorithmFidelityToken] = []
        public var constants: [ConstantDecl] = []
        /// The parser's top-level declaration facts for generated Swift.
        public var sourceContext = BoundSourceContext()
        var instanceBindings: [String: FormalModuleInstance] = [:]
        var sourceValues: [String: StateExpr] = [:]

        public func swiftVariableTypes() -> [String: String] {
            var types = sourceContext.swiftVariableTypes
            for algorithm in sourceAlgorithms {
                let localNames: Set<String> = Set(algorithm.model.processes.flatMap { process in
                    process.components.compactMap {
                        guard case .local(let state) = $0 else { return nil }
                        return state.root
                    }
                })
                for state in algorithm.model.stateDeclarations {
                    if let type = state.swiftTypeName {
                        types[state.root] = localNames.contains(state.root) ? "TLAValue" : type
                    }
                }
            }
            return types
        }

        package func machineSurfaceSwiftFacts(
            for compilation: CompiledSpecification
        ) -> MachineSurfaceSwiftFacts {
            let processDomains = sourceAlgorithms.flatMap { algorithm in
                algorithm.model.processes.map { ($0.domain, $0.typeName) }
            }
            var actionBindingTypes = Dictionary(
                uniqueKeysWithValues: actions.map { ($0.name, $0.bindingSwiftTypes) }
            )
            for action in compilation.spec.actions {
                let bindings = action.bindings.reduce(into: [String: String]()) { types, binding in
                    if let domain = processDomains.first(where: { $0.0 == binding.values }) {
                        types[binding.name] = domain.1
                    }
                }
                if !bindings.isEmpty { actionBindingTypes[action.name] = bindings }
            }
            return .init(
                variableTypes: swiftVariableTypes(),
                actionBindingTypes: actionBindingTypes,
                symmetricCollections: Dictionary(uniqueKeysWithValues: symmetricCollections.map {
                    ($0.name, .init(elementType: $0.elementType, valueType: $0.valueType))
                }),
                collectionActions: Dictionary(uniqueKeysWithValues: collectionActions.map { ($0.name, $0.collectionName) })
            )
        }
    }

    public struct ParsedVariable: Sendable, Equatable {
        public var formal: NamedVar
        public var swiftTypeName: String?

        public init(
            name: String,
            initial: TLAValue,
            initialSet: StateExpr? = nil,
            initExpr: StateExpr? = nil,
            lazySet: StateExpr? = nil,
            collectionType: CollectionVarType = .scalar,
            swiftTypeName: String? = nil
        ) {
            self.formal = NamedVar(
                name: name,
                initial: initial,
                initialSet: initialSet,
                initExpr: initExpr,
                lazySet: lazySet,
                collectionType: collectionType
            )
            self.swiftTypeName = swiftTypeName
        }

        public init(formal: NamedVar, swiftTypeName: String? = nil) {
            self.formal = formal
            self.swiftTypeName = swiftTypeName
        }

        public var name: String { formal.name }
        public var initial: TLAValue { formal.initial }
        public var initialSet: StateExpr? { formal.initialSet }
        public var initExpr: StateExpr? { formal.initExpr }
        public var lazySet: StateExpr? { formal.lazySet }
        public var collectionType: CollectionVarType { formal.collectionType }
    }

    public struct ParsedAction: Sendable, Equatable {
        public let name: String
        public let body: ActionExpr
        public let bindings: [ActionBinding]
        public let bindingSwiftTypes: [String: String]

        public init(
            name: String,
            body: ActionExpr,
            bindings: [ActionBinding] = [],
            bindingSwiftTypes: [String: String] = [:]
        ) {
            self.name = name
            self.body = body
            self.bindings = bindings
            self.bindingSwiftTypes = bindingSwiftTypes
        }
    }

    public struct ParsedSymmetricCollection {
        public let name: String
        public let elementType: String
        public let valueType: String
        public let verificationScope: Int
        public let source: String
        public let declaration: SymmetricCollectionDecl
    }

    public struct ParsedCollectionAction {
        public let name: String
        public let collectionName: String
        /// Swift-only source provenance. The executable action is retained
        /// only in `ParsedAction` and lowered once into `TLASpec`.
        public let source: String
    }

    /// Evidence retained when the source parser cannot form a formal model.
    ///
    /// The historical name is kept because callers already catch this error;
    /// it now covers every source-parser diagnostic, not only collections.
    public struct SymmetricCollectionParseDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
        public struct SourceSpan: Sendable, Hashable, CustomStringConvertible {
            public enum Location: Sendable, Hashable, CustomStringConvertible {
                case utf8Offset(Int)
                case unavailable

                public var description: String {
                    switch self {
                    case .utf8Offset(let offset): return "UTF-8 offset \(offset)"
                    case .unavailable: return "source offset unavailable"
                    }
                }
            }

            public let location: Location
            public let utf8Length: Int

            public init(location: Location, utf8Length: Int) {
                self.location = location
                self.utf8Length = utf8Length
            }

            public var description: String {
                "\(location), length \(utf8Length)"
            }
        }

        /// Short stable summary for clients that already display a headline.
        public let message: String
        /// The exact Swift source fragment that the parser rejected.
        public let source: String
        public let sourceSpan: SourceSpan
        public let expected: String
        public let actual: String
        public let nextSafeAction: String

        public init(
            message: String,
            source: String,
            expected: String = "a supported SwiftTLA declaration or expression",
            actual: String = "",
            nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again."
        ) {
            self.init(
                message: message,
                source: source,
                sourceSpan: SourceSpan(location: .unavailable, utf8Length: source.utf8.count),
                expected: expected,
                actual: actual,
                nextSafeAction: nextSafeAction
            )
        }

        public init(
            message: String,
            source: String,
            sourceSpan: SourceSpan,
            expected: String = "a supported SwiftTLA declaration or expression",
            actual: String = "",
            nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again."
        ) {
            self.message = message
            self.source = source
            self.sourceSpan = sourceSpan
            self.expected = expected
            self.actual = actual.isEmpty ? source.trimmingCharacters(in: .whitespacesAndNewlines) : actual
            self.nextSafeAction = nextSafeAction
        }

        public init<Node: SyntaxProtocol>(
            message: String,
            source: Node,
            expected: String = "a supported SwiftTLA declaration or expression",
            actual: String = "",
            nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again."
        ) {
            let fragment = source.description.trimmingCharacters(in: .whitespacesAndNewlines)
            self.init(
                message: message,
                source: fragment,
                sourceSpan: SourceSpan(
                    location: .utf8Offset(source.positionAfterSkippingLeadingTrivia.utf8Offset),
                    utf8Length: fragment.utf8.count
                ),
                expected: expected,
                actual: actual,
                nextSafeAction: nextSafeAction
            )
        }

        public var description: String {
            "What failed: \(message) Where: \(sourceSpan). Expected: \(expected). "
                + "Actual: \(actual). "
                + "Next safe action: \(nextSafeAction)"
        }
    }

      func parseSpecClosure(_ closure: ClosureExprSyntax) -> ParsedSpecComponents {
        var result = ParsedSpecComponents()
        let collectionTypes = collectSymmetricCollectionTypes(in: closure)
        for statement in closure.statements {
            if case .expr(let expression) = statement.item,
               let fc = expression.as(FunctionCallExprSyntax.self) {
                parseBuilderCall(fc, into: &result, collectionTypes: collectionTypes)
            } else if case .expr(let expression) = statement.item,
                      let reference = expression.as(DeclReferenceExprSyntax.self),
                      result.instanceBindings[reference.baseName.text] != nil {
                continue
            } else if let forStmt = statement.item.as(ForStmtSyntax.self) {
                parseForLoop(forStmt, into: &result)
            } else if case .decl(let decl) = statement.item,
                      let varDecl = decl.as(VariableDeclSyntax.self) {
                parseLocalDeclaration(varDecl, into: &result)
            } else {
                result.diagnostics.append(.init(
                    message: "Specification body contains an unsupported item.",
                    source: statement.item
                ))
            }
        }
        result.sourceContext = .init(variables: result.variables.map {
            .init(sourceName: $0.name, swiftTypeName: $0.swiftTypeName)
        })
        return result
    }

    private func parseLocalDeclaration(
        _ declaration: VariableDeclSyntax,
        into result: inout ParsedSpecComponents
    ) {
        var containsVariableConstructor = false
        for binding in declaration.bindings {
            guard let sourceName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self)
            else {
                result.diagnostics.append(.init(
                    message: "Specification body contains an unsupported local declaration.",
                    source: binding
                ))
                continue
            }
            if call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Instance" {
                let count = result.moduleInstances.count
                parseFormalModuleInstance(
                    call,
                    into: &result,
                    scope: typedFacadeScope(.empty, bindings: result.sourceValues.keys.sorted().compactMap { name in
                        result.sourceValues[name].map { (name, $0) }
                    })
                )
                guard result.moduleInstances.count == count + 1,
                      let instance = result.moduleInstances.last
                else { continue }
                result.instanceBindings[sourceName] = instance
            } else if resolveVarCall(call) != nil {
                containsVariableConstructor = true
            } else if let value = decodeTypedFacadeValue(
                ExprSyntax(call),
                scope: typedFacadeScope(.empty, bindings: result.sourceValues.keys.sorted().compactMap { name in
                    result.sourceValues[name].map { (name, $0) }
                })
            ) {
                result.sourceValues[sourceName] = value
            } else {
                result.diagnostics.append(.init(
                    message: "Specification body contains an unsupported local declaration.",
                    source: binding
                ))
            }
        }
        if containsVariableConstructor {
            parseVarDecl(declaration, into: &result)
        }
    }

    func parseForLoop(_ forStmt: ForStmtSyntax, into result: inout ParsedSpecComponents) {
        guard let pattern = forStmt.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let range = parseIntegerClosedRange(forStmt.sequence)
        else {
            result.diagnostics.append(.init(
                message: "Specification for-loop requires a literal closed integer range.",
                source: forStmt,
                expected: "for item in 1...3 { Action(\"name\") { ... } }"
            ))
            return
        }

        let body = forStmt.body.statements
        for i in range {
            for bodyStmt in body {
                guard case .expr(let expr) = bodyStmt.item,
                      let fc = expr.as(FunctionCallExprSyntax.self)
                else {
                    result.diagnostics.append(.init(
                        message: "Specification for-loop body contains an unsupported item.",
                        source: bodyStmt.item
                    ))
                    continue
                }
                parseBuilderCall(fc, into: &result, loopVar: pattern, loopValue: i)
            }
        }
    }

    /// Parses supported variable bindings into `ParsedSpecComponents.variables`.
    func parseVarDecl(_ varDecl: VariableDeclSyntax, into result: inout ParsedSpecComponents) {
        for binding in varDecl.bindings {
            guard let patternName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let initializer = binding.initializer?.value,
                  let fc = initializer.as(FunctionCallExprSyntax.self)
            else { continue }

            let stateVarInfo = resolveVarCall(fc)
            let varTypeName = swiftValueType(from: binding.typeAnnotation)
                ?? stateVarInfo?.1
                ?? resolveVarTypeArg(fc)
            let callName = stateVarInfo?.0 ?? (resolveVarTypeArg(fc) != nil ? "Var" : nil)

            guard callName != nil else { continue }

            let args = Array(fc.arguments)

            if callName == "Var" && args.count < 2,
               isDefaultConstructibleVarType(fc),
               let name = args.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
                result.variables.append(.init(name: name, initial: .int(0), swiftTypeName: varTypeName))
                continue
            }

            if let rangeExpr = args.first(where: { $0.label?.text == "in" })?.expression {
                if callName == "SharedVar", let range = parseIntegerClosedRange(rangeExpr) {
                    result.variables.append(.init(
                        name: patternName,
                        initial: .int(0),
                        initialSet: .setLiteral(range.map { .value(.int($0)) }),
                        swiftTypeName: varTypeName ?? "Int"
                    ))
                    continue
                }
                if callName == "SharedVar",
                   let initialSet = decodeStateExpr(rangeExpr),
                   case .setLiteral = initialSet,
                   let elementType = setExpressionElementTypeName(rangeExpr) {
                    result.variables.append(.init(
                        name: patternName, initial: .int(0), initialSet: initialSet,
                        swiftTypeName: varTypeName ?? elementType
                    ))
                    continue
                }
                let lowerBound = parseRangeLowerBound(rangeExpr)
                result.variables.append(.init(
                    name: patternName, initial: .int(lowerBound), swiftTypeName: varTypeName
                ))
                continue
            }

            if let valuesArg = args.first(where: { $0.label?.text == "values" })?.expression {
                let firstValue = parseValuesFirst(valuesArg)
                result.variables.append(.init(
                    name: patternName, initial: .string(firstValue), swiftTypeName: varTypeName
                ))
                continue
            }

            guard !args.isEmpty else { continue }

            if let stringLit = args[0].expression.as(StringLiteralExprSyntax.self) {
                guard let varName = stringLit.representedLiteralValue else { continue }
                if callName == "SharedVar" {
                    guard args.count >= 2,
                          let initial = decodeTypedFacadeValue(args[1].expression, scope: .empty)
                    else {
                        result.diagnostics.append(.init(
                            message: "SharedVar requires a supported initial formal expression.",
                            source: fc
                        ))
                        continue
                    }
                    let inferredType = initialValueTypeName(from: args[1].expression)
                    result.variables.append(.init(
                        name: varName,
                        initial: .int(0),
                        initExpr: initial,
                        swiftTypeName: varTypeName ?? inferredType
                    ))
                    continue
                }
                let initial: TLAValue
                if args.count >= 2 {
                    guard let parsed = parsedInitialValue(args[1].expression) else {
                        result.diagnostics.append(.init(
                            message: "Var requires a supported initial formal value.",
                            source: fc
                        ))
                        continue
                    }
                    initial = parsed
                } else {
                    initial = .int(0)
                }
                let inferredType = args.count >= 2 ? initialValueTypeName(from: args[1].expression) : nil
                result.variables.append(.init(
                    name: varName, initial: initial, swiftTypeName: varTypeName ?? inferredType
                ))
            } else {
                guard let initial = parsedInitialValue(args[0].expression) else {
                    result.diagnostics.append(.init(
                        message: "Var requires a supported initial formal value.",
                        source: fc
                    ))
                    continue
                }
                let inferredType = initialValueTypeName(from: args[0].expression)
                result.variables.append(.init(
                    name: patternName, initial: initial, swiftTypeName: varTypeName ?? inferredType
                ))
            }
        }
    }

    /// Resolves a supported low-level variable call expression.
    /// Returns nil if the call is not a variable constructor.
    func resolveVarCall(_ fc: FunctionCallExprSyntax) -> (String, String?)? {
        if let ref = fc.calledExpression.as(DeclReferenceExprSyntax.self) {
            guard ["Var", "SharedVar"].contains(ref.baseName.text) else { return nil }
            return (ref.baseName.text, nil)
        }
        if let generic = fc.calledExpression.as(GenericSpecializationExprSyntax.self),
           let name = terminalTypeName(in: generic.expression) {
            guard name == "Var" else { return nil }
            let typeArgs = Array(generic.genericArgumentClause.arguments)
            let swiftTypeName = typeArgs.first.flatMap { Self.sourceTypeSpelling($0.argument) }
            return (name, swiftTypeName)
        }
        return nil
    }

    func resolveVarTypeArg(_ fc: FunctionCallExprSyntax) -> String? {
        guard let generic = fc.calledExpression.as(GenericSpecializationExprSyntax.self),
              terminalTypeName(in: generic.expression) == "Var"
        else {
            if let ref = fc.calledExpression.as(DeclReferenceExprSyntax.self),
               ref.baseName.text == "Var" {
                return nil
            }
            return nil
        }
        let typeArgs = Array(generic.genericArgumentClause.arguments)
        return typeArgs.first.flatMap { Self.sourceTypeSpelling($0.argument) }
    }

    /// Extracts the value type from a variable declaration annotation without
    /// rendering or reparsing its syntax. `SharedVariable<Mode>` contributes
    /// `Mode`; an explicit value annotation contributes itself.
    func swiftValueType(from annotation: TypeAnnotationSyntax?) -> String? {
        guard let type = annotation?.type else { return nil }
        if let generic = type.as(IdentifierTypeSyntax.self),
           ["SharedVariable", "LocalVariable"].contains(generic.name.text),
           let argument = generic.genericArgumentClause?.arguments.first?.argument {
            return Self.sourceTypeSpelling(argument)
        }
        if let generic = type.as(MemberTypeSyntax.self),
           ["SharedVariable", "LocalVariable"].contains(generic.name.text),
           let argument = generic.genericArgumentClause?.arguments.first?.argument {
            return Self.sourceTypeSpelling(argument)
        }
        return Self.sourceTypeSpelling(type)
    }

    func isDefaultConstructibleVarType(_ call: FunctionCallExprSyntax) -> Bool {
        guard let generic = call.calledExpression.as(GenericSpecializationExprSyntax.self),
              terminalTypeName(in: generic.expression) == "Var",
              let type = generic.genericArgumentClause.arguments.first?.argument
        else { return false }
        switch facadeTypeName(type) {
        case "Function", "Record", "SetExpr": return true
        default: return false
        }
    }

    func parseIntegerClosedRange(_ expression: ExprSyntax) -> ClosedRange<Int>? {
        guard let sequence = expression.as(SequenceExprSyntax.self) else { return nil }
        let elements = Array(sequence.elements)
        guard elements.count == 3,
              elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text == "...",
              let lowerSyntax = elements[0].as(IntegerLiteralExprSyntax.self),
              let upperSyntax = elements[2].as(IntegerLiteralExprSyntax.self),
              let lower = Int(lowerSyntax.literal.text),
              let upper = Int(upperSyntax.literal.text),
              lower <= upper
        else { return nil }
        return lower...upper
    }

    /// Returns the formal element type from `SetExpr<Element>.literal(...)`.
    /// This is syntax-only: the parser must not consult the runtime builder.
    func setExpressionElementTypeName(_ expression: ExprSyntax) -> String? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Where",
           let candidates = call.arguments.first?.expression {
            return setExpressionElementTypeName(candidates)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           name == "Subsets" || name == "NonEmptySubsets",
           let values = call.arguments.first(where: { $0.label?.text == "of" })?.expression,
           let element = setExpressionElementTypeName(values) {
            return "SetExpr<\(element)>"
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Functions",
           let domainSyntax = call.arguments.first(where: { $0.label?.text == "from" })?.expression,
           let domain = finiteAlgorithmDomain(domainSyntax),
           let rangeSyntax = call.arguments.first(where: { $0.label?.text == "to" })?.expression,
           let range = setExpressionElementTypeName(rangeSyntax) {
            return "Function<\(domain.typeName), \(range)>"
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           name == "Sequences" || name == "SortedSequences" || name == "ZeroBasedSequences",
           let members = call.arguments.first(where: { $0.label?.text == "of" })?.expression,
           let element = setExpressionElementTypeName(members) {
            return name == "ZeroBasedSequences"
                ? "ZeroBasedSequence<\(element)>"
                : "TupleExpr<\(element)>"
        }
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "literal",
              let base = member.base
        else { return nil }
        guard let type = typedFacadeType(base), type.name == "SetExpr" else { return nil }
        return type.argument(at: 0).flatMap(Self.sourceTypeSpelling)
    }

    /// Extracts the lower bound from a range expression like `1...12`.
    func parseRangeLowerBound(_ expression: ExprSyntax) -> Int {
        if let seq = expression.as(SequenceExprSyntax.self) {
            let elements = Array(seq.elements)
            if let firstInt = elements.first?.as(IntegerLiteralExprSyntax.self),
               let lower = Int(firstInt.literal.text) {
                return lower
            }
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let firstInt = infix.leftOperand.as(IntegerLiteralExprSyntax.self),
           let lower = Int(firstInt.literal.text) {
            return lower
        }
        return 0
    }

    /// Extracts the first string value from `["a", "b"]`.
    func parseValuesFirst(_ expression: ExprSyntax) -> String {
        if let array = expression.as(ArrayExprSyntax.self),
           let first = array.elements.first?.expression.as(StringLiteralExprSyntax.self) {
            return first.representedLiteralValue ?? ""
        }
        return ""
    }

    /// Converts a Swift initializer expression to a TLAValue.
    func parseInitialExpr(_ expression: ExprSyntax) -> TLAValue? {
        if let decoded = decodeStateExpr(expression), case .value(let value) = decoded {
            return value
        }
        if let intVal = expression.as(IntegerLiteralExprSyntax.self) {
            return Int(intVal.literal.text).map(TLAValue.int)
        }
        if let boolVal = expression.as(BooleanLiteralExprSyntax.self) {
            return .bool(boolVal.literal.text == "true")
        }
        if let stringLit = expression.as(StringLiteralExprSyntax.self) {
            return stringLit.representedLiteralValue.map(TLAValue.string)
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            if let baseRef = memberAccess.base?.as(DeclReferenceExprSyntax.self),
               let value = enumDefinition(named: baseRef.baseName.text)?
                    .value(named: memberAccess.declName.baseName.text) {
                return value
            }
            let caseName = memberAccess.declName.baseName.text
            for definition in enumDefinitions {
                if let value = definition.value(named: caseName) { return value }
            }
        }
        if let fc = expression.as(FunctionCallExprSyntax.self),
           let memberAccess = fc.calledExpression.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "TLAValue" {
            return parseTLAValueConstructor(name: memberAccess.declName.baseName.text, call: fc)
        }
        return nil
    }

    /// Returns the enum type name if `expression` is an enum case reference.
    /// `.idle` → `nil` (implicit member, type unknown from this AST).
    /// `CameraMode.idle` → `"CameraMode"` (explicit member, type known).
    func enumCaseTypeName(from expression: ExprSyntax) -> String? {
        guard let memberAccess = expression.as(MemberAccessExprSyntax.self) else { return nil }
        if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            return base.baseName.text
        }
        return nil
    }

    func initialValueTypeName(from expression: ExprSyntax) -> String? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "IntRange" {
            return "SetExpr<Int>"
        }
        if expression.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if expression.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        if expression.is(StringLiteralExprSyntax.self) { return "String" }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.arguments.isEmpty,
           call.trailingClosure == nil,
           let constructor = typedFacadeType(call.calledExpression) {
            switch constructor.name {
            case "SetExpr", "TupleExpr", "ZeroBasedSequence":
                return constructor.renderedSourceName
            default:
                break
            }
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "filled",
           let base = member.base,
           let type = typedFacadeType(base),
           type.name == "ZeroBasedSequence" {
            return type.renderedSourceName
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLAValue" {
            return "TLAValue"
        }
        return enumCaseTypeName(from: expression)
    }

    /// Evaluates a closed typed formal initializer through the same expression
    /// decoder used for actions. Literal-only parsing is insufficient for
    /// values such as `IntRange(1, through: 4)`.
    func parsedInitialValue(_ expression: ExprSyntax) -> TLAValue? {
        if let decoded = decodeStateExpr(expression),
           let value = try? evaluateClosed(decoded) {
            return value
        }
        return parseInitialExpr(expression)
    }

    func parseBuilderCall(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        loopVar: String? = nil,
        loopValue: Int? = nil,
        collectionTypes: [String: SymmetricCollectionSourceTypes] = [:]
    ) {
        guard let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else {
            result.diagnostics.append(.init(
                message: "Specification body contains an unsupported call.",
                source: call
            ))
            return
        }

        switch name {
        case "Algorithm":
            parseAlgorithm(call, into: &result)
        case "SymmetricCollection":
            parseSymmetricCollectionDecl(call, into: &result, collectionTypes: collectionTypes)
        case "CollectionAction":
            parseCollectionAction(call, into: &result)
        case "Variable":
            let existingVariable = call.arguments.first.flatMap { parsedVariableName($0.expression) }
            parseVariableDecl(call, into: &result)
            if let existingVariable {
                mergeVariableDeclaration(named: existingVariable, into: &result)
            }
            validateVariableDeclaration(call, into: &result)
        case "Action":
            parseAction(call, into: &result, loopVar: loopVar, loopValue: loopValue)
        case "Invariant":
            parseInvariant(call, into: &result)
        case "Constraint":
            if let argument = call.arguments.first,
               let expression = decodeStateExpr(argument.expression) {
                result.constraint = result.constraint.map { .and($0, expression) } ?? expression
            } else {
                result.diagnostics.append(.init(
                    message: "Constraint requires a supported state expression.",
                    source: call
                ))
            }
        case "Constant":
            parseConstantDecl(call, into: &result)
        case "Extends":
            let modules = call.arguments.compactMap { argument -> StandardModule? in
                guard let member = argument.expression.as(MemberAccessExprSyntax.self) else { return nil }
                switch member.declName.baseName.text {
                case "integers": return .integers
                case "naturals": return .naturals
                case "finiteSets": return .finiteSets
                case "sequences": return .sequences
                case "tlc": return .tlc
                default: return nil
                }
            }
            guard modules.count == call.arguments.count else {
                result.diagnostics.append(.init(message: "Extends requires standard modules such as .integers.", source: call))
                return
            }
            result.extendsModules.append(contentsOf: modules)
        case "Parameter":
            guard let name = extractStringArg(call, index: 0), !name.isEmpty else {
                result.diagnostics.append(.init(message: "Parameter requires a name.", source: call))
                return
            }
            guard !result.formalParameters.map(\.name).contains(name) else {
                result.diagnostics.append(.init(message: "Parameter '\(name)' is declared more than once.", source: call))
                return
            }
            let kind: FormalModuleParameterKind
            if let kindExpression = call.arguments.first(where: { $0.label?.text == "kind" })?.expression {
                guard let member = kindExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
                      let parsedKind = FormalModuleParameterKind(rawValue: member)
                else {
                    result.diagnostics.append(.init(message: "Parameter kind must be .constant or .variable.", source: kindExpression))
                    return
                }
                kind = parsedKind
            } else {
                kind = .constant
            }
            result.formalParameters.append(FormalModuleParameter(name, kind: kind))
        case "FormalDefinition":
            parseFormalDefinition(call, into: &result)
        case "LeadsTo", "Eventually", "Always", "AlwaysEventually", "EventuallyAlways":
            if let expr = decodeTemporal(call) {
                result.temporal.append((name, expr))
            } else {
                result.diagnostics.append(.init(
                    message: "Temporal declaration requires a supported temporal expression.",
                    source: call
                ))
            }
        case "WeakFairness", "StrongFairness", "WeakFairnessNext", "StrongFairnessNext":
            if let fc = decodeFairness(call) {
                result.fairness.append(fc)
            } else {
                result.diagnostics.append(.init(
                    message: "Fairness declaration requires a supported fairness expression.",
                    source: call
                ))
            }
        case "Import":
            guard let argument = call.arguments.first?.expression else {
                result.diagnostics.append(.init(message: "Import requires a named formal module.", source: call))
                return
            }
            guard let moduleName = formalModuleName(from: argument)
            else {
                result.diagnostics.append(.init(message: "Import requires a named formal module.", source: call))
                return
            }
            guard let module = BuiltInFormalModules.resolve(moduleName) else {
                result.diagnostics.append(.init(message: "Import requires a built-in formal module.", source: call))
                return
            }
            result.imports.append(module)
            if let configuration = parseFormalModuleConfiguration(
                call,
                moduleName: module.name
            ) {
                result.importConfigurations.append(configuration)
            }
        case "Instance":
            parseFormalModuleInstance(call, into: &result)
        case "Refinement":
            parseRefinement(call, into: &result)
        case "RequireCapability":
            parseCapabilityRequirement(call, into: &result)
        case "Symmetry":
            parseSymmetry(call, into: &result)
        default:
            result.diagnostics.append(.init(
                message: "Specification body contains an unsupported declaration '\(name)'.",
                source: call
            ))
        }
    }

    private func parseSymmetry(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let variableName = extractStringArg(call, index: 0), !variableName.isEmpty,
              let valuesSyntax = call.arguments.dropFirst().first?.expression,
              let values = parseSymmetryValues(valuesSyntax)
        else {
            result.diagnostics.append(.init(
                message: "Symmetry requires a name and a finite domain.",
                source: call.description,
                expected: "Symmetry(\"TxId\", Set(Transaction.all))"
            ))
            return
        }
        result.symmetrySets.append(SymmetrySet(variableName: variableName, values: Set(values)))
    }

    private func parseRefinement(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let name = extractStringArg(call, index: 0), !name.isEmpty,
              let instanceSyntax = call.arguments.first(where: { $0.label?.text == "instance" })?.expression,
              let sourceName = instanceSyntax.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let instance = result.instanceBindings[sourceName]
        else {
            result.diagnostics.append(.init(
                message: "Refinement requires a declared Instance binding.",
                source: call,
                expected: "let C = Instance(\"C\", of: Module.module); C; Refinement(name: \"Refines\", instance: C, operator: .spec, mappings: mappings)",
                nextSafeAction: "Declare the instance in this specification, then pass that binding to Refinement."
            ))
            return
        }
        let target: RefinementDecl.Operator
        if let operatorSyntax = call.arguments.first(where: { $0.label?.text == "operator" })?.expression,
           let operatorName = operatorSyntax.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
           let parsedTarget = RefinementDecl.Operator(sourceName: operatorName) {
            target = parsedTarget
        } else if call.arguments.contains(where: { $0.label?.text == "operator" }) {
            result.diagnostics.append(.init(
                message: "Refinement requires a supported target operator.",
                source: call,
                expected: "operator: .spec",
                nextSafeAction: "Use one of RefinementDecl.Operator's declared cases."
            ))
            return
        }
        else {
            target = .spec
        }
        let mappings: [RefinementMapping]
        if let mappingExpression = call.arguments.first(where: { $0.label?.text == "mappings" })?.expression {
            guard let array = mappingExpression.as(ArrayExprSyntax.self) else {
                result.diagnostics.append(.init(
                    message: "Refinement mappings require an array of RefinementMapping values.",
                    source: mappingExpression
                ))
                return
            }
            var parsed: [RefinementMapping] = []
            let scope = typedFacadeScope(
                .empty,
                bindings: result.sourceValues.keys.sorted().compactMap { name in
                    result.sourceValues[name].map { (name, $0) }
                }
            )
            for element in array.elements {
                guard let mapping = element.expression.as(FunctionCallExprSyntax.self),
                      (mapping.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "RefinementMapping"
                        || mapping.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "init"),
                      let target = mapping.arguments.first?.expression,
                      let mappedName = refinementTargetName(target),
                      let source = mapping.arguments.first(where: { $0.label?.text == "from" })?.expression,
                      let expression = decodeTypedFacadeValue(source, scope: scope) ?? decodeStateExpr(source)
                else {
                    result.diagnostics.append(.init(
                        message: "Each refinement mapping must name an abstract declaration and provide a source expression.",
                        source: element.expression
                    ))
                    return
                }
                parsed.append(.init(target: mappedName, source: expression))
            }
            mappings = parsed
        } else {
            result.diagnostics.append(.init(
                message: "Refinement requires an explicit mapping for every abstract variable and parameter.",
                source: call
            ))
            return
        }
        result.refinements.append(.init(name: name, instance: instance.reference, operator: target, mappings: mappings))
    }

    private func refinementTargetName(_ expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    private func parseCapabilityRequirement(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let name = call.arguments.first?.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
              let capability = FormalCapability(rawValue: name) else {
            result.diagnostics.append(.init(
                message: "RequireCapability requires a declared FormalCapability case.",
                source: call
            ))
            return
        }
        result.requiredCapabilities.append(capability)
    }

    private func parseSymmetryValues(_ expression: ExprSyntax) -> [TLAValue]? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Set",
              let domainSyntax = call.arguments.first?.expression,
              let domain = finiteAlgorithmDomain(domainSyntax)
        else { return nil }
        return domain.values
    }

    private func parseFormalDefinition(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let definition = decodeFormalDefinition(call)
        else {
            result.diagnostics.append(.init(
                message: "FormalDefinition requires a name, supported formal parameters, and a formal body expression.",
                source: call.description,
                expected: "FormalDefinition(\"name\", parameters: [.value(\"value\")], body: expression) or FormalDefinition(\"name\", taking: Int.self) { value in expression }",
                nextSafeAction: "Use the formal-parameter form or a unary/binary typed closure with supported formal expressions."
            ))
            return
        }
        let name = definition.name
        let parameters = definition.parameters
        guard !result.formalOperatorDefinitions.contains(where: { $0.name == name }) else {
            result.diagnostics.append(.init(
                message: "FormalDefinition '\(name)' is declared more than once.",
                source: call
            ))
            return
        }
        guard Set(parameters.map(\.name)).count == parameters.count else {
            result.diagnostics.append(.init(
                message: "FormalDefinition '\(name)' cannot repeat a parameter name.",
                source: call
            ))
            return
        }
        result.formalOperatorDefinitions.append(definition)
    }

    func decodeFormalDefinition(
        _ call: FunctionCallExprSyntax
    ) -> FormalOperatorDefinition? {
        guard let name = extractStringArg(call, index: 0), !name.isEmpty else { return nil }

        if let parametersSyntax = call.arguments.first(where: { $0.label?.text == "parameters" })?.expression,
           let bodySyntax = call.arguments.first(where: { $0.label?.text == "body" })?.expression,
           let parameters = parseFormalParameters(parametersSyntax),
           let body = decodeTypedFacadeValue(bodySyntax, scope: .empty) ?? decodeStateExpr(bodySyntax) {
            return FormalOperatorDefinition(name: name, parameters: parameters, body: body,
                plusCalPhase: plusCalPhase(call), plusCalDependencies: plusCalDependencies(call))
        }

        guard let closure = call.trailingClosure,
              closure.statements.count == 1,
              case .expr(let bodySyntax) = closure.statements.first?.item
        else { return nil }
        let parameters = closureParameterNames(in: closure)
        let typeWitnesses = call.arguments.dropFirst().filter { argument in
            argument.label?.text != "plusCalPhase" && argument.label?.text != "dependsOn"
        }
        guard (1...2).contains(parameters.count),
              parameters.count == typeWitnesses.count,
              typeWitnesses.first?.label?.text == "taking",
              typeWitnesses.dropFirst().allSatisfy({ $0.label == nil }),
              typeWitnesses.allSatisfy({ isMetatype($0.expression) })
        else { return nil }
        let formalParameters = parameters.enumerated().map { index, _ in
            FormalParameter.value("value\(index)")
        }
        let scope = typedFacadeScope(
            .empty,
            bindings: zip(parameters, formalParameters).map {
                (sourceName: $0, value: StateExpr.variable($1.name))
            }
        )
        guard let body = decodeTypedFacadeValue(bodySyntax, scope: scope) else { return nil }
        return FormalOperatorDefinition(
            name: name,
            parameters: formalParameters,
            body: body,
            plusCalPhase: plusCalPhase(call),
            plusCalDependencies: plusCalDependencies(call)
        )
    }

    private func parseFormalParameters(_ expression: ExprSyntax) -> [FormalParameter]? {
        guard let array = expression.as(ArrayExprSyntax.self) else { return nil }
        let parameters: [FormalParameter?] = array.elements.map { element -> FormalParameter? in
            guard let call = element.expression.as(FunctionCallExprSyntax.self),
                  let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  let name = extractStringArg(call, index: 0)
            else { return nil }
            switch member.declName.baseName.text {
            case "value": return .value(name)
            case "operator":
                guard let arityExpression = call.arguments.first(where: { $0.label?.text == "arity" })?.expression,
                      let arityLiteral = arityExpression.as(IntegerLiteralExprSyntax.self),
                      let arity = Int(arityLiteral.literal.text), arity >= 0
                else { return nil }
                return .operator(name, arity: arity)
            default: return nil
            }
        }
        guard parameters.allSatisfy({ $0 != nil }) else { return nil }
        return parameters.compactMap { $0 }
    }

    private func parseFormalModuleInstance(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        scope: TypedFacadeScope = .empty
    ) {
        guard let name = extractStringArg(call, index: 0),
              let moduleArgument = call.arguments.first(where: { $0.label?.text == "of" })?.expression
        else {
            result.diagnostics.append(.init(message: "Instance requires a name and a named formal module.", source: call))
            return
        }
        guard let moduleName = formalModuleName(from: moduleArgument),
              let module = BuiltInFormalModules.resolve(moduleName)
        else {
            result.diagnostics.append(.init(message: "Instance requires a built-in formal module.", source: call))
            return
        }
        let arguments: [ModuleArgument]
        if let withExpression = call.arguments.first(where: { $0.label?.text == "with" })?.expression {
            guard let array = withExpression.as(ArrayExprSyntax.self) else {
                result.diagnostics.append(.init(message: "Instance 'with' requires an array of ModuleArgument values.", source: call))
                return
            }
            var parsedArguments: [ModuleArgument] = []
            for element in array.elements {
                guard let argumentCall = element.expression.as(FunctionCallExprSyntax.self),
                      (argumentCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ModuleArgument"
                        || argumentCall.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "init"),
                      let parameter = extractStringArg(argumentCall, index: 0),
                      let valueSyntax = argumentCall.arguments.first(where: { $0.label?.text == "value" })?.expression,
                      let value = decodeTypedFacadeValue(valueSyntax, scope: scope) ?? decodeStateExpr(valueSyntax)
                else {
                    result.diagnostics.append(.init(
                        message: "Each Instance argument must be ModuleArgument(\"parameter\", value: expression).",
                        source: element.expression
                    ))
                    return
                }
                parsedArguments.append(ModuleArgument(parameter, expression: value))
            }
            arguments = parsedArguments
        } else {
            arguments = []
        }
        guard Set(arguments.map(\.parameter)).count == arguments.count else {
            result.diagnostics.append(.init(message: "An Instance cannot bind the same parameter twice.", source: call))
            return
        }
        let declaredTargets = Set(module.formalParameters.map(\.name)).union(module.variables.map(\.name))
        guard Set(arguments.map(\.parameter)).isSubset(of: declaredTargets) else {
            result.diagnostics.append(.init(message: "Instance arguments must name declarations exported by '\(module.name)'.", source: call))
            return
        }
        result.moduleInstances.append(FormalModuleInstance(
            name, of: module, with: arguments,
            plusCalPhase: plusCalPhase(call), dependsOn: plusCalDependencies(call)
        ))
    }

    private func plusCalPhase(_ call: FunctionCallExprSyntax) -> AuthoredPlusCalDeclarationPhase {
        let phase = call.arguments.first(where: { $0.label?.text == "plusCalPhase" })?
            .expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        switch phase {
        case "define": return .define
        default: return .prelude
        }
    }

    private func plusCalDependencies(_ call: FunctionCallExprSyntax) -> [String] {
        guard let array = call.arguments.first(where: { $0.label?.text == "dependsOn" })?.expression.as(ArrayExprSyntax.self) else { return [] }
        return array.elements.compactMap { $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue }
    }

    private func parseFormalModuleConfiguration(
        _ call: FunctionCallExprSyntax,
        moduleName: String
    ) -> FormalModuleConfiguration? {
        guard let argument = call.arguments.first(where: { $0.label?.text == "configuring" })?.expression
        else { return nil }
        guard moduleName == "ZSequences",
              let call = argument.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "ZSequences",
              member.declName.baseName.text == "boundedNaturalNumbers",
              call.arguments.count == 1,
              let bounds = call.arguments.first?.expression,
              let range = parseIntegerClosedRange(bounds)
        else { return nil }
        return ZSequences.boundedNaturalNumbers(range)
    }

    private func formalModuleName(from expression: ExprSyntax) -> String? {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "module",
              let module = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }
        return module
    }

    func mergeVariableDeclaration(
        named name: String,
        into result: inout ParsedSpecComponents
    ) {
        let matchingIndices = result.variables.indices.filter { result.variables[$0].name == name }
        guard matchingIndices.count > 1, let latest = matchingIndices.last else { return }
        let existing = result.variables[matchingIndices[0]]
        let replacement = result.variables[latest]
        result.variables.remove(at: latest)
        result.variables[matchingIndices[0]] = .init(
            formal: replacement.formal,
            swiftTypeName: replacement.swiftTypeName ?? existing.swiftTypeName
        )
    }

    func validateVariableDeclaration(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        let arguments = Array(call.arguments)
        guard let reference = arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text else { return }
        guard arguments.count == 1 else {
            if arguments.count == 2, [nil, "in"].contains(arguments[1].label?.text) { return }
            result.diagnostics.append(.init(message: "Malformed Variable declaration", source: call))
            return
        }
        guard result.variables.contains(where: { $0.name == reference }) else {
            result.diagnostics.append(.init(
                message: "Variable '\(reference)' is not bound by a prior Var declaration",
                source: call
            ))
            return
        }
    }

    func parseAction(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        loopVar: String?,
        loopValue: Int?
    ) {
        guard let actionName = extractStringArg(call, index: 0, loopVar: loopVar, loopValue: loopValue),
              let closure = call.trailingClosure
        else {
            result.diagnostics.append(.init(
                message: "Action requires a name and a supported action body.",
                source: call
            ))
            return
        }
        let arguments = Array(call.arguments)
        let bindingArguments = arguments.dropFirst()
        if bindingArguments.isEmpty {
            guard closure.statements.allSatisfy({
                if case .expr = $0.item { return true }
                return false
            }) else {
                result.diagnostics.append(.init(
                    message: "Action '\(actionName)' contains an unsupported action expression.",
                    source: closure
                ))
                return
            }
            if let body = decodeActionFromClosure(closure) {
                result.actions.append(.init(name: actionName, body: body))
            } else if let expression = unsupportedActionExpression(in: closure) {
                result.diagnostics.append(.init(
                    message: "Action '\(actionName)' contains an unsupported action expression.",
                    source: expression
                ))
            } else {
                result.diagnostics.append(.init(
                    message: "Action '\(actionName)' contains an unsupported action expression.",
                    source: closure
                ))
            }
            return
        }
        guard bindingArguments.count == 1,
              let argument = bindingArguments.first,
              argument.label?.text == "parameters",
              let parameterList = argument.expression.as(ArrayExprSyntax.self)
        else {
            result.diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' requires a parameters list of ActionParameter descriptors.",
                source: call
            ))
            return
        }
        var bindings: [ActionBinding] = []
        for (index, element) in parameterList.elements.enumerated() {
            guard let binding = actionParameter(
                element.expression,
                actionName: actionName,
                position: index + 1,
                diagnostics: &result.diagnostics
            ) else {
                continue
            }
            if bindings.contains(where: { $0.name == binding.name }) {
                result.diagnostics.append(.init(
                    message: "Parameterized action '\(actionName)' parameter '\(binding.name)' duplicates an earlier parameter name.",
                    source: element.expression
                ))
                continue
            }
            bindings.append(binding)
        }
        guard result.diagnostics.isEmpty else { return }
        guard !bindings.isEmpty else {
            result.diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' requires at least one ActionParameter descriptor.",
                source: parameterList
            ))
            return
        }
        guard closureParameterNames(in: closure).isEmpty else {
            result.diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' uses the removed closure-parameter syntax; bind values through its parameters list.",
                source: closure
            ))
            return
        }
        guard closure.statements.allSatisfy({
            if case .expr = $0.item { return true }
            return false
        }) else {
            result.diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' contains an unsupported action expression.",
                source: closure
            ))
            return
        }
        guard let body = decodeActionFromClosure(closure) else {
            if let expression = unsupportedActionExpression(in: closure),
               let typedUpdate = typedUpdateExpression(in: expression) {
                let message = "Parameterized action '\(actionName)' contains an unsupported typed update; "
                    + "use a directly written finite enum case or schema field token."
                result.diagnostics.append(.init(
                    message: message,
                    source: typedUpdate
                ))
            } else if let expression = unsupportedActionExpression(in: closure) {
                result.diagnostics.append(.init(
                    message: "Parameterized action '\(actionName)' contains an unsupported action expression.",
                    source: expression
                ))
            } else {
                result.diagnostics.append(.init(
                    message: "Parameterized action '\(actionName)' contains an unsupported action expression.",
                    source: closure
                ))
            }
            return
        }
        result.actions.append(.init(
            name: actionName,
            body: body,
            bindings: bindings
        ))
    }

    func unsupportedActionExpression(in closure: ClosureExprSyntax) -> ExprSyntax? {
        closure.statements.compactMap { statement in
            guard case .expr(let expression) = statement.item,
                  decodeActionExpr(expression) == nil
            else { return nil }
            return expression
        }.first
    }

    func typedUpdateExpression(in expression: ExprSyntax) -> ExprSyntax? {
        if let call = expression.as(FunctionCallExprSyntax.self) {
            if call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "updating" {
                return expression
            }
            for argument in call.arguments {
                if let update = typedUpdateExpression(in: argument.expression) {
                    return update
                }
            }
            if let closure = call.trailingClosure {
                for statement in closure.statements {
                    guard case .expr(let nested) = statement.item else { continue }
                    if let update = typedUpdateExpression(in: nested) {
                        return update
                    }
                }
            }
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            return typedUpdateExpression(in: infix.leftOperand)
                ?? typedUpdateExpression(in: infix.rightOperand)
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            for element in sequence.elements {
                if let update = typedUpdateExpression(in: ExprSyntax(element)) {
                    return update
                }
            }
        }
        if let tuple = expression.as(TupleExprSyntax.self) {
            for element in tuple.elements {
                if let update = typedUpdateExpression(in: element.expression) {
                    return update
                }
            }
        }
        return nil
    }

    func actionParameter(
        _ expression: ExprSyntax,
        actionName: String,
        position: Int,
        diagnostics: inout [SymmetricCollectionParseDiagnostic]
    ) -> ActionBinding? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ActionParameter"
        else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter #\(position) requires an ActionParameter descriptor.",
                source: expression
            ))
            return nil
        }
        guard let name = extractStringArg(call, index: 0), !name.isEmpty else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter #\(position) requires a non-empty name.",
                source: call
            ))
            return nil
        }
        guard let valuesExpression = call.arguments.first(where: { $0.label?.text == "values" })?.expression else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter '\(name)' requires an explicitly written finite values array.",
                source: call
            ))
            return nil
        }
        guard let values = finiteDomain(valuesExpression) else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter '\(name)' requires an explicitly written finite values array.",
                source: valuesExpression
            ))
            return nil
        }
        guard !values.isEmpty else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter '\(name)' requires a non-empty finite values array.",
                source: valuesExpression
            ))
            return nil
        }
        guard Set(values).count == values.count else {
            diagnostics.append(.init(
                message: "Parameterized action '\(actionName)' parameter '\(name)' has duplicate finite-domain values.",
                source: valuesExpression
            ))
            return nil
        }
        return ActionBinding(name: name, values: values)
    }

    func closureParameterNames(in closure: ClosureExprSyntax) -> [String] {
        guard let parameters = closure.signature?.parameterClause else { return [] }
        switch parameters {
        case .simpleInput(let list): return list.map { $0.name.text }
        case .parameterClause(let clause):
            return clause.parameters.map { $0.secondName?.text ?? $0.firstName.text }
        }
    }

    func finiteDomain(_ expression: ExprSyntax) -> [TLAValue]? {
        if let array = expression.as(ArrayExprSyntax.self) {
            let values = array.elements.compactMap { element -> TLAValue? in
                guard case .value(let value)? = decodeStateExpr(element.expression) else { return nil }
                return value
            }
            return values.count == array.elements.count ? values : nil
        }
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "finiteValues",
              let type = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return nil }
        return enumDefinition(named: type)?.formalDomain
    }

    func parseInvariant(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let name = extractStringArg(call, index: 0), let closure = call.trailingClosure else {
            result.diagnostics.append(.init(
                message: "Invariant declaration requires a name and a supported invariant expression.",
                source: call.description
            ))
            return
        }
        guard let body = parseInvariantBody(
            closure,
            symmetricCollections: Set(result.symmetricCollections.map(\.name))
        ) else {
            let symmetricCollections = Set(result.symmetricCollections.map(\.name))
            if let expression = unsupportedInvariantExpression(
                in: closure,
                symmetricCollections: symmetricCollections
            ) {
                result.diagnostics.append(.init(
                    message: "Invariant '\(name)' contains an unsupported invariant expression.",
                    source: expression
                ))
            } else {
            result.diagnostics.append(.init(
                message: "Invariant '\(name)' contains an unsupported invariant expression.",
                source: closure
            ))
            }
            return
        }
        result.invariants.append((name, body))
    }

    func parseInvariantBody(
        _ closure: ClosureExprSyntax,
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        var expressions: [StateExpr] = []
        for statement in closure.statements {
            guard case .expr(let expression) = statement.item else { return nil }
            guard let parsed = decodeInvariantExpression(expression, symmetricCollections: symmetricCollections)
            else { return nil }
            expressions.append(parsed)
        }
        guard let first = expressions.first else { return nil }
        return expressions.dropFirst().reduce(first, StateExpr.and)
    }

    func decodeInvariantExpression(
        _ expression: ExprSyntax,
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        if let predicate = parseCollectionPredicate(expression, symmetricCollections: symmetricCollections) {
            return predicate
        }
        let unwrapped = unwrapSingleElementTuple(expression)
        if unwrapped != expression {
            return decodeInvariantExpression(unwrapped, symmetricCollections: symmetricCollections)
        }
        return decodeStateExpr(unwrapped)
    }

    func unsupportedInvariantExpression(
        in closure: ClosureExprSyntax,
        symmetricCollections: Set<String>
    ) -> ExprSyntax? {
        for statement in closure.statements {
            guard case .expr(let expression) = statement.item else { continue }
            if decodeInvariantExpression(expression, symmetricCollections: symmetricCollections) == nil {
                return expression
            }
        }
        return nil
    }

    func parseCollectionPredicate(
        _ expression: ExprSyntax,
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self) else { return nil }
        return decodeCollectionPredicate(
            call,
            requiringCollectionIn: symmetricCollections
        ) { body, scope in
            decodeTypedFacadeValue(body, scope: scope)
        }
    }

    static func collectionPredicateParameter(in closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause else { return "$0" }
        switch parameters {
        case .simpleInput(let list):
            guard list.count == 1 else { return nil }
            return list.first?.name.text
        case .parameterClause(let clause):
            guard clause.parameters.count == 1, let parameter = clause.parameters.first else { return nil }
            return parameter.secondName?.text ?? parameter.firstName.text
        }
    }

}
