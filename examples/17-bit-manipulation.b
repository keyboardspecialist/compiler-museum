// 17-bit-manipulation: shifts, bitwise ops, setbit/testbit.
//
// Concepts:
//   - LSHIFT / RSHIFT do logical (zero-fill) shifts.
//   - & | XOR EQV act bitwise on integers (outside Boolean context).
//   - ~ flips all bits.
//   - Hex literals (#x...) read nicely for bit patterns.
//   - setbit(n, vec, state) / testbit(n, vec) treat a word vector
//     as a packed bit array.

SECTION "bits"

GET "libhdr"

LET start() = VALOF
{ LET flags = VEC 2

  writef("1 LSHIFT 4       = %n*n", 1 LSHIFT 4)
  writef("-16 RSHIFT 2     = %n  (logical, not arithmetic)*n", -16 RSHIFT 2)
  writef("#xFF00 & #xF0F0  = %x4*n", #xFF00 & #xF0F0)
  writef("#xFF00 | #x000F  = %x4*n", #xFF00 | #x000F)
  writef("#xAA   XOR #x55  = %x2*n", #xAA XOR #x55)

  // Packed bit vector: 64 bits = 2 words on a 32-bit target.
  FOR i = 0 TO 1 DO flags!i := 0
  setbit(0,  flags, TRUE)
  setbit(7,  flags, TRUE)
  setbit(33, flags, TRUE)
  writef("flags = %X8 %X8*n", flags!1, flags!0)
  writef("testbit 7 = %n  33 = %n  5 = %n*n",
         testbit(7, flags), testbit(33, flags), testbit(5, flags))
  RESULTIS 0
}
