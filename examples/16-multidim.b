// 16-multidim: 2-D tables via a vector of vectors.
//
// Concepts:
//   - Allocate one outer vec whose cells hold pointers.
//   - Each cell points at its own row (inner vec).
//   - Remember to freevec every row and then the outer vec.

SECTION "mdim"

GET "libhdr"

LET start() = VALOF
{ LET rows = 3
  LET cols = 4
  LET grid = getvec(rows - 1)
  UNLESS grid DO { writef("OOM*n"); RESULTIS 1 }

  // Allocate each row and fill with row*10 + col.
  FOR r = 0 TO rows - 1 DO
  { LET row = getvec(cols - 1)
    grid!r := row
    FOR c = 0 TO cols - 1 DO row!c := r*10 + c
  }

  // Print.
  FOR r = 0 TO rows - 1 DO
  { LET row = grid!r
    FOR c = 0 TO cols - 1 DO writef("%i3 ", row!c)
    newline()
  }

  // Clean up: rows first, then the outer vec.
  FOR r = 0 TO rows - 1 DO freevec(grid!r)
  freevec(grid)
  RESULTIS 0
}
