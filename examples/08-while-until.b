// 08-while-until: head- and tail-tested loops.
//
// Concepts:
//   - WHILE cond DO body     head-tested; may execute 0 times.
//   - UNTIL cond DO body     UNTIL cond is WHILE ~cond.
//   - { body } REPEAT        unconditional loop; exit via BREAK.
//   - { body } REPEATWHILE c tail-tested, run while c is true.
//   - { body } REPEATUNTIL c tail-tested, run until c is true.

SECTION "whlloop"

GET "libhdr"

LET start() = VALOF
{ LET x = 1
  LET y = 50
  LET k = 0

  WHILE x < 100 DO x := x * 2
  writef("doubled past 100: x=%n*n", x)

  UNTIL y <= 1 DO y := y / 2
  writef("halved to 1: y=%n*n", y)

  { k := k + 1
    writef("iter %n*n", k)
  } REPEATUNTIL k = 3

  RESULTIS 0
}
