// 09-switchon: multi-way dispatch.
//
// Concepts:
//   - SWITCHON expr INTO { CASE k: ... ENDCASE }
//   - DEFAULT: catches anything not matched.
//   - Each arm must end with ENDCASE (there's no C-style fallthrough).
//   - Control passes to after the } — no break needed beyond ENDCASE.

SECTION "swon"

GET "libhdr"

LET classify(ch) = VALOF
{ SWITCHON ch INTO
  { CASE '0': CASE '1': CASE '2': CASE '3': CASE '4':
    CASE '5': CASE '6': CASE '7': CASE '8': CASE '9':
      RESULTIS 1  // digit
    CASE 'a': CASE 'e': CASE 'i': CASE 'o': CASE 'u':
      RESULTIS 2  // lowercase vowel
    DEFAULT:
      RESULTIS 0  // other
  }
}

LET start() = VALOF
{ LET samples = "7 a q"
  FOR i = 1 TO samples%0 DO
    writef("'%c' -> class %n*n", samples%i, classify(samples%i))
  RESULTIS 0
}
