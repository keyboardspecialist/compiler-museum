// 15-vectors: allocate and walk a word vector.
//
// Concepts:
//   - LET v = VEC n        — stack-allocated vector of n+1 words.
//   - getvec(n)            — heap-allocated, returns 0 on OOM.
//   - freevec(v)           — return heap memory.
//   - v!i                  — load/store the i'th word (0-indexed).
//   - Pass vectors to functions as a pointer argument.

SECTION "vec"

GET "libhdr"

LET start() = VALOF
{ LET v = getvec(9)
  UNLESS v DO { writef("OOM*n"); RESULTIS 1 }

  FOR i = 0 TO 9 DO v!i := i * i
  FOR i = 0 TO 9 DO writef("%i2^2 = %i3*n", i, v!i)

  freevec(v)
  RESULTIS 0
}
