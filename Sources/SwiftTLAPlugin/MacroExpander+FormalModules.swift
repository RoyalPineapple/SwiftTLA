import SwiftTLA

extension MacroExpander {
    static func codegenFormalModuleConfiguration(_ configuration: FormalModuleConfiguration) -> String {
        let replacements = configuration.replacements.map { replacement in
            "FormalModuleReplacement(" +
                "operatorName: \"\(replacement.operatorName)\", " +
                "definitionName: \"\(replacement.definitionName)\", " +
                "expression: \(codegenStateExpr(replacement.expression)))"
        }.joined(separator: ", ")
        return "FormalModuleConfiguration(moduleName: \"\(configuration.moduleName)\", replacements: [\(replacements)])"
    }

    static func codegenFormalModuleInstance(_ instance: FormalModuleInstance) -> String {
        "FormalModuleInstance(\"\(instance.name)\", " +
            "of: FormalModuleRegistry.lookup(\"\(instance.module.name)\")!)"
    }
}
