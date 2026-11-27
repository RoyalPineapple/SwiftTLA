---- MODULE ScheduledLetActionLowering ----
EXTENDS TLAPS, Sequences, CompilerInputPageBlock225, CompilerInputPageBlock226, CompilerInputPageBlock227, CompilerInputPageBlock228, CompilerInputPageBlock229, CompilerInputPageBlock231

\* CompilerInputPage14383
\* CompilerInputPage14384
\* CompilerInputPage14385
\* CompilerInputPage14386
\* CompilerInputPage14387
\* CompilerInputPage14388
\* CompilerInputPage14389
\* CompilerInputPage14390
\* CompilerInputPage14391
\* CompilerInputPage14392
\* CompilerInputPage14393
\* CompilerInputPage14394
\* CompilerInputPage14395
\* CompilerInputPage14396
\* CompilerInputPage14397
\* CompilerInputPage14398
\* CompilerInputPage14399
\* CompilerInputPage14400
\* CompilerInputPage14401
\* CompilerInputPage14402
\* CompilerInputPage14403
\* CompilerInputPage14404
\* CompilerInputPage14405
\* CompilerInputPage14406
\* CompilerInputPage14407
\* CompilerInputPage14408
\* CompilerInputPage14409
\* CompilerInputPage14410
\* CompilerInputPage14411
\* CompilerInputPage14412
\* CompilerInputPage14413
\* CompilerInputPage14414
\* CompilerInputPage14415
\* CompilerInputPage14416
\* CompilerInputPage14417
\* CompilerInputPage14418
\* CompilerInputPage14419
\* CompilerInputPage14442
\* CompilerInputPage14443
\* CompilerInputPage14444
\* CompilerInputPage14445
\* CompilerInputPage14446
\* CompilerInputPage14447
\* CompilerInputPage14448
\* CompilerInputPage14449
\* CompilerInputPage14450
\* CompilerInputPage14451
\* CompilerInputPage14452
\* CompilerInputPage14453
\* CompilerInputPage14454
\* CompilerInputPage14455
\* CompilerInputPage14456
\* CompilerInputPage14457
\* CompilerInputPage14458
\* CompilerInputPage14459
\* CompilerInputPage14460
\* CompilerInputPage14461
\* CompilerInputPage14462
\* CompilerInputPage14474
\* CompilerInputPage14475
\* CompilerInputPage14476
\* CompilerInputPage14477
\* CompilerInputPage14478
\* CompilerInputPage14479
\* CompilerInputPage14480
\* CompilerInputPage14481
\* CompilerInputPage14482
\* CompilerInputPage14483
\* CompilerInputPage14484
\* CompilerInputPage14485
\* CompilerInputPage14486
\* CompilerInputPage14487
\* CompilerInputPage14488
\* CompilerInputPage14489
\* CompilerInputPage14490
\* CompilerInputPage14491
\* CompilerInputPage14492
\* CompilerInputPage14493
\* CompilerInputPage14494
\* CompilerInputPage14495
\* CompilerInputPage14496
\* CompilerInputPage14497
\* CompilerInputPage14498
\* CompilerInputPage14499
\* CompilerInputPage14500
\* CompilerInputPage14501
\* CompilerInputPage14502
\* CompilerInputPage14503
\* CompilerInputPage14504
\* CompilerInputPage14505
\* CompilerInputPage14506
\* CompilerInputPage14507
\* CompilerInputPage14508
\* CompilerInputPage14509
\* CompilerInputPage14510
\* CompilerInputPage14511
\* CompilerInputPage14512
\* CompilerInputPage14513
\* CompilerInputPage14514
\* CompilerInputPage14515
\* CompilerInputPage14587
\* CompilerInputPage14588
\* CompilerInputPage14589
\* CompilerInputPage14590
\* CompilerInputPage14591
\* CompilerInputPage14592
\* CompilerInputPage14593
\* CompilerInputPage14594
\* CompilerInputPage14595
\* CompilerInputPage14596
\* CompilerInputPage14744
\* CompilerInputPage14745
\* CompilerInputPage14746
\* CompilerInputPage14747

SelectedScheduledLetClauses ==
    /\ \A j \in 1..16: CompilerInputByte[230112 + j - 1] = <<116, 101, 115, 46, 10, 32, 32, 32, 32, 112, 114, 105, 118, 97, 116, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230128 + j - 1] = <<32, 115, 116, 97, 116, 105, 99, 32, 102, 117, 110, 99, 32, 108, 111, 119>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230144 + j - 1] = <<101, 114, 40, 10, 32, 32, 32, 32, 32, 32, 32, 32, 95, 32, 115, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230160 + j - 1] = <<97, 116, 101, 109, 101, 110, 116, 115, 58, 32, 91, 65, 108, 103, 111, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230176 + j - 1] = <<105, 116, 104, 109, 83, 116, 97, 116, 101, 109, 101, 110, 116, 77, 111, 100>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230192 + j - 1] = <<101, 108, 93, 44, 10, 32, 32, 32, 32, 32, 32, 32, 32, 112, 114, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230208 + j - 1] = <<99, 101, 115, 115, 76, 111, 99, 97, 108, 82, 111, 111, 116, 115, 58, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230224 + j - 1] = <<83, 101, 116, 60, 83, 116, 114, 105, 110, 103, 62, 63, 44, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230240 + j - 1] = <<32, 32, 32, 32, 32, 32, 112, 114, 111, 99, 101, 100, 117, 114, 101, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230256 + j - 1] = <<58, 32, 91, 65, 108, 103, 111, 114, 105, 116, 104, 109, 80, 114, 111, 99>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230272 + j - 1] = <<101, 100, 117, 114, 101, 77, 111, 100, 101, 108, 93, 44, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230288 + j - 1] = <<32, 32, 32, 32, 32, 111, 119, 110, 101, 114, 58, 32, 65, 108, 103, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230304 + j - 1] = <<114, 105, 116, 104, 109, 80, 114, 111, 99, 101, 100, 117, 114, 101, 77, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230320 + j - 1] = <<100, 101, 108, 63, 44, 10, 32, 32, 32, 32, 32, 32, 32, 32, 110, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230336 + j - 1] = <<120, 116, 76, 97, 98, 101, 108, 58, 32, 83, 116, 97, 116, 101, 69, 120>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230352 + j - 1] = <<112, 114, 63, 44, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99, 111, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230368 + j - 1] = <<116, 114, 111, 108, 58, 32, 67, 111, 110, 116, 114, 111, 108, 70, 108, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230384 + j - 1] = <<119, 63, 44, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99, 111, 109, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230400 + j - 1] = <<108, 101, 116, 105, 111, 110, 58, 32, 65, 99, 116, 105, 111, 110, 69, 120>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230416 + j - 1] = <<112, 114, 63, 32, 61, 32, 110, 105, 108, 10, 32, 32, 32, 32, 41, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230432 + j - 1] = <<45, 62, 32, 40, 97, 99, 116, 105, 111, 110, 58, 32, 65, 99, 116, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230448 + j - 1] = <<111, 110, 69, 120, 112, 114, 44, 32, 97, 115, 115, 101, 114, 116, 105, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230464 + j - 1] = <<110, 115, 58, 32, 91, 83, 116, 97, 116, 101, 69, 120, 112, 114, 93, 41>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230480 + j - 1] = <<32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 116, 121, 112, 101, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230496 + j - 1] = <<108, 105, 97, 115, 32, 82, 101, 115, 117, 108, 116, 32, 61, 32, 40, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230512 + j - 1] = <<99, 116, 105, 111, 110, 58, 32, 65, 99, 116, 105, 111, 110, 69, 120, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230528 + j - 1] = <<114, 44, 32, 97, 115, 115, 101, 114, 116, 105, 111, 110, 115, 58, 32, 91>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230544 + j - 1] = <<83, 116, 97, 116, 101, 69, 120, 112, 114, 93, 41, 10, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230560 + j - 1] = <<32, 32, 32, 32, 102, 117, 110, 99, 32, 115, 99, 111, 112, 101, 100, 40>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230576 + j - 1] = <<95, 32, 118, 97, 108, 117, 101, 58, 32, 83, 116, 97, 116, 101, 69, 120>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230592 + j - 1] = <<112, 114, 41, 32, 45, 62, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230608 + j - 1] = <<32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230624 + j - 1] = <<114, 111, 99, 101, 115, 115, 76, 111, 99, 97, 108, 82, 111, 111, 116, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230640 + j - 1] = <<46, 109, 97, 112, 32, 123, 32, 114, 101, 119, 114, 105, 116, 101, 40, 118>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230656 + j - 1] = <<97, 108, 117, 101, 44, 32, 108, 111, 99, 97, 108, 82, 111, 111, 116, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230672 + j - 1] = <<58, 32, 36, 48, 41, 32, 125, 32, 63, 63, 32, 118, 97, 108, 117, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230688 + j - 1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231056 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 102, 117, 110, 99, 32, 100, 101, 102>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231072 + j - 1] = <<105, 110, 101, 100, 40, 95, 32, 110, 97, 109, 101, 58, 32, 83, 116, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231088 + j - 1] = <<105, 110, 103, 44, 32, 95, 32, 118, 97, 108, 117, 101, 58, 32, 83, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231104 + j - 1] = <<97, 116, 101, 69, 120, 112, 114, 44, 32, 95, 32, 98, 111, 100, 121, 58>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231120 + j - 1] = <<32, 82, 101, 115, 117, 108, 116, 41, 32, 45, 62, 32, 82, 101, 115, 117>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231136 + j - 1] = <<108, 116, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231152 + j - 1] = <<32, 40, 46, 100, 101, 102, 105, 110, 101, 40, 110, 97, 109, 101, 44, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231168 + j - 1] = <<118, 97, 108, 117, 101, 44, 32, 98, 111, 100, 121, 46, 97, 99, 116, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231184 + j - 1] = <<111, 110, 41, 44, 32, 98, 111, 100, 121, 46, 97, 115, 115, 101, 114, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231200 + j - 1] = <<105, 111, 110, 115, 46, 109, 97, 112, 32, 123, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231216 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 46, 108, 101, 116, 73>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231232 + j - 1] = <<110, 40, 91, 76, 111, 99, 97, 108, 79, 112, 101, 114, 97, 116, 111, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231248 + j - 1] = <<40, 110, 97, 109, 101, 44, 32, 98, 111, 100, 121, 58, 32, 118, 97, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231264 + j - 1] = <<117, 101, 41, 93, 44, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231280 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 83, 116, 97, 116, 101, 69>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231296 + j - 1] = <<120, 112, 114, 46, 115, 117, 98, 115, 116, 105, 116, 117, 116, 101, 86, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231312 + j - 1] = <<114, 105, 97, 98, 108, 101, 40, 110, 97, 109, 101, 44, 32, 119, 105, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231328 + j - 1] = <<104, 58, 32, 46, 114, 101, 99, 117, 114, 115, 105, 118, 101, 67, 97, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231344 + j - 1] = <<108, 40, 110, 97, 109, 101, 44, 32, 91, 93, 41, 44, 32, 105, 110, 58>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231360 + j - 1] = <<32, 36, 48, 41, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231376 + j - 1] = <<32, 32, 125, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231568 + j - 1] = <<32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231584 + j - 1] = <<102, 117, 110, 99, 32, 114, 117, 110, 40, 95, 32, 114, 101, 109, 97, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231600 + j - 1] = <<110, 105, 110, 103, 58, 32, 65, 114, 114, 97, 121, 83, 108, 105, 99, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231616 + j - 1] = <<60, 65, 108, 103, 111, 114, 105, 116, 104, 109, 83, 116, 97, 116, 101, 109>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231632 + j - 1] = <<101, 110, 116, 77, 111, 100, 101, 108, 62, 44, 32, 95, 32, 118, 97, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231648 + j - 1] = <<117, 101, 115, 58, 32, 91, 83, 116, 114, 105, 110, 103, 58, 32, 83, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231664 + j - 1] = <<97, 116, 101, 69, 120, 112, 114, 93, 41, 32, 45, 62, 32, 82, 101, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231680 + j - 1] = <<117, 108, 116, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231696 + j - 1] = <<32, 32, 103, 117, 97, 114, 100, 32, 108, 101, 116, 32, 115, 116, 97, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231712 + j - 1] = <<101, 109, 101, 110, 116, 32, 61, 32, 114, 101, 109, 97, 105, 110, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231728 + j - 1] = <<103, 46, 102, 105, 114, 115, 116, 32, 101, 108, 115, 101, 32, 123, 10, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231744 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231760 + j - 1] = <<101, 116, 32, 119, 114, 105, 116, 101, 115, 32, 61, 32, 97, 115, 115, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231776 + j - 1] = <<103, 110, 109, 101, 110, 116, 115, 40, 118, 97, 108, 117, 101, 115, 41, 10>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231792 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231808 + j - 1] = <<47, 47, 32, 65, 100, 100, 32, 116, 104, 101, 32, 100, 101, 102, 97, 117>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231824 + j - 1] = <<108, 116, 32, 116, 114, 97, 110, 115, 102, 101, 114, 32, 97, 116, 32, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231840 + j - 1] = <<104, 101, 32, 111, 114, 100, 105, 110, 97, 114, 121, 32, 101, 120, 105, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231856 + j - 1] = <<44, 32, 112, 114, 101, 115, 101, 114, 118, 105, 110, 103, 32, 114, 101, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231872 + j - 1] = <<99, 104, 101, 100, 32, 103, 117, 97, 114, 100, 115, 32, 97, 110, 100, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231888 + j - 1] = <<98, 105, 110, 100, 105, 110, 103, 115, 46, 10, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231904 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 116, 117, 114, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231920 + j - 1] = <<32, 40, 99, 111, 109, 112, 108, 101, 116, 105, 111, 110, 46, 109, 97, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231936 + j - 1] = <<32, 123, 32, 46, 97, 110, 100, 40, 119, 114, 105, 116, 101, 115, 44, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231952 + j - 1] = <<36, 48, 41, 32, 125, 32, 63, 63, 32, 119, 114, 105, 116, 101, 115, 44>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231968 + j - 1] = <<32, 91, 93, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231984 + j - 1] = <<32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232000 + j - 1] = <<101, 116, 32, 114, 101, 115, 116, 32, 61, 32, 114, 101, 109, 97, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232016 + j - 1] = <<105, 110, 103, 46, 100, 114, 111, 112, 70, 105, 114, 115, 116, 40, 41, 10>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232032 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 102, 117, 110, 99>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232048 + j - 1] = <<32, 99, 111, 110, 116, 105, 110, 117, 101, 87, 105, 116, 104, 40, 95, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232064 + j - 1] = <<98, 111, 100, 121, 58, 32, 91, 65, 108, 103, 111, 114, 105, 116, 104, 109>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232080 + j - 1] = <<83, 116, 97, 116, 101, 109, 101, 110, 116, 77, 111, 100, 101, 108, 93, 44>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232096 + j - 1] = <<32, 95, 32, 118, 97, 108, 117, 101, 115, 58, 32, 91, 83, 116, 114, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232112 + j - 1] = <<110, 103, 58, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114, 93, 41, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232128 + j - 1] = <<45, 62, 32, 82, 101, 115, 117, 108, 116, 32, 123, 10, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232144 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 117, 110, 40>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232160 + j - 1] = <<40, 98, 111, 100, 121, 32, 43, 32, 114, 101, 115, 116, 41, 91, 46, 46>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232176 + j - 1] = <<46, 93, 44, 32, 118, 97, 108, 117, 101, 115, 41, 10, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232192 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232208 + j - 1] = <<32, 32, 32, 32, 32, 32, 115, 119, 105, 116, 99, 104, 32, 115, 116, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232224 + j - 1] = <<116, 101, 109, 101, 110, 116, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233376 + j - 1] = <<41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233392 + j - 1] = <<115, 101, 32, 46, 108, 101, 116, 66, 105, 110, 100, 105, 110, 103, 40, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233408 + j - 1] = <<101, 116, 32, 118, 97, 114, 105, 97, 98, 108, 101, 44, 32, 108, 101, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233424 + j - 1] = <<32, 118, 97, 108, 117, 101, 44, 32, 108, 101, 116, 32, 98, 111, 100, 121>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233440 + j - 1] = <<41, 58, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233456 + j - 1] = <<32, 32, 32, 114, 101, 116, 117, 114, 110, 32, 100, 101, 102, 105, 110, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233472 + j - 1] = <<100, 40, 118, 97, 114, 105, 97, 98, 108, 101, 44, 32, 115, 99, 111, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233488 + j - 1] = <<101, 100, 40, 118, 97, 108, 117, 101, 41, 44, 32, 99, 111, 110, 116, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233504 + j - 1] = <<110, 117, 101, 87, 105, 116, 104, 40, 98, 111, 100, 121, 44, 32, 118, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233520 + j - 1] = <<108, 117, 101, 115, 41, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[235888 + j - 1] = <<32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 125>>[j]
    /\ \A j \in 1..16: CompilerInputByte[235904 + j - 1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 116, 117, 114, 110, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[235920 + j - 1] = <<114, 117, 110, 40, 115, 116, 97, 116, 101, 109, 101, 110, 116, 115, 91, 46>>[j]
    /\ \A j \in 1..16: CompilerInputByte[235936 + j - 1] = <<46, 46, 93, 44, 32, 91, 58, 93, 41, 10, 32, 32, 32, 32, 125, 10>>[j]

THEOREM ScheduledLetOperationsOccurInProduction == SelectedScheduledLetClauses
    BY ONLY CompilerInputPageBlock225AtFileOffsets, CompilerInputPageBlock226AtFileOffsets, CompilerInputPageBlock227AtFileOffsets, CompilerInputPageBlock228AtFileOffsets, CompilerInputPageBlock229AtFileOffsets, CompilerInputPageBlock231AtFileOffsets, PTL DEF SelectedScheduledLetClauses

ScheduledLetOperands ==
    [patternName |-> <<CompilerInputByte[233411], CompilerInputByte[233412], CompilerInputByte[233413], CompilerInputByte[233414], CompilerInputByte[233415], CompilerInputByte[233416], CompilerInputByte[233417], CompilerInputByte[233418]>>,
     patternValue |-> <<CompilerInputByte[233425], CompilerInputByte[233426], CompilerInputByte[233427], CompilerInputByte[233428], CompilerInputByte[233429]>>,
     patternBody |-> <<CompilerInputByte[233436], CompilerInputByte[233437], CompilerInputByte[233438], CompilerInputByte[233439]>>,
     passName |-> <<CompilerInputByte[233474], CompilerInputByte[233475], CompilerInputByte[233476], CompilerInputByte[233477], CompilerInputByte[233478], CompilerInputByte[233479], CompilerInputByte[233480], CompilerInputByte[233481]>>,
     passValue |-> <<CompilerInputByte[233491], CompilerInputByte[233492], CompilerInputByte[233493], CompilerInputByte[233494], CompilerInputByte[233495]>>,
     passBody |-> <<CompilerInputByte[233512], CompilerInputByte[233513], CompilerInputByte[233514], CompilerInputByte[233515]>>,
     passValues |-> <<CompilerInputByte[233518], CompilerInputByte[233519], CompilerInputByte[233520], CompilerInputByte[233521], CompilerInputByte[233522], CompilerInputByte[233523]>>,
     valuesLocal |-> <<CompilerInputByte[231645], CompilerInputByte[231646], CompilerInputByte[231647], CompilerInputByte[231648], CompilerInputByte[231649], CompilerInputByte[231650]>>,
     innerBody |-> <<CompilerInputByte[232064], CompilerInputByte[232065], CompilerInputByte[232066], CompilerInputByte[232067]>>,
     innerValues |-> <<CompilerInputByte[232099], CompilerInputByte[232100], CompilerInputByte[232101], CompilerInputByte[232102], CompilerInputByte[232103], CompilerInputByte[232104]>>,
     restLocal |-> <<CompilerInputByte[232003], CompilerInputByte[232004], CompilerInputByte[232005], CompilerInputByte[232006]>>,
     recurBody |-> <<CompilerInputByte[232161], CompilerInputByte[232162], CompilerInputByte[232163], CompilerInputByte[232164]>>,
     recurRest |-> <<CompilerInputByte[232168], CompilerInputByte[232169], CompilerInputByte[232170], CompilerInputByte[232171]>>,
     recurValues |-> <<CompilerInputByte[232180], CompilerInputByte[232181], CompilerInputByte[232182], CompilerInputByte[232183], CompilerInputByte[232184], CompilerInputByte[232185]>>,
     defName |-> <<CompilerInputByte[231079], CompilerInputByte[231080], CompilerInputByte[231081], CompilerInputByte[231082]>>,
     defValue |-> <<CompilerInputByte[231095], CompilerInputByte[231096], CompilerInputByte[231097], CompilerInputByte[231098], CompilerInputByte[231099]>>,
     defBody |-> <<CompilerInputByte[231115], CompilerInputByte[231116], CompilerInputByte[231117], CompilerInputByte[231118]>>,
     constructor |-> <<CompilerInputByte[231155], CompilerInputByte[231156], CompilerInputByte[231157], CompilerInputByte[231158], CompilerInputByte[231159], CompilerInputByte[231160]>>,
     emitName |-> <<CompilerInputByte[231162], CompilerInputByte[231163], CompilerInputByte[231164], CompilerInputByte[231165]>>,
     emitValue |-> <<CompilerInputByte[231168], CompilerInputByte[231169], CompilerInputByte[231170], CompilerInputByte[231171], CompilerInputByte[231172]>>,
     emitBody |-> <<CompilerInputByte[231175], CompilerInputByte[231176], CompilerInputByte[231177], CompilerInputByte[231178]>>,
     childField |-> <<CompilerInputByte[231180], CompilerInputByte[231181], CompilerInputByte[231182], CompilerInputByte[231183], CompilerInputByte[231184], CompilerInputByte[231185]>>]

ExpectedLetOperands ==
    [patternName |-> <<118, 97, 114, 105, 97, 98, 108, 101>>,
     patternValue |-> <<118, 97, 108, 117, 101>>,
     patternBody |-> <<98, 111, 100, 121>>,
     passName |-> <<118, 97, 114, 105, 97, 98, 108, 101>>,
     passValue |-> <<118, 97, 108, 117, 101>>,
     passBody |-> <<98, 111, 100, 121>>,
     passValues |-> <<118, 97, 108, 117, 101, 115>>,
     valuesLocal |-> <<118, 97, 108, 117, 101, 115>>,
     innerBody |-> <<98, 111, 100, 121>>,
     innerValues |-> <<118, 97, 108, 117, 101, 115>>,
     restLocal |-> <<114, 101, 115, 116>>,
     recurBody |-> <<98, 111, 100, 121>>,
     recurRest |-> <<114, 101, 115, 116>>,
     recurValues |-> <<118, 97, 108, 117, 101, 115>>,
     defName |-> <<110, 97, 109, 101>>,
     defValue |-> <<118, 97, 108, 117, 101>>,
     defBody |-> <<98, 111, 100, 121>>,
     constructor |-> <<100, 101, 102, 105, 110, 101>>,
     emitName |-> <<110, 97, 109, 101>>,
     emitValue |-> <<118, 97, 108, 117, 101>>,
     emitBody |-> <<98, 111, 100, 121>>,
     childField |-> <<97, 99, 116, 105, 111, 110>>]

THEOREM ActualLetOperandsBindTheProductionLocals == ScheduledLetOperands = ExpectedLetOperands
PROOF
<1>patternNameBytes. <<CompilerInputByte[233411], CompilerInputByte[233412], CompilerInputByte[233413], CompilerInputByte[233414], CompilerInputByte[233415], CompilerInputByte[233416], CompilerInputByte[233417], CompilerInputByte[233418]>> = <<118, 97, 114, 105, 97, 98, 108, 101>>
    BY ONLY CompilerInputPageBlock228AtFileOffsets, SMT
<1>patternValueBytes. <<CompilerInputByte[233425], CompilerInputByte[233426], CompilerInputByte[233427], CompilerInputByte[233428], CompilerInputByte[233429]>> = <<118, 97, 108, 117, 101>>
    BY ONLY CompilerInputPageBlock228AtFileOffsets, SMT
<1>patternBodyBytes. <<CompilerInputByte[233436], CompilerInputByte[233437], CompilerInputByte[233438], CompilerInputByte[233439]>> = <<98, 111, 100, 121>>
    BY ONLY CompilerInputPageBlock228AtFileOffsets, SMT
<1>passNameBytes. <<CompilerInputByte[233474], CompilerInputByte[233475], CompilerInputByte[233476], CompilerInputByte[233477], CompilerInputByte[233478], CompilerInputByte[233479], CompilerInputByte[233480], CompilerInputByte[233481]>> = <<118, 97, 114, 105, 97, 98, 108, 101>>
    BY ONLY CompilerInputPageBlock229AtFileOffsets, SMT
<1>passValueBytes. <<CompilerInputByte[233491], CompilerInputByte[233492], CompilerInputByte[233493], CompilerInputByte[233494], CompilerInputByte[233495]>> = <<118, 97, 108, 117, 101>>
    BY ONLY CompilerInputPageBlock229AtFileOffsets, SMT
<1>passBodyBytes. <<CompilerInputByte[233512], CompilerInputByte[233513], CompilerInputByte[233514], CompilerInputByte[233515]>> = <<98, 111, 100, 121>>
    BY ONLY CompilerInputPageBlock229AtFileOffsets, SMT
<1>passValuesBytes. <<CompilerInputByte[233518], CompilerInputByte[233519], CompilerInputByte[233520], CompilerInputByte[233521], CompilerInputByte[233522], CompilerInputByte[233523]>> = <<118, 97, 108, 117, 101, 115>>
    BY ONLY CompilerInputPageBlock229AtFileOffsets, SMT
<1>valuesLocalBytes. <<CompilerInputByte[231645], CompilerInputByte[231646], CompilerInputByte[231647], CompilerInputByte[231648], CompilerInputByte[231649], CompilerInputByte[231650]>> = <<118, 97, 108, 117, 101, 115>>
    BY ONLY CompilerInputPageBlock227AtFileOffsets, SMT
<1>innerBodyBytes. <<CompilerInputByte[232064], CompilerInputByte[232065], CompilerInputByte[232066], CompilerInputByte[232067]>> = <<98, 111, 100, 121>>
    BY ONLY CompilerInputPageBlock227AtFileOffsets, SMT
<1>innerValuesBytes. <<CompilerInputByte[232099], CompilerInputByte[232100], CompilerInputByte[232101], CompilerInputByte[232102], CompilerInputByte[232103], CompilerInputByte[232104]>> = <<118, 97, 108, 117, 101, 115>>
    BY ONLY CompilerInputPageBlock227AtFileOffsets, SMT
<1>restLocalBytes. <<CompilerInputByte[232003], CompilerInputByte[232004], CompilerInputByte[232005], CompilerInputByte[232006]>> = <<114, 101, 115, 116>>
    BY ONLY CompilerInputPageBlock227AtFileOffsets, SMT
<1>recurBodyBytes. <<CompilerInputByte[232161], CompilerInputByte[232162], CompilerInputByte[232163], CompilerInputByte[232164]>> = <<98, 111, 100, 121>>
    BY ONLY CompilerInputPageBlock227AtFileOffsets, SMT
<1>recurRestBytes. <<CompilerInputByte[232168], CompilerInputByte[232169], CompilerInputByte[232170], CompilerInputByte[232171]>> = <<114, 101, 115, 116>>
    BY ONLY CompilerInputPageBlock227AtFileOffsets, SMT
<1>recurValuesBytes. <<CompilerInputByte[232180], CompilerInputByte[232181], CompilerInputByte[232182], CompilerInputByte[232183], CompilerInputByte[232184], CompilerInputByte[232185]>> = <<118, 97, 108, 117, 101, 115>>
    BY ONLY CompilerInputPageBlock227AtFileOffsets, SMT
<1>defNameBytes. <<CompilerInputByte[231079], CompilerInputByte[231080], CompilerInputByte[231081], CompilerInputByte[231082]>> = <<110, 97, 109, 101>>
    BY ONLY CompilerInputPageBlock226AtFileOffsets, SMT
<1>defValueBytes. <<CompilerInputByte[231095], CompilerInputByte[231096], CompilerInputByte[231097], CompilerInputByte[231098], CompilerInputByte[231099]>> = <<118, 97, 108, 117, 101>>
    BY ONLY CompilerInputPageBlock226AtFileOffsets, SMT
<1>defBodyBytes. <<CompilerInputByte[231115], CompilerInputByte[231116], CompilerInputByte[231117], CompilerInputByte[231118]>> = <<98, 111, 100, 121>>
    BY ONLY CompilerInputPageBlock226AtFileOffsets, SMT
<1>constructorBytes. <<CompilerInputByte[231155], CompilerInputByte[231156], CompilerInputByte[231157], CompilerInputByte[231158], CompilerInputByte[231159], CompilerInputByte[231160]>> = <<100, 101, 102, 105, 110, 101>>
    BY ONLY CompilerInputPageBlock226AtFileOffsets, SMT
<1>emitNameBytes. <<CompilerInputByte[231162], CompilerInputByte[231163], CompilerInputByte[231164], CompilerInputByte[231165]>> = <<110, 97, 109, 101>>
    BY ONLY CompilerInputPageBlock226AtFileOffsets, SMT
<1>emitValueBytes. <<CompilerInputByte[231168], CompilerInputByte[231169], CompilerInputByte[231170], CompilerInputByte[231171], CompilerInputByte[231172]>> = <<118, 97, 108, 117, 101>>
    BY ONLY CompilerInputPageBlock226AtFileOffsets, SMT
<1>emitBodyBytes. <<CompilerInputByte[231175], CompilerInputByte[231176], CompilerInputByte[231177], CompilerInputByte[231178]>> = <<98, 111, 100, 121>>
    BY ONLY CompilerInputPageBlock226AtFileOffsets, SMT
<1>childFieldBytes. <<CompilerInputByte[231180], CompilerInputByte[231181], CompilerInputByte[231182], CompilerInputByte[231183], CompilerInputByte[231184], CompilerInputByte[231185]>> = <<97, 99, 116, 105, 111, 110>>
    BY ONLY CompilerInputPageBlock226AtFileOffsets, SMT
<1>. QED BY ONLY <1>patternNameBytes, <1>patternValueBytes, <1>patternBodyBytes, <1>passNameBytes, <1>passValueBytes, <1>passBodyBytes, <1>passValuesBytes, <1>valuesLocalBytes, <1>innerBodyBytes, <1>innerValuesBytes, <1>restLocalBytes, <1>recurBodyBytes, <1>recurRestBytes, <1>recurValuesBytes, <1>defNameBytes, <1>defValueBytes, <1>defBodyBytes, <1>constructorBytes, <1>emitNameBytes, <1>emitValueBytes, <1>emitBodyBytes, <1>childFieldBytes DEF ScheduledLetOperands, ExpectedLetOperands

\* Projection of the action component of the selected Swift clause. Continue
\* returns the actual recursive call's Result. No assumption on its action.
\* roots = <<>> represents Swift nil; <<{}>> represents a present empty set.
ScopedLetValue(roots, rhs, Rewrite(_, _)) ==
    IF roots = <<>> THEN rhs ELSE Rewrite(rhs, roots[1])
LocalArguments(keys, values) ==
    [key \in {keys[i] : i \in DOMAIN keys} |-> values[CHOOSE i \in DOMAIN keys : keys[i] = key]]

ExecuteScheduledLet(n, statements, pending, roots, Rewrite(_, _), Continue(_, _)) ==
    LET head == Head(statements)
        locals == LocalArguments(<<n.patternName,n.patternValue,n.patternBody,n.valuesLocal>>,
                                 <<head.variable,head.value,head.body,pending>>)
        continuation == LocalArguments(<<n.innerBody,n.restLocal,n.innerValues>>,
                                       <<locals[n.passBody],Tail(statements),locals[n.passValues]>>)
        child == Continue(continuation[n.recurBody] \o continuation[n.recurRest],continuation[n.recurValues])
        define == LocalArguments(<<n.defName,n.defValue,n.defBody>>,
                        <<locals[n.passName],ScopedLetValue(roots,locals[n.passValue],Rewrite),child>>)
    IN IF n.constructor = <<100,101,102,105,110,101>> /\ n.childField = <<97,99,116,105,111,110>>
       THEN [kind |-> "define", name |-> define[n.emitName], value |-> define[n.emitValue],
             body |-> define[n.emitBody].action]
       ELSE "unrecognized action constructor"

ScheduledLetAction(statements, pending, roots, Rewrite(_, _), Continue(_, _)) ==
    IF SelectedScheduledLetClauses /\ Head(statements).kind = "letBinding"
    THEN ExecuteScheduledLet(ScheduledLetOperands,statements,pending,roots,Rewrite,Continue)
    ELSE "not a scheduled LET"

THEOREM DistinctCallParametersSelectTheirPassedArguments ==
    ASSUME NEW keys, NEW args, DOMAIN keys = DOMAIN args,
           \A i,j \in DOMAIN keys : keys[i]=keys[j] => i=j, NEW p \in DOMAIN keys
    PROVE LocalArguments(keys,args)[keys[p]] = args[p]
PROOF
<1>known. (CHOOSE i \in DOMAIN keys : keys[i]=keys[p]) = p
    BY ONLY (p \in DOMAIN keys), (\A i,j \in DOMAIN keys : keys[i]=keys[j] => i=j), SMT
<1>image. keys[p] \in {keys[i] : i \in DOMAIN keys}
    BY ONLY (p \in DOMAIN keys), SMT
<1>lookup. LocalArguments(keys,args)[keys[p]] = args[CHOOSE i \in DOMAIN keys : keys[i]=keys[p]]
    BY ONLY <1>image, IsaM("simp"), SMT DEF LocalArguments
<1>. QED BY ONLY <1>known, <1>lookup, SMT

THEOREM OneReturnedScheduledLetIsTheActualDefineAroundItsContinuation ==
    ASSUME NEW head, head.kind="letBinding", NEW statements, head.body \in Seq(statements), NEW pending, NEW roots, NEW Rewrite(_,_), NEW Continue(_,_)
    PROVE ScheduledLetAction(<<head>>,pending,roots,Rewrite,Continue) =
          [kind |-> "define", name |-> head.variable, value |-> ScopedLetValue(roots,head.value,Rewrite),
           body |-> Continue(head.body,pending).action]
PROOF
<1>. DEFINE n == ExpectedLetOperands
            locals == LocalArguments(<<n.patternName,n.patternValue,n.patternBody,n.valuesLocal>>,
                                     <<head.variable,head.value,head.body,pending>>)
            cont == LocalArguments(<<n.innerBody,n.restLocal,n.innerValues>>,<<head.body,<<>>,pending>>)
            rhs == ScopedLetValue(roots,head.value,Rewrite)
            child == Continue(head.body,pending)
            defn == LocalArguments(<<n.defName,n.defValue,n.defBody>>,<<head.variable,rhs,child>>)
<1>head. Head(<<head>>)=head /\ Tail(<<head>>) = <<>>
    BY ONLY IsaM("simp"), SMT DEF Head, Tail
<1>args. /\ locals[n.passName]=head.variable /\ locals[n.passValue]=head.value
         /\ locals[n.passBody]=head.body /\ locals[n.passValues]=pending
    BY ONLY DistinctCallParametersSelectTheirPassedArguments, IsaM("simp"), SMT DEF locals, n, ExpectedLetOperands
<1>cont. /\ cont[n.recurBody]=head.body /\ cont[n.recurRest] = <<>> /\ cont[n.recurValues]=pending
    BY ONLY DistinctCallParametersSelectTheirPassedArguments, IsaM("simp"), SMT DEF cont, n, ExpectedLetOperands
<1>tail. head.body \o <<>> = head.body
    BY ONLY (head.body \in Seq(statements)), IsaM("simp"), SMT
<1>define. /\ defn[n.emitName]=head.variable /\ defn[n.emitValue]=rhs /\ defn[n.emitBody]=child
           /\ n.constructor = <<100,101,102,105,110,101>> /\ n.childField = <<97,99,116,105,111,110>>
    BY ONLY DistinctCallParametersSelectTheirPassedArguments, IsaM("simp"), SMT DEF defn, n, ExpectedLetOperands
<1>run. ExecuteScheduledLet(n,<<head>>,pending,roots,Rewrite,Continue) =
        [kind |-> "define",name |-> head.variable,value |-> rhs,body |-> child.action]
    BY ONLY <1>head, <1>args, <1>cont, <1>tail, <1>define, SMT
        DEF ExecuteScheduledLet, locals, cont, defn, rhs, child
<1>. QED BY ONLY (head.kind="letBinding"), <1>head, <1>run, ActualLetOperandsBindTheProductionLocals,
        ScheduledLetOperationsOccurInProduction DEF ScheduledLetAction, rhs, child, n
====
