// 01-hello: your first BCPL program.
//
// Concepts:
//   - SECTION declares a compilation unit.
//   - GET "libhdr" imports the standard library declarations.
//   - start() is the conventional entry point.
//   - writef formats output like C's printf.
//   - *n inside a string literal is a newline escape.
//   - RESULTIS returns a value from a VALOF block.

SECTION "hello"

GET "libhdr"

LET start() = VALOF
{ writef("Hello, BCPL!*n")
  RESULTIS 0
}
