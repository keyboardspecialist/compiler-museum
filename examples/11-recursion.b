// 11-recursion: functions that call themselves.
//
// Concepts:
//   - A recursive call uses the same call-stack machinery as any other.
//   - Always include a base case so the recursion terminates.
//   - Factorial: fact(0) = 1; fact(n) = n * fact(n-1).
//   - The call stack depth is proportional to n for this definition.

SECTION "fact"

GET "libhdr"

LET start() = VALOF
{ FOR i = 0 TO 8 DO writef("fact(%n) = %i5*n", i, fact(i))
  RESULTIS 0
}

AND fact(n) = n=0 -> 1, n*fact(n-1)
