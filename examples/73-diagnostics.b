// 73-diagnostics — pure-BCPL safety nets that catch the usual
// silent-corruption / null-deref bugs at their source instead of
// via a downstream SIGSEGV.
//
// Three helpers live in BLIB (added 2026); both cintsys and the
// wasm playground export them at fixed global slots:
//
//   assert(cond, "msg")
//       Aborts (code 901) if cond is FALSE, printing
//         ASSERT FAIL: <msg>
//       Use to nail invariants at the failing line instead of
//       chasing a downstream crash.
//
//   getvec_or_abort(n, "msg") -> ptr
//       Like getvec(n) but aborts with
//         GETVEC OOM: <msg> (requested N words)
//       on allocation failure instead of returning 0 silently.
//
//   vsafe_get(v, i, "msg") -> v!i
//       Reads v!i with a bounds check against BLIB's size header.
//       Aborts on OOB or NULL with
//         VSAFE OOB: <msg> (i=N upb=N)
//
// All three abort with code 901, which bootsys.b reports as
// "Diagnostic abort (assert/vsafe/OOM)" so the standard fault
// prompt names exactly what fired.
//
// Cintsys also gets a BCPL call-chain dump on SIGSEGV (entry
// point + return-PC per frame) via the segvhandler in
// sysc/cintmain.c, surfacing "where am I in the BCPL source"
// even for crashes outside the standard abort path.

SECTION "DIAG"

GET "libhdr"

// Run a section that's expected to succeed.
LET show_pass(label, p) BE
{ writef("PASS  %s : returned %n*n", label, p)
}

// Demonstrate the four guarded code paths. We only trip the last
// one — earlier examples show the helpers passing silently when
// their condition holds.

LET demo_assert() BE
{ writes("*ndemo 1: assert with a true condition*n")
  assert(2 + 2 = 4, "arithmetic still works")
  writes("  (silently passed)*n")
}

LET demo_getvec_ok() = VALOF
{ LET p = 0
  writes("*ndemo 2: getvec_or_abort with a sane size*n")
  p := getvec_or_abort(64, "scratch vector")
  show_pass("getvec_or_abort(64)", p)
  freevec(p)
  RESULTIS 0
}

LET demo_vsafe_ok() BE
{ LET v = getvec_or_abort(32, "demo vec")
  writes("*ndemo 3: vsafe_get within bounds*n")
  // Seed a value so the read produces something visible.
  v!17 := 4242
  writef("  v[17] = %n*n", vsafe_get(v, 17, "v[17] read"))
  freevec(v)
}

// Trip the safety net intentionally. Picks ONE of three; toggle
// the constant in main to see each path. We default to the OOB
// case because it's the most visually obvious.

LET demo_vsafe_oob() BE
{ LET v = getvec_or_abort(8, "tiny vec")
  writes("*ndemo 4: vsafe_get OOB — should abort below*n")
  writes("  about to read v[9999]...*n")
  vsafe_get(v, 9999, "intentional OOB demo")
  writes("  UNREACHED*n")           // never gets here
}

LET demo_assert_fail() BE
{ writes("*ndemo 4 (alt): assert fail*n")
  assert(1 = 2, "deliberate assertion failure")
  writes("  UNREACHED*n")
}

LET demo_oom() BE
{ LET p = 0
  writes("*ndemo 4 (alt): OOM trip — request 100 million words*n")
  p := getvec_or_abort(100000000, "absurd allocation")
  writes("  UNREACHED*n")
}

LET start() = VALOF
{ writes("=== BCPL diagnostic helpers ===*n")
  writes("All three helpers abort with code 901 on failure.*n")
  writes("Look for the formatted message above the abort prompt.*n")

  demo_assert()
  demo_getvec_ok()
  demo_vsafe_ok()

  // Pick the failure to trigger. Comment out two of the three.
  demo_vsafe_oob()
  // demo_assert_fail()
  // demo_oom()

  writes("*n(unreachable: control fell through)*n")
  RESULTIS 0
}
