import Foundation

extension TLASpec {
    func renderTLAModuleSource(sectionPlan: DirectModuleSectionPlan) -> String {
        sectionPlan.renderedModuleSource
    }

    func renderTLCConfiguration(sectionPlan: DirectModuleSectionPlan) -> String {
        sectionPlan.renderedConfiguration
    }
}
