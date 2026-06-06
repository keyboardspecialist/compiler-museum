// 27-every-sum: EVERY expressions + commands.
//
// MATCH stops at the first arm that fires (see 26-match-patterns).
// EVERY runs every arm whose patterns match, in order. Two forms:
//
//   EVERY (args)              — expression form, results combined
//   : pat => expr             —   with + (or | for non-numeric).
//   : pat => expr
//
//   EVERY (args)              — command form, runs each matching
//   : pat BE stmt             —   arm for its side effects.
//   : pat BE stmt
//
// Useful for flag tallies (expression) and dispatch tables where
// multiple categories apply (command).

SECTION "every"

GET "libhdr"

// Module-level mutable counters live in STATIC.
STATIC { digits = 0; evens = 0; letters = 0 }

// Expression form: every matching arm contributes to the sum.
// score(150) hits >0 and >10 and >100  =>  1 + 10 + 100 = 111.
LET score(n) = EVERY (n)
: >0     => 1
: >10    => 10
: >100   => 100

// Command form: classify each char into multiple bucket counters.
// A digit that's also even runs both arms.
LET tally(ch) BE EVERY (ch)
: '0'..'9'                    BE digits  +:= 1
: '0' | '2' | '4' | '6' | '8' BE evens   +:= 1
: 'A'..'Z' | 'a'..'z'         BE letters +:= 1
: ?                           BE { /* ignore */ }

LET start() = VALOF
{ FOR n = 0 TO 4 DO
  { LET v = n * 75
    writef("score(%i4) = %i4*n", v, score(v))
  }

  FOR ch = '0' TO '9' DO tally(ch)
  FOR ch = 'a' TO 'f' DO tally(ch)
  tally('!') ; tally('?')

  writef("*ndigits=%n  evens=%n  letters=%n*n", digits, evens, letters)
  RESULTIS 0
}
