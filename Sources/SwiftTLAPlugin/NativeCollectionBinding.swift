import SwiftTLA

/// One private identifier shared by all native collection binding references.
func nativeCollectionBinding(_ collection: MachineSurfacePlan.SymmetricCollection, in model: MacroCompilation) -> String {
    let index = model.compilation.machineSurfacePlan.symmetricCollections.firstIndex(of: collection)!
    return "_members\(index)"
}
