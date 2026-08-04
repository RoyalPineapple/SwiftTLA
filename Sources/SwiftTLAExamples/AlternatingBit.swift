import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct AlternatingBit {
    public static var spec = TLASpec("AlternatingBit") {
        let senderBit = Var(0)
        let senderState = Var(0)
        let receiverBit = Var(0)
        let receiverState = Var(0)
        let message = Var(0)

        Action("sendData") { message.becomes(senderBit).when(senderState == 0) && senderState.becomes(1) }
        Action("timeout")    { senderState.becomes(0).when(senderState == 1) }
        Action("receive")    { receiverState.becomes(1).when(receiverState == 0) && receiverBit.becomes(message) }
        Action("sendAck")    { message.becomes(-1).when(receiverState == 1) && receiverState.becomes(2) }
        Action("receiveAck") { senderBit.becomes(1 - senderBit).when(senderState == 1 && message == -1) && senderState.becomes(0) }
    }
}
