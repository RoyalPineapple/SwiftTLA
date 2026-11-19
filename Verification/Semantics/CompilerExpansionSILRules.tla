---- MODULE CompilerExpansionSILRules ----
EXTENDS TLAPS, Integers, Sequences

\* Restricted textual SIL and primitive value semantics for the production helper.
\* External contracts: pinned Swift compiler SIL printing, SIL instruction semantics,
\* and Swift Array.append. No repository decoder or instruction sequence is assumed.
SILSSA(bytes) ==
    /\ bytes \in Seq(0..255) /\ Len(bytes) >= 2
    /\ bytes[1] = 37
    /\ \A j \in 2..Len(bytes): bytes[j] \in 48..57
    /\ Len(bytes) > 2 => bytes[2] # 48
SILQuotedName(bytes) ==
    /\ bytes \in Seq(0..255) /\ Len(bytes) >= 2
    /\ bytes[1] = 34 /\ bytes[Len(bytes)] = 34
    /\ \A j \in 2..(Len(bytes)-1): bytes[j] \in 32..126 \ {34, 92}
SILPunctuation == {<<40>>, <<41>>, <<91>>, <<93>>, <<44>>, <<58>>,
                   <<60>>, <<62>>, <<61>>, <<36>>, <<45, 62>>}
SILLexeme(bytes) ==
    /\ bytes \in Seq(0..255) /\ Len(bytes) > 0
    /\ (bytes \in SILPunctuation \/ SILQuotedName(bytes) \/
         bytes = <<207, 132, 95, 48, 95, 48>> \/
         (\A j \in 1..Len(bytes):
             bytes[j] \in 33..126 \ {34,40,41,44,47,58,60,61,62,91,92,93,123,125}))

\* A proposal must cover every byte, including indentation, spaces and comment.
SILTokenAt(raw, token, start, comment) ==
    /\ SILLexeme(token)
    /\ start \in 1..comment /\ start + Len(token) <= comment
    /\ \A j \in 1..Len(token): raw[start+j-1] = token[j]
SILGap(raw, left, right, first, last) ==
    /\ first + Len(left) <= last
    /\ left \notin SILPunctuation /\ right \notin SILPunctuation
        => first + Len(left) < last
    /\ \A j \in (first+Len(left))..(last-1): raw[j] \in {9,32}
SILLineTokens(raw, tokens, starts, comment) ==
    /\ raw \in Seq(0..255) /\ tokens \in Seq(Seq(0..255))
    /\ Len(tokens) > 0 /\ DOMAIN starts = 1..Len(tokens)
    /\ comment \in Nat /\ comment <= Len(raw)
    /\ \A k \in 1..Len(tokens): SILTokenAt(raw, tokens[k], starts[k], comment)
    /\ \A j \in 1..(starts[1]-1): raw[j] \in {9,32}
    /\ \A k \in 1..(Len(tokens)-1):
        SILGap(raw, tokens[k], tokens[k+1], starts[k], starts[k+1])
    /\ \A j \in (starts[Len(tokens)]+Len(tokens[Len(tokens)]))..(comment-1): raw[j] \in {9,32}
    /\ raw[Len(raw)] = 10
    /\ (comment = Len(raw) \/
         (/\ comment + 2 <= Len(raw) /\ raw[comment] = 47 /\ raw[comment+1] = 47
          /\ \A j \in (comment+2)..(Len(raw)-1): raw[j] \notin {10,13}))

SILInstructionWellFormed(i) ==
    /\ DOMAIN i = {"op", "out", "args", "data"}
    /\ i.args \in Seq(Seq(0..255))
    /\ \A j \in 1..Len(i.args): SILSSA(i.args[j])
    /\ IF i.op \in {"store", "end", "free", "return", "debug"}
        THEN i.out = <<>> ELSE SILSSA(i.out)
    /\ CASE i.op = "literal" -> Len(i.args) = 0 /\ i.data \in BOOLEAN
         [] i.op \in {"struct", "begin", "end", "free", "return"} -> Len(i.args) = 1 /\ i.data = 0
         [] i.op \in {"tuple", "store"} -> Len(i.args) = 2 /\ i.data = 0
         [] i.op \in {"alloc", "ref", "unit"} -> Len(i.args) = 0 /\ i.data = 0
         [] i.op = "call" -> Len(i.args) = 3 /\ i.data = 0
         [] i.op = "debug" -> /\ Len(i.args) = 1
                              /\ DOMAIN i.data = {"mode", "name", "argno", "deref"}
                              /\ i.data.mode \in {"let", "var"}
                              /\ SILQuotedName(i.data.name)
                              /\ i.data.argno \in 1..5
                              /\ i.data.deref \in BOOLEAN
         [] OTHER -> FALSE
SILInstructionTokens(i) ==
    CASE i.op = "literal" -> <<i.out, <<61>>, <<105, 110, 116, 101, 103, 101, 114, 95, 108, 105, 116, 101, 114, 97, 108>>, <<36, 66, 117, 105, 108, 116, 105, 110, 46, 73, 110, 116, 49>>, <<44>>, (IF i.data THEN <<45,49>> ELSE <<48>>)>>
    [] i.op = "struct" -> <<i.out, <<61>>, <<115, 116, 114, 117, 99, 116>>, <<36, 66, 111, 111, 108>>, <<40>>, i.args[1], <<41>>>>
    [] i.op = "tuple" -> <<i.out, <<61>>, <<116, 117, 112, 108, 101>>, <<36>>, <<40>>, <<111, 114, 105, 103, 105, 110>>, <<58>>, <<73, 110, 116>>, <<44>>, <<101, 120, 112, 97, 110, 100, 101, 100>>, <<58>>, <<66, 111, 111, 108>>, <<41>>, <<40>>, i.args[1], <<44>>, i.args[2], <<41>>>>
    [] i.op = "alloc" -> <<i.out, <<61>>, <<97, 108, 108, 111, 99, 95, 115, 116, 97, 99, 107>>, <<36>>, <<40>>, <<111, 114, 105, 103, 105, 110>>, <<58>>, <<73, 110, 116>>, <<44>>, <<101, 120, 112, 97, 110, 100, 101, 100>>, <<58>>, <<66, 111, 111, 108>>, <<41>>>>
    [] i.op = "store" -> <<<<115, 116, 111, 114, 101>>, i.args[1], <<116, 111>>, <<91>>, <<116, 114, 105, 118, 105, 97, 108>>, <<93>>, i.args[2]>>
    [] i.op = "begin" -> <<i.out, <<61>>, <<98, 101, 103, 105, 110, 95, 97, 99, 99, 101, 115, 115>>, <<91>>, <<109, 111, 100, 105, 102, 121>>, <<93>>, <<91>>, <<115, 116, 97, 116, 105, 99>>, <<93>>, i.args[1]>>
    [] i.op = "ref" -> <<i.out, <<61>>, <<102, 117, 110, 99, 116, 105, 111, 110, 95, 114, 101, 102>>, <<64, 36, 115, 83, 97, 54, 97, 112, 112, 101, 110, 100, 121, 121, 120, 110, 70>>, <<58>>, <<36, 64, 99, 111, 110, 118, 101, 110, 116, 105, 111, 110>>, <<40>>, <<109, 101, 116, 104, 111, 100>>, <<41>>, <<60>>, <<207, 132, 95, 48, 95, 48>>, <<62>>, <<40>>, <<64, 105, 110>>, <<207, 132, 95, 48, 95, 48>>, <<44>>, <<64, 105, 110, 111, 117, 116>>, <<65, 114, 114, 97, 121>>, <<60>>, <<207, 132, 95, 48, 95, 48>>, <<62>>, <<41>>, <<45, 62>>, <<40>>, <<41>>>>
    [] i.op = "call" -> <<i.out, <<61>>, <<97, 112, 112, 108, 121>>, i.args[1], <<60>>, <<40>>, <<111, 114, 105, 103, 105, 110>>, <<58>>, <<73, 110, 116>>, <<44>>, <<101, 120, 112, 97, 110, 100, 101, 100>>, <<58>>, <<66, 111, 111, 108>>, <<41>>, <<62>>, <<40>>, i.args[2], <<44>>, i.args[3], <<41>>, <<58>>, <<36, 64, 99, 111, 110, 118, 101, 110, 116, 105, 111, 110>>, <<40>>, <<109, 101, 116, 104, 111, 100>>, <<41>>, <<60>>, <<207, 132, 95, 48, 95, 48>>, <<62>>, <<40>>, <<64, 105, 110>>, <<207, 132, 95, 48, 95, 48>>, <<44>>, <<64, 105, 110, 111, 117, 116>>, <<65, 114, 114, 97, 121>>, <<60>>, <<207, 132, 95, 48, 95, 48>>, <<62>>, <<41>>, <<45, 62>>, <<40>>, <<41>>>>
    [] i.op = "end" -> <<<<101, 110, 100, 95, 97, 99, 99, 101, 115, 115>>, i.args[1]>>
    [] i.op = "free" -> <<<<100, 101, 97, 108, 108, 111, 99, 95, 115, 116, 97, 99, 107>>, i.args[1]>>
    [] i.op = "unit" -> <<i.out, <<61>>, <<116, 117, 112, 108, 101>>, <<40>>, <<41>>>>
    [] i.op = "return" -> <<<<114, 101, 116, 117, 114, 110>>, i.args[1]>>
    [] i.op = "debug" -> IF i.data.deref THEN <<<<100, 101, 98, 117, 103, 95, 118, 97, 108, 117, 101>>, i.args[1], <<44>>, (IF i.data.mode = "let" THEN <<108,101,116>> ELSE <<118,97,114>>), <<44>>, <<110, 97, 109, 101>>, i.data.name, <<44>>, <<97, 114, 103, 110, 111>>, <<48+i.data.argno>>, <<44>>, <<101, 120, 112, 114>>, <<111, 112, 95, 100, 101, 114, 101, 102>>>> ELSE <<<<100, 101, 98, 117, 103, 95, 118, 97, 108, 117, 101>>, i.args[1], <<44>>, (IF i.data.mode = "let" THEN <<108,101,116>> ELSE <<118,97,114>>), <<44>>, <<110, 97, 109, 101>>, i.data.name, <<44>>, <<97, 114, 103, 110, 111>>, <<48+i.data.argno>>>>
SILDecodesInstruction(raw, i, starts, comment) ==
    /\ SILInstructionWellFormed(i)
    /\ SILLineTokens(raw, SILInstructionTokens(i), starts, comment)

SILMapPut(map, key, value) == [k \in DOMAIN map \cup {key} |-> IF k = key THEN value ELSE map[k]]
SILMapRemove(map, key) == [k \in DOMAIN map \ {key} |-> map[k]]
SILRegister(s, key, value) == [s EXCEPT !.r = SILMapPut(s.r, key, value)]
SILReject(s) == [s EXCEPT !.control = "unsupported"]
SILArrayAppend(array, value) ==
    [count |-> array.count + 1,
     items |-> [index \in 0..array.count |-> IF index = array.count THEN value ELSE array.items[index]]]

\* Semantics of the admitted operations, independent of which helper is decoded.
\* Local stack cells and access scopes are private to this invocation.
\* A loop may execute a result-defining instruction again; register writes rebind.
SILOperands(i, s) == [j \in 1..Len(i.args) |-> s.r[i.args[j]]]

SILExecute(i, s, maxInt) ==
    IF s.control # "normal" THEN s
    ELSE IF ~SILInstructionWellFormed(i) THEN SILReject(s)
    ELSE IF \E j \in 1..Len(i.args): i.args[j] \notin DOMAIN s.r THEN SILReject(s)
    ELSE CASE i.op = "debug" -> s
    [] i.op = "literal" -> SILRegister(s, i.out, <<"bit", i.data>>)
    [] i.op = "struct" -> IF SILOperands(i, s)[1][1] = "bit" /\ SILOperands(i, s)[1][2] \in BOOLEAN
                         THEN SILRegister(s, i.out, <<"bool", SILOperands(i, s)[1][2]>>) ELSE SILReject(s)
    [] i.op = "tuple" -> IF SILOperands(i, s)[1][1] = "int" /\ SILOperands(i, s)[2][1] = "bool"
                        THEN SILRegister(s, i.out, <<"frame", <<SILOperands(i, s)[1][2], SILOperands(i, s)[2][2]>>>>) ELSE SILReject(s)
    [] i.op = "alloc" -> IF i.out \notin DOMAIN s.m
                        THEN [SILRegister(s, i.out, <<"local", i.out>>) EXCEPT
                                !.m = SILMapPut(s.m, i.out, "uninitialized"), !.stack = Append(@, i.out)]
                        ELSE SILReject(s)
    [] i.op = "store" -> IF SILOperands(i, s)[1][1] = "frame" /\ SILOperands(i, s)[2][1] = "local" /\ SILOperands(i, s)[2][2] \in DOMAIN s.m
                        THEN [s EXCEPT !.m = SILMapPut(s.m, SILOperands(i, s)[2][2], SILOperands(i, s)[1][2])] ELSE SILReject(s)
    [] i.op = "begin" -> IF SILOperands(i, s)[1] = <<"pending", 0>> /\ s.active = {}
                        THEN [SILRegister(s, i.out, <<"pending", 0>>) EXCEPT !.active = {i.out}]
                        ELSE SILReject(s)
    [] i.op = "ref" -> SILRegister(s, i.out, <<"callee", "append">>)
    [] i.op = "call" -> IF /\ SILOperands(i, s)[1] = <<"callee", "append">> /\ SILOperands(i, s)[2][1] = "local"
                           /\ SILOperands(i, s)[2][2] \in DOMAIN s.m /\ SILOperands(i, s)[3] = <<"pending", 0>>
                           /\ i.args[3] \in s.active /\ s.array.count < maxInt
                           /\ s.m[SILOperands(i, s)[2][2]] \in (Int \X BOOLEAN)
                       THEN [SILRegister(s, i.out, <<"unit", 0>>) EXCEPT
                               !.array = SILArrayAppend(@, s.m[SILOperands(i, s)[2][2]]),
                               !.m = SILMapPut(s.m, SILOperands(i, s)[2][2], "uninitialized")]
                       ELSE SILReject(s)
    [] i.op = "end" -> IF i.args[1] \in s.active
                      THEN [s EXCEPT !.active = @ \ {i.args[1]}] ELSE SILReject(s)
    [] i.op = "free" -> IF /\ SILOperands(i, s)[1][1] = "local" /\ Len(s.stack) > 0
                           /\ SILOperands(i, s)[1][2] = s.stack[Len(s.stack)] /\ SILOperands(i, s)[1][2] \in DOMAIN s.m
                           /\ s.m[SILOperands(i, s)[1][2]] = "uninitialized"
                       THEN [s EXCEPT !.m = SILMapRemove(s.m, SILOperands(i, s)[1][2]), !.stack = SubSeq(@, 1, Len(@)-1)]
                       ELSE SILReject(s)
    [] i.op = "unit" -> SILRegister(s, i.out, <<"unit", 0>>)
    [] i.op = "return" -> IF SILOperands(i, s)[1] = <<"unit", 0>> /\ s.active = {} /\ s.stack = <<>>
                         THEN [s EXCEPT !.control = "returned"] ELSE SILReject(s)

SILExecutedLines(rawLines, instructions, starts, comments, history, maxInt) ==
    /\ DOMAIN history = 0..Len(instructions)
    /\ DOMAIN rawLines = 1..Len(instructions)
    /\ DOMAIN starts = DOMAIN rawLines /\ DOMAIN comments = DOMAIN rawLines
    /\ \A k \in 1..Len(instructions):
        /\ SILDecodesInstruction(rawLines[k], instructions[k], starts[k], comments[k])
        /\ history[k] = SILExecute(instructions[k], history[k-1], maxInt)
====
