// 05-conditionals: IF, UNLESS, TEST, and the -> ternary.
//
// Concepts:
//   - IF cond DO stmt        — run stmt when cond is true.
//   - UNLESS cond DO stmt    — run stmt when cond is false.
//   - TEST cond THEN ... ELSE ...  — two-branch form.
//   - expr -> a, b           — ternary expression.

SECTION "cond"

GET "libhdr"

LET start() = VALOF
{ LET n = -7

  IF n < 0 DO writef("n is negative: %n*n", n)
  UNLESS n = 0 DO writef("n is nonzero*n")

  TEST n > 0
  THEN writef("positive*n")
  ELSE writef("not positive*n")

  // Ternary expression, handy inside writef args.
  writef("sign = %s*n", n < 0 -> "neg",
                        n = 0 -> "zero",
                                 "pos")
  RESULTIS 0
}
