// 22-format-output: the family of formatted-output functions.
//
// Concepts:
//   - writed(n, w)   space-pad signed decimal to width w.
//   - writeu(n, w)   space-pad unsigned decimal.
//   - writez(n, w)   zero-pad signed decimal.
//   - writehex(n, d) zero-pad unsigned hex to d digits (uppercase).
//   - writeoct(n, d) zero-pad unsigned octal to d digits.
//   - writeflt(x, w, p) float x (f32 bits) as fixed-point w.p.
//   - writee(x, w, p)   float x as exponential w.p.

SECTION "fmt"

GET "libhdr"

LET start() = VALOF
{ LET x = 0
  LET y = 0

  writes("writed 42 width 6  -> [")
  writed(42, 6)
  writes("]*n")

  writes("writez -9 width 5  -> [")
  writez(-9, 5)
  writes("]*n")

  writes("writehex 255 d=4   -> [")
  writehex(255, 4)
  writes("]*n")

  writes("writeoct 8   d=4   -> [")
  writeoct(8, 4)
  writes("]*n")

  x #:= 3.14159
  writes("writeflt pi  w=10 p=4 -> [")
  writeflt(x, 10, 4)
  writes("]*n")

  y #:= 0.000125
  writes("writee 1.25e-4 w=14 p=3 -> [")
  writee(y, 14, 3)
  writes("]*n")
  RESULTIS 0
}
