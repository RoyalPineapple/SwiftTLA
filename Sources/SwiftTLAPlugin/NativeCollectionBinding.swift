import SwiftTLA

/// One private identifier shared by all native collection binding references.
func nativeCollectionBinding(_ collection: MachineSurfacePlan.Collection, in model: MacroCompilation) -> String {
    let index = model.surface.collections.firstIndex(of: collection)!
    return "_members\(index)"
}
