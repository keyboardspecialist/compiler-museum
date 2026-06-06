// 12-valof: turn a block into an expression that yields a value.
//
// Concepts:
//   - VALOF { ... RESULTIS v } yields v from the surrounding expression.
//   - Locals and any commands can appear before RESULTIS.
//   - A function defined with '= <expr>' is equivalent to '= VALOF { RESULTIS <expr> }'.
//   - VALOF blocks nest.

SECTION "valof"

GET "libhdr"

LET start() = VALOF
{ LET a = VALOF { RESULTIS 10 }
  LET b = VALOF
  { LET inner = VALOF { RESULTIS 3 }
    RESULTIS inner + 7
  }
  writef("a=%n b=%n a+b=%n*n", a, b, a+b)
  RESULTIS 0
}
