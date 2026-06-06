// 13-nested-fns: functions declared inside a VALOF.
//
// Concepts:
//   - A LET inside a VALOF can define helper functions.
//   - The compiler hoists them but their names stay scoped to the block.
//   - Use them to factor a helper that only makes sense in one caller.

SECTION "nested"

GET "libhdr"

LET start() = VALOF
{ LET inner(x) = VALOF
  { LET deep(y) = y + 1  // only visible inside inner
    RESULTIS deep(x) * 2
  }

  writef("inner(3) = %n*n", inner(3))
  RESULTIS 0
}
