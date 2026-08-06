import SwiftTLA

let specName = CommandLine.arguments[1]
var output = ""
switch specName {
case "HourClock":
    let hr = Var<Int>("hr", value: 1)
    let s = TLASpec("HourClock") { Variable(hr, in: 1...12); Action("HCnxt") { (hr != 12) && hr.becomes(hr + 1) || (hr == 12) && hr.becomes(1) } }
    output = s.tlaModule
case "DieHard":
    let big = Var<Int>("big", value: 0); let small = Var<Int>("small", value: 0)
    let s = TLASpec("DieHard") {
        Variable(big, 0); Variable(small, 0)
        Action("FB") { big.becomes(5) }; Action("FS") { small.becomes(3) }
        Action("EB") { big.becomes(0).when(big>0) }; Action("ES") { small.becomes(0).when(small>0) }
        Action("S2B") { (big+small<=5) && big.becomes(big+small) && small.becomes(0) || (big+small>5) && big.becomes(5) && small.becomes(small-(5-big)) }
        Action("B2S") { (big+small<=3) && small.becomes(big+small) && big.becomes(0) || (big+small>3) && small.becomes(3) && big.becomes(big-(3-small)) }
    }
    output = s.tlaModule
case "Allocator":
    let a = Var<Int>("available", value: 3); let b = Var<Int>("allocated", value: 0)
    let s = TLASpec("allocator") { Variable(a, 3); Variable(b, 0); Action("A") { a.becomes(a-1).when(a>0) && b.becomes(b+1) }; Action("F") { a.becomes(a+1).when(b>0) && b.becomes(b-1) } }
    output = s.tlaModule
default:
    output = "UNKNOWN\n"
}
print(output)
