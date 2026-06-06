// 23-parsing: read integers, tokens, and structured numbers.
//
// Concepts:
//   - readn() parses a decimal integer from the current input stream.
//     result2 = 0 on success, -1 if no digits were found.
//   - rditem(v, upb) reads the next token into vector v; returns a
//     type code (0=EOF, 1=unquoted, 2=quoted, 3=newline, 4=';', 5='=').
//   - string_to_number(s) accepts full BCPL syntax:
//     signs, #O/#X/#B bases, underscores, 'A' char literals.
//     Returns TRUE on success with value in result2.

SECTION "parse"

GET "libhdr"

LET start() = VALOF
{ LET n = 0
  LET ok = 0

  writef("try parsing -42: ")
  ok := string_to_number("-42")
  writef("ok=%n result2=%n*n", ok, result2)

  writef("try parsing #xFF: ")
  ok := string_to_number("#xFF")
  writef("ok=%n result2=%n*n", ok, result2)

  writef("try parsing #b_1100_0010: ")
  ok := string_to_number("#b_1100_0010")
  writef("ok=%n result2=%n*n", ok, result2)

  writef("try parsing hello (invalid): ")
  ok := string_to_number("hello")
  writef("ok=%n result2=%n*n", ok, result2)

  writef("char literal 'Z': ")
  ok := string_to_number("'Z'")
  writef("ok=%n result2=%n (= %c)*n", ok, result2, result2)

  // readn from stdin (use the Stdin pane to supply digits).
  writef("type an integer in the Stdin pane, then press space:*n")
  n := readn()
  writef("readn returned %n (result2=%n)*n", n, result2)
  RESULTIS 0
}
