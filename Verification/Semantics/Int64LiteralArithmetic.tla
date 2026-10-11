--------------------- MODULE Int64LiteralArithmetic ---------------------
EXTENDS TLAPS, Integers

THEOREM Int64MaximumMinusOne ==
    9223372036854775807 - 1 = 9223372036854775806
    BY Isa

THEOREM BillionBelowInt64MaximumMinusOne ==
    1000000000 <= 9223372036854775806
    BY Isa

THEOREM FourBelowInt64MaximumMinusOne ==
    4 <= 9223372036854775806
    BY Isa

=======================================================================
