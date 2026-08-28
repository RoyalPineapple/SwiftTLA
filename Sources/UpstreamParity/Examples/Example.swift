import SwiftTLA

package enum Example {
    package struct FiniteModelFixture: Sendable {
        package let expectedDistinct: Int
        package let maximumStateLimit: Int
        package let spec: TLASpec
    }
}
