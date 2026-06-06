// 19-manifest-static: MANIFEST constants and STATIC variables.
//
// Concepts:
//   - MANIFEST { name = value; ... }   — compile-time constants; no
//     storage, just substitution.
//   - STATIC { name = value; ... }     — persistent storage initialised
//     once at program start; visible to every function in the section.
//   - Use MANIFEST for magic numbers; STATIC for program-wide state.

SECTION "msta"

GET "libhdr"

MANIFEST {
  max_depth = 5
  greeting_count = 3
}

STATIC {
  hits = 0
}

LET bump() BE hits := hits + 1

LET start() = VALOF
{ FOR i = 1 TO greeting_count DO
  { bump()
    writef("hello #%n (limit %n)*n", hits, max_depth)
  }
  writef("final hit count: %n*n", hits)
  RESULTIS 0
}
