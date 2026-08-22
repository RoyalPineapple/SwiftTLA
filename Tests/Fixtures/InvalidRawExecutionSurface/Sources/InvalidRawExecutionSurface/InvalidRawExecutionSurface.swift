import SwiftTLA

// Raw checker and graph implementation types are package implementation
// details. A client uses a generated model machine instead.
let checker: ModelChecker? = nil
let graph: StateGraph? = nil
let runtime: TLALiveMachine<Int>? = nil
let driver: TLALiveMachineTransitionDriver<Int>? = nil

print(checker as Any, graph as Any, runtime as Any, driver as Any)
