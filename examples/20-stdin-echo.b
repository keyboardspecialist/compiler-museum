// 20-stdin-echo: read stdin char-by-char, echo to stdout.
//
// Concepts:
//   - rdch() returns the next char, or endstreamch (-1) at EOF.
//   - wrch(ch) writes one char.
//   - Use the Stdin pane (right of Output) to feed characters
//     before clicking Compile & Run.

SECTION "echo"

GET "libhdr"

LET start() = VALOF
{ LET ch = rdch()
  UNTIL ch = endstreamch DO
  { wrch(ch)
    ch := rdch()
  }
  RESULTIS 0
}
