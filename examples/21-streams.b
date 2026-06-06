// 21-streams: named read/write streams backed by browser storage.
//
// Concepts:
//   - findoutput(name) opens a write stream under <name>.
//   - selectoutput(h) switches the current output handle.
//   - endstream(h) closes and commits a write stream to storage.
//   - findinput(name) opens an existing stream for reading.
//   - selectinput(h) switches the current input handle.
//   - rdch/wrch always target the currently selected streams.

SECTION "streams"

GET "libhdr"

LET start() = VALOF
{ LET out = findoutput("greeting")
  LET in  = ?
  LET ch  = ?
  LET old = ?

  UNLESS out DO { writef("findoutput failed*n"); RESULTIS 1 }

  old := selectoutput(out)
  writes("hello from a saved stream")
  newline()
  writef("%n squared = %n*n", 7, 7*7)
  selectoutput(old)
  endstream(out)

  writef("wrote 'greeting'. now reading it back:*n")

  in := findinput("greeting")
  UNLESS in DO { writef("findinput failed*n"); RESULTIS 1 }

  old := selectinput(in)
  ch  := rdch()
  UNTIL ch = endstreamch DO
  { wrch(ch)
    ch := rdch()
  }
  selectinput(old)
  endstream(in)
  RESULTIS 0
}
