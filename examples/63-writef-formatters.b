// 63-writef-formatters: every writef() format code, end to end.
//
// writef walks the format string consuming one argument per code it
// finds. Codes:
//   %n            signed decimal (no padding)
//   %d            same as %n
//   %i N          signed decimal, space-pad to width N
//   %u            unsigned decimal
//   %c            character
//   %s            BCPL string (length byte + bytes)
//   %x N          unsigned hex, zero-pad to N digits (uppercase)
//   %o N          unsigned octal, zero-pad to N digits
//   %b N          unsigned binary, zero-pad to N digits
//   %z N          signed decimal, zero-pad to N digits
//   %t N          string padded RIGHT with spaces to width N
//   %f, %e, %g    floats — see 25-floats / 64-flt-modes for FLT mode
//   %n.mD         pre-code "width.precision" form (works on D=d/i/f/e/g)
//   %#            codewrch — Unicode codepoint as UTF-8
//   %+            advance argument pointer (skip one)
//   %-            back up argument pointer (re-use one)
//   %%            literal '%'
//
// Compare with 22-format-output, which uses the standalone writen /
// writeu / writez / writehex / writeoct functions directly.

SECTION "wfmt"

GET "libhdr"

LET start() = VALOF
{ LET ch = 65   // 'A'
  LET who = "BCPL"
  LET small = 42
  LET large = 305419896   // 0x12345678

  writef("plain  %n*n", small)
  writef("dec    %i6  width 6, space-padded*n", small)
  writef("zdec   %z6  width 6, zero-padded*n",  small)
  writef("hex    %x4  width 4, zero-padded (uppercase)*n", large)
  writef("oct    %o6  width 6, zero-padded*n", small)
  writef("bin    %b8  width 8, zero-padded*n", small)
  writef("unsign %u4  width 4 unsigned*n", -1)

  writef("char   '%c' (codepoint %n)*n", ch, ch)
  writef("string '%s' length=%n*n", who, who % 0)
  writef("padstr '%t10' right-padded to width 10*n", who)

  writef("escape  literal percent: 100%%*n")
  writef("escape  newline already inserted by *n at the end*n")

  // Argument cursor controls.
  // %+ skips the next arg, %- re-uses the previous arg.
  writef("skip    a=%n  (skip)%+  c=%n*n", 1, 999, 3)
  writef("reuse   a=%n  again=%-%n*n", 7, 0)   // 7 then 7

  // Unicode via %# — accepts the codepoint as an integer arg.
  writef("unicode lambda='%#'  pi='%#'*n", #x03BB, #x03C0)

  RESULTIS 0
}
