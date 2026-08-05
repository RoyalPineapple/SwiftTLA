import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct Allocator {
    static var spec: TLASpec {
        TLASpec("allocator") {
            Extends("Naturals")
            let available = Var("available", 3)
            let allocated = Var("allocated", 0)
            Variable(available, 3)
            Variable(allocated, 0)
            Action("Allocate")   { available.becomes(available - 1).when(available > 0) && allocated.becomes(allocated + 1) }
            Action("Deallocate") { available.becomes(available + 1).when(allocated > 0) && allocated.becomes(allocated - 1) }
            Invariant("ResourceCount") { available + allocated == 3 }
        }
    }
}
