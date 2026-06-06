// 64-flt-modes: FLOAT, FIX, and the FLT feature in depth.
//
// BCPL words are untyped bit patterns. A word can store either an int
// or a 32-bit float (IEEE-754 bits) — interpretation is up to the
// operators you apply. Three tools manage the int / float split:
//
//   FLOAT x   — convert int x to float bits  (i32 → f32 reinterpret)
//   FIX x     — convert float bits x to int  (truncate)
//   FLT       — declaration tag: parameters / variables typed FLT
//               make the compiler emit '#' operators automatically.
//
// '#' before an operator means "treat operands as floats":
//   #+  #-  (mul)  #/  #MOD
//   #=  #~=  #<  #>  #<=  #>=
//   #:= assignment
//
// (Multiplication uses '#' before '*'. The '*' is the BCPL string-
//  escape prefix so it's spelled out in words here, not in symbols.)
//
// Compare with 25-floats which introduces the # operators.

SECTION "fmod"

GET "libhdr"

// FLT on the parameter list makes the compiler treat a + b internally
// as a #+ b — no need to litter the body with # for those operands.
// The function returns float bits.
LET hypot2(FLT a, FLT b) = a*a + b*b

LET start() = VALOF
{ LET i = 5
  LET f = 0
  LET back = 0

  // --- FLOAT: int -> float bits --------------------------------------
  f #:= FLOAT i
  writef("FLOAT %n  ->  %5.2f*n", i, f)

  // --- FIX: float bits -> int (truncate, NOT round) ------------------
  f #:= 3.78
  back := FIX f
  writef("FIX   %5.2f  ->  %n  (truncated, not rounded)*n", f, back)

  // --- FLT on params: hypot2 with two int-looking call args -----------
  // The arguments are floats — passed as f32 bit patterns. We pass
  // FLOAT-converted ints to make that explicit.
  { LET r = hypot2(FLOAT 3, FLOAT 4)   // returns 25.0
    writef("hypot2(3,4)^2 = %5.2f*n", r)
  }

  // --- FLT mode mixed with literals via #:= -----------------------------
  { LET x, y = 0, 0
    x #:= 1.5
    y #:= 2.5
    writef("1.5 #+ 2.5 = %4.1f*n", x #+ y)
    writef("1.5 #/ 2.5 = %4.2f*n", x #/ y)
  }

  // --- Compare: native int arithmetic loses precision before FIX -------
  // 7 / 2 in BCPL int math is integer division = 3.
  // 7.0 #/ 2.0 in float math = 3.5, then FIX = 3 (truncation).
  { LET ii = 0
    LET ff = 0
    ii := 7 / 2
    ff #:= 7.0 #/ 2.0
    writef("int  7/2     = %n*n", ii)
    writef("float 7.0/2.0= %4.2f (FIX -> %n)*n", ff, FIX ff)
  }

  // --- FLT local + literal-recognition ---------------------------------
  // A LET-FLT local accepts a float literal directly and participates
  // in '#' arithmetic without manual #:= ceremony.
  { LET FLT t = 2.5
    LET FLT g = 9.80665
    LET FLT h = 0.5 #* g #* t #* t
    writef("free fall after %4.2fs under g=%6.4f m/s^2  -> %6.2f m*n",
           t, g, h)
  }

  RESULTIS 0
}
