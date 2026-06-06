// 03-variables: LET declarations and assignment.
//
// Concepts:
//   - LET <name> = <expr>  introduces a local.
//   - := reassigns.
//   - Integer literals: 42, -7, #xFF (hex), #o777 (octal), #b1010 (binary).
//   - Arithmetic: + - * /  MOD  and unary - for negation.

SECTION "vars"

GET "libhdr"

LET start() = VALOF
{ LET a = 42
  LET b = #xFF        // 255 in hex
  LET c = #b1010      // 10 in binary
  LET d = 0

  writef("a=%n b=%n c=%n*n", a, b, c)

  d := a + b * 2      // 42 + 510
  writef("d = a + b*2 = %n*n", d)

  d := d - 100        // reassignment
  writef("d after := %n*n", d)

  writef("17 MOD 5 = %n*n", 17 MOD 5)
  RESULTIS 0
}
