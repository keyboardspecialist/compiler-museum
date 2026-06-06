// 06-boolean-short-circuit: & and | inside Boolean contexts
// short-circuit; elsewhere they act bitwise.
//
// Concepts:
//   - A "Boolean context" is the condition of IF/UNLESS/TEST/WHILE/UNTIL
//     and the operand of ~.
//   - In that context, & stops at the first FALSE, | stops at first TRUE.
//   - Outside Boolean context, & and | do bitwise AND/OR on integers.
//   - ~ flips: Boolean in a Boolean context, bitwise otherwise.

SECTION "bool"

GET "libhdr"

LET sidefx(label, v) = VALOF
{ writef("  eval %s=%n*n", label, v)
  RESULTIS v
}

LET start() = VALOF
{ // Boolean AND — second arg only evaluated if first is TRUE.
  writef("testing (TRUE & call)*n")
  IF TRUE & sidefx("RHS", -1) DO writef("  taken*n")

  writef("testing (FALSE & call) — call should be skipped*n")
  IF FALSE & sidefx("RHS", -1) DO writef("  taken*n")

  // Bitwise — both sides always evaluated.
  writef("#b1100 & #b1010 = %b4*n", #b1100 & #b1010)
  writef("#b1100 | #b1010 = %b4*n", #b1100 | #b1010)

  RESULTIS 0
}
