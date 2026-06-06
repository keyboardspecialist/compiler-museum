// 10-functions: value-returning functions vs side-effect routines.
//
// Concepts:
//   - LET f(x) = <expr>          — value-returning function.
//   - LET f(x) = VALOF { ... }   — function with a body, ends in RESULTIS.
//   - LET r(x) BE { ... }        — routine, no return value.
//   - AND chains additional defs at the same scope level.
//   - Parameters are passed by value; everything is a word.

SECTION "fns"

GET "libhdr"

LET sqr(x) = x * x

AND cube(x) = VALOF
{ LET s = sqr(x)
  RESULTIS s * x
}

AND greet(name) BE writef("hello, %s*n", name)

LET start() = VALOF
{ writef("sqr(7)=%n cube(4)=%n*n", sqr(7), cube(4))
  greet("world")
  RESULTIS 0
}
