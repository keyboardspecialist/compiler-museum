// 24-rdargs: command-line argument parsing via a key-spec string.
//
// Concepts:
//   - Key-spec syntax: comma-separated. Suffix flags change behavior:
//       /A  required
//       /K  takes a value after the keyword
//       /N  value is numeric (pointer to integer slot)
//       /S  switch (boolean; TRUE if the keyword appears)
//   - After rdargs, argv!i holds the i'th parsed field, or 0 if absent.
//   - /N fields point at a cell; dereference with !argv!i.
//   - The "command line" in the playground comes from the `input`
//     buffer passed to BcplRuntime at load time. For Compile & Run,
//     put your args in the Stdin pane before clicking Run.

SECTION "rdargs"

GET "libhdr"

LET start() = VALOF
{ LET argv = VEC 50
  LET spec = "FROM/A,TO/K,SIZE/K/N,VERBOSE/S"

  IF rdargs(spec, argv, 50) = 0 DO
  { writef("rdargs failed. expected spec: %s*n", spec)
    RESULTIS 20
  }

  writef("FROM    = %s*n",  argv!0)
  writef("TO      = %s*n",  argv!1 -> argv!1, "(none)")
  IF argv!2 DO writef("SIZE    = %n*n", !argv!2)
  writef("VERBOSE = %n*n",  argv!3)
  RESULTIS 0
}
