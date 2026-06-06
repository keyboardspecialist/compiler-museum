// 07-for-loop: FOR with optional BY, plus LOOP / BREAK / NEXT.
//
// Concepts:
//   - FOR i = a TO b DO body       — i runs a..b inclusive.
//   - FOR i = a TO b BY s DO body  — custom step s.
//   - LOOP  — skip to the next iteration of the enclosing loop.
//   - BREAK — exit the enclosing loop.

SECTION "forloop"

GET "libhdr"

LET start() = VALOF
{ // Simple forward loop.
  writef("squares: ")
  FOR i = 1 TO 5 DO writef("%n ", i*i)
  newline()

  // Descending / stepping loop.
  writef("odd down: ")
  FOR i = 9 TO 1 BY -2 DO writef("%n ", i)
  newline()

  // LOOP and BREAK.
  writef("skip multiples of 3 until 15: ")
  FOR i = 1 TO 100 DO
  { IF i MOD 3 = 0 LOOP
    IF i > 15 BREAK
    writef("%n ", i)
  }
  newline()
  RESULTIS 0
}
