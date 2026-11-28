---- MODULE AtomicSchedulerLocalOperands ----
EXTENDS AtomicSchedulerReturnSource, CompilerInputPageBlock30, CompilerInputPageBlock35, CompilerInputPageBlock36, CompilerInputPageBlock37

\* Byte ingress alone supplies no interpretation of the selected Swift statements.
\* Root dispatch, lexical binding, normal Swift calls and array operations are reviewed.

\* CompilerInputPage1901
\* CompilerInputPage1902
\* CompilerInputPage1903
\* CompilerInputPage1904
\* CompilerInputPage1906
\* CompilerInputPage1907
\* CompilerInputPage2237
\* CompilerInputPage2238
\* CompilerInputPage2239
\* CompilerInputPage2240
\* CompilerInputPage2241
\* CompilerInputPage2242
\* CompilerInputPage2243
\* CompilerInputPage2244
\* CompilerInputPage2245
\* CompilerInputPage2246
\* CompilerInputPage2259
\* CompilerInputPage2260
\* CompilerInputPage2261
\* CompilerInputPage2262
\* CompilerInputPage2263
\* CompilerInputPage2264
\* CompilerInputPage2265
\* CompilerInputPage2266
\* CompilerInputPage2267
\* CompilerInputPage2268
\* CompilerInputPage2269
\* CompilerInputPage2270
\* CompilerInputPage2271
\* CompilerInputPage2285
\* CompilerInputPage2286
\* CompilerInputPage2287
\* CompilerInputPage2288
\* CompilerInputPage2289
\* CompilerInputPage2290
\* CompilerInputPage2291
\* CompilerInputPage2292
\* CompilerInputPage2293
\* CompilerInputPage2294
\* CompilerInputPage2295
\* CompilerInputPage2296
\* CompilerInputPage2297
\* CompilerInputPage2298
\* CompilerInputPage2299
\* CompilerInputPage2300
\* CompilerInputPage2301
\* CompilerInputPage2302
\* CompilerInputPage2303
\* CompilerInputPage2304
\* CompilerInputPage2321
\* CompilerInputPage2322
\* CompilerInputPage2323
\* CompilerInputPage2324
\* CompilerInputPage2325
\* CompilerInputPage2326
\* CompilerInputPage2327
\* CompilerInputPage2328
\* CompilerInputPage2329
\* CompilerInputPage2330
\* CompilerInputPage2331
SchedulerOperandSourcePages ==
    /\ \A j \in 1..16: CompilerInputByte[30400 + j - 1] = <<32, 32, 125, 10, 32, 32, 32, 32, 125, 10, 10, 32, 32, 32, 32, 102>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30416 + j - 1] = <<117, 110, 99, 32, 97, 115, 115, 105, 103, 110, 105, 110, 103, 40, 95, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30432 + j - 1] = <<118, 97, 108, 117, 101, 58, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30448 + j - 1] = <<41, 32, 45, 62, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114, 32, 123>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30480 + j - 1] = <<115, 101, 108, 102, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30496 + j - 1] = <<97, 115, 101, 32, 46, 114, 111, 111, 116, 58, 32, 118, 97, 108, 117, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35776 + j - 1] = <<110, 99, 32, 115, 99, 104, 101, 100, 117, 108, 101, 40, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35792 + j - 1] = <<32, 32, 32, 32, 32, 95, 32, 118, 97, 108, 117, 101, 115, 58, 32, 91>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35808 + j - 1] = <<65, 108, 103, 111, 114, 105, 116, 104, 109, 83, 116, 97, 116, 101, 109, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35824 + j - 1] = <<110, 116, 77, 111, 100, 101, 108, 93, 44, 10, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35840 + j - 1] = <<32, 32, 97, 115, 115, 105, 103, 110, 109, 101, 110, 116, 115, 58, 32, 91>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35856 + j - 1] = <<65, 108, 103, 111, 114, 105, 116, 104, 109, 65, 115, 115, 105, 103, 110, 109>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35872 + j - 1] = <<101, 110, 116, 77, 111, 100, 101, 108, 93, 32, 61, 32, 91, 93, 44, 10>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35888 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 112, 108, 97, 99, 101, 109>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35904 + j - 1] = <<101, 110, 116, 115, 58, 32, 82, 101, 112, 108, 97, 99, 101, 109, 101, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[35920 + j - 1] = <<116, 115, 32, 61, 32, 46, 105, 110, 105, 116, 40, 41, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36128 + j - 1] = <<102, 105, 110, 97, 108, 87, 114, 105, 116, 101, 115, 32, 125, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36144 + j - 1] = <<32, 32, 32, 32, 32, 32, 108, 101, 116, 32, 115, 117, 102, 102, 105, 120>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36160 + j - 1] = <<32, 61, 32, 65, 114, 114, 97, 121, 40, 118, 97, 108, 117, 101, 115, 46>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36176 + j - 1] = <<100, 114, 111, 112, 70, 105, 114, 115, 116, 40, 41, 41, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36192 + j - 1] = <<32, 32, 32, 32, 32, 102, 117, 110, 99, 32, 101, 120, 112, 114, 101, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36208 + j - 1] = <<115, 105, 111, 110, 40, 95, 32, 118, 97, 108, 117, 101, 58, 32, 83, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36224 + j - 1] = <<97, 116, 101, 69, 120, 112, 114, 41, 32, 45, 62, 32, 83, 116, 97, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36240 + j - 1] = <<101, 69, 120, 112, 114, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36256 + j - 1] = <<32, 32, 32, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114, 46, 115, 117>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36272 + j - 1] = <<98, 115, 116, 105, 116, 117, 116, 101, 86, 97, 114, 105, 97, 98, 108, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36288 + j - 1] = <<115, 40, 114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 46, 98>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36304 + j - 1] = <<105, 110, 100, 105, 110, 103, 115, 44, 32, 105, 110, 58, 32, 118, 97, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36320 + j - 1] = <<117, 101, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36544 + j - 1] = <<101, 110, 116, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36560 + j - 1] = <<115, 101, 32, 46, 115, 101, 116, 40, 108, 101, 116, 32, 116, 97, 114, 103>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36576 + j - 1] = <<101, 116, 44, 32, 108, 101, 116, 32, 118, 97, 108, 117, 101, 41, 58, 10>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36592 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 108, 101, 116, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36608 + j - 1] = <<117, 112, 100, 97, 116, 101, 32, 61, 32, 83, 99, 104, 101, 100, 117, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36624 + j - 1] = <<101, 100, 65, 116, 111, 109, 105, 99, 66, 105, 110, 100, 105, 110, 103, 87>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36640 + j - 1] = <<114, 105, 116, 101, 40, 112, 114, 101, 100, 101, 99, 101, 115, 115, 111, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36656 + j - 1] = <<58, 32, 114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 46, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36672 + j - 1] = <<97, 115, 116, 87, 114, 105, 116, 101, 63, 46, 98, 105, 110, 100, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36688 + j - 1] = <<103, 44, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36704 + j - 1] = <<32, 32, 32, 116, 97, 114, 103, 101, 116, 58, 32, 116, 97, 114, 103, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36720 + j - 1] = <<116, 46, 114, 111, 111, 116, 44, 32, 98, 105, 110, 100, 105, 110, 103, 58>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36736 + j - 1] = <<32, 98, 105, 110, 100, 105, 110, 103, 40, 41, 41, 10, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36752 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 108, 101, 116, 32, 117, 112, 100, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36768 + j - 1] = <<116, 101, 100, 32, 61, 32, 101, 120, 112, 114, 101, 115, 115, 105, 111, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36784 + j - 1] = <<40, 116, 97, 114, 103, 101, 116, 46, 97, 115, 115, 105, 103, 110, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36800 + j - 1] = <<103, 40, 118, 97, 108, 117, 101, 41, 41, 10, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36816 + j - 1] = <<32, 32, 32, 32, 32, 32, 108, 101, 116, 32, 110, 101, 120, 116, 32, 61>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36832 + j - 1] = <<32, 114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 46, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[36848 + j - 1] = <<99, 111, 114, 100, 105, 110, 103, 40, 117, 112, 100, 97, 116, 101, 41, 10>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37120 + j - 1] = <<125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 108, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37136 + j - 1] = <<116, 32, 112, 101, 110, 100, 105, 110, 103, 32, 61, 32, 97, 115, 115, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37152 + j - 1] = <<103, 110, 109, 101, 110, 116, 115, 46, 102, 105, 108, 116, 101, 114, 32, 123>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37168 + j - 1] = <<32, 36, 48, 46, 116, 97, 114, 103, 101, 116, 46, 114, 111, 111, 116, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37184 + j - 1] = <<33, 61, 32, 117, 112, 100, 97, 116, 101, 46, 116, 97, 114, 103, 101, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37200 + j - 1] = <<32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37216 + j - 1] = <<32, 32, 32, 43, 32, 91, 46, 105, 110, 105, 116, 40, 116, 97, 114, 103>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37232 + j - 1] = <<101, 116, 58, 32, 46, 114, 111, 111, 116, 40, 117, 112, 100, 97, 116, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37248 + j - 1] = <<46, 116, 97, 114, 103, 101, 116, 41, 44, 32, 118, 97, 108, 117, 101, 58>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37264 + j - 1] = <<32, 46, 118, 97, 114, 105, 97, 98, 108, 101, 40, 117, 112, 100, 97, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[37280 + j - 1] = <<101, 46, 98, 105, 110, 100, 105, 110, 103, 41, 41, 93, 10, 32, 32, 32>>[j]
THEOREM ActualSetOperandSourcePages == SchedulerOperandSourcePages
    BY ONLY CompilerInputPageBlock30AtFileOffsets, CompilerInputPageBlock35AtFileOffsets, CompilerInputPageBlock36AtFileOffsets, CompilerInputPageBlock37AtFileOffsets, PTL DEF SchedulerOperandSourcePages
SwiftSchedulerLocalNames == [
    rootParam |-> <<CompilerInputByte[30432], CompilerInputByte[30433], CompilerInputByte[30434], CompilerInputByte[30435], CompilerInputByte[30436]>>,
    rootReturn |-> <<CompilerInputByte[30507], CompilerInputByte[30508], CompilerInputByte[30509], CompilerInputByte[30510], CompilerInputByte[30511]>>,
    values |-> <<CompilerInputByte[35799], CompilerInputByte[35800], CompilerInputByte[35801], CompilerInputByte[35802], CompilerInputByte[35803], CompilerInputByte[35804]>>,
    assignments |-> <<CompilerInputByte[35842], CompilerInputByte[35843], CompilerInputByte[35844], CompilerInputByte[35845], CompilerInputByte[35846], CompilerInputByte[35847], CompilerInputByte[35848], CompilerInputByte[35849], CompilerInputByte[35850], CompilerInputByte[35851], CompilerInputByte[35852]>>,
    repls |-> <<CompilerInputByte[35896], CompilerInputByte[35897], CompilerInputByte[35898], CompilerInputByte[35899], CompilerInputByte[35900], CompilerInputByte[35901], CompilerInputByte[35902], CompilerInputByte[35903], CompilerInputByte[35904], CompilerInputByte[35905], CompilerInputByte[35906], CompilerInputByte[35907]>>,
    suffix |-> <<CompilerInputByte[36154], CompilerInputByte[36155], CompilerInputByte[36156], CompilerInputByte[36157], CompilerInputByte[36158], CompilerInputByte[36159]>>,
    tailInput |-> <<CompilerInputByte[36169], CompilerInputByte[36170], CompilerInputByte[36171], CompilerInputByte[36172], CompilerInputByte[36173], CompilerInputByte[36174]>>,
    helper |-> <<CompilerInputByte[36202], CompilerInputByte[36203], CompilerInputByte[36204], CompilerInputByte[36205], CompilerInputByte[36206], CompilerInputByte[36207], CompilerInputByte[36208], CompilerInputByte[36209], CompilerInputByte[36210], CompilerInputByte[36211]>>,
    helperParam |-> <<CompilerInputByte[36215], CompilerInputByte[36216], CompilerInputByte[36217], CompilerInputByte[36218], CompilerInputByte[36219]>>,
    mapRecv |-> <<CompilerInputByte[36290], CompilerInputByte[36291], CompilerInputByte[36292], CompilerInputByte[36293], CompilerInputByte[36294], CompilerInputByte[36295], CompilerInputByte[36296], CompilerInputByte[36297], CompilerInputByte[36298], CompilerInputByte[36299], CompilerInputByte[36300], CompilerInputByte[36301]>>,
    mapField |-> <<CompilerInputByte[36303], CompilerInputByte[36304], CompilerInputByte[36305], CompilerInputByte[36306], CompilerInputByte[36307], CompilerInputByte[36308], CompilerInputByte[36309], CompilerInputByte[36310]>>,
    helperValue |-> <<CompilerInputByte[36317], CompilerInputByte[36318], CompilerInputByte[36319], CompilerInputByte[36320], CompilerInputByte[36321]>>,
    patternTarget |-> <<CompilerInputByte[36572], CompilerInputByte[36573], CompilerInputByte[36574], CompilerInputByte[36575], CompilerInputByte[36576], CompilerInputByte[36577]>>,
    patternValue |-> <<CompilerInputByte[36584], CompilerInputByte[36585], CompilerInputByte[36586], CompilerInputByte[36587], CompilerInputByte[36588]>>,
    descriptor |-> <<CompilerInputByte[36608], CompilerInputByte[36609], CompilerInputByte[36610], CompilerInputByte[36611], CompilerInputByte[36612], CompilerInputByte[36613]>>,
    previousReceiver |-> <<CompilerInputByte[36658], CompilerInputByte[36659], CompilerInputByte[36660], CompilerInputByte[36661], CompilerInputByte[36662], CompilerInputByte[36663], CompilerInputByte[36664], CompilerInputByte[36665], CompilerInputByte[36666], CompilerInputByte[36667], CompilerInputByte[36668], CompilerInputByte[36669]>>,
    previousField |-> <<CompilerInputByte[36671], CompilerInputByte[36672], CompilerInputByte[36673], CompilerInputByte[36674], CompilerInputByte[36675], CompilerInputByte[36676], CompilerInputByte[36677], CompilerInputByte[36678], CompilerInputByte[36679]>>,
    previousBinder |-> <<CompilerInputByte[36682], CompilerInputByte[36683], CompilerInputByte[36684], CompilerInputByte[36685], CompilerInputByte[36686], CompilerInputByte[36687], CompilerInputByte[36688]>>,
    rootReceiver |-> <<CompilerInputByte[36715], CompilerInputByte[36716], CompilerInputByte[36717], CompilerInputByte[36718], CompilerInputByte[36719], CompilerInputByte[36720]>>,
    targetProperty |-> <<CompilerInputByte[36722], CompilerInputByte[36723], CompilerInputByte[36724], CompilerInputByte[36725]>>,
    allocator |-> <<CompilerInputByte[36737], CompilerInputByte[36738], CompilerInputByte[36739], CompilerInputByte[36740], CompilerInputByte[36741], CompilerInputByte[36742], CompilerInputByte[36743]>>,
    result |-> <<CompilerInputByte[36764], CompilerInputByte[36765], CompilerInputByte[36766], CompilerInputByte[36767], CompilerInputByte[36768], CompilerInputByte[36769], CompilerInputByte[36770]>>,
    called |-> <<CompilerInputByte[36774], CompilerInputByte[36775], CompilerInputByte[36776], CompilerInputByte[36777], CompilerInputByte[36778], CompilerInputByte[36779], CompilerInputByte[36780], CompilerInputByte[36781], CompilerInputByte[36782], CompilerInputByte[36783]>>,
    assignRecv |-> <<CompilerInputByte[36785], CompilerInputByte[36786], CompilerInputByte[36787], CompilerInputByte[36788], CompilerInputByte[36789], CompilerInputByte[36790]>>,
    assignArg |-> <<CompilerInputByte[36802], CompilerInputByte[36803], CompilerInputByte[36804], CompilerInputByte[36805], CompilerInputByte[36806]>>,
    next |-> <<CompilerInputByte[36826], CompilerInputByte[36827], CompilerInputByte[36828], CompilerInputByte[36829]>>,
    nextRecv |-> <<CompilerInputByte[36833], CompilerInputByte[36834], CompilerInputByte[36835], CompilerInputByte[36836], CompilerInputByte[36837], CompilerInputByte[36838], CompilerInputByte[36839], CompilerInputByte[36840], CompilerInputByte[36841], CompilerInputByte[36842], CompilerInputByte[36843], CompilerInputByte[36844]>>,
    nextArg |-> <<CompilerInputByte[36856], CompilerInputByte[36857], CompilerInputByte[36858], CompilerInputByte[36859], CompilerInputByte[36860], CompilerInputByte[36861]>>,
    pending |-> <<CompilerInputByte[37138], CompilerInputByte[37139], CompilerInputByte[37140], CompilerInputByte[37141], CompilerInputByte[37142], CompilerInputByte[37143], CompilerInputByte[37144]>>,
    pendingInput |-> <<CompilerInputByte[37148], CompilerInputByte[37149], CompilerInputByte[37150], CompilerInputByte[37151], CompilerInputByte[37152], CompilerInputByte[37153], CompilerInputByte[37154], CompilerInputByte[37155], CompilerInputByte[37156], CompilerInputByte[37157], CompilerInputByte[37158]>>,
    keepTarget |-> <<CompilerInputByte[37187], CompilerInputByte[37188], CompilerInputByte[37189], CompilerInputByte[37190], CompilerInputByte[37191], CompilerInputByte[37192]>>,
    appendTarget |-> <<CompilerInputByte[37242], CompilerInputByte[37243], CompilerInputByte[37244], CompilerInputByte[37245], CompilerInputByte[37246], CompilerInputByte[37247]>>,
    appendBinder |-> <<CompilerInputByte[37275], CompilerInputByte[37276], CompilerInputByte[37277], CompilerInputByte[37278], CompilerInputByte[37279], CompilerInputByte[37280]>>]
SchedulerRootBindingsField == <<98,105,110,100,105,110,103,115>>
SchedulerRootPatternValue == <<118,97,108,117,101>>
SchedulerRootReplacements == <<114,101,112,108,97,99,101,109,101,110,116,115>>
SchedulerTokenExpression == <<101, 120, 112, 114, 101, 115, 115, 105, 111, 110>>
SchedulerTokenTarget == <<116, 97, 114, 103, 101, 116>>
SchedulerTokenLastWrite == <<108, 97, 115, 116, 87, 114, 105, 116, 101>>
SchedulerTokenRoot == <<114, 111, 111, 116>>

SchedulerLexicalNames == [
    rootParam |-> SchedulerRootPatternValue,
    rootReturn |-> SchedulerRootPatternValue,
    values |-> SchedulerNameValues,
    assignments |-> SchedulerNameAssignments,
    repls |-> SchedulerRootReplacements,
    suffix |-> SchedulerNameSuffix,
    tailInput |-> SchedulerNameValues,
    helper |-> SchedulerTokenExpression,
    helperParam |-> SchedulerRootPatternValue,
    mapRecv |-> SchedulerRootReplacements,
    mapField |-> SchedulerRootBindingsField,
    helperValue |-> SchedulerRootPatternValue,
    patternTarget |-> SchedulerTokenTarget,
    patternValue |-> SchedulerRootPatternValue,
    descriptor |-> SchedulerNameUpdate,
    previousReceiver |-> SchedulerRootReplacements,
    previousField |-> SchedulerTokenLastWrite,
    previousBinder |-> SchedulerNameBinding,
    rootReceiver |-> SchedulerTokenTarget,
    targetProperty |-> SchedulerTokenRoot,
    allocator |-> SchedulerNameBinding,
    result |-> SchedulerNameUpdated,
    called |-> SchedulerTokenExpression,
    assignRecv |-> SchedulerTokenTarget,
    assignArg |-> SchedulerRootPatternValue,
    next |-> SchedulerNameNext,
    nextRecv |-> SchedulerRootReplacements,
    nextArg |-> SchedulerNameUpdate,
    pending |-> SchedulerNamePending,
    pendingInput |-> SchedulerNameAssignments,
    keepTarget |-> SchedulerNameUpdate,
    appendTarget |-> SchedulerNameUpdate,
    appendBinder |-> SchedulerNameUpdate]
THEOREM ActualSchedulerLocalNameUses == SwiftSchedulerLocalNames = SchedulerLexicalNames
PROOF
<1>rootParamUse. <<CompilerInputByte[30432], CompilerInputByte[30433], CompilerInputByte[30434], CompilerInputByte[30435], CompilerInputByte[30436]>> = SchedulerRootPatternValue
    BY ONLY CompilerInputPageBlock30AtFileOffsets, SMT DEF SchedulerRootPatternValue
<1>rootReturnUse. <<CompilerInputByte[30507], CompilerInputByte[30508], CompilerInputByte[30509], CompilerInputByte[30510], CompilerInputByte[30511]>> = SchedulerRootPatternValue
    BY ONLY CompilerInputPageBlock30AtFileOffsets, SMT DEF SchedulerRootPatternValue
<1>valuesUse. <<CompilerInputByte[35799], CompilerInputByte[35800], CompilerInputByte[35801], CompilerInputByte[35802], CompilerInputByte[35803], CompilerInputByte[35804]>> = SchedulerNameValues
    BY ONLY CompilerInputPageBlock35AtFileOffsets, CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameValues
<1>assignmentsUse. <<CompilerInputByte[35842], CompilerInputByte[35843], CompilerInputByte[35844], CompilerInputByte[35845], CompilerInputByte[35846], CompilerInputByte[35847], CompilerInputByte[35848], CompilerInputByte[35849], CompilerInputByte[35850], CompilerInputByte[35851], CompilerInputByte[35852]>> = SchedulerNameAssignments
    BY ONLY CompilerInputPageBlock35AtFileOffsets, CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameAssignments
<1>replsUse. <<CompilerInputByte[35896], CompilerInputByte[35897], CompilerInputByte[35898], CompilerInputByte[35899], CompilerInputByte[35900], CompilerInputByte[35901], CompilerInputByte[35902], CompilerInputByte[35903], CompilerInputByte[35904], CompilerInputByte[35905], CompilerInputByte[35906], CompilerInputByte[35907]>> = SchedulerRootReplacements
    BY ONLY CompilerInputPageBlock35AtFileOffsets, CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerRootReplacements
<1>suffixUse. <<CompilerInputByte[36154], CompilerInputByte[36155], CompilerInputByte[36156], CompilerInputByte[36157], CompilerInputByte[36158], CompilerInputByte[36159]>> = SchedulerNameSuffix
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameSuffix
<1>tailInputUse. <<CompilerInputByte[36169], CompilerInputByte[36170], CompilerInputByte[36171], CompilerInputByte[36172], CompilerInputByte[36173], CompilerInputByte[36174]>> = SchedulerNameValues
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameValues
<1>helperUse. <<CompilerInputByte[36202], CompilerInputByte[36203], CompilerInputByte[36204], CompilerInputByte[36205], CompilerInputByte[36206], CompilerInputByte[36207], CompilerInputByte[36208], CompilerInputByte[36209], CompilerInputByte[36210], CompilerInputByte[36211]>> = SchedulerTokenExpression
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerTokenExpression
<1>helperParamUse. <<CompilerInputByte[36215], CompilerInputByte[36216], CompilerInputByte[36217], CompilerInputByte[36218], CompilerInputByte[36219]>> = SchedulerRootPatternValue
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerRootPatternValue
<1>mapRecvUse. <<CompilerInputByte[36290], CompilerInputByte[36291], CompilerInputByte[36292], CompilerInputByte[36293], CompilerInputByte[36294], CompilerInputByte[36295], CompilerInputByte[36296], CompilerInputByte[36297], CompilerInputByte[36298], CompilerInputByte[36299], CompilerInputByte[36300], CompilerInputByte[36301]>> = SchedulerRootReplacements
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerRootReplacements
<1>mapFieldUse. <<CompilerInputByte[36303], CompilerInputByte[36304], CompilerInputByte[36305], CompilerInputByte[36306], CompilerInputByte[36307], CompilerInputByte[36308], CompilerInputByte[36309], CompilerInputByte[36310]>> = SchedulerRootBindingsField
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerRootBindingsField
<1>helperValueUse. <<CompilerInputByte[36317], CompilerInputByte[36318], CompilerInputByte[36319], CompilerInputByte[36320], CompilerInputByte[36321]>> = SchedulerRootPatternValue
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerRootPatternValue
<1>patternTargetUse. <<CompilerInputByte[36572], CompilerInputByte[36573], CompilerInputByte[36574], CompilerInputByte[36575], CompilerInputByte[36576], CompilerInputByte[36577]>> = SchedulerTokenTarget
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerTokenTarget
<1>patternValueUse. <<CompilerInputByte[36584], CompilerInputByte[36585], CompilerInputByte[36586], CompilerInputByte[36587], CompilerInputByte[36588]>> = SchedulerRootPatternValue
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerRootPatternValue
<1>descriptorUse. <<CompilerInputByte[36608], CompilerInputByte[36609], CompilerInputByte[36610], CompilerInputByte[36611], CompilerInputByte[36612], CompilerInputByte[36613]>> = SchedulerNameUpdate
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameUpdate
<1>previousReceiverUse. <<CompilerInputByte[36658], CompilerInputByte[36659], CompilerInputByte[36660], CompilerInputByte[36661], CompilerInputByte[36662], CompilerInputByte[36663], CompilerInputByte[36664], CompilerInputByte[36665], CompilerInputByte[36666], CompilerInputByte[36667], CompilerInputByte[36668], CompilerInputByte[36669]>> = SchedulerRootReplacements
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerRootReplacements
<1>previousFieldUse. <<CompilerInputByte[36671], CompilerInputByte[36672], CompilerInputByte[36673], CompilerInputByte[36674], CompilerInputByte[36675], CompilerInputByte[36676], CompilerInputByte[36677], CompilerInputByte[36678], CompilerInputByte[36679]>> = SchedulerTokenLastWrite
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerTokenLastWrite
<1>previousBinderUse. <<CompilerInputByte[36682], CompilerInputByte[36683], CompilerInputByte[36684], CompilerInputByte[36685], CompilerInputByte[36686], CompilerInputByte[36687], CompilerInputByte[36688]>> = SchedulerNameBinding
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameBinding
<1>rootReceiverUse. <<CompilerInputByte[36715], CompilerInputByte[36716], CompilerInputByte[36717], CompilerInputByte[36718], CompilerInputByte[36719], CompilerInputByte[36720]>> = SchedulerTokenTarget
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerTokenTarget
<1>targetPropertyUse. <<CompilerInputByte[36722], CompilerInputByte[36723], CompilerInputByte[36724], CompilerInputByte[36725]>> = SchedulerTokenRoot
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerTokenRoot
<1>allocatorUse. <<CompilerInputByte[36737], CompilerInputByte[36738], CompilerInputByte[36739], CompilerInputByte[36740], CompilerInputByte[36741], CompilerInputByte[36742], CompilerInputByte[36743]>> = SchedulerNameBinding
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameBinding
<1>resultUse. <<CompilerInputByte[36764], CompilerInputByte[36765], CompilerInputByte[36766], CompilerInputByte[36767], CompilerInputByte[36768], CompilerInputByte[36769], CompilerInputByte[36770]>> = SchedulerNameUpdated
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameUpdated
<1>calledUse. <<CompilerInputByte[36774], CompilerInputByte[36775], CompilerInputByte[36776], CompilerInputByte[36777], CompilerInputByte[36778], CompilerInputByte[36779], CompilerInputByte[36780], CompilerInputByte[36781], CompilerInputByte[36782], CompilerInputByte[36783]>> = SchedulerTokenExpression
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerTokenExpression
<1>assignRecvUse. <<CompilerInputByte[36785], CompilerInputByte[36786], CompilerInputByte[36787], CompilerInputByte[36788], CompilerInputByte[36789], CompilerInputByte[36790]>> = SchedulerTokenTarget
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerTokenTarget
<1>assignArgUse. <<CompilerInputByte[36802], CompilerInputByte[36803], CompilerInputByte[36804], CompilerInputByte[36805], CompilerInputByte[36806]>> = SchedulerRootPatternValue
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerRootPatternValue
<1>nextUse. <<CompilerInputByte[36826], CompilerInputByte[36827], CompilerInputByte[36828], CompilerInputByte[36829]>> = SchedulerNameNext
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameNext
<1>nextRecvUse. <<CompilerInputByte[36833], CompilerInputByte[36834], CompilerInputByte[36835], CompilerInputByte[36836], CompilerInputByte[36837], CompilerInputByte[36838], CompilerInputByte[36839], CompilerInputByte[36840], CompilerInputByte[36841], CompilerInputByte[36842], CompilerInputByte[36843], CompilerInputByte[36844]>> = SchedulerRootReplacements
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerRootReplacements
<1>nextArgUse. <<CompilerInputByte[36856], CompilerInputByte[36857], CompilerInputByte[36858], CompilerInputByte[36859], CompilerInputByte[36860], CompilerInputByte[36861]>> = SchedulerNameUpdate
    BY ONLY CompilerInputPageBlock36AtFileOffsets, SMT DEF SchedulerNameUpdate
<1>pendingUse. <<CompilerInputByte[37138], CompilerInputByte[37139], CompilerInputByte[37140], CompilerInputByte[37141], CompilerInputByte[37142], CompilerInputByte[37143], CompilerInputByte[37144]>> = SchedulerNamePending
    BY ONLY CompilerInputPageBlock37AtFileOffsets, SMT DEF SchedulerNamePending
<1>pendingInputUse. <<CompilerInputByte[37148], CompilerInputByte[37149], CompilerInputByte[37150], CompilerInputByte[37151], CompilerInputByte[37152], CompilerInputByte[37153], CompilerInputByte[37154], CompilerInputByte[37155], CompilerInputByte[37156], CompilerInputByte[37157], CompilerInputByte[37158]>> = SchedulerNameAssignments
    BY ONLY CompilerInputPageBlock37AtFileOffsets, SMT DEF SchedulerNameAssignments
<1>keepTargetUse. <<CompilerInputByte[37187], CompilerInputByte[37188], CompilerInputByte[37189], CompilerInputByte[37190], CompilerInputByte[37191], CompilerInputByte[37192]>> = SchedulerNameUpdate
    BY ONLY CompilerInputPageBlock37AtFileOffsets, SMT DEF SchedulerNameUpdate
<1>appendTargetUse. <<CompilerInputByte[37242], CompilerInputByte[37243], CompilerInputByte[37244], CompilerInputByte[37245], CompilerInputByte[37246], CompilerInputByte[37247]>> = SchedulerNameUpdate
    BY ONLY CompilerInputPageBlock37AtFileOffsets, SMT DEF SchedulerNameUpdate
<1>appendBinderUse. <<CompilerInputByte[37275], CompilerInputByte[37276], CompilerInputByte[37277], CompilerInputByte[37278], CompilerInputByte[37279], CompilerInputByte[37280]>> = SchedulerNameUpdate
    BY ONLY CompilerInputPageBlock37AtFileOffsets, SMT DEF SchedulerNameUpdate
<1>. QED BY ONLY <1>rootParamUse, <1>rootReturnUse, <1>valuesUse, <1>assignmentsUse, <1>replsUse, <1>suffixUse, <1>tailInputUse, <1>helperUse, <1>helperParamUse, <1>mapRecvUse, <1>mapFieldUse, <1>helperValueUse, <1>patternTargetUse, <1>patternValueUse, <1>descriptorUse, <1>previousReceiverUse, <1>previousFieldUse, <1>previousBinderUse, <1>rootReceiverUse, <1>targetPropertyUse, <1>allocatorUse, <1>resultUse, <1>calledUse, <1>assignRecvUse, <1>assignArgUse, <1>nextUse, <1>nextRecvUse, <1>nextArgUse, <1>pendingUse, <1>pendingInputUse, <1>keepTargetUse, <1>appendTargetUse, <1>appendBinderUse, SMT DEF SwiftSchedulerLocalNames, SchedulerLexicalNames

SchedulerWriteLocal(locals, name, value) ==
    [k \in DOMAIN locals \cup {name} |-> IF k = name THEN value ELSE locals[k]]

\* Every assignment below binds at its declaration token; uses read the token at the call site.
\* Substitute and Record are normal-return operations, not assertions about what they return.
\* The descriptor (including the newly allocated binder) comes from the preceding declaration.
SchedulerUse(declaration, use, value) == IF declaration = use THEN value ELSE "unbound"

SchedulerRhsLocal(entry, Substitute(_,_)) ==
    LET n == SwiftSchedulerLocalNames
        argument == SchedulerUse(n.patternValue, n.assignArg, entry[n.patternValue])
        assigned == SchedulerUse(n.rootParam, n.rootReturn, argument)
        local == SchedulerUse(n.helperParam, n.helperValue, assigned)
    IN IF n.called = n.helper /\ n.assignRecv = n.patternTarget
       THEN Substitute(entry[n.mapRecv][n.mapField], local) ELSE "unbound"

SchedulerNextLocal(entry, descriptor, Record(_,_)) ==
    LET n == SwiftSchedulerLocalNames
    IN Record(entry[n.nextRecv], SchedulerUse(n.descriptor, n.nextArg, descriptor))

SchedulerKeepPending(pending, target) == SelectSeq(pending, LAMBDA a: a.target # target)

SchedulerPendingLocal(entry, descriptor) ==
    LET n == SwiftSchedulerLocalNames
        removed == SchedulerUse(n.descriptor, n.keepTarget, descriptor)
        target == SchedulerUse(n.descriptor, n.appendTarget, descriptor)
        binder == SchedulerUse(n.descriptor, n.appendBinder, descriptor)
    IN Append(SchedulerKeepPending(entry[n.pendingInput], removed.target),
              [target |-> target.target, value |-> [variable |-> binder[SchedulerNameBinding]]])

SchedulerExecuteSetLocals(entry, descriptor, Substitute(_,_), Record(_,_)) ==
    LET n == SwiftSchedulerLocalNames
    IN [k \in {n.descriptor, n.suffix, n.next, n.pending, n.result} |->
        CASE k = n.descriptor -> descriptor
          [] k = n.suffix -> Tail(entry[n.tailInput])
          [] k = n.result -> SchedulerRhsLocal(entry, Substitute)
          [] k = n.next -> SchedulerNextLocal(entry,descriptor,Record)
          [] OTHER -> SchedulerPendingLocal(entry,descriptor)]


SchedulerOperandEdges(n) ==
    /\ n.assignArg = n.patternValue /\ n.rootParam = n.rootReturn
    /\ n.helperParam = n.helperValue /\ n.called = n.helper /\ n.assignRecv = n.patternTarget
    /\ n.patternValue = SchedulerRootPatternValue
    /\ n.mapRecv = SchedulerRootReplacements /\ n.mapField = SchedulerRootBindingsField
    /\ n.nextRecv = SchedulerRootReplacements /\ n.nextArg = n.descriptor
    /\ n.tailInput = SchedulerNameValues /\ n.pendingInput = SchedulerNameAssignments
    /\ n.keepTarget = n.descriptor /\ n.appendTarget = n.descriptor /\ n.appendBinder = n.descriptor
    /\ n.descriptor = SchedulerNameUpdate /\ n.suffix = SchedulerNameSuffix
    /\ n.pending = SchedulerNamePending /\ n.next = SchedulerNameNext /\ n.result = SchedulerNameUpdated
    /\ n.suffix # n.descriptor /\ n.result \notin {n.descriptor, n.suffix}
    /\ n.next \notin {n.descriptor, n.suffix, n.result}
    /\ n.pending \notin {n.descriptor, n.suffix, n.result, n.next}

THEOREM SourceSetBindingsResolveTheirUses == SchedulerOperandEdges(SwiftSchedulerLocalNames)
PROOF
<1>edge1. SchedulerLexicalNames.assignArg = SchedulerLexicalNames.patternValue
    BY DEF SchedulerLexicalNames
<1>edge2. SchedulerLexicalNames.rootParam = SchedulerLexicalNames.rootReturn
    BY DEF SchedulerLexicalNames
<1>edge3. SchedulerLexicalNames.helperParam = SchedulerLexicalNames.helperValue
    BY DEF SchedulerLexicalNames
<1>edge4. SchedulerLexicalNames.called = SchedulerLexicalNames.helper
    BY DEF SchedulerLexicalNames
<1>edge5. SchedulerLexicalNames.assignRecv = SchedulerLexicalNames.patternTarget
    BY DEF SchedulerLexicalNames
<1>edge6. SchedulerLexicalNames.patternValue = SchedulerRootPatternValue
    BY DEF SchedulerLexicalNames
<1>edge7. SchedulerLexicalNames.mapRecv = SchedulerRootReplacements
    BY DEF SchedulerLexicalNames
<1>edge8. SchedulerLexicalNames.mapField = SchedulerRootBindingsField
    BY DEF SchedulerLexicalNames
<1>edge9. SchedulerLexicalNames.nextRecv = SchedulerRootReplacements
    BY DEF SchedulerLexicalNames
<1>edge10. SchedulerLexicalNames.nextArg = SchedulerLexicalNames.descriptor
    BY DEF SchedulerLexicalNames
<1>edge11. SchedulerLexicalNames.tailInput = SchedulerNameValues
    BY DEF SchedulerLexicalNames
<1>edge12. SchedulerLexicalNames.pendingInput = SchedulerNameAssignments
    BY DEF SchedulerLexicalNames
<1>edge13. SchedulerLexicalNames.keepTarget = SchedulerLexicalNames.descriptor
    BY DEF SchedulerLexicalNames
<1>edge14. SchedulerLexicalNames.appendTarget = SchedulerLexicalNames.descriptor
    BY DEF SchedulerLexicalNames
<1>edge15. SchedulerLexicalNames.appendBinder = SchedulerLexicalNames.descriptor
    BY DEF SchedulerLexicalNames
<1>edge16. SchedulerLexicalNames.descriptor = SchedulerNameUpdate
    BY DEF SchedulerLexicalNames
<1>edge17. SchedulerLexicalNames.suffix = SchedulerNameSuffix
    BY DEF SchedulerLexicalNames
<1>edge18. SchedulerLexicalNames.pending = SchedulerNamePending
    BY DEF SchedulerLexicalNames
<1>edge19. SchedulerLexicalNames.next = SchedulerNameNext
    BY DEF SchedulerLexicalNames
<1>edge20. SchedulerLexicalNames.result = SchedulerNameUpdated
    BY DEF SchedulerLexicalNames
<1>edge21. SchedulerLexicalNames.suffix # SchedulerLexicalNames.descriptor
    BY ONLY SMT DEF SchedulerLexicalNames, SchedulerNameSuffix, SchedulerNameUpdate
<1>edge22. SchedulerLexicalNames.result \notin {SchedulerLexicalNames.descriptor, SchedulerLexicalNames.suffix}
    BY ONLY SMT DEF SchedulerLexicalNames, SchedulerNameUpdated, SchedulerNameUpdate, SchedulerNameSuffix
<1>edge23. SchedulerLexicalNames.next \notin {SchedulerLexicalNames.descriptor, SchedulerLexicalNames.suffix, SchedulerLexicalNames.result}
    BY ONLY SMT DEF SchedulerLexicalNames, SchedulerNameNext, SchedulerNameUpdate, SchedulerNameSuffix, SchedulerNameUpdated
<1>edge24. SchedulerLexicalNames.pending \notin {SchedulerLexicalNames.descriptor, SchedulerLexicalNames.suffix, SchedulerLexicalNames.result, SchedulerLexicalNames.next}
    BY ONLY SMT DEF SchedulerLexicalNames, SchedulerNamePending, SchedulerNameUpdate, SchedulerNameSuffix, SchedulerNameUpdated, SchedulerNameNext
<1>literals. SchedulerOperandEdges(SchedulerLexicalNames)
    BY ONLY <1>edge1, <1>edge2, <1>edge3, <1>edge4, <1>edge5, <1>edge6, <1>edge7, <1>edge8, <1>edge9, <1>edge10, <1>edge11, <1>edge12, <1>edge13, <1>edge14, <1>edge15, <1>edge16, <1>edge17, <1>edge18, <1>edge19, <1>edge20, <1>edge21, <1>edge22, <1>edge23, <1>edge24, PTL DEF SchedulerOperandEdges
<1>. QED BY ONLY <1>literals, ActualSchedulerLocalNameUses

THEOREM ActualSetReturnUsesTheIncomingMapAndTheRecordedMap ==
    ASSUME NEW entry, {SchedulerNameValues, SchedulerNameAssignments, SchedulerRootReplacements,
                       SchedulerRootPatternValue, <<116,97,114,103,101,116>>} \subseteq DOMAIN entry,
           NEW descriptor, NEW Substitute(_,_), NEW Record(_,_), NEW recur(_,_,_,_)
    PROVE LET locals == SchedulerExecuteSetLocals(entry, descriptor, Substitute, Record)
              tail == Tail(entry[SchedulerNameValues])
              incoming == entry[SchedulerRootReplacements]
              rhs == entry[SchedulerRootPatternValue]
              binder == descriptor[SchedulerNameBinding]
              pending == Append(SchedulerKeepPending(entry[SchedulerNameAssignments], descriptor.target),
                                [target |-> descriptor.target, value |-> [variable |-> binder]])
          IN SchedulerSetReturn(locals, recur) =
                <<[kind |-> "letBinding", variable |-> binder,
                   value |-> Substitute(incoming[SchedulerRootBindingsField], rhs),
                   body |-> recur(SchedulerNameSchedule, tail, pending, Record(incoming, descriptor))]>>
PROOF
<1>. DEFINE locals == SchedulerExecuteSetLocals(entry, descriptor, Substitute, Record)
            old == entry[SchedulerRootReplacements]
            x == entry[SchedulerRootPatternValue]
            b == descriptor[SchedulerNameBinding]
            tail == Tail(entry[SchedulerNameValues])
            pending == Append(SchedulerKeepPending(entry[SchedulerNameAssignments],descriptor.target),
                              [target |-> descriptor.target, value |-> [variable |-> b]])
<1>rhs. SchedulerRhsLocal(entry, Substitute) = Substitute(old[SchedulerRootBindingsField], x)
    BY ONLY SourceSetBindingsResolveTheirUses, SMT DEF SchedulerRhsLocal, SchedulerOperandEdges, SchedulerUse, old, x
<1>nextStep. SchedulerNextLocal(entry,descriptor,Record) = Record(old,descriptor)
    BY ONLY SourceSetBindingsResolveTheirUses, SMT DEF SchedulerNextLocal, SchedulerOperandEdges, SchedulerUse, old
<1>lastWrites. SchedulerPendingLocal(entry,descriptor) = pending
    BY ONLY SourceSetBindingsResolveTheirUses, SMT DEF SchedulerPendingLocal, SchedulerOperandEdges, SchedulerUse, pending, b
<1>outputs. /\ locals[SchedulerNameUpdate] = descriptor /\ locals[SchedulerNameSuffix] = tail
            /\ locals[SchedulerNameUpdated] = SchedulerRhsLocal(entry,Substitute)
            /\ locals[SchedulerNameNext] = SchedulerNextLocal(entry,descriptor,Record)
            /\ locals[SchedulerNamePending] = SchedulerPendingLocal(entry,descriptor)
    BY ONLY SourceSetBindingsResolveTheirUses, SMT DEF locals, SchedulerExecuteSetLocals, SchedulerOperandEdges, tail
<1>returned. SchedulerSetReturn(locals,recur) =
     <<[kind |-> "letBinding", variable |-> locals[SchedulerNameUpdate][SchedulerNameBinding],
        value |-> locals[SchedulerNameUpdated],
        body |-> recur(SchedulerNameSchedule,locals[SchedulerNameSuffix],locals[SchedulerNamePending],locals[SchedulerNameNext])]>>
    BY ONLY ActualSchedulerReturnOperands, SMT DEF SchedulerSetReturn
<1>joined. SchedulerSetReturn(locals,recur) =
     <<[kind |-> "letBinding", variable |-> b, value |-> Substitute(old[SchedulerRootBindingsField],x),
        body |-> recur(SchedulerNameSchedule,tail,pending,Record(old,descriptor))]>>
    BY ONLY <1>returned, <1>outputs, <1>rhs, <1>lastWrites, <1>nextStep, SMT DEF b
<1>. QED BY ONLY <1>joined DEF locals,old,x,b,tail,pending
====
