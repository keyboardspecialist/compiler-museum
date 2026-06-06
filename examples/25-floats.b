// 25-floats: the FLT feature for floating-point arithmetic.
//
// Concepts:
//   - A BCPL word can hold a float's bit pattern.
//   - FLT mode prefixes ops with # to mean float:
//       #+  #-  (mul)  #/  #MOD
//       #=  #~=  #<  #>  #<=  #>=
//     (Multiplication is the '#' form of '*'. The '*' character inside
//     a BCPL string literal is the escape prefix, so we describe it
//     here in words instead of the symbol.)
//   - Assignment: x #:= 1.5 stores the float bits into x.
//   - writef %f prints the bits as a float.

SECTION "fmod"

GET "libhdr"

LET start() = VALOF
{ LET a = 0
  LET b = 0
  LET r = 0
  a #:= 10.5
  b #:= 3.0
  r #:= a #MOD b
  writef("%6.2f  mod %6.2f = %6.2f*n", a, b, r)
  r #:= a #+ b
  writef("%6.2f  +   %6.2f = %6.2f*n", a, b, r)
  r #:= a #- b
  writef("%6.2f  -   %6.2f = %6.2f*n", a, b, r)
  RESULTIS 0
}
