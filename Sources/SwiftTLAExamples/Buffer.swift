import SwiftTLA
public enum BufferSpec {
    public static let buf = Var<Int>("buf")
    public static let spec = TLASpec("Buffer") {
        Variable(buf, 0)
        Action("Put") { (buf == 0) && buf.next == 1 }
        Action("Get") { (buf == 1) && buf.next == 0 }
        Invariant("Binary") { buf >= 0 && buf <= 1 }
    }
}
