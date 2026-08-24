import SwiftTLA
import SwiftTLAMacros

/// The single-switch prisoner puzzle from *Specifying Systems*.
///
/// A single scheduler process chooses the prisoner who enters the room. The
/// model keeps the choice formal with `With`, so no host-language loop or UI
/// policy decides who visits next.
@TLAModel
public struct PrisonerModel: Sendable {
    public enum Prisoner: String, CaseIterable {
        case alice = "Alice"
        case bob = "Bob"
        case eve = "Eve"

}
