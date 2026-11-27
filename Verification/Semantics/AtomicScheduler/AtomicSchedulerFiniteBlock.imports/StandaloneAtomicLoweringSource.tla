---- MODULE StandaloneAtomicLoweringSource ----
EXTENDS TLAPS, Sequences, NaturalsInduction, CompilerInputPageBlock30, CompilerInputPageBlock37, CompilerInputPageBlock39, CompilerInputPageBlock182, CompilerInputPageBlock183, CompilerInputPageBlock225, CompilerInputPageBlock226, CompilerInputPageBlock227, CompilerInputPageBlock228, CompilerInputPageBlock231

\* CompilerInputPage1860
\* CompilerInputPage1861
\* CompilerInputPage1862
\* CompilerInputPage1863
\* CompilerInputPage1864
\* CompilerInputPage1865
\* CompilerInputPage1866
\* CompilerInputPage1867
\* CompilerInputPage1868
\* CompilerInputPage1869
\* CompilerInputPage1870
\* CompilerInputPage1871
\* CompilerInputPage1872
\* CompilerInputPage1873
\* CompilerInputPage1874
\* CompilerInputPage1875
\* CompilerInputPage1876
\* CompilerInputPage1877
\* CompilerInputPage1878
\* CompilerInputPage1879
\* CompilerInputPage1880
\* CompilerInputPage1881
\* CompilerInputPage1882
\* CompilerInputPage1883
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
\* CompilerInputPage2466
\* CompilerInputPage2467
\* CompilerInputPage2468
\* CompilerInputPage11637
\* CompilerInputPage11638
\* CompilerInputPage11639
\* CompilerInputPage11640
\* CompilerInputPage11641
\* CompilerInputPage11642
\* CompilerInputPage11643
\* CompilerInputPage11644
\* CompilerInputPage11645
\* CompilerInputPage11646
\* CompilerInputPage11647
\* CompilerInputPage11648
\* CompilerInputPage11649
\* CompilerInputPage11650
\* CompilerInputPage11651
\* CompilerInputPage11652
\* CompilerInputPage11653
\* CompilerInputPage11654
\* CompilerInputPage11655
\* CompilerInputPage11656
\* CompilerInputPage11657
\* CompilerInputPage11658
\* CompilerInputPage11659
\* CompilerInputPage11660
\* CompilerInputPage11661
\* CompilerInputPage11662
\* CompilerInputPage11663
\* CompilerInputPage11664
\* CompilerInputPage11665
\* CompilerInputPage11666
\* CompilerInputPage11667
\* CompilerInputPage11668
\* CompilerInputPage11669
\* CompilerInputPage11670
\* CompilerInputPage11671
\* CompilerInputPage11672
\* CompilerInputPage11673
\* CompilerInputPage11674
\* CompilerInputPage11675
\* CompilerInputPage11676
\* CompilerInputPage11677
\* CompilerInputPage11678
\* CompilerInputPage11679
\* CompilerInputPage11680
\* CompilerInputPage11681
\* CompilerInputPage11682
\* CompilerInputPage11683
\* CompilerInputPage11684
\* CompilerInputPage11685
\* CompilerInputPage11686
\* CompilerInputPage11687
\* CompilerInputPage11688
\* CompilerInputPage11689
\* CompilerInputPage11690
\* CompilerInputPage11691
\* CompilerInputPage11692
\* CompilerInputPage11693
\* CompilerInputPage11694
\* CompilerInputPage11695
\* CompilerInputPage11696
\* CompilerInputPage11697
\* CompilerInputPage11698
\* CompilerInputPage11699
\* CompilerInputPage11700
\* CompilerInputPage11701
\* CompilerInputPage11702
\* CompilerInputPage11703
\* CompilerInputPage11704
\* CompilerInputPage11705
\* CompilerInputPage14377
\* CompilerInputPage14378
\* CompilerInputPage14379
\* CompilerInputPage14380
\* CompilerInputPage14381
\* CompilerInputPage14382
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
\* CompilerInputPage14420
\* CompilerInputPage14421
\* CompilerInputPage14422
\* CompilerInputPage14423
\* CompilerInputPage14424
\* CompilerInputPage14425
\* CompilerInputPage14426
\* CompilerInputPage14427
\* CompilerInputPage14428
\* CompilerInputPage14429
\* CompilerInputPage14430
\* CompilerInputPage14431
\* CompilerInputPage14432
\* CompilerInputPage14433
\* CompilerInputPage14434
\* CompilerInputPage14435
\* CompilerInputPage14436
\* CompilerInputPage14437
\* CompilerInputPage14438
\* CompilerInputPage14439
\* CompilerInputPage14440
\* CompilerInputPage14441
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
\* CompilerInputPage14523
\* CompilerInputPage14524
\* CompilerInputPage14525
\* CompilerInputPage14526
\* CompilerInputPage14527
\* CompilerInputPage14528
\* CompilerInputPage14529
\* CompilerInputPage14530
\* CompilerInputPage14531
\* CompilerInputPage14532
\* CompilerInputPage14533
\* CompilerInputPage14534
\* CompilerInputPage14535
\* CompilerInputPage14536
\* CompilerInputPage14537
\* CompilerInputPage14538
\* CompilerInputPage14539
\* CompilerInputPage14540
\* CompilerInputPage14541
\* CompilerInputPage14542
\* CompilerInputPage14543
\* CompilerInputPage14544
\* CompilerInputPage14545
\* CompilerInputPage14546
\* CompilerInputPage14547
\* CompilerInputPage14548
\* CompilerInputPage14549
\* CompilerInputPage14550
\* CompilerInputPage14551
\* CompilerInputPage14552
\* CompilerInputPage14553
\* CompilerInputPage14554
\* CompilerInputPage14555
\* CompilerInputPage14556
\* CompilerInputPage14557
\* CompilerInputPage14558
\* CompilerInputPage14559
\* CompilerInputPage14560
\* CompilerInputPage14561
\* CompilerInputPage14562
\* CompilerInputPage14563
\* CompilerInputPage14564
\* CompilerInputPage14565
\* CompilerInputPage14566
\* CompilerInputPage14567
\* CompilerInputPage14568
\* CompilerInputPage14569
\* CompilerInputPage14570
\* CompilerInputPage14745
\* CompilerInputPage14746
\* CompilerInputPage14747

StandaloneAtomicLowererCallBytes ==
    /\ \A j \in 1..16: CompilerInputByte[186176 + j - 1] = <<46, 112, 114, 111, 99, 101, 115, 115, 10, 10, 32, 32, 32, 32, 115, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186192 + j - 1] = <<97, 116, 105, 99, 32, 102, 117, 110, 99, 32, 108, 111, 119, 101, 114, 65>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186208 + j - 1] = <<116, 111, 109, 105, 99, 83, 116, 101, 112, 40, 95, 32, 115, 116, 101, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186224 + j - 1] = <<58, 32, 65, 116, 111, 109, 105, 99, 83, 116, 101, 112, 44, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186240 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186256 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186272 + j - 1] = <<99, 111, 114, 100, 83, 99, 104, 101, 100, 117, 108, 101, 100, 65, 115, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186288 + j - 1] = <<105, 103, 110, 109, 101, 110, 116, 58, 32, 40, 40, 83, 116, 114, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186304 + j - 1] = <<103, 44, 32, 83, 99, 104, 101, 100, 117, 108, 101, 100, 65, 116, 111, 109>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186320 + j - 1] = <<105, 99, 65, 115, 115, 105, 103, 110, 109, 101, 110, 116, 41, 32, 45, 62>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186336 + j - 1] = <<32, 86, 111, 105, 100, 41, 63, 32, 61, 32, 110, 105, 108, 41, 32, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186352 + j - 1] = <<104, 114, 111, 119, 115, 10, 32, 32, 32, 32, 32, 32, 32, 32, 45, 62>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186368 + j - 1] = <<32, 40, 97, 99, 116, 105, 111, 110, 58, 32, 65, 99, 116, 105, 111, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186384 + j - 1] = <<69, 120, 112, 114, 44, 32, 97, 115, 115, 101, 114, 116, 105, 111, 110, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186400 + j - 1] = <<58, 32, 91, 83, 116, 97, 116, 101, 69, 120, 112, 114, 93, 44, 32, 100>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186416 + j - 1] = <<105, 115, 112, 108, 97, 99, 101, 100, 65, 115, 115, 105, 103, 110, 109, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186432 + j - 1] = <<110, 116, 84, 97, 114, 103, 101, 116, 115, 58, 32, 91, 83, 116, 114, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186448 + j - 1] = <<110, 103, 58, 32, 83, 116, 114, 105, 110, 103, 93, 41, 32, 123, 10, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186464 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 116, 114, 121, 32, 115, 116, 101, 112, 46>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186480 + j - 1] = <<114, 101, 113, 117, 105, 114, 101, 73, 110, 100, 101, 112, 101, 110, 100, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186496 + j - 1] = <<110, 116, 83, 116, 101, 112, 40, 41, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186512 + j - 1] = <<32, 118, 97, 114, 32, 117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186528 + j - 1] = <<115, 32, 61, 32, 115, 116, 101, 112, 46, 109, 111, 100, 101, 108, 46, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186544 + j - 1] = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 46, 97, 108, 103, 111, 114, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186560 + j - 1] = <<116, 104, 109, 83, 99, 111, 112, 101, 78, 97, 109, 101, 115, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186576 + j - 1] = <<32, 32, 32, 32, 32, 32, 118, 97, 114, 32, 111, 114, 100, 105, 110, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186592 + j - 1] = <<108, 32, 61, 32, 48, 10, 32, 32, 32, 32, 32, 32, 32, 32, 102, 117>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186608 + j - 1] = <<110, 99, 32, 98, 105, 110, 100, 105, 110, 103, 40, 41, 32, 45, 62, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186624 + j - 1] = <<83, 116, 114, 105, 110, 103, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186640 + j - 1] = <<32, 32, 32, 32, 32, 119, 104, 105, 108, 101, 32, 116, 114, 117, 101, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186656 + j - 1] = <<123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186672 + j - 1] = <<32, 32, 108, 101, 116, 32, 110, 97, 109, 101, 32, 61, 32, 34, 95, 95>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186688 + j - 1] = <<97, 116, 111, 109, 105, 99, 95, 92, 40, 111, 114, 100, 105, 110, 97, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186704 + j - 1] = <<41, 34, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186720 + j - 1] = <<32, 32, 32, 111, 114, 100, 105, 110, 97, 108, 32, 43, 61, 32, 49, 10>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186736 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186752 + j - 1] = <<105, 102, 32, 117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103, 115, 46>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186768 + j - 1] = <<105, 110, 115, 101, 114, 116, 40, 110, 97, 109, 101, 41, 46, 105, 110, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186784 + j - 1] = <<101, 114, 116, 101, 100, 32, 123, 32, 114, 101, 116, 117, 114, 110, 32, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186800 + j - 1] = <<97, 109, 101, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186816 + j - 1] = <<32, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186832 + j - 1] = <<32, 32, 32, 32, 32, 32, 118, 97, 114, 32, 100, 105, 115, 112, 108, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186848 + j - 1] = <<99, 101, 100, 84, 97, 114, 103, 101, 116, 115, 58, 32, 91, 83, 116, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186864 + j - 1] = <<105, 110, 103, 58, 32, 83, 116, 114, 105, 110, 103, 93, 32, 61, 32, 91>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186880 + j - 1] = <<58, 93, 10, 32, 32, 32, 32, 32, 32, 32, 32, 108, 101, 116, 32, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186896 + j - 1] = <<99, 104, 101, 100, 117, 108, 101, 100, 32, 61, 32, 115, 99, 104, 101, 100>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186912 + j - 1] = <<117, 108, 101, 65, 116, 111, 109, 105, 99, 83, 116, 97, 116, 101, 109, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186928 + j - 1] = <<110, 116, 115, 40, 115, 116, 101, 112, 46, 109, 111, 100, 101, 108, 46, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186944 + j - 1] = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 44, 32, 98, 105, 110, 100, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186960 + j - 1] = <<110, 103, 58, 32, 98, 105, 110, 100, 105, 110, 103, 44, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186976 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 99, 111, 114, 100, 65>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186992 + j - 1] = <<115, 115, 105, 103, 110, 109, 101, 110, 116, 58, 32, 114, 101, 99, 111, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187008 + j - 1] = <<100, 83, 99, 104, 101, 100, 117, 108, 101, 100, 65, 115, 115, 105, 103, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187024 + j - 1] = <<109, 101, 110, 116, 41, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187040 + j - 1] = <<32, 32, 32, 32, 100, 105, 115, 112, 108, 97, 99, 101, 100, 84, 97, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187056 + j - 1] = <<103, 101, 116, 115, 91, 36, 48, 93, 32, 61, 32, 36, 49, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187072 + j - 1] = <<32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187088 + j - 1] = <<108, 101, 116, 32, 108, 111, 119, 101, 114, 101, 100, 32, 61, 32, 108, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187104 + j - 1] = <<119, 101, 114, 40, 115, 99, 104, 101, 100, 117, 108, 101, 100, 44, 32, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187120 + j - 1] = <<114, 111, 99, 101, 115, 115, 76, 111, 99, 97, 108, 82, 111, 111, 116, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187136 + j - 1] = <<58, 32, 110, 105, 108, 44, 32, 112, 114, 111, 99, 101, 100, 117, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187152 + j - 1] = <<115, 58, 32, 91, 93, 44, 32, 111, 119, 110, 101, 114, 58, 32, 110, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187168 + j - 1] = <<108, 44, 32, 110, 101, 120, 116, 76, 97, 98, 101, 108, 58, 32, 110, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187184 + j - 1] = <<108, 44, 32, 99, 111, 110, 116, 114, 111, 108, 58, 32, 110, 105, 108, 41>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187200 + j - 1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 116, 117, 114, 110, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187216 + j - 1] = <<40, 108, 111, 119, 101, 114, 101, 100, 46, 97, 99, 116, 105, 111, 110, 44>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187232 + j - 1] = <<32, 108, 111, 119, 101, 114, 101, 100, 46, 97, 115, 115, 101, 114, 116, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187248 + j - 1] = <<111, 110, 115, 44, 32, 100, 105, 115, 112, 108, 97, 99, 101, 100, 84, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187264 + j - 1] = <<114, 103, 101, 116, 115, 41, 10, 32, 32, 32, 32, 125, 10, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230016 + j - 1] = <<32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 125, 10, 10, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230032 + j - 1] = <<32, 32, 32, 47, 47, 47, 32, 76, 111, 119, 101, 114, 115, 32, 115, 99>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230048 + j - 1] = <<104, 101, 100, 117, 108, 101, 100, 32, 97, 116, 111, 109, 105, 99, 32, 98>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230064 + j - 1] = <<114, 97, 110, 99, 104, 101, 115, 44, 32, 112, 114, 101, 115, 101, 114, 118>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230080 + j - 1] = <<105, 110, 103, 32, 116, 104, 101, 105, 114, 32, 98, 105, 110, 100, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230096 + j - 1] = <<103, 115, 32, 97, 110, 100, 32, 102, 105, 110, 97, 108, 32, 119, 114, 105>>[j]
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
    /\ \A j \in 1..16: CompilerInputByte[235904 + j - 1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 116, 117, 114, 110, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[235920 + j - 1] = <<114, 117, 110, 40, 115, 116, 97, 116, 101, 109, 101, 110, 116, 115, 91, 46>>[j]
    /\ \A j \in 1..16: CompilerInputByte[235936 + j - 1] = <<46, 46, 93, 44, 32, 91, 58, 93, 41, 10, 32, 32, 32, 32, 125, 10>>[j]

THEOREM ActualStandaloneAtomicLowererCall == StandaloneAtomicLowererCallBytes
PROOF
<1>block182.
    /\ \A j \in 1..16: CompilerInputByte[186176 + j - 1] = <<46, 112, 114, 111, 99, 101, 115, 115, 10, 10, 32, 32, 32, 32, 115, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186192 + j - 1] = <<97, 116, 105, 99, 32, 102, 117, 110, 99, 32, 108, 111, 119, 101, 114, 65>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186208 + j - 1] = <<116, 111, 109, 105, 99, 83, 116, 101, 112, 40, 95, 32, 115, 116, 101, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186224 + j - 1] = <<58, 32, 65, 116, 111, 109, 105, 99, 83, 116, 101, 112, 44, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186240 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186256 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186272 + j - 1] = <<99, 111, 114, 100, 83, 99, 104, 101, 100, 117, 108, 101, 100, 65, 115, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186288 + j - 1] = <<105, 103, 110, 109, 101, 110, 116, 58, 32, 40, 40, 83, 116, 114, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186304 + j - 1] = <<103, 44, 32, 83, 99, 104, 101, 100, 117, 108, 101, 100, 65, 116, 111, 109>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186320 + j - 1] = <<105, 99, 65, 115, 115, 105, 103, 110, 109, 101, 110, 116, 41, 32, 45, 62>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186336 + j - 1] = <<32, 86, 111, 105, 100, 41, 63, 32, 61, 32, 110, 105, 108, 41, 32, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186352 + j - 1] = <<104, 114, 111, 119, 115, 10, 32, 32, 32, 32, 32, 32, 32, 32, 45, 62>>[j]
    BY ONLY CompilerInputPageBlock182AtFileOffsets, PTL
<1>block183.
    /\ \A j \in 1..16: CompilerInputByte[186368 + j - 1] = <<32, 40, 97, 99, 116, 105, 111, 110, 58, 32, 65, 99, 116, 105, 111, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186384 + j - 1] = <<69, 120, 112, 114, 44, 32, 97, 115, 115, 101, 114, 116, 105, 111, 110, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186400 + j - 1] = <<58, 32, 91, 83, 116, 97, 116, 101, 69, 120, 112, 114, 93, 44, 32, 100>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186416 + j - 1] = <<105, 115, 112, 108, 97, 99, 101, 100, 65, 115, 115, 105, 103, 110, 109, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186432 + j - 1] = <<110, 116, 84, 97, 114, 103, 101, 116, 115, 58, 32, 91, 83, 116, 114, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186448 + j - 1] = <<110, 103, 58, 32, 83, 116, 114, 105, 110, 103, 93, 41, 32, 123, 10, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186464 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 116, 114, 121, 32, 115, 116, 101, 112, 46>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186480 + j - 1] = <<114, 101, 113, 117, 105, 114, 101, 73, 110, 100, 101, 112, 101, 110, 100, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186496 + j - 1] = <<110, 116, 83, 116, 101, 112, 40, 41, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186512 + j - 1] = <<32, 118, 97, 114, 32, 117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186528 + j - 1] = <<115, 32, 61, 32, 115, 116, 101, 112, 46, 109, 111, 100, 101, 108, 46, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186544 + j - 1] = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 46, 97, 108, 103, 111, 114, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186560 + j - 1] = <<116, 104, 109, 83, 99, 111, 112, 101, 78, 97, 109, 101, 115, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186576 + j - 1] = <<32, 32, 32, 32, 32, 32, 118, 97, 114, 32, 111, 114, 100, 105, 110, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186592 + j - 1] = <<108, 32, 61, 32, 48, 10, 32, 32, 32, 32, 32, 32, 32, 32, 102, 117>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186608 + j - 1] = <<110, 99, 32, 98, 105, 110, 100, 105, 110, 103, 40, 41, 32, 45, 62, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186624 + j - 1] = <<83, 116, 114, 105, 110, 103, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186640 + j - 1] = <<32, 32, 32, 32, 32, 119, 104, 105, 108, 101, 32, 116, 114, 117, 101, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186656 + j - 1] = <<123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186672 + j - 1] = <<32, 32, 108, 101, 116, 32, 110, 97, 109, 101, 32, 61, 32, 34, 95, 95>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186688 + j - 1] = <<97, 116, 111, 109, 105, 99, 95, 92, 40, 111, 114, 100, 105, 110, 97, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186704 + j - 1] = <<41, 34, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186720 + j - 1] = <<32, 32, 32, 111, 114, 100, 105, 110, 97, 108, 32, 43, 61, 32, 49, 10>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186736 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186752 + j - 1] = <<105, 102, 32, 117, 115, 101, 100, 66, 105, 110, 100, 105, 110, 103, 115, 46>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186768 + j - 1] = <<105, 110, 115, 101, 114, 116, 40, 110, 97, 109, 101, 41, 46, 105, 110, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186784 + j - 1] = <<101, 114, 116, 101, 100, 32, 123, 32, 114, 101, 116, 117, 114, 110, 32, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186800 + j - 1] = <<97, 109, 101, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186816 + j - 1] = <<32, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186832 + j - 1] = <<32, 32, 32, 32, 32, 32, 118, 97, 114, 32, 100, 105, 115, 112, 108, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186848 + j - 1] = <<99, 101, 100, 84, 97, 114, 103, 101, 116, 115, 58, 32, 91, 83, 116, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186864 + j - 1] = <<105, 110, 103, 58, 32, 83, 116, 114, 105, 110, 103, 93, 32, 61, 32, 91>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186880 + j - 1] = <<58, 93, 10, 32, 32, 32, 32, 32, 32, 32, 32, 108, 101, 116, 32, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186896 + j - 1] = <<99, 104, 101, 100, 117, 108, 101, 100, 32, 61, 32, 115, 99, 104, 101, 100>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186912 + j - 1] = <<117, 108, 101, 65, 116, 111, 109, 105, 99, 83, 116, 97, 116, 101, 109, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186928 + j - 1] = <<110, 116, 115, 40, 115, 116, 101, 112, 46, 109, 111, 100, 101, 108, 46, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186944 + j - 1] = <<116, 97, 116, 101, 109, 101, 110, 116, 115, 44, 32, 98, 105, 110, 100, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186960 + j - 1] = <<110, 103, 58, 32, 98, 105, 110, 100, 105, 110, 103, 44, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186976 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 99, 111, 114, 100, 65>>[j]
    /\ \A j \in 1..16: CompilerInputByte[186992 + j - 1] = <<115, 115, 105, 103, 110, 109, 101, 110, 116, 58, 32, 114, 101, 99, 111, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187008 + j - 1] = <<100, 83, 99, 104, 101, 100, 117, 108, 101, 100, 65, 115, 115, 105, 103, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187024 + j - 1] = <<109, 101, 110, 116, 41, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187040 + j - 1] = <<32, 32, 32, 32, 100, 105, 115, 112, 108, 97, 99, 101, 100, 84, 97, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187056 + j - 1] = <<103, 101, 116, 115, 91, 36, 48, 93, 32, 61, 32, 36, 49, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187072 + j - 1] = <<32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187088 + j - 1] = <<108, 101, 116, 32, 108, 111, 119, 101, 114, 101, 100, 32, 61, 32, 108, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187104 + j - 1] = <<119, 101, 114, 40, 115, 99, 104, 101, 100, 117, 108, 101, 100, 44, 32, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187120 + j - 1] = <<114, 111, 99, 101, 115, 115, 76, 111, 99, 97, 108, 82, 111, 111, 116, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187136 + j - 1] = <<58, 32, 110, 105, 108, 44, 32, 112, 114, 111, 99, 101, 100, 117, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187152 + j - 1] = <<115, 58, 32, 91, 93, 44, 32, 111, 119, 110, 101, 114, 58, 32, 110, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187168 + j - 1] = <<108, 44, 32, 110, 101, 120, 116, 76, 97, 98, 101, 108, 58, 32, 110, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187184 + j - 1] = <<108, 44, 32, 99, 111, 110, 116, 114, 111, 108, 58, 32, 110, 105, 108, 41>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187200 + j - 1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 116, 117, 114, 110, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187216 + j - 1] = <<40, 108, 111, 119, 101, 114, 101, 100, 46, 97, 99, 116, 105, 111, 110, 44>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187232 + j - 1] = <<32, 108, 111, 119, 101, 114, 101, 100, 46, 97, 115, 115, 101, 114, 116, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187248 + j - 1] = <<111, 110, 115, 44, 32, 100, 105, 115, 112, 108, 97, 99, 101, 100, 84, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[187264 + j - 1] = <<114, 103, 101, 116, 115, 41, 10, 32, 32, 32, 32, 125, 10, 10, 32, 32>>[j]
    BY ONLY CompilerInputPageBlock183AtFileOffsets, PTL
<1>block225.
    /\ \A j \in 1..16: CompilerInputByte[230016 + j - 1] = <<32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 125, 10, 10, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230032 + j - 1] = <<32, 32, 32, 47, 47, 47, 32, 76, 111, 119, 101, 114, 115, 32, 115, 99>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230048 + j - 1] = <<104, 101, 100, 117, 108, 101, 100, 32, 97, 116, 111, 109, 105, 99, 32, 98>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230064 + j - 1] = <<114, 97, 110, 99, 104, 101, 115, 44, 32, 112, 114, 101, 115, 101, 114, 118>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230080 + j - 1] = <<105, 110, 103, 32, 116, 104, 101, 105, 114, 32, 98, 105, 110, 100, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230096 + j - 1] = <<103, 115, 32, 97, 110, 100, 32, 102, 105, 110, 97, 108, 32, 119, 114, 105>>[j]
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
    BY ONLY CompilerInputPageBlock225AtFileOffsets, PTL
<1>block226.
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
    BY ONLY CompilerInputPageBlock226AtFileOffsets, PTL
<1>block231.
    /\ \A j \in 1..16: CompilerInputByte[235904 + j - 1] = <<10, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 116, 117, 114, 110, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[235920 + j - 1] = <<114, 117, 110, 40, 115, 116, 97, 116, 101, 109, 101, 110, 116, 115, 91, 46>>[j]
    /\ \A j \in 1..16: CompilerInputByte[235936 + j - 1] = <<46, 46, 93, 44, 32, 91, 58, 93, 41, 10, 32, 32, 32, 32, 125, 10>>[j]
    BY ONLY CompilerInputPageBlock231AtFileOffsets, PTL
<1>. QED BY ONLY <1>block182, <1>block183, <1>block225, <1>block226, <1>block231, PTL DEF StandaloneAtomicLowererCallBytes

TerminalAssignmentFoldBytes ==
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
    /\ \A j \in 1..16: CompilerInputByte[230704 + j - 1] = <<32, 32, 32, 102, 117, 110, 99, 32, 97, 115, 115, 105, 103, 110, 109, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230720 + j - 1] = <<110, 116, 115, 40, 95, 32, 118, 97, 108, 117, 101, 115, 58, 32, 91, 83>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230736 + j - 1] = <<116, 114, 105, 110, 103, 58, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230752 + j - 1] = <<93, 44, 32, 101, 120, 99, 108, 117, 100, 105, 110, 103, 58, 32, 83, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230768 + j - 1] = <<116, 60, 65, 99, 116, 105, 111, 110, 84, 97, 114, 103, 101, 116, 62, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230784 + j - 1] = <<61, 32, 91, 93, 41, 32, 45, 62, 32, 65, 99, 116, 105, 111, 110, 69>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230800 + j - 1] = <<120, 112, 114, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230816 + j - 1] = <<32, 32, 118, 97, 108, 117, 101, 115, 46, 115, 111, 114, 116, 101, 100, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230832 + j - 1] = <<123, 32, 36, 48, 46, 107, 101, 121, 32, 60, 32, 36, 49, 46, 107, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230848 + j - 1] = <<121, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230864 + j - 1] = <<32, 32, 32, 32, 46, 102, 105, 108, 116, 101, 114, 32, 123, 32, 33, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230880 + j - 1] = <<120, 99, 108, 117, 100, 105, 110, 103, 46, 99, 111, 110, 116, 97, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230896 + j - 1] = <<115, 40, 46, 110, 97, 109, 101, 100, 40, 36, 48, 46, 107, 101, 121, 41>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230912 + j - 1] = <<41, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230928 + j - 1] = <<32, 32, 32, 32, 46, 114, 101, 100, 117, 99, 101, 40, 46, 103, 117, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230944 + j - 1] = <<114, 100, 95, 40, 46, 98, 111, 111, 108, 40, 116, 114, 117, 101, 41, 41>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230960 + j - 1] = <<41, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230976 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 46, 97, 110, 100, 40, 36, 48, 44>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230992 + j - 1] = <<32, 46, 97, 115, 115, 105, 103, 110, 40, 46, 110, 97, 109, 101, 100, 40>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231008 + j - 1] = <<36, 49, 46, 107, 101, 121, 41, 44, 32, 36, 49, 46, 118, 97, 108, 117>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231024 + j - 1] = <<101, 41, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231040 + j - 1] = <<32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10>>[j]
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

THEOREM ActualTerminalAssignmentFold == TerminalAssignmentFoldBytes
PROOF
<1>block226.
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
    /\ \A j \in 1..16: CompilerInputByte[230704 + j - 1] = <<32, 32, 32, 102, 117, 110, 99, 32, 97, 115, 115, 105, 103, 110, 109, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230720 + j - 1] = <<110, 116, 115, 40, 95, 32, 118, 97, 108, 117, 101, 115, 58, 32, 91, 83>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230736 + j - 1] = <<116, 114, 105, 110, 103, 58, 32, 83, 116, 97, 116, 101, 69, 120, 112, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230752 + j - 1] = <<93, 44, 32, 101, 120, 99, 108, 117, 100, 105, 110, 103, 58, 32, 83, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230768 + j - 1] = <<116, 60, 65, 99, 116, 105, 111, 110, 84, 97, 114, 103, 101, 116, 62, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230784 + j - 1] = <<61, 32, 91, 93, 41, 32, 45, 62, 32, 65, 99, 116, 105, 111, 110, 69>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230800 + j - 1] = <<120, 112, 114, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230816 + j - 1] = <<32, 32, 118, 97, 108, 117, 101, 115, 46, 115, 111, 114, 116, 101, 100, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230832 + j - 1] = <<123, 32, 36, 48, 46, 107, 101, 121, 32, 60, 32, 36, 49, 46, 107, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230848 + j - 1] = <<121, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230864 + j - 1] = <<32, 32, 32, 32, 46, 102, 105, 108, 116, 101, 114, 32, 123, 32, 33, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230880 + j - 1] = <<120, 99, 108, 117, 100, 105, 110, 103, 46, 99, 111, 110, 116, 97, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230896 + j - 1] = <<115, 40, 46, 110, 97, 109, 101, 100, 40, 36, 48, 46, 107, 101, 121, 41>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230912 + j - 1] = <<41, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230928 + j - 1] = <<32, 32, 32, 32, 46, 114, 101, 100, 117, 99, 101, 40, 46, 103, 117, 97>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230944 + j - 1] = <<114, 100, 95, 40, 46, 98, 111, 111, 108, 40, 116, 114, 117, 101, 41, 41>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230960 + j - 1] = <<41, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230976 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 46, 97, 110, 100, 40, 36, 48, 44>>[j]
    /\ \A j \in 1..16: CompilerInputByte[230992 + j - 1] = <<32, 46, 97, 115, 115, 105, 103, 110, 40, 46, 110, 97, 109, 101, 100, 40>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231008 + j - 1] = <<36, 49, 46, 107, 101, 121, 41, 44, 32, 36, 49, 46, 118, 97, 108, 117>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231024 + j - 1] = <<101, 41, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[231040 + j - 1] = <<32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10>>[j]
    BY ONLY CompilerInputPageBlock226AtFileOffsets, PTL
<1>block227.
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
    BY ONLY CompilerInputPageBlock227AtFileOffsets, PTL
<1>. QED BY ONLY <1>block226, <1>block227, PTL DEF TerminalAssignmentFoldBytes

TerminalParallelUpdateBytes ==
    /\ \A j \in 1..16: CompilerInputByte[232352 + j - 1] = <<103, 34, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232368 + j - 1] = <<99, 97, 115, 101, 32, 46, 112, 97, 114, 97, 108, 108, 101, 108, 40, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232384 + j - 1] = <<101, 116, 32, 103, 114, 111, 117, 112, 41, 58, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232400 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 118, 97, 114, 32, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232416 + j - 1] = <<101, 120, 116, 32, 61, 32, 118, 97, 108, 117, 101, 115, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232432 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 102, 111, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232448 + j - 1] = <<32, 97, 115, 115, 105, 103, 110, 109, 101, 110, 116, 32, 105, 110, 32, 103>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232464 + j - 1] = <<114, 111, 117, 112, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232480 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 108, 101, 116, 32, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232496 + j - 1] = <<111, 111, 116, 32, 61, 32, 97, 115, 115, 105, 103, 110, 109, 101, 110, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232512 + j - 1] = <<46, 116, 97, 114, 103, 101, 116, 46, 114, 111, 111, 116, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232528 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232544 + j - 1] = <<32, 108, 101, 116, 32, 118, 97, 108, 117, 101, 32, 61, 32, 115, 99, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232560 + j - 1] = <<112, 101, 100, 40, 97, 115, 115, 105, 103, 110, 109, 101, 110, 116, 46, 118>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232576 + j - 1] = <<97, 108, 117, 101, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232592 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 115, 119, 105, 116, 99, 104>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232608 + j - 1] = <<32, 97, 115, 115, 105, 103, 110, 109, 101, 110, 116, 46, 116, 97, 114, 103>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232624 + j - 1] = <<101, 116, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232640 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97, 115, 101, 32, 46, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232656 + j - 1] = <<111, 111, 116, 32, 119, 104, 101, 114, 101, 32, 112, 114, 111, 99, 101, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232672 + j - 1] = <<115, 76, 111, 99, 97, 108, 82, 111, 111, 116, 115, 63, 46, 99, 111, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232688 + j - 1] = <<116, 97, 105, 110, 115, 40, 114, 111, 111, 116, 41, 32, 61, 61, 32, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232704 + j - 1] = <<114, 117, 101, 58, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232720 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 110, 101, 120>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232736 + j - 1] = <<116, 91, 114, 111, 111, 116, 93, 32, 61, 32, 46, 101, 120, 99, 101, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232752 + j - 1] = <<116, 40, 46, 118, 97, 114, 105, 97, 98, 108, 101, 40, 114, 111, 111, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232768 + j - 1] = <<41, 44, 32, 46, 118, 97, 114, 105, 97, 98, 108, 101, 40, 112, 114, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232784 + j - 1] = <<99, 101, 115, 115, 66, 105, 110, 100, 105, 110, 103, 46, 114, 97, 119, 86>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232800 + j - 1] = <<97, 108, 117, 101, 41, 44, 32, 118, 97, 108, 117, 101, 41, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232816 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232832 + j - 1] = <<32, 32, 99, 97, 115, 101, 32, 46, 114, 111, 111, 116, 58, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232848 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232864 + j - 1] = <<32, 32, 32, 32, 32, 32, 110, 101, 120, 116, 91, 114, 111, 111, 116, 93>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232880 + j - 1] = <<32, 61, 32, 118, 97, 108, 117, 101, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232896 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232912 + j - 1] = <<101, 32, 46, 102, 117, 110, 99, 116, 105, 111, 110, 44, 32, 46, 102, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232928 + j - 1] = <<101, 108, 100, 58, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232944 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 112, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232960 + j - 1] = <<99, 111, 110, 100, 105, 116, 105, 111, 110, 70, 97, 105, 108, 117, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232976 + j - 1] = <<40, 34, 83, 99, 104, 101, 100, 117, 108, 101, 100, 32, 97, 115, 115, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232992 + j - 1] = <<103, 110, 109, 101, 110, 116, 115, 32, 109, 117, 115, 116, 32, 116, 97, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233008 + j - 1] = <<103, 101, 116, 32, 99, 111, 109, 112, 108, 101, 116, 101, 32, 114, 111, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233024 + j - 1] = <<116, 115, 34, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233040 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233056 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233072 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233088 + j - 1] = <<117, 114, 110, 32, 114, 117, 110, 40, 114, 101, 115, 116, 44, 32, 110, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233104 + j - 1] = <<120, 116, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]

THEOREM ActualTerminalParallelUpdate == TerminalParallelUpdateBytes
PROOF
<1>block227.
    /\ \A j \in 1..16: CompilerInputByte[232352 + j - 1] = <<103, 34, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232368 + j - 1] = <<99, 97, 115, 101, 32, 46, 112, 97, 114, 97, 108, 108, 101, 108, 40, 108>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232384 + j - 1] = <<101, 116, 32, 103, 114, 111, 117, 112, 41, 58, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232400 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 118, 97, 114, 32, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232416 + j - 1] = <<101, 120, 116, 32, 61, 32, 118, 97, 108, 117, 101, 115, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232432 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 102, 111, 114>>[j]
    BY ONLY CompilerInputPageBlock227AtFileOffsets, PTL
<1>block228.
    /\ \A j \in 1..16: CompilerInputByte[232448 + j - 1] = <<32, 97, 115, 115, 105, 103, 110, 109, 101, 110, 116, 32, 105, 110, 32, 103>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232464 + j - 1] = <<114, 111, 117, 112, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232480 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 108, 101, 116, 32, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232496 + j - 1] = <<111, 111, 116, 32, 61, 32, 97, 115, 115, 105, 103, 110, 109, 101, 110, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232512 + j - 1] = <<46, 116, 97, 114, 103, 101, 116, 46, 114, 111, 111, 116, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232528 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232544 + j - 1] = <<32, 108, 101, 116, 32, 118, 97, 108, 117, 101, 32, 61, 32, 115, 99, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232560 + j - 1] = <<112, 101, 100, 40, 97, 115, 115, 105, 103, 110, 109, 101, 110, 116, 46, 118>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232576 + j - 1] = <<97, 108, 117, 101, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232592 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 115, 119, 105, 116, 99, 104>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232608 + j - 1] = <<32, 97, 115, 115, 105, 103, 110, 109, 101, 110, 116, 46, 116, 97, 114, 103>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232624 + j - 1] = <<101, 116, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232640 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97, 115, 101, 32, 46, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232656 + j - 1] = <<111, 111, 116, 32, 119, 104, 101, 114, 101, 32, 112, 114, 111, 99, 101, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232672 + j - 1] = <<115, 76, 111, 99, 97, 108, 82, 111, 111, 116, 115, 63, 46, 99, 111, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232688 + j - 1] = <<116, 97, 105, 110, 115, 40, 114, 111, 111, 116, 41, 32, 61, 61, 32, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232704 + j - 1] = <<114, 117, 101, 58, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232720 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 110, 101, 120>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232736 + j - 1] = <<116, 91, 114, 111, 111, 116, 93, 32, 61, 32, 46, 101, 120, 99, 101, 112>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232752 + j - 1] = <<116, 40, 46, 118, 97, 114, 105, 97, 98, 108, 101, 40, 114, 111, 111, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232768 + j - 1] = <<41, 44, 32, 46, 118, 97, 114, 105, 97, 98, 108, 101, 40, 112, 114, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232784 + j - 1] = <<99, 101, 115, 115, 66, 105, 110, 100, 105, 110, 103, 46, 114, 97, 119, 86>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232800 + j - 1] = <<97, 108, 117, 101, 41, 44, 32, 118, 97, 108, 117, 101, 41, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232816 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232832 + j - 1] = <<32, 32, 99, 97, 115, 101, 32, 46, 114, 111, 111, 116, 58, 10, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232848 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232864 + j - 1] = <<32, 32, 32, 32, 32, 32, 110, 101, 120, 116, 91, 114, 111, 111, 116, 93>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232880 + j - 1] = <<32, 61, 32, 118, 97, 108, 117, 101, 10, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232896 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232912 + j - 1] = <<101, 32, 46, 102, 117, 110, 99, 116, 105, 111, 110, 44, 32, 46, 102, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232928 + j - 1] = <<101, 108, 100, 58, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232944 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 112, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232960 + j - 1] = <<99, 111, 110, 100, 105, 116, 105, 111, 110, 70, 97, 105, 108, 117, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232976 + j - 1] = <<40, 34, 83, 99, 104, 101, 100, 117, 108, 101, 100, 32, 97, 115, 115, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[232992 + j - 1] = <<103, 110, 109, 101, 110, 116, 115, 32, 109, 117, 115, 116, 32, 116, 97, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233008 + j - 1] = <<103, 101, 116, 32, 99, 111, 109, 112, 108, 101, 116, 101, 32, 114, 111, 111>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233024 + j - 1] = <<116, 115, 34, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233040 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233056 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233072 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 114, 101, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233088 + j - 1] = <<117, 114, 110, 32, 114, 117, 110, 40, 114, 101, 115, 116, 44, 32, 110, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[233104 + j - 1] = <<120, 116, 41, 10, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32>>[j]
    BY ONLY CompilerInputPageBlock228AtFileOffsets, PTL
<1>. QED BY ONLY <1>block227, <1>block228, PTL DEF TerminalParallelUpdateBytes

ScheduledRootTargetsBytes ==
    /\ \A j \in 1..16: CompilerInputByte[29744 + j - 1] = <<10, 112, 97, 99, 107, 97, 103, 101, 32, 105, 110, 100, 105, 114, 101, 99>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29760 + j - 1] = <<116, 32, 101, 110, 117, 109, 32, 65, 108, 103, 111, 114, 105, 116, 104, 109>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29776 + j - 1] = <<76, 86, 97, 108, 117, 101, 77, 111, 100, 101, 108, 58, 32, 83, 101, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29792 + j - 1] = <<100, 97, 98, 108, 101, 44, 32, 69, 113, 117, 97, 116, 97, 98, 108, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29808 + j - 1] = <<32, 123, 10, 32, 32, 32, 32, 99, 97, 115, 101, 32, 114, 111, 111, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29824 + j - 1] = <<40, 83, 116, 114, 105, 110, 103, 41, 10, 32, 32, 32, 32, 99, 97, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29840 + j - 1] = <<101, 32, 102, 117, 110, 99, 116, 105, 111, 110, 40, 98, 97, 115, 101, 58>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29856 + j - 1] = <<32, 65, 108, 103, 111, 114, 105, 116, 104, 109, 76, 86, 97, 108, 117, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29872 + j - 1] = <<77, 111, 100, 101, 108, 44, 32, 107, 101, 121, 58, 32, 83, 116, 97, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29888 + j - 1] = <<101, 69, 120, 112, 114, 41, 10, 32, 32, 32, 32, 99, 97, 115, 101, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29904 + j - 1] = <<102, 105, 101, 108, 100, 40, 65, 108, 103, 111, 114, 105, 116, 104, 109, 76>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29920 + j - 1] = <<86, 97, 108, 117, 101, 77, 111, 100, 101, 108, 44, 32, 83, 116, 114, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29936 + j - 1] = <<110, 103, 41, 10, 10, 32, 32, 32, 32, 112, 97, 99, 107, 97, 103, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29952 + j - 1] = <<32, 118, 97, 114, 32, 114, 111, 111, 116, 58, 32, 83, 116, 114, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29968 + j - 1] = <<103, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 115, 119, 105, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29984 + j - 1] = <<99, 104, 32, 115, 101, 108, 102, 32, 123, 10, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30000 + j - 1] = <<32, 32, 99, 97, 115, 101, 32, 46, 114, 111, 111, 116, 40, 108, 101, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30016 + j - 1] = <<32, 114, 111, 111, 116, 41, 58, 32, 114, 101, 116, 117, 114, 110, 32, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30032 + j - 1] = <<111, 111, 116, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97, 115, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30048 + j - 1] = <<32, 46, 102, 117, 110, 99, 116, 105, 111, 110, 40, 108, 101, 116, 32, 98>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30064 + j - 1] = <<97, 115, 101, 44, 32, 95, 41, 44, 32, 46, 102, 105, 101, 108, 100, 40>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30080 + j - 1] = <<108, 101, 116, 32, 98, 97, 115, 101, 44, 32, 95, 41, 58, 32, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30096 + j - 1] = <<116, 117, 114, 110, 32, 98, 97, 115, 101, 46, 114, 111, 111, 116, 10, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30112 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 125, 10, 10>>[j]
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
    /\ \A j \in 1..16: CompilerInputByte[39440 + j - 1] = <<10, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 114, 101, 116, 117, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[39456 + j - 1] = <<110, 32, 115, 99, 104, 101, 100, 117, 108, 101, 40, 115, 116, 97, 116, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[39472 + j - 1] = <<109, 101, 110, 116, 115, 41, 10, 125, 10, 0, 0, 0, 0, 0, 0, 0>>[j]

THEOREM ActualScheduledRootTargets == ScheduledRootTargetsBytes
PROOF
<1>block30.
    /\ \A j \in 1..16: CompilerInputByte[29744 + j - 1] = <<10, 112, 97, 99, 107, 97, 103, 101, 32, 105, 110, 100, 105, 114, 101, 99>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29760 + j - 1] = <<116, 32, 101, 110, 117, 109, 32, 65, 108, 103, 111, 114, 105, 116, 104, 109>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29776 + j - 1] = <<76, 86, 97, 108, 117, 101, 77, 111, 100, 101, 108, 58, 32, 83, 101, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29792 + j - 1] = <<100, 97, 98, 108, 101, 44, 32, 69, 113, 117, 97, 116, 97, 98, 108, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29808 + j - 1] = <<32, 123, 10, 32, 32, 32, 32, 99, 97, 115, 101, 32, 114, 111, 111, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29824 + j - 1] = <<40, 83, 116, 114, 105, 110, 103, 41, 10, 32, 32, 32, 32, 99, 97, 115>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29840 + j - 1] = <<101, 32, 102, 117, 110, 99, 116, 105, 111, 110, 40, 98, 97, 115, 101, 58>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29856 + j - 1] = <<32, 65, 108, 103, 111, 114, 105, 116, 104, 109, 76, 86, 97, 108, 117, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29872 + j - 1] = <<77, 111, 100, 101, 108, 44, 32, 107, 101, 121, 58, 32, 83, 116, 97, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29888 + j - 1] = <<101, 69, 120, 112, 114, 41, 10, 32, 32, 32, 32, 99, 97, 115, 101, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29904 + j - 1] = <<102, 105, 101, 108, 100, 40, 65, 108, 103, 111, 114, 105, 116, 104, 109, 76>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29920 + j - 1] = <<86, 97, 108, 117, 101, 77, 111, 100, 101, 108, 44, 32, 83, 116, 114, 105>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29936 + j - 1] = <<110, 103, 41, 10, 10, 32, 32, 32, 32, 112, 97, 99, 107, 97, 103, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29952 + j - 1] = <<32, 118, 97, 114, 32, 114, 111, 111, 116, 58, 32, 83, 116, 114, 105, 110>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29968 + j - 1] = <<103, 32, 123, 10, 32, 32, 32, 32, 32, 32, 32, 32, 115, 119, 105, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[29984 + j - 1] = <<99, 104, 32, 115, 101, 108, 102, 32, 123, 10, 32, 32, 32, 32, 32, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30000 + j - 1] = <<32, 32, 99, 97, 115, 101, 32, 46, 114, 111, 111, 116, 40, 108, 101, 116>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30016 + j - 1] = <<32, 114, 111, 111, 116, 41, 58, 32, 114, 101, 116, 117, 114, 110, 32, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30032 + j - 1] = <<111, 111, 116, 10, 32, 32, 32, 32, 32, 32, 32, 32, 99, 97, 115, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30048 + j - 1] = <<32, 46, 102, 117, 110, 99, 116, 105, 111, 110, 40, 108, 101, 116, 32, 98>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30064 + j - 1] = <<97, 115, 101, 44, 32, 95, 41, 44, 32, 46, 102, 105, 101, 108, 100, 40>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30080 + j - 1] = <<108, 101, 116, 32, 98, 97, 115, 101, 44, 32, 95, 41, 58, 32, 114, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30096 + j - 1] = <<116, 117, 114, 110, 32, 98, 97, 115, 101, 46, 114, 111, 111, 116, 10, 32>>[j]
    /\ \A j \in 1..16: CompilerInputByte[30112 + j - 1] = <<32, 32, 32, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 125, 10, 10>>[j]
    BY ONLY CompilerInputPageBlock30AtFileOffsets, PTL
<1>block37.
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
    BY ONLY CompilerInputPageBlock37AtFileOffsets, PTL
<1>block39.
    /\ \A j \in 1..16: CompilerInputByte[39440 + j - 1] = <<10, 32, 32, 32, 32, 125, 10, 32, 32, 32, 32, 114, 101, 116, 117, 114>>[j]
    /\ \A j \in 1..16: CompilerInputByte[39456 + j - 1] = <<110, 32, 115, 99, 104, 101, 100, 117, 108, 101, 40, 115, 116, 97, 116, 101>>[j]
    /\ \A j \in 1..16: CompilerInputByte[39472 + j - 1] = <<109, 101, 110, 116, 115, 41, 10, 125, 10, 0, 0, 0, 0, 0, 0, 0>>[j]
    BY ONLY CompilerInputPageBlock39AtFileOffsets, PTL
<1>. QED BY ONLY <1>block30, <1>block37, <1>block39, PTL DEF ScheduledRootTargetsBytes

\* For the scheduler's .root-only projection, assignment.target is the root
\* payload of the actual Swift AlgorithmLValueModel. Swift Optional, ArraySlice,
\* Dictionary subscript, sorted(by:), filter and reduce use their reviewed normal
\* semantics. Less is the actual Swift String < on the shared name representation.
AtomicLowererEmptyValues == <<>>

AtomicLowererWrite(values, assignment) ==
    [key \in DOMAIN values \cup {assignment.target} |->
        IF key = assignment.target THEN assignment.value ELSE values[key]]

AtomicLowererFold(values, initial, Step(_, _)) ==
    LET at[i \in 0..Len(values)] ==
            IF i = 0 THEN initial ELSE Step(at[i-1], values[i])
    IN at[Len(values)]

AtomicLowererParallelValues(group, values) ==
    AtomicLowererFold(group, values, AtomicLowererWrite)

AtomicLowererNamedTarget(name) == [kind |-> "named", name |-> name]

AtomicLowererSortedKeys(values, Less(_, _)) ==
    CHOOSE keys \in Seq(DOMAIN values) :
        /\ {keys[i] : i \in DOMAIN keys} = DOMAIN values
        /\ \A i,j \in DOMAIN keys : i < j => Less(keys[i], keys[j])

AtomicLowererSeed == [kind |-> "guard", value |-> [kind |-> "bool", value |-> TRUE]]

AtomicLowererConjoinWrite(action, key, values) ==
    [kind |-> "and", left |-> action,
     right |-> [kind |-> "assign", target |-> AtomicLowererNamedTarget(key), value |-> values[key]]]

AtomicLowererAssignments(values, excluding, Less(_, _)) ==
    LET keys == AtomicLowererSortedKeys(values, Less)
        included == SelectSeq(keys, LAMBDA key : AtomicLowererNamedTarget(key) \notin excluding)
    IN AtomicLowererFold(included, AtomicLowererSeed,
                         LAMBDA action, key : AtomicLowererConjoinWrite(action,key,values))

AtomicLowererOrdinaryExit(values, completion, Less(_, _)) ==
    LET writes == AtomicLowererAssignments(values, {}, Less)
    IN IF completion = <<>> THEN writes
       ELSE [kind |-> "and", left |-> writes, right |-> completion[1]]

\* The actual ordinary exit is selected in exactly two cases of this fragment.
\* The parallel group enters the same empty-rest branch with its updated values.
ActualStandaloneTerminalRun(remaining, values, Less(_, _)) ==
    IF TerminalAssignmentFoldBytes /\ TerminalParallelUpdateBytes /\ ScheduledRootTargetsBytes
    THEN IF remaining = <<>> THEN AtomicLowererOrdinaryExit(values, <<>>, Less)
         ELSE LET head == Head(remaining)
              IN IF head.kind = "parallel" /\ Tail(remaining) = <<>>
                 THEN AtomicLowererOrdinaryExit(AtomicLowererParallelValues(head.assignments,values),
                                                <<>>, Less)
                 ELSE "outside standalone terminal"
    ELSE "unrecognized standalone terminal"

\* Projection of the normal lowerAtomicStep return. The entry call omits
\* completion, passes nil roots, and supplies the scheduled array unchanged.
\* Schedule is the invoked scheduler and Run the interpreted local run function.
ActualStandaloneLowerAtomicStepAction(statements, Schedule(_), Run(_, _)) ==
    IF StandaloneAtomicLowererCallBytes
    THEN LET scheduled == Schedule(statements)
             lowered == Run(scheduled, AtomicLowererEmptyValues)
         IN lowered.action
    ELSE "unrecognized standalone call"

THEOREM ActualStandaloneLowersTheSchedulerReturnWithEmptyValues ==
    ASSUME NEW statements, NEW Schedule(_), NEW Run(_, _)
    PROVE ActualStandaloneLowerAtomicStepAction(statements, Schedule, Run) =
          Run(Schedule(statements),AtomicLowererEmptyValues).action
BY ONLY ActualStandaloneAtomicLowererCall, IsaM("simp"), SMT DEF ActualStandaloneLowerAtomicStepAction

THEOREM ActualStandaloneTerminalReturnsTheSortedFoldOfItsPublishedWrites ==
    ASSUME NEW remaining, NEW group, NEW Less(_, _),
           remaining = IF group = <<>> THEN <<>> ELSE <<[kind |-> "parallel", assignments |-> group]>>
    PROVE ActualStandaloneTerminalRun(remaining, AtomicLowererEmptyValues, Less) =
          AtomicLowererAssignments(
              IF group = <<>> THEN AtomicLowererEmptyValues
              ELSE AtomicLowererParallelValues(group,AtomicLowererEmptyValues),
              {}, Less)
PROOF
<1>. DEFINE result == ActualStandaloneTerminalRun(remaining, AtomicLowererEmptyValues, Less)
            parallel == [kind |-> "parallel", assignments |-> group]
<1>recognized. TerminalAssignmentFoldBytes /\ TerminalParallelUpdateBytes /\ ScheduledRootTargetsBytes
    BY ONLY ActualTerminalAssignmentFold, ActualTerminalParallelUpdate, ActualScheduledRootTargets, PTL
<1>empty. group = <<>> =>
    result = AtomicLowererAssignments(AtomicLowererEmptyValues, {}, Less)
    BY ONLY <1>recognized,
        (remaining = IF group = <<>> THEN <<>> ELSE <<parallel>>),
        IsaM("simp"), SMT DEF result, ActualStandaloneTerminalRun, AtomicLowererOrdinaryExit, parallel
<1>single. group # <<>> =>
    /\ remaining # <<>> /\ Head(remaining) = parallel /\ Tail(remaining) = <<>>
    /\ parallel.kind = "parallel" /\ parallel.assignments = group
    BY ONLY (remaining = IF group = <<>> THEN <<>> ELSE <<parallel>>),
        IsaM("simp"), SMT DEF Head, Tail, parallel
<1>nonempty. group # <<>> =>
    result = AtomicLowererAssignments(
        AtomicLowererParallelValues(group,AtomicLowererEmptyValues), {}, Less)
    BY ONLY <1>recognized, <1>single, IsaM("simp"), SMT
        DEF result, ActualStandaloneTerminalRun, AtomicLowererOrdinaryExit
<1>. QED BY ONLY <1>empty, <1>nonempty, SMT DEF result
====
