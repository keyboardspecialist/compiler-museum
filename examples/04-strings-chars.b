// 04-strings-chars: BCPL strings are byte-packed.
//
// Concepts:
//   - A BCPL string literal's byte 0 holds the length.
//   - s%i returns the i'th byte (1-indexed from the char data).
//   - writef codes: %s for string, %c for char.
//   - Escapes in string literals: *n (LF), *t (TAB), *s (space),
//     *" (quote), *' (single quote), ** (literal *).

SECTION "strch"

GET "libhdr"

LET start() = VALOF
{ LET s = "Hello"
  LET len = s%0          // byte 0 is length

  writef("string=[%s] len=%n*n", s, len)

  // Print bytes one at a time using %c.
  FOR i = 1 TO len DO
    writef("  byte %n = '%c' (%n)*n", i, s%i, s%i)

  writef("escape test: *"quoted*" and *n is newline*n")
  RESULTIS 0
}
