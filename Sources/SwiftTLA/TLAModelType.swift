public protocol TLAModelType {
    static var spec: TLASpec { get }
    /// The maximum number of states generated verification may explore.
    /// Override this for a published finite configuration whose complete graph
    /// is larger than the default bound.
    static var verificationStateLimit: Int { get }
}

extension TLAModelType {
    public static var verificationStateLimit: Int { 100_000 }
}
