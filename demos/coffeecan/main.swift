var can = CoffeeCan.initial
print("Start: black=\(can.black) white=\(can.white) parity=\(can.white % 2)")
for _ in 1...8 {
    guard let act = can.availableActions.first else { break }
    can.apply(act)
    print("\(act): black=\(can.black) white=\(can.white)")
}
print("Parity preserved: \(can.parityPreserved)")
