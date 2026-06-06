SECTION "stdlib"

GET "libhdr"

LET start() = VALOF
{ // muldiv: (a*b)/c with 64-bit intermediate.
  writef("muldiv(1000, 1000, 7)  = %n*n", muldiv(1000, 1000, 7))
  writef("muldiv(1_000_000, 1_000_000, 1_000_000) = %n*n",
         muldiv(1000000, 1000000, 1000000))

  // randno: 1..n inclusive.
  writef("randno(6) sample: ")
  FOR i = 1 TO 8 DO writef("%n ", randno(6))
  newline()

  // capitalch + compch.
  writef("capitalch('a') = %c*n", capitalch('a'))
  writef("compch('A','a') = %n (case-insensitive)*n", compch('A', 'a'))
  writef("compch('A','B') = %n*n", compch('A', 'B'))

  // compstring.
  writef("compstring(*"abc*", *"abc*") = %n*n", compstring("abc", "abc"))
  writef("compstring(*"abc*", *"abd*") = %n*n", compstring("abc", "abd"))

  // Zero-padded format %Z.
  writef("%z4 | %z4 | %z4*n", 42, -7, 0)
  RESULTIS 0
}
