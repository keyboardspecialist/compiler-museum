// 26-match-patterns: BCPL function-pattern definitions.
//
// A function (or routine) can be defined as a list of pattern arms
// separated by ':'. The arity of the patterns implicitly declares
// the parameters — no '(n)' header, no MATCH keyword. First arm whose
// patterns all succeed wins; '?' is the wildcard that always matches.
//
//   LET name
//   : pat1, pat2, ... => expr     // function: return the expression
//   : pat1, pat2, ... BE  stmt    // routine:  run the statement
//
// Patterns:
//   42              — literal
//   1 | 2 | 3       — alternatives
//   4..10           — inclusive range
//   x ?             — wildcard, bind matched value to x
//   x 1..9          — bind x and require it in range
//   ?               — wildcard, discard
//
// Compare 27-every-sum.b for the EVERY variant (every arm runs).

SECTION "match"

GET "libhdr"

// Single-arg classifier — no '(n)' needed; the single pattern column
// makes this a 1-arg function.
LET classify
: 0          => "zero"
: 1 | 2 | 3  => "small"
: 4..10      => "medium"
: 11..99     => "big"
: ?          => "huge"

// Variable-binding: name on the left of a pattern captures the
// matched value into a local visible only in that arm's RHS.
LET describe
: x 0          => "exactly zero"
: x 1..9       => "single digit"
: x 10..99     => "two digits"
: x ?          => x < 0 -> "negative", "many digits"

// Two-arg function — pattern arity = 2.
LET cmp
: x ?, y ?  => x = y -> 0, x < y -> -1, 1

LET start() = VALOF
{ FOR i = 0 TO 8 DO
    writef("%i3 -> %s   (%s)*n", i*i, classify(i*i), describe(i*i))
  writef("cmp(3, 7) = %n*n", cmp(3, 7))
  writef("cmp(9, 9) = %n*n", cmp(9, 9))
  RESULTIS 0
}
