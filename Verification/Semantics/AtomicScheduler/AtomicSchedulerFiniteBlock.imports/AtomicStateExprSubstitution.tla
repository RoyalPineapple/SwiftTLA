---- MODULE AtomicStateExprSubstitution ----
EXTENDS OrderedIntExpressionRule, CallerInputPageBlock1, CallerInputPageBlock2, CallerInputPageBlock4, CallerInputPageBlock5, CallerInputPageBlock6, CallerInputPageBlock13

\* These byte facts fix the selected constructor, overload, cases and sub helper.
\* The reviewed Swift interpretation resolves these declarations in their original
\* scopes and uses normal value, Enum, Dictionary and Optional semantics.
\* No allocation, stack, or Swift frontend adequacy result is asserted here.

\* CallerInputPage1
\* CallerInputPage2
\* CallerInputPage3
\* CallerInputPage4
\* CallerInputPage5
\* CallerInputPage6
\* CallerInputPage7
\* CallerInputPage8
\* CallerInputPage9
\* CallerInputPage10
\* CallerInputPage11
\* CallerInputPage12
\* CallerInputPage13
\* CallerInputPage14
\* CallerInputPage15
\* CallerInputPage16
\* CallerInputPage17
\* CallerInputPage18
\* CallerInputPage19
\* CallerInputPage20
\* CallerInputPage21
\* CallerInputPage22
\* CallerInputPage23
\* CallerInputPage24
\* CallerInputPage25
\* CallerInputPage26
\* CallerInputPage27
\* CallerInputPage28
\* CallerInputPage29
\* CallerInputPage30
\* CallerInputPage31
\* CallerInputPage32
\* CallerInputPage33
\* CallerInputPage34
\* CallerInputPage35
\* CallerInputPage36
\* CallerInputPage37
\* CallerInputPage38
\* CallerInputPage39
\* CallerInputPage40
\* CallerInputPage41
\* CallerInputPage42
\* CallerInputPage43
\* CallerInputPage93
\* CallerInputPage94
\* CallerInputPage95
\* CallerInputPage96
\* CallerInputPage97
\* CallerInputPage98
\* CallerInputPage99
\* CallerInputPage100
\* CallerInputPage101
\* CallerInputPage102
\* CallerInputPage103
\* CallerInputPage104
\* CallerInputPage105
\* CallerInputPage106
\* CallerInputPage107
\* CallerInputPage108
\* CallerInputPage109
\* CallerInputPage110
\* CallerInputPage111
\* CallerInputPage112
\* CallerInputPage113
\* CallerInputPage233
\* CallerInputPage234
\* CallerInputPage235
\* CallerInputPage236
\* CallerInputPage237
\* CallerInputPage238
\* CallerInputPage239
\* CallerInputPage240
\* CallerInputPage241
\* CallerInputPage242
\* CallerInputPage243
\* CallerInputPage244
\* CallerInputPage245
\* CallerInputPage246
\* CallerInputPage247
\* CallerInputPage248
\* CallerInputPage249
\* CallerInputPage250
\* CallerInputPage251
\* CallerInputPage252
\* CallerInputPage253
\* CallerInputPage254
\* CallerInputPage255
\* CallerInputPage256
\* CallerInputPage257
\* CallerInputPage258
\* CallerInputPage259
\* CallerInputPage260
\* CallerInputPage261
\* CallerInputPage262
\* CallerInputPage263
\* CallerInputPage264
\* CallerInputPage265
\* CallerInputPage266
\* CallerInputPage267
\* CallerInputPage268
\* CallerInputPage269
\* CallerInputPage270
\* CallerInputPage271
\* CallerInputPage272
\* CallerInputPage273
\* CallerInputPage274
\* CallerInputPage275
\* CallerInputPage276
\* CallerInputPage277
\* CallerInputPage278
\* CallerInputPage279
\* CallerInputPage280
\* CallerInputPage281
\* CallerInputPage282
\* CallerInputPage283
\* CallerInputPage284
\* CallerInputPage285
\* CallerInputPage286
\* CallerInputPage287
\* CallerInputPage288
\* CallerInputPage289
\* CallerInputPage290
\* CallerInputPage291
\* CallerInputPage292
\* CallerInputPage293
\* CallerInputPage294
\* CallerInputPage295
\* CallerInputPage296
\* CallerInputPage297
\* CallerInputPage298
\* CallerInputPage299
\* CallerInputPage300
\* CallerInputPage301
\* CallerInputPage302
\* CallerInputPage303
\* CallerInputPage304
\* CallerInputPage305
\* CallerInputPage306
\* CallerInputPage307
\* CallerInputPage308
\* CallerInputPage309
\* CallerInputPage310
\* CallerInputPage311
\* CallerInputPage312
\* CallerInputPage313
\* CallerInputPage314
\* CallerInputPage315
\* CallerInputPage316
\* CallerInputPage317
\* CallerInputPage318
\* CallerInputPage319
\* CallerInputPage320
\* CallerInputPage321
\* CallerInputPage322
\* CallerInputPage800
\* CallerInputPage801
\* CallerInputPage802
\* CallerInputPage803
\* CallerInputPage804
\* CallerInputPage805
\* CallerInputPage806
\* CallerInputPage807
\* CallerInputPage808

ActualStateExprSubstitutionSourceMatches ==
    /\ \A j \in 1..16: CallerInputByte[0 + j - 1] = <<101, 120, 116, 101, 110, 115, 105, 111, 110, 32, 83, 116, 97, 116, 101, 69>>[j]
    /\ \A j \in 1..16: CallerInputByte[16 + j - 1] = <<120, 112, 114, 32, 123, 10, 32, 32, 32, 32, 112, 114, 105, 118, 97, 116>>[j]
    /\ \A j \in 1..16: CallerInputByte[32 + j - 1] = <<101, 32, 101, 110, 117, 109, 32, 82, 101, 112, 108, 97, 99, 101, 109, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[48 + j - 1] = <<110, 116, 84, 97, 114, 103, 101, 116, 58, 32, 72, 97, 115, 104, 97, 98>>[j]
    /\ \A j \in 1..16: CallerInputByte[64 + j - 1] = <<108, 101, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97, 115>>[j]
    /\ \A j \in 1..16: CallerInputByte[80 + j - 1] = <<101, 32, 118, 97, 114, 105, 97, 98, 108, 101, 40, 83, 116, 114, 105, 110>>[j]
    /\ \A j \in 1..16: CallerInputByte[96 + j - 1] = <<103, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97, 115, 101, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[112 + j - 1] = <<112, 114, 111, 99, 101, 115, 115, 76, 111, 99, 97, 108, 70, 97, 109, 105>>[j]
    /\ \A j \in 1..16: CallerInputByte[128 + j - 1] = <<108, 121, 40, 83, 116, 114, 105, 110, 103, 41, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[144 + j - 1] = <<32, 32, 32, 99, 97, 115, 101, 32, 99, 117, 114, 114, 101, 110, 116, 80>>[j]
    /\ \A j \in 1..16: CallerInputByte[160 + j - 1] = <<114, 111, 99, 101, 115, 115, 10, 32, 32, 32, 32, 125, 10, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[176 + j - 1] = <<32, 32, 112, 114, 105, 118, 97, 116, 101, 32, 115, 116, 114, 117, 99, 116>>[j]
    /\ \A j \in 1..16: CallerInputByte[192 + j - 1] = <<32, 82, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 32, 123, 10>>[j]
    /\ \A j \in 1..16: CallerInputByte[208 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 108, 101, 116, 32, 118, 97, 108, 117>>[j]
    /\ \A j \in 1..16: CallerInputByte[224 + j - 1] = <<101, 115, 58, 32, 91, 82, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116>>[j]
    /\ \A j \in 1..16: CallerInputByte[240 + j - 1] = <<84, 97, 114, 103, 101, 116, 58, 32, 83, 116, 97, 116, 101, 69, 120, 112>>[j]
    /\ \A j \in 1..16: CallerInputByte[256 + j - 1] = <<114, 93, 10, 32, 32, 32, 32, 32, 32, 32, 32, 108, 101, 116, 32, 102>>[j]
    /\ \A j \in 1..16: CallerInputByte[272 + j - 1] = <<114, 101, 101, 86, 97, 114, 105, 97, 98, 108, 101, 115, 58, 32, 83, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[288 + j - 1] = <<116, 60, 83, 116, 114, 105, 110, 103, 62, 10, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[304 + j - 1] = <<32, 32, 108, 101, 116, 32, 118, 97, 114, 105, 97, 98, 108, 101, 78, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[320 + j - 1] = <<109, 101, 115, 58, 32, 83, 101, 116, 60, 83, 116, 114, 105, 110, 103, 62>>[j]
    /\ \A j \in 1..16: CallerInputByte[336 + j - 1] = <<10, 10, 32, 32, 32, 32, 32, 32, 32, 32, 105, 110, 105, 116, 40, 95>>[j]
    /\ \A j \in 1..16: CallerInputByte[352 + j - 1] = <<32, 118, 97, 108, 117, 101, 115, 58, 32, 91, 82, 101, 112, 108, 97, 99>>[j]
    /\ \A j \in 1..16: CallerInputByte[368 + j - 1] = <<101, 109, 101, 110, 116, 84, 97, 114, 103, 101, 116, 58, 32, 83, 116, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[384 + j - 1] = <<116, 101, 69, 120, 112, 114, 93, 41, 32, 123, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[400 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 115, 101, 108, 102, 46, 118, 97, 108, 117>>[j]
    /\ \A j \in 1..16: CallerInputByte[416 + j - 1] = <<101, 115, 32, 61, 32, 118, 97, 108, 117, 101, 115, 10, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[432 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 102, 114, 101, 101, 86, 97, 114, 105>>[j]
    /\ \A j \in 1..16: CallerInputByte[448 + j - 1] = <<97, 98, 108, 101, 115, 32, 61, 32, 83, 101, 116, 40, 118, 97, 108, 117>>[j]
    /\ \A j \in 1..16: CallerInputByte[464 + j - 1] = <<101, 115, 46, 118, 97, 108, 117, 101, 115, 46, 102, 108, 97, 116, 77, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[480 + j - 1] = <<112, 40, 92, 46, 102, 114, 101, 101, 86, 97, 114, 105, 97, 98, 108, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[496 + j - 1] = <<78, 97, 109, 101, 115, 41, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[512 + j - 1] = <<32, 32, 32, 32, 118, 97, 114, 105, 97, 98, 108, 101, 78, 97, 109, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[528 + j - 1] = <<115, 32, 61, 32, 83, 101, 116, 40, 118, 97, 108, 117, 101, 115, 46, 107>>[j]
    /\ \A j \in 1..16: CallerInputByte[544 + j - 1] = <<101, 121, 115, 46, 99, 111, 109, 112, 97, 99, 116, 77, 97, 112, 32, 123>>[j]
    /\ \A j \in 1..16: CallerInputByte[560 + j - 1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[576 + j - 1] = <<32, 103, 117, 97, 114, 100, 32, 99, 97, 115, 101, 32, 46, 118, 97, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[592 + j - 1] = <<105, 97, 98, 108, 101, 40, 108, 101, 116, 32, 110, 97, 109, 101, 41, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[608 + j - 1] = <<61, 32, 36, 48, 32, 101, 108, 115, 101, 32, 123, 32, 114, 101, 116, 117>>[j]
    /\ \A j \in 1..16: CallerInputByte[624 + j - 1] = <<114, 110, 32, 110, 105, 108, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[640 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 116, 117, 114, 110, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[656 + j - 1] = <<110, 97, 109, 101, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[672 + j - 1] = <<32, 125, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 10, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[1472 + j - 1] = <<101, 114, 32, 114, 101, 118, 105, 115, 105, 116, 101, 100, 46, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[1488 + j - 1] = <<32, 32, 112, 97, 99, 107, 97, 103, 101, 32, 115, 116, 97, 116, 105, 99>>[j]
    /\ \A j \in 1..16: CallerInputByte[1504 + j - 1] = <<32, 102, 117, 110, 99, 32, 115, 117, 98, 115, 116, 105, 116, 117, 116, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[1520 + j - 1] = <<86, 97, 114, 105, 97, 98, 108, 101, 115, 40, 95, 32, 118, 97, 108, 117>>[j]
    /\ \A j \in 1..16: CallerInputByte[1536 + j - 1] = <<101, 115, 58, 32, 91, 83, 116, 114, 105, 110, 103, 58, 32, 83, 116, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[1552 + j - 1] = <<116, 101, 69, 120, 112, 114, 93, 44, 32, 105, 110, 32, 101, 120, 112, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[1568 + j - 1] = <<58, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114, 41, 32, 45, 62, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[1584 + j - 1] = <<83, 116, 97, 116, 101, 69, 120, 112, 114, 32, 123, 10, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[1600 + j - 1] = <<32, 32, 32, 32, 108, 101, 116, 32, 114, 101, 112, 108, 97, 99, 101, 109>>[j]
    /\ \A j \in 1..16: CallerInputByte[1616 + j - 1] = <<101, 110, 116, 115, 32, 61, 32, 68, 105, 99, 116, 105, 111, 110, 97, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[1632 + j - 1] = <<121, 40, 117, 110, 105, 113, 117, 101, 75, 101, 121, 115, 87, 105, 116, 104>>[j]
    /\ \A j \in 1..16: CallerInputByte[1648 + j - 1] = <<86, 97, 108, 117, 101, 115, 58, 32, 118, 97, 108, 117, 101, 115, 46, 109>>[j]
    /\ \A j \in 1..16: CallerInputByte[1664 + j - 1] = <<97, 112, 32, 123, 32, 40, 82, 101, 112, 108, 97, 99, 101, 109, 101, 110>>[j]
    /\ \A j \in 1..16: CallerInputByte[1680 + j - 1] = <<116, 84, 97, 114, 103, 101, 116, 46, 118, 97, 114, 105, 97, 98, 108, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[1696 + j - 1] = <<40, 36, 48, 46, 107, 101, 121, 41, 44, 32, 36, 48, 46, 118, 97, 108>>[j]
    /\ \A j \in 1..16: CallerInputByte[1712 + j - 1] = <<117, 101, 41, 32, 125, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[1728 + j - 1] = <<101, 116, 117, 114, 110, 32, 114, 101, 112, 108, 97, 99, 101, 40, 105, 110>>[j]
    /\ \A j \in 1..16: CallerInputByte[1744 + j - 1] = <<58, 32, 101, 120, 112, 114, 44, 32, 117, 115, 105, 110, 103, 58, 32, 82>>[j]
    /\ \A j \in 1..16: CallerInputByte[1760 + j - 1] = <<101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 40, 114, 101, 112, 108>>[j]
    /\ \A j \in 1..16: CallerInputByte[1776 + j - 1] = <<97, 99, 101, 109, 101, 110, 116, 115, 41, 41, 10, 32, 32, 32, 32, 125>>[j]
    /\ \A j \in 1..16: CallerInputByte[1792 + j - 1] = <<10, 10, 32, 32, 32, 32, 112, 97, 99, 107, 97, 103, 101, 32, 102, 117>>[j]
    /\ \A j \in 1..16: CallerInputByte[3712 + j - 1] = <<100, 41, 41, 10, 32, 32, 32, 32, 125, 10, 10, 10, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[3728 + j - 1] = <<112, 114, 105, 118, 97, 116, 101, 32, 115, 116, 97, 116, 105, 99, 32, 102>>[j]
    /\ \A j \in 1..16: CallerInputByte[3744 + j - 1] = <<117, 110, 99, 32, 114, 101, 112, 108, 97, 99, 101, 40, 105, 110, 32, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[3760 + j - 1] = <<120, 112, 114, 58, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114, 44, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[3776 + j - 1] = <<117, 115, 105, 110, 103, 32, 114, 101, 112, 108, 97, 99, 101, 109, 101, 110>>[j]
    /\ \A j \in 1..16: CallerInputByte[3792 + j - 1] = <<116, 115, 58, 32, 82, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>[j]
    /\ \A j \in 1..16: CallerInputByte[3808 + j - 1] = <<41, 32, 45, 62, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114, 32, 123>>[j]
    /\ \A j \in 1..16: CallerInputByte[3824 + j - 1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 103, 117, 97, 114, 100, 32, 33>>[j]
    /\ \A j \in 1..16: CallerInputByte[3840 + j - 1] = <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 46, 118, 97, 108>>[j]
    /\ \A j \in 1..16: CallerInputByte[3856 + j - 1] = <<117, 101, 115, 46, 105, 115, 69, 109, 112, 116, 121, 32, 101, 108, 115, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[3872 + j - 1] = <<32, 123, 32, 114, 101, 116, 117, 114, 110, 32, 101, 120, 112, 114, 32, 125>>[j]
    /\ \A j \in 1..16: CallerInputByte[3888 + j - 1] = <<10, 10, 32, 32, 32, 32, 32, 32, 32, 32, 102, 117, 110, 99, 32, 117>>[j]
    /\ \A j \in 1..16: CallerInputByte[3904 + j - 1] = <<110, 100, 101, 114, 80, 97, 114, 97, 109, 101, 116, 101, 114, 115, 40, 95>>[j]
    /\ \A j \in 1..16: CallerInputByte[3920 + j - 1] = <<32, 112, 97, 114, 97, 109, 101, 116, 101, 114, 115, 58, 32, 91, 83, 116>>[j]
    /\ \A j \in 1..16: CallerInputByte[3936 + j - 1] = <<114, 105, 110, 103, 93, 44, 32, 98, 111, 100, 121, 58, 32, 83, 116, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[3952 + j - 1] = <<116, 101, 69, 120, 112, 114, 41, 32, 45, 62, 32, 40, 112, 97, 114, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[3968 + j - 1] = <<109, 101, 116, 101, 114, 115, 58, 32, 91, 83, 116, 114, 105, 110, 103, 93>>[j]
    /\ \A j \in 1..16: CallerInputByte[3984 + j - 1] = <<44, 32, 98, 111, 100, 121, 58, 32, 83, 116, 97, 116, 101, 69, 120, 112>>[j]
    /\ \A j \in 1..16: CallerInputByte[4000 + j - 1] = <<114, 41, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4016 + j - 1] = <<32, 83, 101, 108, 102, 46, 115, 117, 98, 115, 116, 105, 116, 117, 116, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[4032 + j - 1] = <<85, 110, 100, 101, 114, 80, 97, 114, 97, 109, 101, 116, 101, 114, 115, 40>>[j]
    /\ \A j \in 1..16: CallerInputByte[4048 + j - 1] = <<112, 97, 114, 97, 109, 101, 116, 101, 114, 115, 44, 32, 98, 111, 100, 121>>[j]
    /\ \A j \in 1..16: CallerInputByte[4064 + j - 1] = <<58, 32, 98, 111, 100, 121, 44, 32, 117, 115, 105, 110, 103, 58, 32, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[4080 + j - 1] = <<101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 41, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4096 + j - 1] = <<32, 32, 32, 32, 32, 125, 10, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4112 + j - 1] = <<102, 117, 110, 99, 32, 117, 110, 100, 101, 114, 66, 105, 110, 100, 101, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[4128 + j - 1] = <<40, 95, 32, 98, 105, 110, 100, 101, 114, 58, 32, 83, 116, 114, 105, 110>>[j]
    /\ \A j \in 1..16: CallerInputByte[4144 + j - 1] = <<103, 44, 32, 98, 111, 100, 121, 58, 32, 83, 116, 97, 116, 101, 69, 120>>[j]
    /\ \A j \in 1..16: CallerInputByte[4160 + j - 1] = <<112, 114, 41, 32, 45, 62, 32, 40, 110, 97, 109, 101, 58, 32, 83, 116>>[j]
    /\ \A j \in 1..16: CallerInputByte[4176 + j - 1] = <<114, 105, 110, 103, 44, 32, 98, 111, 100, 121, 58, 32, 83, 116, 97, 116>>[j]
    /\ \A j \in 1..16: CallerInputByte[4192 + j - 1] = <<101, 69, 120, 112, 114, 41, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4208 + j - 1] = <<32, 32, 32, 32, 32, 108, 101, 116, 32, 115, 99, 111, 112, 101, 100, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4224 + j - 1] = <<61, 32, 117, 110, 100, 101, 114, 80, 97, 114, 97, 109, 101, 116, 101, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[4240 + j - 1] = <<115, 40, 91, 98, 105, 110, 100, 101, 114, 93, 44, 32, 98, 111, 100, 121>>[j]
    /\ \A j \in 1..16: CallerInputByte[4256 + j - 1] = <<58, 32, 98, 111, 100, 121, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4272 + j - 1] = <<32, 32, 32, 32, 114, 101, 116, 117, 114, 110, 32, 40, 115, 99, 111, 112>>[j]
    /\ \A j \in 1..16: CallerInputByte[4288 + j - 1] = <<101, 100, 46, 112, 97, 114, 97, 109, 101, 116, 101, 114, 115, 91, 48, 93>>[j]
    /\ \A j \in 1..16: CallerInputByte[4304 + j - 1] = <<44, 32, 115, 99, 111, 112, 101, 100, 46, 98, 111, 100, 121, 41, 10, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4320 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 125, 10, 10, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4336 + j - 1] = <<32, 32, 115, 119, 105, 116, 99, 104, 32, 101, 120, 112, 114, 32, 123, 10>>[j]
    /\ \A j \in 1..16: CallerInputByte[4352 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 99, 97, 115, 101, 32, 46, 115, 111>>[j]
    /\ \A j \in 1..16: CallerInputByte[4368 + j - 1] = <<117, 114, 99, 101, 73, 115, 115, 117, 101, 44, 32, 46, 112, 97, 114, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[4384 + j - 1] = <<109, 101, 116, 101, 114, 44, 32, 46, 99, 104, 101, 99, 107, 105, 110, 103>>[j]
    /\ \A j \in 1..16: CallerInputByte[4400 + j - 1] = <<82, 101, 103, 105, 115, 116, 101, 114, 44, 32, 46, 99, 104, 101, 99, 107>>[j]
    /\ \A j \in 1..16: CallerInputByte[4416 + j - 1] = <<105, 110, 103, 76, 101, 118, 101, 108, 44, 32, 46, 99, 104, 101, 99, 107>>[j]
    /\ \A j \in 1..16: CallerInputByte[4432 + j - 1] = <<105, 110, 103, 68, 105, 97, 109, 101, 116, 101, 114, 58, 32, 114, 101, 116>>[j]
    /\ \A j \in 1..16: CallerInputByte[4448 + j - 1] = <<117, 114, 110, 32, 101, 120, 112, 114, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4464 + j - 1] = <<32, 99, 97, 115, 101, 32, 46, 115, 101, 116, 67, 104, 101, 99, 107, 105>>[j]
    /\ \A j \in 1..16: CallerInputByte[4480 + j - 1] = <<110, 103, 82, 101, 103, 105, 115, 116, 101, 114, 40, 108, 101, 116, 32, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[4496 + j - 1] = <<101, 102, 101, 114, 101, 110, 99, 101, 44, 32, 108, 101, 116, 32, 118, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[4512 + j - 1] = <<108, 117, 101, 41, 58, 32, 114, 101, 116, 117, 114, 110, 32, 46, 115, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[4528 + j - 1] = <<116, 67, 104, 101, 99, 107, 105, 110, 103, 82, 101, 103, 105, 115, 116, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[4544 + j - 1] = <<114, 40, 114, 101, 102, 101, 114, 101, 110, 99, 101, 44, 32, 115, 117, 98>>[j]
    /\ \A j \in 1..16: CallerInputByte[4560 + j - 1] = <<40, 118, 97, 108, 117, 101, 41, 41, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4576 + j - 1] = <<32, 99, 97, 115, 101, 32, 46, 118, 97, 114, 105, 97, 98, 108, 101, 40>>[j]
    /\ \A j \in 1..16: CallerInputByte[4592 + j - 1] = <<108, 101, 116, 32, 110, 97, 109, 101, 41, 58, 32, 114, 101, 116, 117, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[4608 + j - 1] = <<110, 32, 114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 46, 118>>[j]
    /\ \A j \in 1..16: CallerInputByte[4624 + j - 1] = <<97, 108, 117, 101, 115, 91, 46, 118, 97, 114, 105, 97, 98, 108, 101, 40>>[j]
    /\ \A j \in 1..16: CallerInputByte[4640 + j - 1] = <<110, 97, 109, 101, 41, 93, 32, 63, 63, 32, 101, 120, 112, 114, 10, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4656 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 99, 97, 115, 101, 32, 46, 112, 114, 111>>[j]
    /\ \A j \in 1..16: CallerInputByte[4672 + j - 1] = <<99, 101, 115, 115, 76, 111, 99, 97, 108, 70, 97, 109, 105, 108, 121, 40>>[j]
    /\ \A j \in 1..16: CallerInputByte[4688 + j - 1] = <<108, 101, 116, 32, 110, 97, 109, 101, 41, 58, 32, 114, 101, 116, 117, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[4704 + j - 1] = <<110, 32, 114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 46, 118>>[j]
    /\ \A j \in 1..16: CallerInputByte[4720 + j - 1] = <<97, 108, 117, 101, 115, 91, 46, 112, 114, 111, 99, 101, 115, 115, 76, 111>>[j]
    /\ \A j \in 1..16: CallerInputByte[4736 + j - 1] = <<99, 97, 108, 70, 97, 109, 105, 108, 121, 40, 110, 97, 109, 101, 41, 93>>[j]
    /\ \A j \in 1..16: CallerInputByte[4752 + j - 1] = <<32, 63, 63, 32, 101, 120, 112, 114, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4768 + j - 1] = <<32, 99, 97, 115, 101, 32, 46, 99, 117, 114, 114, 101, 110, 116, 80, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[4784 + j - 1] = <<111, 99, 101, 115, 115, 58, 32, 114, 101, 116, 117, 114, 110, 32, 114, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[4800 + j - 1] = <<112, 108, 97, 99, 101, 109, 101, 110, 116, 115, 46, 118, 97, 108, 117, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[4816 + j - 1] = <<115, 91, 46, 99, 117, 114, 114, 101, 110, 116, 80, 114, 111, 99, 101, 115>>[j]
    /\ \A j \in 1..16: CallerInputByte[4832 + j - 1] = <<115, 93, 32, 63, 63, 32, 101, 120, 112, 114, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[4848 + j - 1] = <<32, 32, 32, 99, 97, 115, 101, 32, 46, 112, 114, 111, 103, 114, 97, 109>>[j]
    /\ \A j \in 1..16: CallerInputByte[4864 + j - 1] = <<67, 111, 117, 110, 116, 101, 114, 44, 32, 46, 112, 114, 111, 99, 101, 100>>[j]
    /\ \A j \in 1..16: CallerInputByte[4880 + j - 1] = <<117, 114, 101, 83, 116, 97, 99, 107, 58, 32, 114, 101, 116, 117, 114, 110>>[j]
    /\ \A j \in 1..16: CallerInputByte[4896 + j - 1] = <<32, 101, 120, 112, 114, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[4912 + j - 1] = <<115, 101, 32, 46, 118, 97, 108, 117, 101, 44, 32, 46, 105, 110, 116, 101>>[j]
    /\ \A j \in 1..16: CallerInputByte[4928 + j - 1] = <<103, 101, 114, 83, 101, 116, 44, 32, 46, 99, 111, 110, 116, 114, 111, 108>>[j]
    /\ \A j \in 1..16: CallerInputByte[4944 + j - 1] = <<76, 111, 99, 97, 116, 105, 111, 110, 58, 32, 114, 101, 116, 117, 114, 110>>[j]
    /\ \A j \in 1..16: CallerInputByte[4960 + j - 1] = <<32, 101, 120, 112, 114, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[4976 + j - 1] = <<115, 101, 32, 46, 101, 110, 97, 98, 108, 101, 100, 65, 99, 116, 105, 111>>[j]
    /\ \A j \in 1..16: CallerInputByte[4992 + j - 1] = <<110, 40, 108, 101, 116, 32, 110, 97, 109, 101, 44, 32, 108, 101, 116, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[5008 + j - 1] = <<97, 114, 103, 117, 109, 101, 110, 116, 41, 58, 32, 114, 101, 116, 117, 114>>[j]
    /\ \A j \in 1..16: CallerInputByte[5024 + j - 1] = <<110, 32, 46, 101, 110, 97, 98, 108, 101, 100, 65, 99, 116, 105, 111, 110>>[j]
    /\ \A j \in 1..16: CallerInputByte[5040 + j - 1] = <<40, 110, 97, 109, 101, 44, 32, 97, 114, 103, 117, 109, 101, 110, 116, 58>>[j]
    /\ \A j \in 1..16: CallerInputByte[5056 + j - 1] = <<32, 97, 114, 103, 117, 109, 101, 110, 116, 46, 109, 97, 112, 32, 123, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[5072 + j - 1] = <<115, 117, 98, 40, 36, 48, 41, 32, 125, 41, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[5088 + j - 1] = <<32, 32, 32, 99, 97, 115, 101, 32, 46, 97, 100, 100, 40, 108, 101, 116>>[j]
    /\ \A j \in 1..16: CallerInputByte[5104 + j - 1] = <<32, 108, 44, 32, 108, 101, 116, 32, 114, 41, 58, 32, 114, 101, 116, 117>>[j]
    /\ \A j \in 1..16: CallerInputByte[5120 + j - 1] = <<114, 110, 32, 46, 97, 100, 100, 40, 115, 117, 98, 40, 108, 41, 44, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[5136 + j - 1] = <<115, 117, 98, 40, 114, 41, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[12784 + j - 1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 102, 117, 110, 99, 32, 115, 117>>[j]
    /\ \A j \in 1..16: CallerInputByte[12800 + j - 1] = <<98, 40, 95, 32, 101, 120, 112, 114, 101, 115, 115, 105, 111, 110, 58, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[12816 + j - 1] = <<83, 116, 97, 116, 101, 69, 120, 112, 114, 41, 32, 45, 62, 32, 83, 116>>[j]
    /\ \A j \in 1..16: CallerInputByte[12832 + j - 1] = <<97, 116, 101, 69, 120, 112, 114, 32, 123, 10, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[12848 + j - 1] = <<32, 32, 32, 32, 32, 32, 83, 101, 108, 102, 46, 114, 101, 112, 108, 97>>[j]
    /\ \A j \in 1..16: CallerInputByte[12864 + j - 1] = <<99, 101, 40, 105, 110, 58, 32, 101, 120, 112, 114, 101, 115, 115, 105, 111>>[j]
    /\ \A j \in 1..16: CallerInputByte[12880 + j - 1] = <<110, 44, 32, 117, 115, 105, 110, 103, 58, 32, 114, 101, 112, 108, 97, 99>>[j]
    /\ \A j \in 1..16: CallerInputByte[12896 + j - 1] = <<101, 109, 101, 110, 116, 115, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CallerInputByte[12912 + j - 1] = <<125, 10, 32, 32, 32, 32, 125, 10, 10, 32, 32, 32, 32, 115, 116, 97>>[j]

THEOREM ActualStateExprSubstitutionClausesMatchSource ==
    ActualStateExprSubstitutionSourceMatches
    BY ONLY CallerInputPageBlock1AtFileOffsets, CallerInputPageBlock2AtFileOffsets, CallerInputPageBlock4AtFileOffsets, CallerInputPageBlock5AtFileOffsets, CallerInputPageBlock6AtFileOffsets, CallerInputPageBlock13AtFileOffsets, PTL DEF ActualStateExprSubstitutionSourceMatches

ActualStateExprSubstitutionNames ==
    [entryDict |-> <<CallerInputByte[1532], CallerInputByte[1533], CallerInputByte[1534], CallerInputByte[1535], CallerInputByte[1536], CallerInputByte[1537]>>,
     entryExpr |-> <<CallerInputByte[1564], CallerInputByte[1565], CallerInputByte[1566], CallerInputByte[1567]>>,
     entryMap |-> <<CallerInputByte[1608], CallerInputByte[1609], CallerInputByte[1610], CallerInputByte[1611], CallerInputByte[1612], CallerInputByte[1613], CallerInputByte[1614], CallerInputByte[1615], CallerInputByte[1616], CallerInputByte[1617], CallerInputByte[1618], CallerInputByte[1619]>>,
     mappedDict |-> <<CallerInputByte[1656], CallerInputByte[1657], CallerInputByte[1658], CallerInputByte[1659], CallerInputByte[1660], CallerInputByte[1661]>>,
     inputExpr |-> <<CallerInputByte[1746], CallerInputByte[1747], CallerInputByte[1748], CallerInputByte[1749]>>,
     mappedArgument |-> <<CallerInputByte[1772], CallerInputByte[1773], CallerInputByte[1774], CallerInputByte[1775], CallerInputByte[1776], CallerInputByte[1777], CallerInputByte[1778], CallerInputByte[1779], CallerInputByte[1780], CallerInputByte[1781], CallerInputByte[1782], CallerInputByte[1783]>>,
     replaceExpr |-> <<CallerInputByte[3759], CallerInputByte[3760], CallerInputByte[3761], CallerInputByte[3762]>>,
     replaceArgument |-> <<CallerInputByte[3782], CallerInputByte[3783], CallerInputByte[3784], CallerInputByte[3785], CallerInputByte[3786], CallerInputByte[3787], CallerInputByte[3788], CallerInputByte[3789], CallerInputByte[3790], CallerInputByte[3791], CallerInputByte[3792], CallerInputByte[3793]>>,
     emptyArgument |-> <<CallerInputByte[3840], CallerInputByte[3841], CallerInputByte[3842], CallerInputByte[3843], CallerInputByte[3844], CallerInputByte[3845], CallerInputByte[3846], CallerInputByte[3847], CallerInputByte[3848], CallerInputByte[3849], CallerInputByte[3850], CallerInputByte[3851]>>,
     emptyExpr |-> <<CallerInputByte[3882], CallerInputByte[3883], CallerInputByte[3884], CallerInputByte[3885]>>,
     dispatchedExpr |-> <<CallerInputByte[4345], CallerInputByte[4346], CallerInputByte[4347], CallerInputByte[4348]>>,
     readParameter |-> <<CallerInputByte[4596], CallerInputByte[4597], CallerInputByte[4598], CallerInputByte[4599]>>,
     readArgument |-> <<CallerInputByte[4610], CallerInputByte[4611], CallerInputByte[4612], CallerInputByte[4613], CallerInputByte[4614], CallerInputByte[4615], CallerInputByte[4616], CallerInputByte[4617], CallerInputByte[4618], CallerInputByte[4619], CallerInputByte[4620], CallerInputByte[4621]>>,
     readKey |-> <<CallerInputByte[4640], CallerInputByte[4641], CallerInputByte[4642], CallerInputByte[4643]>>,
     readFallback |-> <<CallerInputByte[4650], CallerInputByte[4651], CallerInputByte[4652], CallerInputByte[4653]>>,
     literalExpr |-> <<CallerInputByte[4961], CallerInputByte[4962], CallerInputByte[4963], CallerInputByte[4964]>>,
     leftParameter |-> <<CallerInputByte[5105]>>,
     rightParameter |-> <<CallerInputByte[5112]>>,
     leftChild |-> <<CallerInputByte[5132]>>,
     rightChild |-> <<CallerInputByte[5140]>>,
     subParameter |-> <<CallerInputByte[12804], CallerInputByte[12805], CallerInputByte[12806], CallerInputByte[12807], CallerInputByte[12808], CallerInputByte[12809], CallerInputByte[12810], CallerInputByte[12811], CallerInputByte[12812], CallerInputByte[12813]>>,
     subExpr |-> <<CallerInputByte[12871], CallerInputByte[12872], CallerInputByte[12873], CallerInputByte[12874], CallerInputByte[12875], CallerInputByte[12876], CallerInputByte[12877], CallerInputByte[12878], CallerInputByte[12879], CallerInputByte[12880]>>,
     subArgument |-> <<CallerInputByte[12890], CallerInputByte[12891], CallerInputByte[12892], CallerInputByte[12893], CallerInputByte[12894], CallerInputByte[12895], CallerInputByte[12896], CallerInputByte[12897], CallerInputByte[12898], CallerInputByte[12899], CallerInputByte[12900], CallerInputByte[12901]>>]

StateExprSubstitutionNames ==
    [entryDict |-> <<118, 97, 108, 117, 101, 115>>,
     entryExpr |-> <<101, 120, 112, 114>>,
     entryMap |-> <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>,
     mappedDict |-> <<118, 97, 108, 117, 101, 115>>,
     inputExpr |-> <<101, 120, 112, 114>>,
     mappedArgument |-> <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>,
     replaceExpr |-> <<101, 120, 112, 114>>,
     replaceArgument |-> <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>,
     emptyArgument |-> <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>,
     emptyExpr |-> <<101, 120, 112, 114>>,
     dispatchedExpr |-> <<101, 120, 112, 114>>,
     readParameter |-> <<110, 97, 109, 101>>,
     readArgument |-> <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>,
     readKey |-> <<110, 97, 109, 101>>,
     readFallback |-> <<101, 120, 112, 114>>,
     literalExpr |-> <<101, 120, 112, 114>>,
     leftParameter |-> <<108>>,
     rightParameter |-> <<114>>,
     leftChild |-> <<108>>,
     rightChild |-> <<114>>,
     subParameter |-> <<101, 120, 112, 114, 101, 115, 115, 105, 111, 110>>,
     subExpr |-> <<101, 120, 112, 114, 101, 115, 115, 105, 111, 110>>,
     subArgument |-> <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>]

THEOREM ActualStateExprSubstitutionUsesItsDeclaredNames ==
    ActualStateExprSubstitutionNames = StateExprSubstitutionNames
PROOF
<1>entryDictUse. <<CallerInputByte[1532], CallerInputByte[1533], CallerInputByte[1534], CallerInputByte[1535], CallerInputByte[1536], CallerInputByte[1537]>> = <<118, 97, 108, 117, 101, 115>>
    BY ONLY CallerInputPageBlock2AtFileOffsets, SMT
<1>entryExprUse. <<CallerInputByte[1564], CallerInputByte[1565], CallerInputByte[1566], CallerInputByte[1567]>> = <<101, 120, 112, 114>>
    BY ONLY CallerInputPageBlock2AtFileOffsets, SMT
<1>entryMapUse. <<CallerInputByte[1608], CallerInputByte[1609], CallerInputByte[1610], CallerInputByte[1611], CallerInputByte[1612], CallerInputByte[1613], CallerInputByte[1614], CallerInputByte[1615], CallerInputByte[1616], CallerInputByte[1617], CallerInputByte[1618], CallerInputByte[1619]>> = <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>
    BY ONLY CallerInputPageBlock2AtFileOffsets, SMT
<1>mappedDictUse. <<CallerInputByte[1656], CallerInputByte[1657], CallerInputByte[1658], CallerInputByte[1659], CallerInputByte[1660], CallerInputByte[1661]>> = <<118, 97, 108, 117, 101, 115>>
    BY ONLY CallerInputPageBlock2AtFileOffsets, SMT
<1>inputExprUse. <<CallerInputByte[1746], CallerInputByte[1747], CallerInputByte[1748], CallerInputByte[1749]>> = <<101, 120, 112, 114>>
    BY ONLY CallerInputPageBlock2AtFileOffsets, SMT
<1>mappedArgumentUse. <<CallerInputByte[1772], CallerInputByte[1773], CallerInputByte[1774], CallerInputByte[1775], CallerInputByte[1776], CallerInputByte[1777], CallerInputByte[1778], CallerInputByte[1779], CallerInputByte[1780], CallerInputByte[1781], CallerInputByte[1782], CallerInputByte[1783]>> = <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>
    BY ONLY CallerInputPageBlock2AtFileOffsets, SMT
<1>replaceExprUse. <<CallerInputByte[3759], CallerInputByte[3760], CallerInputByte[3761], CallerInputByte[3762]>> = <<101, 120, 112, 114>>
    BY ONLY CallerInputPageBlock4AtFileOffsets, SMT
<1>replaceArgumentUse. <<CallerInputByte[3782], CallerInputByte[3783], CallerInputByte[3784], CallerInputByte[3785], CallerInputByte[3786], CallerInputByte[3787], CallerInputByte[3788], CallerInputByte[3789], CallerInputByte[3790], CallerInputByte[3791], CallerInputByte[3792], CallerInputByte[3793]>> = <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>
    BY ONLY CallerInputPageBlock4AtFileOffsets, SMT
<1>emptyArgumentUse. <<CallerInputByte[3840], CallerInputByte[3841], CallerInputByte[3842], CallerInputByte[3843], CallerInputByte[3844], CallerInputByte[3845], CallerInputByte[3846], CallerInputByte[3847], CallerInputByte[3848], CallerInputByte[3849], CallerInputByte[3850], CallerInputByte[3851]>> = <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>
    BY ONLY CallerInputPageBlock4AtFileOffsets, SMT
<1>emptyExprUse. <<CallerInputByte[3882], CallerInputByte[3883], CallerInputByte[3884], CallerInputByte[3885]>> = <<101, 120, 112, 114>>
    BY ONLY CallerInputPageBlock4AtFileOffsets, SMT
<1>dispatchedExprUse. <<CallerInputByte[4345], CallerInputByte[4346], CallerInputByte[4347], CallerInputByte[4348]>> = <<101, 120, 112, 114>>
    BY ONLY CallerInputPageBlock5AtFileOffsets, SMT
<1>readParameterUse. <<CallerInputByte[4596], CallerInputByte[4597], CallerInputByte[4598], CallerInputByte[4599]>> = <<110, 97, 109, 101>>
    BY ONLY CallerInputPageBlock5AtFileOffsets, SMT
<1>readArgumentUse. <<CallerInputByte[4610], CallerInputByte[4611], CallerInputByte[4612], CallerInputByte[4613], CallerInputByte[4614], CallerInputByte[4615], CallerInputByte[4616], CallerInputByte[4617], CallerInputByte[4618], CallerInputByte[4619], CallerInputByte[4620], CallerInputByte[4621]>> = <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>
    BY ONLY CallerInputPageBlock5AtFileOffsets, SMT
<1>readKeyUse. <<CallerInputByte[4640], CallerInputByte[4641], CallerInputByte[4642], CallerInputByte[4643]>> = <<110, 97, 109, 101>>
    BY ONLY CallerInputPageBlock5AtFileOffsets, SMT
<1>readFallbackUse. <<CallerInputByte[4650], CallerInputByte[4651], CallerInputByte[4652], CallerInputByte[4653]>> = <<101, 120, 112, 114>>
    BY ONLY CallerInputPageBlock5AtFileOffsets, SMT
<1>literalExprUse. <<CallerInputByte[4961], CallerInputByte[4962], CallerInputByte[4963], CallerInputByte[4964]>> = <<101, 120, 112, 114>>
    BY ONLY CallerInputPageBlock5AtFileOffsets, SMT
<1>leftParameterUse. <<CallerInputByte[5105]>> = <<108>>
    BY ONLY CallerInputPageBlock5AtFileOffsets, SMT
<1>rightParameterUse. <<CallerInputByte[5112]>> = <<114>>
    BY ONLY CallerInputPageBlock5AtFileOffsets, SMT
<1>leftChildUse. <<CallerInputByte[5132]>> = <<108>>
    BY ONLY CallerInputPageBlock6AtFileOffsets, SMT
<1>rightChildUse. <<CallerInputByte[5140]>> = <<114>>
    BY ONLY CallerInputPageBlock6AtFileOffsets, SMT
<1>subParameterUse. <<CallerInputByte[12804], CallerInputByte[12805], CallerInputByte[12806], CallerInputByte[12807], CallerInputByte[12808], CallerInputByte[12809], CallerInputByte[12810], CallerInputByte[12811], CallerInputByte[12812], CallerInputByte[12813]>> = <<101, 120, 112, 114, 101, 115, 115, 105, 111, 110>>
    BY ONLY CallerInputPageBlock13AtFileOffsets, SMT
<1>subExprUse. <<CallerInputByte[12871], CallerInputByte[12872], CallerInputByte[12873], CallerInputByte[12874], CallerInputByte[12875], CallerInputByte[12876], CallerInputByte[12877], CallerInputByte[12878], CallerInputByte[12879], CallerInputByte[12880]>> = <<101, 120, 112, 114, 101, 115, 115, 105, 111, 110>>
    BY ONLY CallerInputPageBlock13AtFileOffsets, SMT
<1>subArgumentUse. <<CallerInputByte[12890], CallerInputByte[12891], CallerInputByte[12892], CallerInputByte[12893], CallerInputByte[12894], CallerInputByte[12895], CallerInputByte[12896], CallerInputByte[12897], CallerInputByte[12898], CallerInputByte[12899], CallerInputByte[12900], CallerInputByte[12901]>> = <<114, 101, 112, 108, 97, 99, 101, 109, 101, 110, 116, 115>>
    BY ONLY CallerInputPageBlock13AtFileOffsets, SMT
<1>. QED BY ONLY <1>entryDictUse, <1>entryExprUse, <1>entryMapUse, <1>mappedDictUse, <1>inputExprUse,
    <1>mappedArgumentUse, <1>replaceExprUse, <1>replaceArgumentUse, <1>emptyArgumentUse, <1>emptyExprUse,
    <1>dispatchedExprUse, <1>readParameterUse, <1>readArgumentUse, <1>readKeyUse, <1>readFallbackUse,
    <1>literalExprUse, <1>leftParameterUse, <1>rightParameterUse, <1>leftChildUse, <1>rightChildUse,
    <1>subParameterUse, <1>subExprUse, <1>subArgumentUse
    DEF ActualStateExprSubstitutionNames, StateExprSubstitutionNames


\* Mapping every old String key to the same .variable constructor is
\* injective. Erase that common tag so lookup still uses the old key.
\* The other Replacements fields do not participate in these three cases.
ActualStateExprSubstitutionInput(incoming, expression) ==
    LET n == ActualStateExprSubstitutionNames
        entry == [name \in {n.entryDict, n.entryExpr} |->
                     IF name = n.entryDict THEN incoming ELSE expression]
        mapped == [name \in {n.entryMap} |-> entry[n.mappedDict]]
    IN [expr |-> entry[n.inputExpr], replacements |-> [values |-> mapped[n.mappedArgument]]]

\* The argument passed by the recursive helper is taken from its enclosing
\* replace call, while the expression argument is the helper's parameter.
ActualStateExprSubstitutionChildren(source, replacements) ==
    LET n == ActualStateExprSubstitutionNames
        children == [name \in {n.leftParameter, n.rightParameter} |->
                         IF name = n.leftParameter THEN source.left ELSE source.right]
        captured == [name \in {n.replaceArgument} |-> replacements]
        call(child) == LET locals == [name \in {n.subParameter} |-> child]
                       IN [expression |-> locals[n.subExpr], replacements |-> captured[n.subArgument]]
    IN <<call(children[n.leftChild]), call(children[n.rightChild])>>

ActualStateExprSubstitutionStep(view, incoming, returned, origin) ==
    LET n == ActualStateExprSubstitutionNames
        entry == ActualStateExprSubstitutionInput(incoming, StateExprSourceOccurrence(view, origin))
        scope == [name \in {n.replaceExpr, n.replaceArgument} |->
                     IF name = n.replaceExpr THEN entry.expr ELSE entry.replacements]
        source == scope[n.dispatchedExpr]
    IN IF DOMAIN scope[n.emptyArgument].values = {} THEN scope[n.emptyExpr]
       ELSE CASE source.kind = "read" ->
                   LET readScope == [name \in {n.readParameter} |-> source.payload]
                       key == readScope[n.readKey]
                       values == scope[n.readArgument].values
                   IN IF key \in DOMAIN values THEN [source EXCEPT !.payload = values[key].variable]
                      ELSE scope[n.readFallback]
              [] source.kind = "add" ->
                   LET children == ActualStateExprSubstitutionChildren(source, scope[n.replaceArgument])
                   IN [source EXCEPT !.left = returned[children[1].expression].origin,
                                      !.right = returned[children[2].expression].origin]
              [] OTHER -> scope[n.literalExpr]

ActualStateExprSubstitutionReturns(view, incoming, returned) ==
    /\ returned = [origin \in DOMAIN view.kinds |-> returned[origin]]
    /\ \A origin \in DOMAIN view.kinds :
           returned[origin] = ActualStateExprSubstitutionStep(view, incoming, returned, origin)

ActualStateExprSubstitutionProjection(view, incoming) ==
    CHOOSE returned : ActualStateExprSubstitutionReturns(view, incoming, returned)

StateExprIncomingVariableNames(incoming) ==
    [name \in DOMAIN incoming |-> incoming[name].variable]

THEOREM ActualStateExprEntryBindsTheOldMap ==
    ASSUME NEW incoming, NEW expression
    PROVE ActualStateExprSubstitutionInput(incoming, expression) =
          [expr |-> expression, replacements |-> [values |-> incoming]]
    BY ONLY ActualStateExprSubstitutionUsesItsDeclaredNames, SMT
        DEF ActualStateExprSubstitutionInput, StateExprSubstitutionNames

THEOREM ActualStateExprAdditionCallsBothChildrenWithItsSameMap ==
    ASSUME NEW source, NEW argument
    PROVE ActualStateExprSubstitutionChildren(source, argument) =
          <<[expression |-> source.left, replacements |-> argument],
            [expression |-> source.right, replacements |-> argument]>>
    BY ONLY ActualStateExprSubstitutionUsesItsDeclaredNames, SMT
        DEF ActualStateExprSubstitutionChildren, StateExprSubstitutionNames

THEOREM ActualStateExprSubstitutionStepUsesTheConstructorRules ==
    ASSUME NEW view, NEW incoming, NEW returned, NEW origin \in DOMAIN view.kinds
    PROVE ActualStateExprSubstitutionStep(view, incoming, returned, origin) =
          StateExprReplaceConstructor(view, StateExprIncomingVariableNames(incoming), returned, origin)
PROOF
<1>. DEFINE source == StateExprSourceOccurrence(view, origin)
            entry == ActualStateExprSubstitutionInput(incoming, source)
            projected == StateExprIncomingVariableNames(incoming)
            args == [values |-> incoming]
            n == ActualStateExprSubstitutionNames
            scope == [name \in {n.replaceExpr, n.replaceArgument} |->
                         IF name = n.replaceExpr THEN entry.expr ELSE entry.replacements]
            readScope == [name \in {n.readParameter} |-> scope[n.dispatchedExpr].payload]
            actual == ActualStateExprSubstitutionStep(view, incoming, returned, origin)
            expected == StateExprReplaceConstructor(view, projected, returned, origin)
<1>input. entry = [expr |-> source, replacements |-> args]
    BY ONLY ActualStateExprEntryBindsTheOldMap, SMT DEF entry, args
<1>exprNames. /\ n.replaceExpr # n.replaceArgument
               /\ n.dispatchedExpr = n.replaceExpr /\ n.emptyExpr = n.replaceExpr
               /\ n.readFallback = n.replaceExpr /\ n.literalExpr = n.replaceExpr
    BY ONLY ActualStateExprSubstitutionUsesItsDeclaredNames, SMT DEF n, StateExprSubstitutionNames
<1>mapNames. /\ n.emptyArgument = n.replaceArgument /\ n.readArgument = n.replaceArgument
              /\ n.readParameter = n.readKey
    BY ONLY ActualStateExprSubstitutionUsesItsDeclaredNames, SMT DEF n, StateExprSubstitutionNames
<1>parameters. /\ scope[n.replaceExpr] = source /\ scope[n.replaceArgument] = args
    BY ONLY <1>input, <1>exprNames, SMT DEF scope
<1>selected. /\ scope[n.dispatchedExpr] = source /\ scope[n.emptyExpr] = source
              /\ scope[n.readFallback] = source /\ scope[n.literalExpr] = source
              /\ scope[n.emptyArgument].values = incoming /\ scope[n.readArgument].values = incoming
              /\ readScope[n.readKey] = source.payload
    BY ONLY <1>parameters, <1>exprNames, <1>mapNames, SMT DEF readScope, args
<1>children. ActualStateExprSubstitutionChildren(source, scope[n.replaceArgument]) =
    <<[expression |-> source.left, replacements |-> args],
      [expression |-> source.right, replacements |-> args]>>
    BY ONLY <1>parameters, ActualStateExprAdditionCallsBothChildrenWithItsSameMap, SMT
<1>shape. actual =
    IF DOMAIN scope[n.emptyArgument].values = {} THEN scope[n.emptyExpr]
    ELSE CASE scope[n.dispatchedExpr].kind = "read" ->
                IF readScope[n.readKey] \in DOMAIN scope[n.readArgument].values
                THEN [scope[n.dispatchedExpr] EXCEPT !.payload =
                       scope[n.readArgument].values[readScope[n.readKey]].variable]
                ELSE scope[n.readFallback]
           [] scope[n.dispatchedExpr].kind = "add" ->
                LET children == ActualStateExprSubstitutionChildren(
                                   scope[n.dispatchedExpr], scope[n.replaceArgument])
                IN [scope[n.dispatchedExpr] EXCEPT !.left = returned[children[1].expression].origin,
                                                !.right = returned[children[2].expression].origin]
           [] OTHER -> scope[n.literalExpr]
    BY ONLY SMT DEF actual, ActualStateExprSubstitutionStep, n, source, scope, entry, readScope
<1>keys. /\ DOMAIN projected = DOMAIN incoming
         /\ \A key \in DOMAIN incoming : projected[key] = incoming[key].variable
    BY ONLY SMT DEF projected, StateExprIncomingVariableNames
<1>readName. StateExprReplaceReadName(projected, source.payload) =
    IF source.payload \in DOMAIN incoming THEN incoming[source.payload].variable ELSE source.payload
    BY ONLY <1>keys, SMT DEF StateExprReplaceReadName
<1>empty. CASE DOMAIN incoming = {}
    BY ONLY <1>empty, <1>shape, <1>selected, <1>keys, SMT DEF expected, StateExprReplaceConstructor, source
<1>read. CASE DOMAIN incoming # {} /\ source.kind = "read"
    <2>miss. CASE source.payload \notin DOMAIN incoming
        <3>same. [source EXCEPT !.payload = source.payload] = source
            BY ONLY IsaM("simp"), SMT DEF source, StateExprSourceOccurrence
        <3>. QED BY ONLY <1>read, <2>miss, <3>same, <1>shape, <1>selected,
            <1>keys, <1>readName, SMT DEF expected, StateExprReplaceConstructor, source
    <2>hit. CASE source.payload \in DOMAIN incoming
        BY ONLY <1>read, <2>hit, <1>shape, <1>selected, <1>keys, <1>readName, SMT
            DEF expected, StateExprReplaceConstructor, source
    <2>. QED BY ONLY <2>hit, <2>miss
<1>add. CASE DOMAIN incoming # {} /\ source.kind = "add"
    BY ONLY <1>add, <1>shape, <1>selected, <1>keys, <1>children, SMT DEF expected, StateExprReplaceConstructor, source
<1>literal. CASE DOMAIN incoming # {} /\ source.kind \notin {"read", "add"}
    BY ONLY <1>literal, <1>shape, <1>selected, <1>keys, SMT DEF expected, StateExprReplaceConstructor, source
<1>. QED BY ONLY <1>empty, <1>read, <1>add, <1>literal, SMT DEF actual, expected

THEOREM ActualStateExprSubstitutionReturnsTheSourceProjection ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count), NEW incoming
    PROVE LET actual == ActualStateExprSubstitutionProjection(view, incoming)
              oldNames == StateExprIncomingVariableNames(incoming)
          IN /\ ActualStateExprSubstitutionSourceMatches
             /\ ActualStateExprSubstitutionReturns(view, incoming, actual)
             /\ actual = StateExprReplaceProjection(view, oldNames)
             /\ \A origin \in DOMAIN view.kinds : view.kinds[origin] = "read" =>
                    actual[origin].payload = StateExprReplaceReadName(oldNames, view.reads[origin])
PROOF
<1>. DEFINE oldNames == StateExprIncomingVariableNames(incoming)
            projected == StateExprReplaceProjection(view, oldNames)
            actual == ActualStateExprSubstitutionProjection(view, incoming)
<1>same. \A returned :
    ActualStateExprSubstitutionReturns(view, incoming, returned) <=>
        StateExprReplaceReturns(view, oldNames, returned)
    BY ONLY ActualStateExprSubstitutionStepUsesTheConstructorRules, SMT
        DEF ActualStateExprSubstitutionReturns, StateExprReplaceReturns, oldNames
<1>exists. ActualStateExprSubstitutionReturns(view, incoming, projected)
    BY ONLY <1>same, CompilerOccurrenceTree(view, count), StateExprReplacementHasAUniqueProjection, SMT DEF projected
<1>actual. ActualStateExprSubstitutionReturns(view, incoming, actual)
    BY ONLY <1>exists, SMT DEF actual, ActualStateExprSubstitutionProjection
<1>shape. /\ actual = projected
          /\ \A origin \in DOMAIN view.kinds : view.kinds[origin] = "read" =>
                actual[origin].payload = StateExprReplaceReadName(oldNames, view.reads[origin])
    BY ONLY <1>same, <1>actual, CompilerOccurrenceTree(view, count), StateExprReplacementHasAUniqueProjection, SMT DEF projected
<1>. QED BY ONLY ActualStateExprSubstitutionClausesMatchSource, <1>actual, <1>shape DEF projected
====
