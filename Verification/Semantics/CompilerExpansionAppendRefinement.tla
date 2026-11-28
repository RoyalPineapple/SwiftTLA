---- MODULE CompilerExpansionAppendRefinement ----
EXTENDS CompilerExpansionSILRules

\* Normal-return contract, independently stated over logical Swift storage.
\* External foundation (manual formalization, NOT proved from documentation):
\* Array.append appends one value; SIL @in consumes its initialized argument;
\* @inout returns initialized storage. References: Swift Array.append(_:),
\* swiftlang/swift docs/SIL/Types.md (parameter conventions), Instructions.md
\* (apply, begin_access). Allocation failure and conflicting accesses are not
\* normal returns. Establishing the caller's exclusive access remains separate.
\* No claim here that current upstream documentation pins our compiler version.
SwiftAppendNormalReturn(before, after, arrayAddress, argumentAddress, access) ==
    /\ arrayAddress # argumentAddress
    /\ {arrayAddress, argumentAddress} \subseteq DOMAIN before.store
    /\ before.store[arrayAddress] \in Seq(Int \X BOOLEAN)
    /\ before.store[argumentAddress] \in Int \X BOOLEAN
    /\ before.control = "normal"
    /\ access \in DOMAIN before.accesses
    /\ before.accesses[access] = [address |-> arrayAddress, mode |-> "modify"]
    /\ after.control = "normal" /\ after.result = <<>>
    /\ after.stack = before.stack /\ after.accesses = before.accesses
    /\ DOMAIN after.store = DOMAIN before.store
    /\ after.store[arrayAddress] \in Seq(Int \X BOOLEAN)
    /\ Len(after.store[arrayAddress]) = Len(before.store[arrayAddress]) + 1
    /\ \A j \in 1..Len(before.store[arrayAddress]):
           after.store[arrayAddress][j] = before.store[arrayAddress][j]
    /\ after.store[arrayAddress][Len(after.store[arrayAddress])] = before.store[argumentAddress]
    /\ after.store[argumentAddress] = "uninitialized"
    /\ \A address \in DOMAIN before.store \ {arrayAddress, argumentAddress}:
           after.store[address] = before.store[address]

\* Addresses are arbitrary and injective, not the interpreter's register names.
\* Unrepresented caller storage is retained by the primitive's frame condition.
AppendStorageRepresentation(reference, reduced, arrayAddress, locations) ==
    /\ reference.control = reduced.control
    /\ arrayAddress \in DOMAIN reference.store
    /\ reference.store[arrayAddress] \in Seq(Int \X BOOLEAN)
    /\ reduced.array.count \in Nat
    /\ reduced.array = [count |-> reduced.array.count, items |-> reduced.array.items]
    /\ reduced.array.count = Len(reference.store[arrayAddress])
    /\ reduced.array.items = [j \in 0..(reduced.array.count-1) |-> reference.store[arrayAddress][j+1]]
    /\ DOMAIN reduced.m \subseteq DOMAIN locations
    /\ \A key \in DOMAIN reduced.m:
           /\ locations[key] \in DOMAIN reference.store
           /\ locations[key] # arrayAddress
           /\ reference.store[locations[key]] = reduced.m[key]
    /\ \A a,b \in DOMAIN reduced.m: locations[a] = locations[b] => a = b
    /\ reference.stack = [j \in DOMAIN reduced.stack |-> locations[reduced.stack[j]]]
    /\ reference.accesses = [key \in reduced.active |-> [address |-> arrayAddress, mode |-> "modify"]]

AppendCallInputs(instruction, state, key, limit) ==
    /\ SILInstructionWellFormed(instruction) /\ instruction.op = "call"
    /\ state = [control |-> "normal", r |-> state.r, m |-> state.m,
                  stack |-> state.stack, active |-> state.active, array |-> state.array]
    /\ state.r = [register \in DOMAIN state.r |-> state.r[register]]
    /\ state.m = [cell \in DOMAIN state.m |-> state.m[cell]]
    /\ \A j \in 1..3: instruction.args[j] \in DOMAIN state.r
    /\ state.r[instruction.args[1]] = <<"callee", "append">>
    /\ state.r[instruction.args[2]] = <<"local", key>>
    /\ state.r[instruction.args[3]] = <<"pending", 0>>
    /\ instruction.args[3] \in state.active
    /\ key \in DOMAIN state.m /\ state.m[key] \in Int \X BOOLEAN
    /\ state.array.count < limit

\* This closes the storage/result obligation at the actual append apply rule.
\* AppendAddsFrame consumes it; full helper adequacy also needs the other ops.
THEOREM AppendCallRefinesEveryNormalReturn ==
    ASSUME NEW instruction, NEW state, NEW key, NEW limit,
           NEW before, NEW after, NEW arrayAddress, NEW locations,
           AppendCallInputs(instruction, state, key, limit),
           AppendStorageRepresentation(before, state, arrayAddress, locations),
           SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3])
    PROVE LET next == SILExecute(instruction, state, limit)
          IN /\ AppendStorageRepresentation(after, next, arrayAddress, locations)
             /\ next.control = "normal"
             /\ next.r[instruction.out] = <<"unit", 0>> /\ after.result = <<>>
             /\ \A register \in DOMAIN state.r \ {instruction.out}: next.r[register] = state.r[register]
    PROOF
    <1>next. DEFINE next == SILExecute(instruction, state, limit)
    <1>record. state = [control |-> "normal", r |-> state.r, m |-> state.m,
                       stack |-> state.stack, active |-> state.active, array |-> state.array]
        BY ONLY AppendCallInputs(instruction, state, key, limit) DEF AppendCallInputs
    <1>shape. Len(instruction.args) = 3
        BY ONLY AppendCallInputs(instruction, state, key, limit), SMT
            DEF AppendCallInputs, SILInstructionWellFormed
    <1>operands. /\ SILOperands(instruction, state)[1] = <<"callee", "append">>
                    /\ SILOperands(instruction, state)[2] = <<"local", key>>
                    /\ SILOperands(instruction, state)[3] = <<"pending", 0>>
        BY ONLY <1>shape, AppendCallInputs(instruction, state, key, limit), SMT
            DEF AppendCallInputs, SILOperands
    <1>execute. next = [SILRegister(state, instruction.out, <<"unit", 0>>) EXCEPT
            !.array = SILArrayAppend(state.array, state.m[key]),
            !.m = SILMapPut(state.m, key, "uninitialized")]
        BY ONLY <1>shape, <1>operands, AppendCallInputs(instruction, state, key, limit), SMT
            DEF next, AppendCallInputs, SILExecute, SILRegister
    <1>length. /\ next.array.count = Len(after.store[arrayAddress])
                  /\ state.array.count = Len(before.store[arrayAddress])
                  /\ next.array.count = state.array.count + 1
        BY ONLY <1>record, <1>execute, AppendStorageRepresentation(before, state, arrayAddress, locations),
            SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3]), SMT
            DEF AppendStorageRepresentation, SwiftAppendNormalReturn, SILArrayAppend, SILRegister
    <1>last. before.store[locations[key]] = state.m[key]
        BY ONLY AppendCallInputs(instruction, state, key, limit),
            AppendStorageRepresentation(before, state, arrayAddress, locations), SMT
            DEF AppendCallInputs, AppendStorageRepresentation
    <1>items. next.array.items = [j \in 0..(next.array.count-1) |-> after.store[arrayAddress][j+1]]
        BY ONLY <1>record, <1>execute, <1>length, <1>last,
            AppendStorageRepresentation(before, state, arrayAddress, locations),
            SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3]), SMT
            DEF AppendStorageRepresentation, SwiftAppendNormalReturn, SILArrayAppend, SILRegister
    <1>memoryMap. next.m = SILMapPut(state.m, key, "uninitialized")
        BY ONLY <1>record, <1>execute, SMT DEF SILRegister
    <1>keyInMemory. key \in DOMAIN state.m
        BY ONLY AppendCallInputs(instruction, state, key, limit) DEF AppendCallInputs
    <1>memoryDomain. DOMAIN next.m = DOMAIN state.m
        BY ONLY <1>memoryMap, <1>keyInMemory, SMT DEF SILMapPut
    <1>memory. \A cell \in DOMAIN next.m:
          /\ locations[cell] \in DOMAIN after.store /\ locations[cell] # arrayAddress
          /\ after.store[locations[cell]] = next.m[cell]
        BY ONLY <1>record, <1>execute, <1>memoryDomain,
            AppendCallInputs(instruction, state, key, limit),
            AppendStorageRepresentation(before, state, arrayAddress, locations),
            SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3]), SMT
            DEF AppendCallInputs, AppendStorageRepresentation, SwiftAppendNormalReturn, SILMapPut, SILRegister
    <1>unchanged. /\ next.stack = state.stack /\ next.active = state.active
                     /\ next.control = state.control /\ next.control = "normal"
        BY ONLY <1>record, <1>execute, AppendCallInputs(instruction, state, key, limit), SMT
            DEF SILRegister, AppendCallInputs
    <1>arrayShape. next.array = [count |-> next.array.count, items |-> next.array.items]
        BY ONLY <1>record, <1>execute, SMT DEF SILRegister, SILArrayAppend
    <1>representation. AppendStorageRepresentation(after, next, arrayAddress, locations)
        BY ONLY <1>arrayShape, <1>length, <1>items, <1>memoryDomain, <1>memory, <1>unchanged,
            AppendStorageRepresentation(before, state, arrayAddress, locations),
            SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3]), SMT
            DEF AppendStorageRepresentation, SwiftAppendNormalReturn
    <1>registers. /\ next.r[instruction.out] = <<"unit", 0>>
                     /\ \A register \in DOMAIN state.r \ {instruction.out}: next.r[register] = state.r[register]
        BY ONLY <1>record, <1>execute, SMT DEF SILRegister, SILMapPut
    <1>. QED BY ONLY <1>representation, <1>unchanged, <1>registers,
        SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3])
        DEF next, SwiftAppendNormalReturn

AppendCallNormalRefinement(instruction, state, key, limit) ==
    \A before, arrayAddress, locations:
        AppendStorageRepresentation(before, state, arrayAddress, locations) =>
        /\ \E after:
             /\ SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3])
             /\ AppendStorageRepresentation(after, SILExecute(instruction, state, limit), arrayAddress, locations)
        /\ \A after:
             SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3]) =>
             AppendStorageRepresentation(after, SILExecute(instruction, state, limit), arrayAddress, locations)

\* Existence here is contract consistency, not a claim that allocation succeeds.
THEOREM AppendCallHasExactNormalReturnCorrespondence ==
    ASSUME NEW instruction, NEW state, NEW key, NEW limit,
           AppendCallInputs(instruction, state, key, limit)
    PROVE AppendCallNormalRefinement(instruction, state, key, limit)
    PROOF
    <1>reference. SUFFICES ASSUME NEW before, NEW arrayAddress, NEW locations,
        AppendStorageRepresentation(before, state, arrayAddress, locations)
        PROVE /\ \E after:
                 /\ SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3])
                 /\ AppendStorageRepresentation(after, SILExecute(instruction, state, limit), arrayAddress, locations)
              /\ \A after:
                 SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3]) =>
                 AppendStorageRepresentation(after, SILExecute(instruction, state, limit), arrayAddress, locations)
        BY DEF AppendCallNormalRefinement
    <1>before. /\ {arrayAddress, locations[key]} \subseteq DOMAIN before.store
                   /\ locations[key] # arrayAddress
                   /\ before.store[arrayAddress] \in Seq(Int \X BOOLEAN)
                   /\ before.store[locations[key]] = state.m[key]
                   /\ state.m[key] \in Int \X BOOLEAN
                   /\ before.control = "normal"
                   /\ instruction.args[3] \in DOMAIN before.accesses
                   /\ before.accesses[instruction.args[3]] = [address |-> arrayAddress, mode |-> "modify"]
        BY ONLY AppendCallInputs(instruction, state, key, limit),
            AppendStorageRepresentation(before, state, arrayAddress, locations), SMT
            DEF AppendCallInputs, AppendStorageRepresentation
    <1>post. DEFINE values == Append(before.store[arrayAddress], state.m[key])
                    post == [control |-> "normal", result |-> <<>>, stack |-> before.stack,
                             accesses |-> before.accesses,
                             store |-> [address \in DOMAIN before.store |->
                                 IF address = arrayAddress THEN values
                                 ELSE IF address = locations[key] THEN "uninitialized"
                                 ELSE before.store[address]]]
    <1>values. /\ values \in Seq(Int \X BOOLEAN)
                   /\ Len(values) = Len(before.store[arrayAddress]) + 1
                   /\ \A j \in 1..Len(before.store[arrayAddress]): values[j] = before.store[arrayAddress][j]
                   /\ values[Len(values)] = state.m[key]
        BY ONLY <1>before, SMT DEF values
    <1>normal. SwiftAppendNormalReturn(before, post, arrayAddress, locations[key], instruction.args[3])
        BY ONLY <1>before, <1>values, SMT DEF post, SwiftAppendNormalReturn
    <1>represented. AppendStorageRepresentation(post, SILExecute(instruction, state, limit), arrayAddress, locations)
        BY ONLY <1>normal, AppendCallRefinesEveryNormalReturn,
            AppendCallInputs(instruction, state, key, limit),
            AppendStorageRepresentation(before, state, arrayAddress, locations), Zenon
    <1>all. \A after:
        SwiftAppendNormalReturn(before, after, arrayAddress, locations[key], instruction.args[3]) =>
        AppendStorageRepresentation(after, SILExecute(instruction, state, limit), arrayAddress, locations)
        BY ONLY AppendCallRefinesEveryNormalReturn,
            AppendCallInputs(instruction, state, key, limit),
            AppendStorageRepresentation(before, state, arrayAddress, locations), Zenon
    <1>. QED BY ONLY <1>normal, <1>represented, <1>all, Zenon
====
